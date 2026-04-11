package api

import (
	"sync"
	"time"
)

// RateLimiter is a server-wide fixed-window counter. Used to cap the
// global enrollment attempt rate.
//
// Why this is NOT keyed by client IP (M7.1.1):
//   - Mobile carriers + corporate NATs put thousands of legit users
//     behind a single IPv4 address; an IP-based limiter would either
//     be too tight (false positives) or too loose to matter.
//   - An attacker who wants to brute-force the 16-char code can
//     trivially rotate IPs (cellular, residential proxies, Tor,
//     IPv6 prefix delegation). Per-IP rate limiting against an
//     IP-rotating attacker is theatre.
//   - The actual security of the enrollment endpoint comes from the
//     code's entropy (32^16 ≈ 2^80, brute-force-impossible at any
//     rate the universe can support), the 10-minute TTL, the
//     single-use semantics, and the out-of-band delivery channel
//     (the admin reads the code via SSH, not via the public network).
//   - The server-wide limit is therefore a DoS-mitigation measure,
//     not a primary defence: stop a runaway loop from saturating
//     the agent without penalising any specific client.
//
// Implementation: fixed window, not sliding. Lazy reset on every
// Allow() call (no goroutine). Thread safe.
type RateLimiter struct {
	mu        sync.Mutex
	count     int
	limit     int
	window    time.Duration
	lastReset time.Time
}

// NewRateLimiter constructs a server-wide limiter that allows up to
// `limit` requests per `window`. Suitable defaults for the
// enrollment endpoint: 60 per minute (~1/sec average).
func NewRateLimiter(limit int, window time.Duration) *RateLimiter {
	return &RateLimiter{
		limit:     limit,
		window:    window,
		lastReset: time.Now(),
	}
}

// Allow returns true if this request should be processed. Counts ALL
// attempts globally; the key parameter is ignored — kept only so
// existing call sites compile during the M7.1.1 rate-limit redesign.
func (rl *RateLimiter) Allow(_ string) bool {
	rl.mu.Lock()
	defer rl.mu.Unlock()
	if time.Since(rl.lastReset) > rl.window {
		rl.count = 0
		rl.lastReset = time.Now()
	}
	rl.count++
	return rl.count <= rl.limit
}
