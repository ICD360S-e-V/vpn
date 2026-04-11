package api

import (
	"encoding/json"
	"log/slog"
	"net/http"
	"time"
)

// withLogging wraps a handler so every request emits a structured
// JSON log line with method, path, status, latency, remote address,
// and the client cert CommonName (so the audit trail says who did what).
func withLogging(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}

		clientCN := ""
		if r.TLS != nil && len(r.TLS.PeerCertificates) > 0 {
			clientCN = r.TLS.PeerCertificates[0].Subject.CommonName
		}

		next.ServeHTTP(rec, r)

		slog.Info("request",
			"method", r.Method,
			"path", r.URL.Path,
			"status", rec.status,
			"duration_ms", time.Since(start).Milliseconds(),
			"remote_addr", r.RemoteAddr,
			"client_cn", clientCN,
		)
	})
}

// statusRecorder captures the status code so the logging middleware
// can report it. http.ResponseWriter does not expose the status by
// default.
type statusRecorder struct {
	http.ResponseWriter
	status      int
	wroteHeader bool
}

func (r *statusRecorder) WriteHeader(code int) {
	if r.wroteHeader {
		return
	}
	r.wroteHeader = true
	r.status = code
	r.ResponseWriter.WriteHeader(code)
}

func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	enc := json.NewEncoder(w)
	enc.SetIndent("", "  ")
	if err := enc.Encode(body); err != nil {
		slog.Error("write json", "err", err)
	}
}

// problemDetails follows RFC 7807. Simplified for our needs.
type problemDetails struct {
	Type   string `json:"type"`
	Title  string `json:"title"`
	Status int    `json:"status"`
	Detail string `json:"detail,omitempty"`
}

// writeError emits a JSON error response. The 'kind' becomes the
// suffix of the type URL so machines can distinguish problem classes
// without parsing the human-readable title.
func writeError(w http.ResponseWriter, status int, kind, detail string) {
	w.Header().Set("Content-Type", "application/problem+json")
	w.WriteHeader(status)
	pd := problemDetails{
		Type:   "/problems/" + kind,
		Title:  http.StatusText(status),
		Status: status,
		Detail: detail,
	}
	enc := json.NewEncoder(w)
	enc.SetIndent("", "  ")
	if err := enc.Encode(pd); err != nil {
		slog.Error("write error", "err", err)
	}
}
