// ICD360SVPN — internal/api/stats.go
// MARK: - Bandwidth stats endpoint

package api

import (
	"net/http"
	"time"
)

// getPeerBandwidth handles GET /v1/peers/{pubkey}/bandwidth
//
// Query params:
//
//	from        RFC 3339 timestamp (default: now - 24h)
//	to          RFC 3339 timestamp (default: now)
//	granularity minute | hour | day  (default: hour)
//
// Returns a `Series` JSON object: per-peer time series of RX/TX
// deltas at the requested bucket size.
func (h *handlers) getPeerBandwidth(w http.ResponseWriter, r *http.Request) {
	if h.cfg.Stats == nil {
		writeError(w, http.StatusServiceUnavailable, "stats-disabled",
			"the stats subsystem is not running on this agent")
		return
	}

	pubkey := r.PathValue("pubkey")
	if pubkey == "" {
		writeError(w, http.StatusBadRequest, "missing-pubkey", "path parameter 'pubkey' is required")
		return
	}

	now := time.Now().UTC()
	from := now.Add(-24 * time.Hour)
	to := now

	q := r.URL.Query()
	if v := q.Get("from"); v != "" {
		if t, err := time.Parse(time.RFC3339, v); err == nil {
			from = t
		} else {
			writeError(w, http.StatusBadRequest, "bad-from", "from must be RFC 3339")
			return
		}
	}
	if v := q.Get("to"); v != "" {
		if t, err := time.Parse(time.RFC3339, v); err == nil {
			to = t
		} else {
			writeError(w, http.StatusBadRequest, "bad-to", "to must be RFC 3339")
			return
		}
	}
	granularity := q.Get("granularity")
	if granularity == "" {
		granularity = "hour"
	}

	series, err := h.cfg.Stats.Query(r.Context(), pubkey, from, to, granularity)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "stats-query-failed", err.Error())
		return
	}
	writeJSON(w, http.StatusOK, series)
}
