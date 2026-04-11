package api

import (
	"sync"
	"time"
)

// RateLimiter is a tiny in-memory fixed-window rate limiter keyed by
// arbitrary string (we use the client IP). Counts reset after every
// `window` interval. Used by the public enrollment endpoint to make
// brute-forcing the 16-char code impractical.
//
// Implementation notes:
//   - Fixed window, not sliding window. The window resets when the
//     first request after the window expiry arrives. Bursts at the
//     edge of two windows can briefly double the limit; for the
//     enrollment use case (5 per minute) that is fine.
//   - The reset is lazy. There is no goroutine; we just check
//     `time.Since(lastReset)` on every Allow() call.
//   - Thread safe.
type RateLimiter struct {
	mu        sync.Mutex
	counts    map[string]int
	limit     int
	window    time.Duration
	lastReset time.Time
}

// NewRateLimiter constructs a limiter that allows up to `limit`
// requests per key per `window`.
func NewRateLimiter(limit int, window time.Duration) *RateLimiter {
	return &RateLimiter{
		counts:    map[string]int{},
		limit:     limit,
		window:    window,
		lastReset: time.Now(),
	}
}

// Allow returns true if this request should be processed, false if
// the key has hit its limit in the current window.
func (rl *RateLimiter) Allow(key string) bool {
	rl.mu.Lock()
	defer rl.mu.Unlock()
	if time.Since(rl.lastReset) > rl.window {
		rl.counts = map[string]int{}
		rl.lastReset = time.Now()
	}
	rl.counts[key]++
	return rl.counts[key] <= rl.limit
}
