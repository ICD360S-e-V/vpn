package api

import (
	"encoding/json"
	"errors"
	"net/http"
	"strings"

	"github.com/ICD360S-e-V/vpn/agent/internal/wg"
)

// peerCreateRequest matches PeerCreateRequest in proto/openapi.yaml.
type peerCreateRequest struct {
	Name string `json:"name"`
}

// peerCreateResponse matches PeerCreateResponse in proto/openapi.yaml.
type peerCreateResponse struct {
	Peer         wg.Peer `json:"peer"`
	ClientConfig string  `json:"client_config"`
}

// listPeers handles GET /v1/peers.
func (h *handlers) listPeers(w http.ResponseWriter, r *http.Request) {
	peers, err := h.cfg.WG.List(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, "list-peers-failed", err.Error())
		return
	}
	if peers == nil {
		peers = []wg.Peer{}
	}
	writeJSON(w, http.StatusOK, peers)
}

// createPeer handles POST /v1/peers.
func (h *handlers) createPeer(w http.ResponseWriter, r *http.Request) {
	if r.Body == nil {
		writeError(w, http.StatusBadRequest, "missing-body", "request body is required")
		return
	}
	defer r.Body.Close()

	var req peerCreateRequest
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	if err := dec.Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid-json", err.Error())
		return
	}
	req.Name = strings.TrimSpace(req.Name)
	if req.Name == "" {
		writeError(w, http.StatusBadRequest, "missing-name", "field 'name' is required")
		return
	}

	createdBy := callerCN(r)
	res, err := h.cfg.WG.Add(r.Context(), wg.CreateRequest{
		Name:      req.Name,
		CreatedBy: createdBy,
	})
	if err != nil {
		writeError(w, http.StatusInternalServerError, "create-peer-failed", err.Error())
		return
	}
	writeJSON(w, http.StatusCreated, peerCreateResponse{
		Peer:         res.Peer,
		ClientConfig: res.ClientConfig,
	})
}

// deletePeer handles DELETE /v1/peers/{pubkey}.
func (h *handlers) deletePeer(w http.ResponseWriter, r *http.Request) {
	pubkey := r.PathValue("pubkey")
	if pubkey == "" {
		writeError(w, http.StatusBadRequest, "missing-pubkey", "path parameter 'pubkey' is required")
		return
	}
	if err := h.cfg.WG.Remove(r.Context(), pubkey); err != nil {
		if errors.Is(err, wg.ErrPeerNotFound) {
			writeError(w, http.StatusNotFound, "peer-not-found", "no peer with that public key")
			return
		}
		writeError(w, http.StatusInternalServerError, "remove-peer-failed", err.Error())
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// callerCN extracts the CommonName of the verified client cert.
func callerCN(r *http.Request) string {
	if r.TLS == nil || len(r.TLS.PeerCertificates) == 0 {
		return ""
	}
	return r.TLS.PeerCertificates[0].Subject.CommonName
}
