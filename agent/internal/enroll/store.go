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
type Entry struct {
	Code      string    `json:"code"`
	Bundle    []byte    `json:"bundle"` // raw JSON of the enrollment bundle
	ExpiresAt time.Time `json:"expires_at"`
	IssuedFor string    `json:"issued_for,omitempty"`
}

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

// ErrNotFound is returned by PopValid when the code is unknown,
// expired, or already redeemed.
var ErrNotFound = errors.New("code not found, expired, or already used")

// PopValid looks up a code, deletes it (single-use), and returns the
// bundle. Returns ErrNotFound if no valid entry exists.
func (s *Store) PopValid(code string) ([]byte, error) {
	var bundle []byte
	err := s.modify(func(entries map[string]Entry) {
		s.pruneExpired(entries)
		e, ok := entries[code]
		if !ok {
			return
		}
		bundle = e.Bundle
		delete(entries, code)
	})
	if err != nil {
		return nil, err
	}
	if bundle == nil {
		return nil, ErrNotFound
	}
	return bundle, nil
}

// pruneExpired drops any entries whose ExpiresAt is in the past.
// Caller must already hold the modify lock + flock.
func (s *Store) pruneExpired(entries map[string]Entry) {
	now := time.Now()
	for k, v := range entries {
		if now.After(v.ExpiresAt) {
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
