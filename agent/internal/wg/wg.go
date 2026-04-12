package wg

import (
	"context"
	"errors"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"

	"golang.zx2c4.com/wireguard/wgctrl"
	"golang.zx2c4.com/wireguard/wgctrl/wgtypes"
)

// Manager owns the wg0.conf file (the persistent source of truth) AND
// the live kernel interface state (read and mutated via wgctrl-go,
// which talks netlink directly — no shelling out to `wg` or `wg-quick`).
//
// Every mutation goes through three coordinated steps:
//   1. Acquire the on-disk flock (wg0.conf.lock).
//   2. Edit + atomically rewrite wg0.conf so the change survives reboot.
//   3. Apply the same change to the kernel via wgctrl.ConfigureDevice
//      so existing peer sessions are not disrupted.
type Manager struct {
	confPath  string
	iface     string
	subnet    *net.IPNet
	publicEnd string

	client *wgctrl.Client
	mu     sync.Mutex // serialises in-process callers; flock guards across processes
}

// Peer is the typed representation of a single WireGuard peer combining
// static config (from wg0.conf) and runtime state (from wgctrl).
type Peer struct {
	Name            string     `json:"name"`
	PublicKey       string     `json:"public_key"`
	PresharedKey    string     `json:"-"` // never returned over the API
	AllowedIPs      []string   `json:"allowed_ips"`
	Enabled         bool       `json:"enabled"`
	CreatedAt       time.Time  `json:"created_at"`
	CreatedBy       string     `json:"created_by,omitempty"`
	Endpoint        string     `json:"endpoint,omitempty"`
	LastHandshakeAt *time.Time `json:"last_handshake_at,omitempty"`
	RxBytesTotal    uint64     `json:"rx_bytes_total"`
	TxBytesTotal    uint64     `json:"tx_bytes_total"`
}

// CreateRequest is what callers pass to Manager.Add.
type CreateRequest struct {
	Name      string // human-readable label, e.g. "phone"
	CreatedBy string // CN of the admin client cert that asked for it
}

// CreateResult is what Manager.Add returns to callers.
type CreateResult struct {
	Peer         Peer
	ClientConfig string // ready-to-import wg .conf for the new client
}

// NewManager constructs a Manager and opens a wgctrl client.
//
// Caller must call Close() at shutdown to release the netlink socket.
func NewManager(confPath, iface, subnet, publicEnd string) (*Manager, error) {
	_, ipnet, err := net.ParseCIDR(subnet)
	if err != nil {
		return nil, fmt.Errorf("invalid subnet %q: %w", subnet, err)
	}
	client, err := wgctrl.New()
	if err != nil {
		return nil, fmt.Errorf("open wgctrl: %w", err)
	}
	// Probe the interface immediately so any misconfiguration is loud.
	if _, err := client.Device(iface); err != nil {
		client.Close()
		return nil, fmt.Errorf("wgctrl device %q: %w", iface, err)
	}
	return &Manager{
		confPath:  confPath,
		iface:     iface,
		subnet:    ipnet,
		publicEnd: publicEnd,
		client:    client,
	}, nil
}

// Close releases the netlink socket. Safe to call multiple times.
func (m *Manager) Close() error {
	if m.client == nil {
		return nil
	}
	err := m.client.Close()
	m.client = nil
	return err
}

// Client returns the underlying wgctrl client so other subsystems
// (e.g. the bandwidth sampler) can read live device state without
// opening their own netlink socket. Do NOT call Close() on the
// returned client — the Manager owns it.
func (m *Manager) Client() *wgctrl.Client {
	return m.client
}

// List returns the current peers, joining static config from wg0.conf
// with live transfer/handshake data from wgctrl.
func (m *Manager) List(ctx context.Context) ([]Peer, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	cfg, err := readConfigFile(m.confPath)
	if err != nil {
		return nil, fmt.Errorf("read wg0.conf: %w", err)
	}
	dev, err := m.client.Device(m.iface)
	if err != nil {
		// Non-fatal: we can still return static peer list without live data.
		return mergeConfigAndLive(cfg, nil), nil
	}
	return mergeConfigAndLive(cfg, snapshotLivePeers(dev)), nil
}

