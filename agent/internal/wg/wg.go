package wg

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
)

// Manager owns the wg0.conf file and applies live changes to the
// running interface via `wg syncconf`.
type Manager struct {
	confPath  string
	iface     string
	subnet    *net.IPNet
	publicEnd string

	mu sync.Mutex // serialises in-process callers; flock guards across processes
}

// Peer is the typed representation of a single WireGuard peer combining
// static config (from wg0.conf) and runtime state (from `wg show dump`).
type Peer struct {
	Name            string    `json:"name"`
	PublicKey       string    `json:"public_key"`
	PresharedKey    string    `json:"-"` // never returned over the API
	AllowedIPs      []string  `json:"allowed_ips"`
	CreatedAt       time.Time `json:"created_at"`
	CreatedBy       string    `json:"created_by,omitempty"`
	Endpoint        string    `json:"endpoint,omitempty"`
	LastHandshakeAt *time.Time `json:"last_handshake_at,omitempty"`
	RxBytesTotal    uint64    `json:"rx_bytes_total"`
	TxBytesTotal    uint64    `json:"tx_bytes_total"`
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

// NewManager constructs a Manager. confPath is /etc/wireguard/wg0.conf,
// iface is "wg0", subnet is the CIDR the server uses (e.g. 10.8.0.0/24),
// publicEnd is the externally-reachable Endpoint clients should dial
// (e.g. "vpn.icd360s.de:443").
func NewManager(confPath, iface, subnet, publicEnd string) (*Manager, error) {
	_, ipnet, err := net.ParseCIDR(subnet)
	if err != nil {
		return nil, fmt.Errorf("invalid subnet %q: %w", subnet, err)
	}
	return &Manager{
		confPath:  confPath,
		iface:     iface,
		subnet:    ipnet,
		publicEnd: publicEnd,
	}, nil
}

// List returns the current peers, joining static config from wg0.conf
// with live transfer/handshake data from `wg show dump`.
func (m *Manager) List(ctx context.Context) ([]Peer, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	cfg, err := readConfigFile(m.confPath)
	if err != nil {
		return nil, fmt.Errorf("read wg0.conf: %w", err)
	}
	live, err := m.dumpLive(ctx)
	if err != nil {
		// Non-fatal: we can still return static peer list without live data.
		live = nil
	}
	return mergeConfigAndLive(cfg, live), nil
}

// Add generates fresh keys + PSK, allocates the next free /32 in the
// subnet, appends a [Peer] block to wg0.conf, applies the change with
// `wg syncconf`, and returns the rendered client .conf.
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

	priv, pub, err := wgGenKeyPair(ctx)
	if err != nil {
		return nil, fmt.Errorf("generate keys: %w", err)
	}
	psk, err := wgGenPSK(ctx)
	if err != nil {
		return nil, fmt.Errorf("generate psk: %w", err)
	}

	allowed := clientIP.String() + "/32"
	cfg.addPeer(pub, psk, allowed, req.Name, req.CreatedBy)

	if err := writeConfigFile(m.confPath, cfg); err != nil {
		return nil, fmt.Errorf("write wg0.conf: %w", err)
	}
	if err := m.syncConf(ctx); err != nil {
		return nil, fmt.Errorf("apply via wg syncconf: %w", err)
	}

	serverPub, err := m.serverPublicKey(ctx)
	if err != nil {
		return nil, fmt.Errorf("read server pubkey: %w", err)
	}

	clientConf := renderClientConfig(clientConfigInput{
		ClientPrivateKey: priv,
		ClientAddress:    allowed,
		DNS:              "10.8.0.1",
		MTU:              1420,
		ServerPublicKey:  serverPub,
		PresharedKey:     psk,
		Endpoint:         m.publicEnd,
	})

	peer := Peer{
		Name:         req.Name,
		PublicKey:    pub,
		AllowedIPs:   []string{allowed},
		CreatedAt:    time.Now().UTC(),
		CreatedBy:    req.CreatedBy,
	}
	return &CreateResult{Peer: peer, ClientConfig: clientConf}, nil
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
	return m.syncConf(ctx)
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

// dumpLive runs `wg show <iface> dump` and parses each peer line.
//
// Format of `wg show <iface> dump` (man wg, section "Output Format"):
//
//	First line  (interface): private-key  public-key  listen-port  fwmark
//	Other lines (peers):     public-key  preshared-key  endpoint  allowed-ips  latest-handshake  rx  tx  persistent-keepalive
//
// Fields are tab-separated. Empty values are reported as "(none)".
func (m *Manager) dumpLive(ctx context.Context) (map[string]livePeer, error) {
	out, err := exec.CommandContext(ctx, "wg", "show", m.iface, "dump").Output()
	if err != nil {
		return nil, fmt.Errorf("wg show dump: %w", err)
	}
	live := map[string]livePeer{}
	for i, line := range strings.Split(strings.TrimRight(string(out), "\n"), "\n") {
		if i == 0 {
			continue // interface line
		}
		fields := strings.Split(line, "\t")
		if len(fields) < 8 {
			continue
		}
		lp := livePeer{
			PublicKey: fields[0],
			Endpoint:  noneToEmpty(fields[2]),
		}
		if hs, err := strconv.ParseInt(fields[4], 10, 64); err == nil && hs > 0 {
			t := time.Unix(hs, 0).UTC()
			lp.LastHandshake = &t
		}
		if rx, err := strconv.ParseUint(fields[5], 10, 64); err == nil {
			lp.Rx = rx
		}
		if tx, err := strconv.ParseUint(fields[6], 10, 64); err == nil {
			lp.Tx = tx
		}
		live[lp.PublicKey] = lp
	}
	return live, nil
}

// serverPublicKey returns the server's WG public key from `wg show
// <iface> dump`. Reading it from the running interface avoids touching
// the private key file.
func (m *Manager) serverPublicKey(ctx context.Context) (string, error) {
	out, err := exec.CommandContext(ctx, "wg", "show", m.iface, "dump").Output()
	if err != nil {
		return "", err
	}
	lines := strings.Split(string(out), "\n")
	if len(lines) == 0 {
		return "", errors.New("empty wg show output")
	}
	fields := strings.Split(lines[0], "\t")
	if len(fields) < 2 {
		return "", errors.New("malformed wg show interface line")
	}
	return fields[1], nil
}

// syncConf applies the on-disk wg0.conf to the live interface without
// disrupting existing connections.
//
// We do not use `bash -c "wg syncconf wg0 <(wg-quick strip wg0)"`
// because shelling out to bash adds an attack surface and brittle
// quoting. Instead: run wg-quick strip to a buffer, write to a temp
// file, pass the path to wg syncconf.
func (m *Manager) syncConf(ctx context.Context) error {
	stripped, err := exec.CommandContext(ctx, "wg-quick", "strip", m.iface).Output()
	if err != nil {
		return fmt.Errorf("wg-quick strip: %w", err)
	}
	tmp, err := os.CreateTemp("", "wg-syncconf-*.conf")
	if err != nil {
		return err
	}
	tmpPath := tmp.Name()
	defer os.Remove(tmpPath)
	if _, err := tmp.Write(stripped); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	cmd := exec.CommandContext(ctx, "wg", "syncconf", m.iface, tmpPath)
	if out, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("wg syncconf: %w (%s)", err, bytes.TrimSpace(out))
	}
	return nil
}

