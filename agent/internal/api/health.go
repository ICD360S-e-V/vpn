package api

import (
	"context"
	"net/http"
	"os/exec"
	"time"
)

// handlers groups the dependencies that route handlers need. Currently
// just the agent's Config; will grow with M2 (DB, wg layer, etc.).
type handlers struct {
	cfg Config
}

// healthResponse is the wire shape for GET /v1/health.
// Keep in sync with proto/openapi.yaml#/components/schemas/Health.
type healthResponse struct {
	Status        string    `json:"status"`
	WGUp          bool      `json:"wg_up"`
	AdGuardUp     bool      `json:"adguard_up"`
	UptimeSeconds int64     `json:"uptime_seconds"`
	AgentVersion  string    `json:"agent_version"`
	ServerTime    time.Time `json:"server_time"`
}

func (h *handlers) health(w http.ResponseWriter, r *http.Request) {
	wgUp := wgInterfaceUp(r.Context(), h.cfg.WGInterface)
	agUp := adguardUp(r.Context(),
		h.cfg.AdGuardURL, h.cfg.AdGuardUser, h.cfg.AdGuardPass)

	resp := healthResponse{
		Status:        "ok",
		WGUp:          wgUp,
		AdGuardUp:     agUp,
		UptimeSeconds: int64(time.Since(h.cfg.Started).Seconds()),
		AgentVersion:  h.cfg.Version,
		ServerTime:    time.Now().UTC(),
	}
	if !wgUp || !agUp {
		resp.Status = "degraded"
	}
	writeJSON(w, http.StatusOK, resp)
}

// wgInterfaceUp returns true if `wg show <iface>` exits 0 within 2s.
// We deliberately call the `wg` binary instead of opening a netlink
// socket: it is the same code path WireGuard upstream uses, fewer
// surprises.
func wgInterfaceUp(ctx context.Context, iface string) bool {
	ctx, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()
	return exec.CommandContext(ctx, "wg", "show", iface).Run() == nil
}

// adguardUp probes AdGuard Home's /control/status endpoint. Status
// requires basic auth in current AdGuard Home releases.
func adguardUp(ctx context.Context, url, user, pass string) bool {
	ctx, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url+"/control/status", nil)
	if err != nil {
		return false
	}
	if user != "" {
		req.SetBasicAuth(user, pass)
	}
	cli := &http.Client{Timeout: 3 * time.Second}
	resp, err := cli.Do(req)
	if err != nil {
		return false
	}
	defer resp.Body.Close()
	return resp.StatusCode == http.StatusOK
}