// Add generates fresh keys + PSK, allocates the next free /32 in the
// subnet, appends a [Peer] block to wg0.conf, applies the change to
// the kernel via wgctrl, and returns the rendered client .conf.
func (m *Manager) Add(ctx context.Context, req CreateRequest) (*CreateResult, error) {
	if strings.TrimSpace(req.Name) == "" {
		return nil, errors.New("peer name must not be empty")
	}
	if len(req.Name) > 64 {
		return nil, errors.New("peer name must be at most 64 characters")
	}

	m.mu.Lock()
	defer m.mu.Unlock()

	unlock, err := flockExclusive(m.confPath + ".lock")
	if err != nil {
		return nil, fmt.Errorf("lock: %w", err)
	}
	defer unlock()

	cfg, err := readConfigFile(m.confPath)
	if err != nil {
		return nil, fmt.Errorf("read wg0.conf: %w", err)
	}

	// Allocate the next free host IP in the subnet.
	clientIP, err := m.nextFreeIP(cfg)
	if err != nil {
		return nil, err
	}

	priv, err := wgtypes.GeneratePrivateKey()
	if err != nil {
		return nil, fmt.Errorf("generate private key: %w", err)
	}
	pub := priv.PublicKey()
	psk, err := wgtypes.GenerateKey()
	if err != nil {
		return nil, fmt.Errorf("generate psk: %w", err)
	}

	allowedCIDR := clientIP.String() + "/32"
	cfg.addPeer(pub.String(), psk.String(), allowedCIDR, req.Name, req.CreatedBy)

	if err := writeConfigFile(m.confPath, cfg); err != nil {
		return nil, fmt.Errorf("write wg0.conf: %w", err)
	}

	// Apply to kernel without disrupting existing peers: ReplacePeers=false.
	_, ipnet, err := net.ParseCIDR(allowedCIDR)
	if err != nil {
		return nil, fmt.Errorf("parse allowed cidr: %w", err)
	}
	pcfg := wgtypes.PeerConfig{
		PublicKey:         pub,
		PresharedKey:      &psk,
		ReplaceAllowedIPs: true,
		AllowedIPs:        []net.IPNet{*ipnet},
	}
	if err := m.client.ConfigureDevice(m.iface, wgtypes.Config{
		ReplacePeers: false,
		Peers:        []wgtypes.PeerConfig{pcfg},
	}); err != nil {
		return nil, fmt.Errorf("configure device: %w", err)
	}

	serverPub, err := m.serverPublicKey()
	if err != nil {
		return nil, fmt.Errorf("read server pubkey: %w", err)
	}

	clientConf := renderClientConfig(clientConfigInput{
		ClientPrivateKey: priv.String(),
		ClientAddress:    allowedCIDR,
		DNS:              "10.8.0.1",
		MTU:              1420,
		ServerPublicKey:  serverPub,
		PresharedKey:     psk.String(),
		Endpoint:         m.publicEnd,
	})

	peer := Peer{
		Name:       req.Name,
		PublicKey:  pub.String(),
		AllowedIPs: []string{allowedCIDR},
		CreatedAt:  time.Now().UTC(),
		CreatedBy:  req.CreatedBy,
	}
	return &CreateResult{Peer: peer, ClientConfig: clientConf}, nil
}

// SetEnabled toggles a peer's enabled flag.
//
// When disabled, the [Peer] block stays in wg0.conf (so the keys, IP
// allocation, and metadata are preserved) but the kernel is updated
// to remove the peer from the live interface — existing sessions are
// dropped immediately and new sessions cannot be established. The
// peer block in wg0.conf is annotated with `# enabled=false`.
//
// When re-enabled, the kernel is reconfigured with the original keys
// and AllowedIPs. The peer can resume the moment the client retries.
//
// This is the wg-portal / wg-easy "suspend" pattern: cheaper than
// revoke + re-issue + redistribute.
func (m *Manager) SetEnabled(ctx context.Context, pubkey string, enabled bool) error {
	if strings.TrimSpace(pubkey) == "" {
		return errors.New("pubkey must not be empty")
	}
	m.mu.Lock()
	defer m.mu.Unlock()

	unlock, err := flockExclusive(m.confPath + ".lock")
	if err != nil {
		return fmt.Errorf("lock: %w", err)
	}
	defer unlock()

	cfg, err := readConfigFile(m.confPath)
	if err != nil {
		return fmt.Errorf("read wg0.conf: %w", err)
	}
	sec := cfg.findPeer(pubkey)
	if sec == nil {
		return ErrPeerNotFound
	}

	// Persist the new enabled flag in metadata.
	if enabled {
		delete(sec.Meta, "enabled")
	} else {
		sec.Meta["enabled"] = "false"
	}
	if err := writeConfigFile(m.confPath, cfg); err != nil {
		return fmt.Errorf("write wg0.conf: %w", err)
	}

	parsedKey, err := wgtypes.ParseKey(pubkey)
	if err != nil {
		return fmt.Errorf("parse pubkey: %w", err)
	}

	if !enabled {
		// Suspend: drop the peer from the live kernel interface but
		// keep its [Peer] block in wg0.conf.
		return m.client.ConfigureDevice(m.iface, wgtypes.Config{
			ReplacePeers: false,
			Peers: []wgtypes.PeerConfig{{
				PublicKey: parsedKey,
				Remove:    true,
			}},
		})
	}

	// Re-enable: re-add the peer to the kernel from the on-disk config.
	var psk *wgtypes.Key
	var allowed []net.IPNet
	for _, e := range sec.Entries {
		switch e.Key {
		case "PresharedKey":
			k, perr := wgtypes.ParseKey(e.Value)
			if perr != nil {
				return fmt.Errorf("parse psk: %w", perr)
			}
			psk = &k
		case "AllowedIPs":
			for _, addr := range strings.Split(e.Value, ",") {
				_, ipnet, perr := net.ParseCIDR(strings.TrimSpace(addr))
				if perr != nil {
					return fmt.Errorf("parse allowed ip %q: %w", addr, perr)
				}
				allowed = append(allowed, *ipnet)
			}
		}
	}
	return m.client.ConfigureDevice(m.iface, wgtypes.Config{
		ReplacePeers: false,
		Peers: []wgtypes.PeerConfig{{
			PublicKey:         parsedKey,
			PresharedKey:      psk,
			ReplaceAllowedIPs: true,
			AllowedIPs:        allowed,
		}},
	})
}