// livePeer is the per-peer data extracted from `wg show dump`.
type livePeer struct {
	PublicKey     string
	Endpoint      string
	LastHandshake *time.Time
	Rx            uint64
	Tx            uint64
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
		p := Peer{
			Name:         s.Meta["name"],
			PublicKey:    pub,
			PresharedKey: psk,
			AllowedIPs:   allowed,
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
	fmt.Fprintln(&b, "MTU        =", in.MTU)
	fmt.Fprintln(&b)
	fmt.Fprintln(&b, "[Peer]")
	fmt.Fprintln(&b, "PublicKey           =", in.ServerPublicKey)
	fmt.Fprintln(&b, "PresharedKey        =", in.PresharedKey)
	fmt.Fprintln(&b, "Endpoint            =", in.Endpoint)
	fmt.Fprintln(&b, "AllowedIPs          = 0.0.0.0/0, ::/0")
	fmt.Fprintln(&b, "PersistentKeepalive = 25")
	return b.String()
}

// wgGenKeyPair runs `wg genkey | wg pubkey` and returns the (priv,pub) pair.
func wgGenKeyPair(ctx context.Context) (string, string, error) {
	priv, err := exec.CommandContext(ctx, "wg", "genkey").Output()
	if err != nil {
		return "", "", err
	}
	privTrim := strings.TrimSpace(string(priv))
	pubCmd := exec.CommandContext(ctx, "wg", "pubkey")
	pubCmd.Stdin = strings.NewReader(privTrim + "\n")
	pub, err := pubCmd.Output()
	if err != nil {
		return "", "", err
	}
	return privTrim, strings.TrimSpace(string(pub)), nil
}

// wgGenPSK runs `wg genpsk` and returns the resulting key.
func wgGenPSK(ctx context.Context) (string, error) {
	out, err := exec.CommandContext(ctx, "wg", "genpsk").Output()
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(out)), nil
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

func noneToEmpty(s string) string {
	if s == "(none)" {
		return ""
	}
	return s
}
