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
//	vpn-agent issue-cert <name> [flags]  Issue a client cert (signed by the
//	                                     local CA) to bootstrap a new admin
//	vpn-agent version                    Print version
package main

import (
	"context"
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
    vpn-agent serve [flags]               Run the HTTPS API server (mTLS required)
    vpn-agent issue-cert <name> [flags]   Issue a client cert signed by the local CA
    vpn-agent version                     Print version

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

	srv, err := api.NewServer(api.Config{
		Listen:      *listenAddr,
		WGInterface: *wgIface,
		AdGuardURL:  *adguardURL,
		AdGuardUser: *adguardUser,
		AdGuardPass: *adguardPass,
		CA:          ca,
		ServerCert:  serverCert,
		WG:          wgMgr,
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

	slog.Info("vpn-agent starting",
		"listen", *listenAddr,
		"version", version,
		"wg_interface", *wgIface,
		"wg_config", *wgConfig,
		"wg_subnet", *wgSubnet,
		"public_endpoint", *publicEnd,
		"adguard_url", *adguardURL,
	)
	if err := srv.Run(ctx); err != nil {
		slog.Error("server exited with error", "err", err)
		os.Exit(1)
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