// Remove deletes the peer with the given public key from wg0.conf and
// applies the change. Returns ErrPeerNotFound if no such peer exists.
var ErrPeerNotFound = errors.New("peer not found")

func (m *Manager) Remove(ctx context.Context, pubkey string) error {
	if strings.TrimSpace(pubkey) == "" {
		return errors.New("pubkey must not be empty")
	}
	m.mu.Lock()
	defer m.mu.Unlock()

	unlock, err := flockExclusive(m.confPath + ".lock")
	if err != nil {
		return fmt.Errorf("lock: %w", err)
	}
	defer unlock()

	cfg, err := readConfigFile(m.confPath)
	if err != nil {
		return fmt.Errorf("read wg0.conf: %w", err)
	}
	if !cfg.removePeer(pubkey) {
		return ErrPeerNotFound
	}
	if err := writeConfigFile(m.confPath, cfg); err != nil {
		return fmt.Errorf("write wg0.conf: %w", err)
	}

	// Apply to kernel: ReplacePeers=false + Remove=true on this peer only.
	parsedKey, err := wgtypes.ParseKey(pubkey)
	if err != nil {
		return fmt.Errorf("parse pubkey: %w", err)
	}
	if err := m.client.ConfigureDevice(m.iface, wgtypes.Config{
		ReplacePeers: false,
		Peers: []wgtypes.PeerConfig{{
			PublicKey: parsedKey,
			Remove:    true,
		}},
	}); err != nil {
		return fmt.Errorf("configure device: %w", err)
	}
	return nil
}

// nextFreeIP returns the lowest unused host IP in the manager's subnet,
// excluding the network and broadcast addresses.
func (m *Manager) nextFreeIP(cfg *rawConfig) (net.IP, error) {
	used := cfg.usedIPs()
	first, last := networkRange(m.subnet)
	for ip := nextIP(first); !ipEqual(ip, last); ip = nextIP(ip) {
		if !used[ip.String()] {
			return ip, nil
		}
	}
	return nil, fmt.Errorf("no free IPs in %s", m.subnet)
}

// serverPublicKey returns the server's WG public key from the live
// kernel interface (no need to read the private key file).
func (m *Manager) serverPublicKey() (string, error) {
	dev, err := m.client.Device(m.iface)
	if err != nil {
		return "", err
	}
	return dev.PublicKey.String(), nil
}

// livePeer is the per-peer runtime data extracted from wgctrl.
type livePeer struct {
	PublicKey     string
	Endpoint      string
	LastHandshake *time.Time
	Rx            uint64
	Tx            uint64
}

// snapshotLivePeers converts a wgtypes.Device into the by-pubkey map
// the merge step expects.
func snapshotLivePeers(dev *wgtypes.Device) map[string]livePeer {
	out := make(map[string]livePeer, len(dev.Peers))
	for _, p := range dev.Peers {
		lp := livePeer{
			PublicKey: p.PublicKey.String(),
			Rx:        uint64(p.ReceiveBytes),
			Tx:        uint64(p.TransmitBytes),
		}
		if p.Endpoint != nil {
			lp.Endpoint = p.Endpoint.String()
		}
		if !p.LastHandshakeTime.IsZero() {
			t := p.LastHandshakeTime.UTC()
			lp.LastHandshake = &t
		}
		out[lp.PublicKey] = lp
	}
	return out
}

