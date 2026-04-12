package api

import (
	"encoding/json"
	"net/http"
)

// configRefreshRequest is the body for POST /v1/config/refresh.
type configRefreshRequest struct {
	PublicKey  string `json:"public_key"`
	PrivateKey string `json:"private_key"`
}

// configRefreshResponse wraps the updated WireGuard client config.
type configRefreshResponse struct {
	WireguardConfig string `json:"wireguard_config"`
}

// refreshConfig handles POST /v1/config/refresh.
// The client sends its WG public key + private key (which the server
// never stores), and gets back a fresh .conf with current server
// settings (AllowedIPs, MTU, DNS, endpoint).
func (h *handlers) refreshConfig(w http.ResponseWriter, r *http.Request) {
	if r.Body == nil {
		writeError(w, http.StatusBadRequest, "missing-body", "request body required")
		return
	}
	var req configRefreshRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "bad-json", err.Error())
		return
	}
	if req.PublicKey == "" || req.PrivateKey == "" {
		writeError(w, http.StatusBadRequest, "missing-fields", "public_key and private_key are required")
		return
	}

	conf, err := h.cfg.WG.RefreshConfig(r.Context(), req.PublicKey, req.PrivateKey)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "refresh-failed", err.Error())
		return
	}
	if conf == "" {
		writeError(w, http.StatusNotFound, "peer-not-found", "no peer with that public key")
		return
	}

	writeJSON(w, http.StatusOK, configRefreshResponse{WireguardConfig: conf})
}
