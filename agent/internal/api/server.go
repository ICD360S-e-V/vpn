// Package api wires the HTTPS server, mTLS configuration, and route
// handlers for the vpn-agent daemon.
package api

import (
	"context"
	"crypto/tls"
	"errors"
	"log/slog"
	"net/http"
	"time"

	"github.com/ICD360S-e-V/vpn/agent/internal/mtls"
	"github.com/ICD360S-e-V/vpn/agent/internal/wg"
)

// Config carries everything NewServer needs. Built once in main and
// passed in.
type Config struct {
	Listen      string
	WGInterface string
	AdGuardURL  string
	AdGuardUser string
	AdGuardPass string
	CA          *mtls.CA
	ServerCert  tls.Certificate
	WG          *wg.Manager
	Version     string
	Started     time.Time
}

// Server wraps an *http.Server with our typed config.
type Server struct {
	cfg Config
	srv *http.Server
}

// NewServer constructs the routes and the underlying *http.Server with
// mTLS enforced.
func NewServer(cfg Config) (*Server, error) {
	mux := http.NewServeMux()
	h := &handlers{cfg: cfg}

	// All routes are versioned. Adding a new route?
	// 1. Define the handler in this package.
	// 2. Register it here.
	// 3. Update proto/openapi.yaml.
	mux.HandleFunc("GET /v1/health", h.health)
	mux.HandleFunc("GET /v1/peers", h.listPeers)
	mux.HandleFunc("POST /v1/peers", h.createPeer)
	mux.HandleFunc("PATCH /v1/peers/{pubkey}", h.patchPeer)
	mux.HandleFunc("DELETE /v1/peers/{pubkey}", h.deletePeer)

	tlsCfg := &tls.Config{
		Certificates: []tls.Certificate{cfg.ServerCert},
		ClientAuth:   tls.RequireAndVerifyClientCert,
		ClientCAs:    cfg.CA.Pool,
		MinVersion:   tls.VersionTLS13,
		NextProtos:   []string{"h2", "http/1.1"},
	}

	srv := &http.Server{
		Addr:              cfg.Listen,
		Handler:           withLogging(mux),
		TLSConfig:         tlsCfg,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	return &Server{cfg: cfg, srv: srv}, nil
}

// Run blocks until ctx is cancelled or the server crashes. On ctx
// cancellation it performs a graceful shutdown with a 5-second timeout.
func (s *Server) Run(ctx context.Context) error {
	errCh := make(chan error, 1)
	go func() {
		// Empty cert/key paths because TLSConfig.Certificates is set.
		err := s.srv.ListenAndServeTLS("", "")
		if err != nil && !errors.Is(err, http.ErrServerClosed) {
			errCh <- err
			return
		}
		errCh <- nil
	}()

	select {
	case <-ctx.Done():
		slog.Info("shutdown signal received, draining connections")
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		return s.srv.Shutdown(shutdownCtx)
	case err := <-errCh:
		return err
	}
}
