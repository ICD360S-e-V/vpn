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
//	vpn-agent issue-bundle <name> [flgs] Issue a client cert as a single
//	                                     base64-gzip-json blob ready to
//	                                     paste into the admin app
//	vpn-agent version                    Print version
package main

import (
	"bytes"
	"compress/gzip"
	"context"
	"encoding/base64"
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
	case "issue-bundle":
		cmdIssueBundle(args)
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
    vpn-agent issue-cert   <name> [flags]   Issue a client cert as 3 PEM files
    vpn-agent issue-bundle <name> [flags]   Issue a client cert as a single
                                            base64-gzip-json blob ready to paste
                                            into the admin app's enrollment field
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

	srv, err := api.NewServer(api.Config{
		Listen:      *listenAddr,
		WGInterface: *wgIface,
		AdGuardURL:  *adguardURL,
		AdGuardUser: *adguardUser,
		AdGuardPass: *adguardPass,
		CA:          ca,
		ServerCert:  serverCert,
		WG:          wgMgr,
		Stats:       statsStore,
		Version:     version,
		Started:     time.Now(),
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

// enrollmentBundle is the JSON wire format embedded inside the
// `vpn-agent issue-bundle` output. The `Version` field lets the
// Flutter admin app refuse incompatible bundles cleanly. Bumped
// whenever fields are added or removed.
type enrollmentBundle struct {
	Version  int       `json:"version"`
	Name     string    `json:"name"`
	IssuedAt time.Time `json:"issued_at"`
	AgentURL string    `json:"agent_url"`
	CertPEM  string    `json:"cert_pem"`
	KeyPEM   string    `json:"key_pem"`
	CAPEM    string    `json:"ca_pem"`
}

const enrollmentBundleVersion = 1

// cmdIssueBundle handles `vpn-agent issue-bundle <name>`.
//
// It generates a fresh client cert + key signed by the local CA,
// bundles them with the CA cert and the agent URL into a JSON, gzips
// it, base64-encodes it, and prints the resulting single-line blob to
// stdout (followed by a newline). The admin pastes that blob into the
// macOS / Flutter app's enrollment field — one input, no copying
// three separate PEMs.
//
// The output is intentionally a single ASCII-safe line so it survives
// being copied through SSH terminals, Slack messages, or printed
// instructions. Standard base64 (not URL-safe) is used because the
// blob is not embedded in URLs.
func cmdIssueBundle(args []string) {
	fs := flag.NewFlagSet("issue-bundle", flag.ExitOnError)
	certDir := fs.String("cert-dir", "/etc/vpn-agent",
		"directory containing the CA")
	agentURL := fs.String("agent-url", "https://10.8.0.1:8443",
		"URL the admin app should dial — must be reachable through the WireGuard tunnel")
	wrap := fs.Bool("wrap", false,
		"wrap the output at 76 columns for human readability (the app accepts both forms)")
	if err := fs.Parse(args); err != nil {
		os.Exit(2)
	}
	if fs.NArg() < 1 {
		fmt.Fprintln(os.Stderr, "issue-bundle requires a name argument, e.g. 'andrei-laptop'")
		fmt.Fprintln(os.Stderr, "all flags must appear BEFORE the name")
		os.Exit(2)
	}
	name := fs.Arg(0)

	ca, err := mtls.LoadOrCreateCA(*certDir)
	if err != nil {
		slog.Error("CA load failed", "err", err)
		os.Exit(1)
	}
	certPEM, keyPEM, caPEM, err := ca.IssueClientCertPEM(name)
	if err != nil {
		slog.Error("issue failed", "err", err)
		os.Exit(1)
	}

	bundle := enrollmentBundle{
		Version:  enrollmentBundleVersion,
		Name:     name,
		IssuedAt: time.Now().UTC(),
		AgentURL: *agentURL,
		CertPEM:  string(certPEM),
		KeyPEM:   string(keyPEM),
		CAPEM:    string(caPEM),
	}
	jsonBytes, err := json.Marshal(bundle)
	if err != nil {
		slog.Error("marshal bundle", "err", err)
		os.Exit(1)
	}

	var gzbuf bytes.Buffer
	gz := gzip.NewWriter(&gzbuf)
	if _, err := gz.Write(jsonBytes); err != nil {
		slog.Error("gzip bundle", "err", err)
		os.Exit(1)
	}
	if err := gz.Close(); err != nil {
		slog.Error("gzip close", "err", err)
		os.Exit(1)
	}

	encoded := base64.StdEncoding.EncodeToString(gzbuf.Bytes())

	if *wrap {
		// Wrap at 76 columns for emails / printed runbooks. The app
		// strips whitespace before decoding, so both forms work.
		for i := 0; i < len(encoded); i += 76 {
			end := i + 76
			if end > len(encoded) {
				end = len(encoded)
			}
			fmt.Println(encoded[i:end])
		}
	} else {
		fmt.Println(encoded)
	}

	// Friendly footer on stderr so it does not get captured into a
	// pipe but is still visible to a human running the command.
	fmt.Fprintf(os.Stderr,
		"\n# enrollment bundle for %q (%d bytes raw, %d bytes encoded)\n"+
			"# paste the line(s) above into the admin app's enrollment field.\n",
		name, len(jsonBytes), len(encoded))
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
