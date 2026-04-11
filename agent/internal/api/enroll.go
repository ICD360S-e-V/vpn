// ICD360SVPN — internal/api/enroll.go
//
// Public enrollment endpoint. Listens on the agent's plaintext
// 127.0.0.1:8081 listener (NOT the mTLS one) and is reverse-proxied
// by nginx so the user can hit `https://vpn.icd360s.de/enroll`
// BEFORE they have a WireGuard tunnel.
//
// The endpoint accepts a 16-char one-time code (issued by the CLI
// `vpn-agent issue-code <name>`) and returns the bundle JSON
// containing the admin client cert + the WireGuard peer config the
// app needs to bring up its tunnel.

package api

import (
	"encoding/json"
	"errors"
	"net"
	"net/http"
	"strings"
	"time"

	"github.com/ICD360S-e-V/vpn/agent/internal/enroll"
)

// failureBackoff slows down brute-force attempts after a 4xx response.
// Bounds an attacker (single connection) at ~4 req/sec regardless of
// IP rotation. The genuine user only ever waits this once on a typo.
const failureBackoff = 250 * time.Millisecond

type enrollRequest struct {
	Code string `json:"code"`
}

// postEnroll handles `POST /v1/enroll`.
//
// Body: {"code": "XXXX-XXXX-XXXX-XXXX"} (dashes optional, case insensitive)
// Success: 200 OK with the raw bundle JSON in the body.
// Failure: 400 (bad code format), 404 (code not found / expired / used),
//          429 (rate limited).
func (h *handlers) postEnroll(w http.ResponseWriter, r *http.Request) {
	if h.cfg.EnrollStore == nil {
		writeError(w, http.StatusServiceUnavailable, "enroll-disabled",
			"enrollment is not configured on this agent")
		return
	}
	if r.Body == nil {
		writeError(w, http.StatusBadRequest, "missing-body", "request body is required")
		return
	}
	defer r.Body.Close()

	// Server-wide rate limit (M7.1.1: dropped per-IP keying because
	// IP-based limits are theatre against an IP-rotating attacker
	// and unfair to legit users behind carrier-grade NAT). The IP
	// is still recorded in the audit log via the request middleware
	// but is no longer used to gate the request.
	if h.cfg.EnrollLimiter != nil && !h.cfg.EnrollLimiter.Allow("global") {
		writeError(w, http.StatusTooManyRequests, "rate-limited",
			"server-wide enrollment rate limit hit, try again in a minute")
		return
	}

	var req enrollRequest
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	if err := dec.Decode(&req); err != nil {
		time.Sleep(failureBackoff)
		writeError(w, http.StatusBadRequest, "invalid-json", err.Error())
		return
	}

	normalized, err := enroll.Normalize(req.Code)
	if err != nil {
		time.Sleep(failureBackoff)
		writeError(w, http.StatusBadRequest, "invalid-code", err.Error())
		return
	}

	bundle, err := h.cfg.EnrollStore.PopValid(normalized)
	if err != nil {
		// Slow down a bit. Bounds the brute-force rate well below
		// what would matter against a 32^16 keyspace anyway.
		time.Sleep(failureBackoff)
		if errors.Is(err, enroll.ErrNotFound) {
			// Don't reveal whether the code was wrong vs expired vs used.
			writeError(w, http.StatusNotFound, "code-not-found",
				"the code is invalid, expired, or already used")
			return
		}
		writeError(w, http.StatusInternalServerError, "enroll-lookup-failed", err.Error())
		return
	}

	// The bundle is already valid JSON; we just pass it through.
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(bundle)
}

// callerIPForRateLimit picks the client IP behind nginx. We trust the
// X-Forwarded-For / X-Real-IP headers since the enroll listener only
// binds 127.0.0.1 — only nginx can talk to it, so the headers are
// guaranteed to be set by nginx, not a remote client.
func callerIPForRateLimit(r *http.Request) string {
	if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
		// XFF can be a comma-separated list — take the leftmost (the
		// original client) which nginx writes first.
		if i := strings.Index(xff, ","); i >= 0 {
			return strings.TrimSpace(xff[:i])
		}
		return strings.TrimSpace(xff)
	}
	if xri := r.Header.Get("X-Real-IP"); xri != "" {
		return strings.TrimSpace(xri)
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}