// mergeConfigAndLive walks the parsed config + the live state and
// returns a normalised []Peer for the API.
func mergeConfigAndLive(cfg *rawConfig, live map[string]livePeer) []Peer {
	var peers []Peer
	for _, s := range cfg.Sections {
		if s.Type != sectionPeer {
			continue
		}
		var pub, psk string
		var allowed []string
		for _, e := range s.Entries {
			switch e.Key {
			case "PublicKey":
				pub = e.Value
			case "PresharedKey":
				psk = e.Value
			case "AllowedIPs":
				for _, a := range strings.Split(e.Value, ",") {
					allowed = append(allowed, strings.TrimSpace(a))
				}
			}
		}
		// Default to enabled unless explicitly disabled in metadata.
		// Backward-compat: peers created before M4.3 have no enabled
		// flag and are treated as enabled.
		enabled := true
		if v := s.Meta["enabled"]; v == "false" {
			enabled = false
		}
		p := Peer{
			Name:         s.Meta["name"],
			PublicKey:    pub,
			PresharedKey: psk,
			AllowedIPs:   allowed,
			Enabled:      enabled,
			CreatedBy:    s.Meta["created_by"],
		}
		if ts := s.Meta["created_at"]; ts != "" {
			if t, err := time.Parse(time.RFC3339, ts); err == nil {
				p.CreatedAt = t
			}
		}
		if lp, ok := live[pub]; ok {
			p.Endpoint = lp.Endpoint
			p.LastHandshakeAt = lp.LastHandshake
			p.RxBytesTotal = lp.Rx
			p.TxBytesTotal = lp.Tx
		}
		peers = append(peers, p)
	}
	return peers
}

// clientConfigInput is the data needed to render a wg client .conf.
type clientConfigInput struct {
	ClientPrivateKey string
	ClientAddress    string
	DNS              string
	MTU              int
	ServerPublicKey  string
	PresharedKey     string
	Endpoint         string
}

func renderClientConfig(in clientConfigInput) string {
	var b strings.Builder
	fmt.Fprintln(&b, "# WireGuard client config")
	fmt.Fprintln(&b, "# Generated by vpn-agent on", time.Now().UTC().Format(time.RFC3339))
	fmt.Fprintln(&b, "# DNS via AdGuard Home (Quad9 DoH upstream, blocks ads/trackers)")
	fmt.Fprintln(&b)
	fmt.Fprintln(&b, "[Interface]")
	fmt.Fprintln(&b, "PrivateKey =", in.ClientPrivateKey)
	fmt.Fprintln(&b, "Address    =", in.ClientAddress)
	fmt.Fprintln(&b, "DNS        =", in.DNS)
	// MTU 1280 is safe for any path including cellular/hotspot.
	// Higher values cause silent packet drops on iPhone tethering
	// and other constrained links.
	fmt.Fprintln(&b, "MTU        = 1280")
	fmt.Fprintln(&b)
	// NOTE: PostUp/PostDown are NOT in the .conf because wg-quick
	// on macOS fails to parse multiline heredoc rules. Instead,
	// firewall (socketfilterfw) and DNS/IPv6 leak protection are
	// handled by the Flutter app in vpn_tunnel.dart before/after
	// calling wg-quick.
	fmt.Fprintln(&b, "[Peer]")
	fmt.Fprintln(&b, "PublicKey           =", in.ServerPublicKey)
	fmt.Fprintln(&b, "PresharedKey        =", in.PresharedKey)
	fmt.Fprintln(&b, "Endpoint            =", in.Endpoint)
	// Use split-route /1 subnets instead of /0 to avoid clobbering
	// the default gateway on macOS. wg-quick on macOS has trouble
	// replacing the default route with 0.0.0.0/0; the two /1 routes
	// cover the full address space while keeping the original gateway
	// intact. Same trick for IPv6.
	fmt.Fprintln(&b, "AllowedIPs          = 0.0.0.0/1, 128.0.0.0/1, ::/1, 8000::/1")
	fmt.Fprintln(&b, "PersistentKeepalive = 25")
	return b.String()
}

// flockExclusive acquires an exclusive flock on path. The returned
// closure releases it. Path is created mode 0600 if it does not exist.
func flockExclusive(path string) (func(), error) {
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return nil, err
	}
	f, err := os.OpenFile(path, os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		return nil, err
	}
	if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX); err != nil {
		f.Close()
		return nil, err
	}
	return func() {
		_ = syscall.Flock(int(f.Fd()), syscall.LOCK_UN)
		f.Close()
	}, nil
}

// ip helpers

func networkRange(n *net.IPNet) (first, last net.IP) {
	first = n.IP.To4()
	if first == nil {
		// Only IPv4 supported in M2.
		return nil, nil
	}
	last = make(net.IP, 4)
	copy(last, first)
	for i := 0; i < 4; i++ {
		last[i] |= ^n.Mask[i]
	}
	return first, last
}

func nextIP(ip net.IP) net.IP {
	out := make(net.IP, len(ip))
	copy(out, ip)
	for i := len(out) - 1; i >= 0; i-- {
		out[i]++
		if out[i] != 0 {
			return out
		}
	}
	return out
}

func ipEqual(a, b net.IP) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}
