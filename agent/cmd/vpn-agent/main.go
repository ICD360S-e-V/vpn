// Command vpn-agent is the management daemon that runs on vpn.icd360s.de
// and exposes a typed JSON API over mTLS for the macOS admin app.
//
// It binds only on private/loopback interfaces (refuses public IPs) and
// validates client certificates against an internally-managed CA. The CA,
// server cert, and key are auto-generated on first run under --cert-dir.
//
// Subcommands:
//
//	vpn-agent serve [flags]              Run the HTTP server
//	vpn-agent issue-cert <name> [flags]  Issue a client cert as 3 PEM files
//	vpn-agent issue-code <name> [flags]  Issue a one-time XXXX-XXXX-XXXX-XXXX
//	                                     code that the admin app exchanges
//	                                     for an enrollment bundle (admin
//	                                     cert + WireGuard peer config)
//	vpn-agent version                    Print version
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log/slog"
	"net"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/ICD360S-e-V/vpn/agent/internal/api"
	"github.com/ICD360S-e-V/vpn/agent/internal/enroll"
	"github.com/ICD360S-e-V/vpn/agent/internal/mtls"
	"github.com/ICD360S-e-V/vpn/agent/internal/stats"
	"github.com/ICD360S-e-V/vpn/agent/internal/wg"
)

// version is overridden at build time via -ldflags '-X main.version=...'.
var version = "0.0.1-m1"

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(2)
	}

	logger := slog.New(slog.NewJSONHandler(os.Stderr, &slog.HandlerOptions{
		Level: slog.LevelInfo,
	}))
	slog.SetDefault(logger)

	cmd, args := os.Args[1], os.Args[2:]
	switch cmd {
	case "serve":
		cmdServe(args)
	case "issue-cert":
		cmdIssueCert(args)
	case "issue-code":
		cmdIssueCode(args)
	case "version", "--version", "-v":
		fmt.Println("vpn-agent", version)
	case "help", "--help", "-h":
		usage()
	default:
		fmt.Fprintf(os.Stderr, "unknown command: %q\n\n", cmd)
		usage()
		os.Exit(2)
	}
}

func usage() {
	fmt.Fprint(os.Stderr, `vpn-agent — ICD360S VPN management daemon

Usage:
    vpn-agent serve [flags]                 Run the HTTPS API server (mTLS required)
    vpn-agent issue-cert <name> [flags]     Issue a client cert as 3 PEM files
                                            (legacy / scripting workflow)
    vpn-agent issue-code <name> [flags]     Issue a one-time XXXX-XXXX-XXXX-XXXX
                                            enrollment code. The user types it
                                            into the admin app and the app
                                            exchanges it for the bundle
                                            (admin cert + WireGuard peer config)
                                            via POST https://vpn.icd360s.de/enroll
    vpn-agent version                       Print version

Run "vpn-agent <command> -h" for command-specific flags.
`)
}

