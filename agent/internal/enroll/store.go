package enroll

import (
	"encoding/json"
	"errors"
	"io"
	"os"
	"path/filepath"
	"sync"
	"syscall"
	"time"
)

// DefaultTTL is how long an issued code stays valid.
const DefaultTTL = 10 * time.Minute

// Entry is one record in the code → bundle store.
//
// We keep entries around even after they expire or are redeemed so
// PopValid can return a specific reason (ErrExpired vs ErrAlreadyUsed
// vs ErrNotFound) for friendlier client-side error messages. The
// pruneExpired helper still drops them eventually — see its comment
// for the retention window.
type Entry struct {
	Code       string    `json:"code"`
	Bundle     []byte    `json:"bundle"` // raw JSON of the enrollment bundle
	ExpiresAt  time.Time `json:"expires_at"`
	IssuedFor  string    `json:"issued_for,omitempty"`
	RedeemedAt time.Time `json:"redeemed_at,omitempty"`
}

func (e Entry) isExpired(now time.Time) bool { return now.After(e.ExpiresAt) }
func (e Entry) isRedeemed() bool             { return !e.RedeemedAt.IsZero() }

// Store is a tiny on-disk JSON store for enrollment codes.
//
// Reads + writes happen under an exclusive flock so the issue-code CLI
// and the running vpn-agent daemon (separate processes) can both
// modify it without races. The store auto-prunes expired entries on
// every write.
type Store struct {
	path string
	mu   sync.Mutex // serialises in-process callers; flock guards across processes
}

// New constructs a Store backed by the given path. The file is
// created on first write.
func New(path string) *Store {
	return &Store{path: path}
}

// Put saves a bundle under code with the given TTL. Any existing
// entry for the same code is overwritten.
func (s *Store) Put(code string, bundle []byte, ttl time.Duration) error {
	return s.modify(func(entries map[string]Entry) {
		entries[code] = Entry{
			Code:      code,
			Bundle:    bundle,
			ExpiresAt: time.Now().Add(ttl),
		}
		s.pruneExpired(entries)
	})
}

// PutNamed is like Put but also records who the code was issued for
// (for audit logging on the daemon's side).
func (s *Store) PutNamed(code, name string, bundle []byte, ttl time.Duration) error {
	return s.modify(func(entries map[string]Entry) {
		entries[code] = Entry{
			Code:      code,
			IssuedFor: name,
			Bundle:    bundle,
			ExpiresAt: time.Now().Add(ttl),
		}
		s.pruneExpired(entries)
	})
}

// Distinct errors so the API handler can return a specific status
// to the client. The original "don't reveal which" stance was
// security theatre against the 32^16 keyspace + 10min TTL + global
// rate limit; the UX cost was real (a user with a typo couldn't
// tell whether to retry or get a fresh code), so we now distinguish.
var (
	ErrNotFound     = errors.New("code not found")
	ErrExpired      = errors.New("code expired")
	ErrAlreadyUsed  = errors.New("code already used")
)

// retentionAfterTerminal is how long we keep an entry around after
// it expires or gets redeemed, so PopValid can still tell the client
// "expired" or "already used" instead of "not found". After this
// window the entry is pruned to keep the store from growing forever.
const retentionAfterTerminal = 24 * time.Hour

// PopValid looks up a code and returns the bundle on success. On
// failure it returns a specific error: ErrNotFound (never existed),
// ErrExpired (was valid but past its TTL), or ErrAlreadyUsed
// (single-use semantics already consumed).
func (s *Store) PopValid(code string) ([]byte, error) {
	var (
		bundle []byte
		retErr error
	)
	err := s.modify(func(entries map[string]Entry) {
		s.pruneExpired(entries)
		e, ok := entries[code]
		if !ok {
			retErr = ErrNotFound
			return
		}
		now := time.Now()
		if e.isRedeemed() {
			retErr = ErrAlreadyUsed
			return
		}
		if e.isExpired(now) {
			retErr = ErrExpired
			return
		}
		// Mark redeemed (don't delete) so a second attempt with the
		// same code returns ErrAlreadyUsed instead of ErrNotFound.
		e.RedeemedAt = now
		entries[code] = e
		bundle = e.Bundle
	})
	if err != nil {
		return nil, err
	}
	return bundle, retErr
}

// pruneExpired drops entries whose terminal state (expired OR
// redeemed) is older than retentionAfterTerminal. Active entries
// and recently-terminated entries are kept so PopValid can still
// distinguish ErrExpired and ErrAlreadyUsed from ErrNotFound for
// the friendly client error message.
//
// Caller must already hold the modify lock + flock.
func (s *Store) pruneExpired(entries map[string]Entry) {
	now := time.Now()
	for k, v := range entries {
		// Active code: keep.
		if !v.isExpired(now) && !v.isRedeemed() {
			continue
		}
		// Terminal: keep until retention window passes so PopValid
		// can return a specific error.
		terminalAt := v.ExpiresAt
		if v.isRedeemed() && v.RedeemedAt.After(terminalAt) {
			terminalAt = v.RedeemedAt
		}
		if now.Sub(terminalAt) > retentionAfterTerminal {
			delete(entries, k)
		}
	}
}

// modify holds the flock + reads + mutates + writes atomically.
func (s *Store) modify(fn func(map[string]Entry)) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	if err := os.MkdirAll(filepath.Dir(s.path), 0o700); err != nil {
		return err
	}

	f, err := os.OpenFile(s.path, os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		return err
	}
	defer f.Close()

	if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX); err != nil {
		return err
	}
	defer syscall.Flock(int(f.Fd()), syscall.LOCK_UN)

	entries := map[string]Entry{}
	raw, err := io.ReadAll(f)
	if err != nil {
		return err
	}
	if len(raw) > 0 {
		if err := json.Unmarshal(raw, &entries); err != nil {
			// Corrupt file — start fresh.
			entries = map[string]Entry{}
		}
	}

	fn(entries)

	out, err := json.MarshalIndent(entries, "", "  ")
	if err != nil {
		return err
	}
	if _, err := f.Seek(0, 0); err != nil {
		return err
	}
	if err := f.Truncate(0); err != nil {
		return err
	}
	if _, err := f.Write(out); err != nil {
		return err
	}
	return f.Sync()
}