func cmdServe(args []string) {
	fs := flag.NewFlagSet("serve", flag.ExitOnError)
	listenAddr := fs.String("listen", "10.8.0.1:8443",
		"address to listen on — must be a private/loopback IP, never public")
	certDir := fs.String("cert-dir", "/etc/vpn-agent",
		"directory holding the CA + server cert + key")
	wgIface := fs.String("wg-interface", "wg0",
		"WireGuard interface to monitor")
	wgConfig := fs.String("wg-config", "/etc/wireguard/wg0.conf",
		"path to the WireGuard server config file")
	wgSubnet := fs.String("wg-subnet", "10.8.0.0/24",
		"CIDR of the VPN client subnet")
	publicEnd := fs.String("public-endpoint", "vpn.icd360s.de:443",
		"public endpoint clients should dial in their .conf")
	adguardURL := fs.String("adguard-url", "http://10.8.0.1:3000",
		"AdGuard Home base URL")
	adguardUser := fs.String("adguard-user", "admin",
		"AdGuard Home basic auth username")
	adguardPass := fs.String("adguard-pass", "admin",
		"AdGuard Home basic auth password")
	statsDB := fs.String("stats-db", "/var/lib/vpn-agent/stats.db",
		"sqlite database path for bandwidth samples")
	statsPeriod := fs.Duration("stats-period", 60*time.Second,
		"how often the sampler reads wgctrl byte counters")
	statsRetention := fs.Duration("stats-retention", 90*24*time.Hour,
		"how long to keep raw bandwidth samples before pruning")
	enrollListen := fs.String("enroll-listen", "127.0.0.1:8081",
		"plaintext listener for the public /enroll endpoint, behind nginx (empty disables)")
	enrollStorePath := fs.String("enroll-store", "/var/lib/vpn-agent/enrollment_codes.json",
		"file-backed store of pending enrollment codes")
	enrollRateLimit := fs.Int("enroll-rate-limit", 5,
		"max enrollment attempts per source IP per minute")
	if err := fs.Parse(args); err != nil {
		os.Exit(2)
	}

	// Refuse to start if the configured listen address is public.
	// Defense in depth: even if firewalld/NSG is misconfigured, we
	// fail closed.
	if err := refuseIfPublicListen(*listenAddr); err != nil {
		slog.Error("refusing to start", "err", err)
		os.Exit(1)
	}

	ca, err := mtls.LoadOrCreateCA(*certDir)
	if err != nil {
		slog.Error("CA setup failed", "err", err)
		os.Exit(1)
	}
	serverCert, err := ca.LoadOrIssueServerCert(*certDir, *listenAddr)
	if err != nil {
		slog.Error("server cert setup failed", "err", err)
		os.Exit(1)
	}

	wgMgr, err := wg.NewManager(*wgConfig, *wgIface, *wgSubnet, *publicEnd)
	if err != nil {
		slog.Error("wg manager setup failed", "err", err)
		os.Exit(1)
	}

	statsStore, err := stats.Open(*statsDB)
	if err != nil {
		slog.Error("stats store open failed", "err", err)
		os.Exit(1)
	}

	enrollStore := enroll.New(*enrollStorePath)
	enrollLimiter := api.NewRateLimiter(*enrollRateLimit, time.Minute)

	srv, err := api.NewServer(api.Config{
		Listen:        *listenAddr,
		EnrollListen:  *enrollListen,
		WGInterface:   *wgIface,
		AdGuardURL:    *adguardURL,
		AdGuardUser:   *adguardUser,
		AdGuardPass:   *adguardPass,
		CA:            ca,
		ServerCert:    serverCert,
		WG:            wgMgr,
		Stats:         statsStore,
		EnrollStore:   enrollStore,
		EnrollLimiter: enrollLimiter,
		Version:       version,
		Started:       time.Now(),
	})
	if err != nil {
		slog.Error("server build failed", "err", err)
		os.Exit(1)
	}

	ctx, stop := signal.NotifyContext(context.Background(),
		syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	// Start the bandwidth sampler in its own goroutine. It shares
	// the wgctrl client with the Manager so we don't open a second
	// netlink socket.
	sampler := stats.NewSampler(wgMgr.Client(), *wgIface, statsStore, *statsPeriod, *statsRetention)
	go func() {
		if err := sampler.Run(ctx); err != nil {
			slog.Error("sampler exited", "err", err)
		}
	}()

	slog.Info("vpn-agent starting",
		"listen", *listenAddr,
		"version", version,
		"wg_interface", *wgIface,
		"wg_config", *wgConfig,
		"wg_subnet", *wgSubnet,
		"public_endpoint", *publicEnd,
		"adguard_url", *adguardURL,
		"stats_db", *statsDB,
		"stats_period", *statsPeriod,
		"stats_retention", *statsRetention,
	)
	if err := srv.Run(ctx); err != nil {
		slog.Error("server exited with error", "err", err)
		os.Exit(1)
	}
	if err := statsStore.Close(); err != nil {
		slog.Warn("stats store close failed", "err", err)
	}
	if err := wgMgr.Close(); err != nil {
		slog.Warn("wg manager close failed", "err", err)
	}
	slog.Info("vpn-agent stopped cleanly")
}

func cmdIssueCert(args []string) {
	fs := flag.NewFlagSet("issue-cert", flag.ExitOnError)
	certDir := fs.String("cert-dir", "/etc/vpn-agent",
		"directory containing the CA")
	outDir := fs.String("out", ".",
		"output directory for <name>.pem, <name>.key, <name>-ca.pem")
	// Note: Go's flag package stops parsing at the first positional
	// argument, so callers must put all flags BEFORE the name:
	//   vpn-agent issue-cert --cert-dir /etc/vpn-agent --out . andrei-laptop
	// Putting flags after the name silently makes them ineffective.
	if err := fs.Parse(args); err != nil {
		os.Exit(2)
	}
	if fs.NArg() < 1 {
		fmt.Fprintln(os.Stderr, "issue-cert requires a name argument, e.g. 'andrei-laptop'")
		fmt.Fprintln(os.Stderr, "all flags must appear BEFORE the name")
		os.Exit(2)
	}
	name := fs.Arg(0)

	ca, err := mtls.LoadOrCreateCA(*certDir)
	if err != nil {
		slog.Error("CA load failed", "err", err)
		os.Exit(1)
	}
	if err := ca.IssueClientCert(name, *outDir); err != nil {
		slog.Error("issue failed", "err", err)
		os.Exit(1)
	}
	fmt.Printf("Issued client cert for %q in %s\n", name, *outDir)
	fmt.Printf("Files: %s.pem  %s.key  %s-ca.pem\n", name, name, name)
}

// enrollmentBundle is the JSON wire format the admin app downloads
// from `POST /v1/enroll`. Version 2 (M7.1) added the wireguard_*
// fields so the bundle now contains EVERYTHING the app needs to
// bring up its own tunnel — admins no longer have to import a
// separate `peer1.conf` into the standalone WireGuard.app first.
type enrollmentBundle struct {
	Version            int       `json:"version"`
	Name               string    `json:"name"`
	IssuedAt           time.Time `json:"issued_at"`
	AgentURL           string    `json:"agent_url"`
	CertPEM            string    `json:"cert_pem"`
	KeyPEM             string    `json:"key_pem"`
	CAPEM              string    `json:"ca_pem"`
	WireguardConfig    string    `json:"wireguard_config"`     // rendered .conf for WireGuard.app import
	WireguardPublicKey string    `json:"wireguard_public_key"` // for revoke later
	WireguardAddress   string    `json:"wireguard_address"`    // e.g. "10.8.0.7/32"
}

const enrollmentBundleVersion = 2

// cmdIssueCode handles `vpn-agent issue-code <name>`.
//
// 1. Generate a fresh admin client cert + key signed by the local CA.
// 2. Generate a fresh WireGuard peer (keys, PSK, allocated /32) and
//    add it to wg0.conf via the wg.Manager (same code path as
//    POST /v1/peers — atomic write + wgctrl apply).
// 3. Bundle everything as enrollmentBundleV2 JSON.
// 4. Generate a 16-char one-time code (XXXX-XXXX-XXXX-XXXX), store
//    the bundle under it in the file-backed enroll.Store with a 10-
//    minute TTL.
// 5. Print the code to stdout. The admin reads it to the user; the
//    user types it into the app; the app POSTs it to /v1/enroll and
//    receives the bundle.
func cmdIssueCode(args []string) {
	fs := flag.NewFlagSet("issue-code", flag.ExitOnError)
	certDir := fs.String("cert-dir", "/etc/vpn-agent",
		"directory containing the CA")
	agentURL := fs.String("agent-url", "https://10.8.0.1:8443",
		"URL the admin app should dial after enrolling — must be reachable through the WireGuard tunnel")
	wgConfig := fs.String("wg-config", "/etc/wireguard/wg0.conf",
		"WireGuard server config file")
	wgIface := fs.String("wg-interface", "wg0",
		"WireGuard interface to manage")
	wgSubnet := fs.String("wg-subnet", "10.8.0.0/24",
		"WireGuard subnet for peer IP allocation")
	publicEnd := fs.String("public-endpoint", "vpn.icd360s.de:443",
		"WireGuard public endpoint clients dial")
	enrollStorePath := fs.String("enroll-store", "/var/lib/vpn-agent/enrollment_codes.json",
		"file-backed store of pending enrollment codes")
	ttl := fs.Duration("ttl", enroll.DefaultTTL,
		"how long the issued code stays valid before it expires")
	if err := fs.Parse(args); err != nil {
		os.Exit(2)
	}
	if fs.NArg() < 1 {
		fmt.Fprintln(os.Stderr, "issue-code requires a name argument, e.g. 'andrei-laptop'")
		fmt.Fprintln(os.Stderr, "all flags must appear BEFORE the name")
		os.Exit(2)
	}
	name := fs.Arg(0)

	// Step 1: admin client cert.
	ca, err := mtls.LoadOrCreateCA(*certDir)
	if err != nil {
		slog.Error("CA load failed", "err", err)
		os.Exit(1)
	}
	certPEM, keyPEM, caPEM, err := ca.IssueClientCertPEM(name)
	if err != nil {
		slog.Error("issue cert failed", "err", err)
		os.Exit(1)
	}

	// Step 2: WireGuard peer via the same Manager the daemon uses.
	wgMgr, err := wg.NewManager(*wgConfig, *wgIface, *wgSubnet, *publicEnd)
	if err != nil {
		slog.Error("wg manager open failed", "err", err)
		os.Exit(1)
	}
	defer wgMgr.Close()

	created, err := wgMgr.Add(context.Background(), wg.CreateRequest{
		Name:      name,
		CreatedBy: "issue-code",
	})
	if err != nil {
		slog.Error("wg peer create failed", "err", err)
		os.Exit(1)
	}

	// Step 3: bundle.
	bundle := enrollmentBundle{
		Version:            enrollmentBundleVersion,
		Name:               name,
		IssuedAt:           time.Now().UTC(),
		AgentURL:           *agentURL,
		CertPEM:            string(certPEM),
		KeyPEM:             string(keyPEM),
		CAPEM:              string(caPEM),
		WireguardConfig:    created.ClientConfig,
		WireguardPublicKey: created.Peer.PublicKey,
	}
	if len(created.Peer.AllowedIPs) > 0 {
		bundle.WireguardAddress = created.Peer.AllowedIPs[0]
	}
	bundleJSON, err := json.Marshal(bundle)
	if err != nil {
		slog.Error("marshal bundle", "err", err)
		os.Exit(1)
	}

	// Step 4: code + store.
	code, err := enroll.Generate()
	if err != nil {
		slog.Error("code generate failed", "err", err)
		os.Exit(1)
	}
	normalized, err := enroll.Normalize(code)
	if err != nil {
		slog.Error("code normalize failed", "err", err)
		os.Exit(1)
	}
	store := enroll.New(*enrollStorePath)
	if err := store.PutNamed(normalized, name, bundleJSON, *ttl); err != nil {
		slog.Error("enroll store put failed", "err", err)
		os.Exit(1)
	}

	// Step 5: stdout = the code, stderr = friendly footer.
	fmt.Println(code)
	fmt.Fprintf(os.Stderr,
		"\n"+
			"# enrollment code for %q\n"+
			"# valid %s, single-use\n"+
			"# wireguard peer allocated: %s\n"+
			"# tell the user to type the code into the admin app's enrollment screen\n",
		name, ttl.Round(time.Second), bundle.WireguardAddress)
}

// refuseIfPublicListen returns nil if addr's host is loopback, link-local,
// or RFC1918 / RFC4193 private. Anything else is considered public and
// rejected.
func refuseIfPublicListen(addr string) error {
	host, _, err := net.SplitHostPort(addr)
	if err != nil {
		return fmt.Errorf("invalid listen address %q: %w", addr, err)
	}
	if host == "" || host == "0.0.0.0" || host == "::" {
		return fmt.Errorf("refuse to bind on %q — must specify a private interface IP", addr)
	}
	ip := net.ParseIP(host)
	if ip == nil {
		return fmt.Errorf("invalid IP literal in listen address: %q", host)
	}
	if ip.IsLoopback() || ip.IsPrivate() || ip.IsLinkLocalUnicast() {
		return nil
	}
	return fmt.Errorf("refuse to bind on %q — not loopback / private / link-local", host)
}
