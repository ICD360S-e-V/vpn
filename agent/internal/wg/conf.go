// Package wg manages the WireGuard server configuration on disk
// (/etc/wireguard/wg0.conf) and the live interface state (via the
// `wg` and `wg-quick` binaries).
//
// Persistence model
//
// We do NOT use a database for peer metadata. Instead we encode it as
// comments inside wg0.conf, immediately preceding the [Peer] block:
//
//	[Peer]
//	# name=phone-andrei
//	# created_at=2026-04-11T13:00:00Z
//	# created_by=macos-bootstrap
//	PublicKey = ...
//	PresharedKey = ...
//	AllowedIPs = 10.8.0.3/32
//
// The parser is permissive: it also recognises a single-token comment
// like `# peer1` and treats it as a `name`, so configs created by hand
// before vpn-agent existed are migrated transparently on the next save.
//
// Concurrency
//
// All file mutations are guarded by a flock(2) lock on
// /etc/wireguard/wg0.conf.lock. Writes go to a sibling .tmp file and are
// rename(2)d into place — atomic on the same filesystem.
package wg

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// Section represents either an [Interface] or a [Peer] block.
type sectionType string

const (
	sectionInterface sectionType = "Interface"
	sectionPeer      sectionType = "Peer"
)

// rawSection is the byte-for-byte parsed shape of a single section.
// Field order is preserved (we use a slice of pairs, not a map) so
// that round-tripping does not reshuffle keys.
type rawSection struct {
	Type    sectionType
	Meta    map[string]string // key=value comments that preceded this section
	Entries []rawEntry        // raw key/value lines, order preserved
}

type rawEntry struct {
	Key   string
	Value string
}

// rawConfig is the in-memory representation of a parsed wg0.conf.
type rawConfig struct {
	Header   []string // free-form comments before the first section
	Sections []*rawSection
}

// parseConfig reads wg0.conf and returns its raw structure.
//
// Comment-handling rules (these matter — see the test fixtures):
//
//  1. Comments BEFORE the first section that look like free-form text
//     (have spaces, no '=') become the file header.
//  2. Comments BEFORE a section header (or between sections) that look
//     like `key=value` or a single token become metadata for the NEXT
//     section. Held in `pendingMeta` until the next section header
//     consumes them.
//  3. Comments INSIDE a section but BEFORE its first `key = value`
//     entry (i.e. immediately after the `[Peer]` header) become
//     metadata for the CURRENT section. This handles the legacy
//     hand-written form `[Peer]\n# peer1\nPublicKey = ...`.
//  4. Comments INSIDE a section AFTER its first entry are treated as
//     metadata for the NEXT section (placed in pendingMeta). Once you
//     have started writing data, vpn-agent assumes any subsequent
//     comment block is for the next peer.
func parseConfig(r io.Reader) (*rawConfig, error) {
	cfg := &rawConfig{}
	var (
		current             *rawSection
		pendingMeta         = map[string]string{}
		seenSection         bool
		currentHasEntries   bool // has the current section seen a key=value yet?
	)
	sc := bufio.NewScanner(r)
	sc.Buffer(make([]byte, 0, 64*1024), 1<<20)
	for sc.Scan() {
		line := sc.Text()
		trimmed := strings.TrimSpace(line)

		// Section headers.
		switch trimmed {
		case "[Interface]":
			current = &rawSection{Type: sectionInterface, Meta: pendingMeta}
			cfg.Sections = append(cfg.Sections, current)
			pendingMeta = map[string]string{}
			seenSection = true
			currentHasEntries = false
			continue
		case "[Peer]":
			current = &rawSection{Type: sectionPeer, Meta: pendingMeta}
			cfg.Sections = append(cfg.Sections, current)
			pendingMeta = map[string]string{}
			seenSection = true
			currentHasEntries = false
			continue
		}

		// Comments.
		if strings.HasPrefix(trimmed, "#") {
			body := strings.TrimSpace(strings.TrimPrefix(trimmed, "#"))
			if body == "" {
				continue
			}
			// Pick destination per the rules above.
			target := pendingMeta
			if current != nil && !currentHasEntries {
				target = current.Meta
			}
			if k, v, ok := splitKV(body); ok {
				target[k] = v
				continue
			}
			if isSingleToken(body) {
				if _, exists := target["name"]; !exists {
					target["name"] = body
				}
				continue
			}
			if !seenSection {
				cfg.Header = append(cfg.Header, line)
			}
			continue
		}

		// Blank lines: ignore (we re-emit canonical spacing on render).
		if trimmed == "" {
			continue
		}

		// Key = value lines belong to the current section.
		if current == nil {
			return nil, fmt.Errorf("config line outside any section: %q", trimmed)
		}
		k, v, ok := splitKV(trimmed)
		if !ok {
			return nil, fmt.Errorf("malformed config line: %q", trimmed)
		}
		current.Entries = append(current.Entries, rawEntry{Key: k, Value: v})
		currentHasEntries = true
	}
	if err := sc.Err(); err != nil {
		return nil, err
	}
	return cfg, nil
}

// renderConfig writes a rawConfig back to disk as a canonical wg0.conf.
// The Interface section keeps its existing entries verbatim. Peer
// sections are rewritten in the canonical format with metadata comments
// followed by Key = Value lines.
func renderConfig(w io.Writer, cfg *rawConfig) error {
	bw := bufio.NewWriter(w)
	defer bw.Flush()

	// Header
	header := cfg.Header
	if len(header) == 0 {
		header = []string{
			"# WireGuard server config — managed by vpn-agent.",
			"# Do not edit by hand: changes outside [Interface] will be lost on next API call.",
		}
	}
	for _, line := range header {
		if _, err := fmt.Fprintln(bw, line); err != nil {
			return err
		}
	}
	if _, err := fmt.Fprintln(bw); err != nil {
		return err
	}

	for i, sec := range cfg.Sections {
		if i > 0 {
			if _, err := fmt.Fprintln(bw); err != nil {
				return err
			}
		}
		// Metadata comments — only for Peer (Interface metadata is meaningless).
		if sec.Type == sectionPeer {
			for _, k := range sortedKeys(sec.Meta) {
				if _, err := fmt.Fprintf(bw, "# %s=%s\n", k, sec.Meta[k]); err != nil {
					return err
				}
			}
		}
		if _, err := fmt.Fprintf(bw, "[%s]\n", sec.Type); err != nil {
			return err
		}
		for _, e := range sec.Entries {
			if _, err := fmt.Fprintf(bw, "%s = %s\n", e.Key, e.Value); err != nil {
				return err
			}
		}
	}
	return nil
}

// readConfigFile parses a wg0.conf from a path on disk.
func readConfigFile(path string) (*rawConfig, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	return parseConfig(f)
}

// writeConfigFile renders cfg and atomically replaces path.
//
// Strategy: write to <path>.tmp, fsync, rename. Caller must hold the
// flock for path.
func writeConfigFile(path string, cfg *rawConfig) error {
	dir := filepath.Dir(path)
	tmp, err := os.CreateTemp(dir, ".wg0.conf.tmp.")
	if err != nil {
		return fmt.Errorf("create temp: %w", err)
	}
	tmpPath := tmp.Name()
	defer os.Remove(tmpPath) // no-op on success after rename

	if err := tmp.Chmod(0o600); err != nil {
		tmp.Close()
		return err
	}
	if err := renderConfig(tmp, cfg); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Sync(); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	if err := os.Rename(tmpPath, path); err != nil {
		return fmt.Errorf("rename: %w", err)
	}
	return nil
}

// findInterface returns the [Interface] section, or an error if there
// is none or there are multiple.
func (c *rawConfig) findInterface() (*rawSection, error) {
	var iface *rawSection
	for _, s := range c.Sections {
		if s.Type == sectionInterface {
			if iface != nil {
				return nil, errors.New("multiple [Interface] sections in wg0.conf")
			}
			iface = s
		}
	}
	if iface == nil {
		return nil, errors.New("no [Interface] section in wg0.conf")
	}
	return iface, nil
}

// findPeer returns the [Peer] section with the given PublicKey, or nil.
func (c *rawConfig) findPeer(pubkey string) *rawSection {
	for _, s := range c.Sections {
		if s.Type != sectionPeer {
			continue
		}
		for _, e := range s.Entries {
			if e.Key == "PublicKey" && e.Value == pubkey {
				return s
			}
		}
	}
	return nil
}

// removePeer drops the [Peer] section with the given PublicKey.
// Returns true if a peer was removed.
func (c *rawConfig) removePeer(pubkey string) bool {
	out := c.Sections[:0]
	removed := false
	for _, s := range c.Sections {
		if s.Type == sectionPeer && !removed {
			match := false
			for _, e := range s.Entries {
				if e.Key == "PublicKey" && e.Value == pubkey {
					match = true
					break
				}
			}
			if match {
				removed = true
				continue
			}
		}
		out = append(out, s)
	}
	c.Sections = out
	return removed
}

// addPeer appends a new [Peer] section. Caller is responsible for
// ensuring uniqueness.
func (c *rawConfig) addPeer(pubkey, psk, allowedIP, name, createdBy string) {
	sec := &rawSection{
		Type: sectionPeer,
		Meta: map[string]string{
			"name":       name,
			"created_at": time.Now().UTC().Format(time.RFC3339),
			"created_by": createdBy,
		},
		Entries: []rawEntry{
			{Key: "PublicKey", Value: pubkey},
			{Key: "PresharedKey", Value: psk},
			{Key: "AllowedIPs", Value: allowedIP},
		},
	}
	c.Sections = append(c.Sections, sec)
}

// usedIPs returns the set of /32 host IPs already assigned to peers,
// plus the server's own Address.
func (c *rawConfig) usedIPs() map[string]bool {
	used := map[string]bool{}
	if iface, err := c.findInterface(); err == nil {
		for _, e := range iface.Entries {
			if e.Key == "Address" {
				for _, addr := range strings.Split(e.Value, ",") {
					addr = strings.TrimSpace(addr)
					if i := strings.Index(addr, "/"); i >= 0 {
						addr = addr[:i]
					}
					used[addr] = true
				}
			}
		}
	}
	for _, s := range c.Sections {
		if s.Type != sectionPeer {
			continue
		}
		for _, e := range s.Entries {
			if e.Key != "AllowedIPs" {
				continue
			}
			for _, addr := range strings.Split(e.Value, ",") {
				addr = strings.TrimSpace(addr)
				if i := strings.Index(addr, "/"); i >= 0 {
					addr = addr[:i]
				}
				used[addr] = true
			}
		}
	}
	return used
}

// helpers

func splitKV(s string) (string, string, bool) {
	i := strings.Index(s, "=")
	if i < 0 {
		return "", "", false
	}
	k := strings.TrimSpace(s[:i])
	v := strings.TrimSpace(s[i+1:])
	if k == "" {
		return "", "", false
	}
	return k, v, true
}

func isSingleToken(s string) bool {
	if s == "" {
		return false
	}
	for i := 0; i < len(s); i++ {
		c := s[i]
		if c == ' ' || c == '\t' || c == '=' {
			return false
		}
	}
	return true
}

func sortedKeys(m map[string]string) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	// Stable canonical order: name first, then created_*, then alpha.
	canonical := []string{"name", "created_at", "created_by"}
	priority := map[string]int{}
	for i, k := range canonical {
		priority[k] = i
	}
	for i := 0; i < len(out); i++ {
		for j := i + 1; j < len(out); j++ {
			pi, pj := rank(priority, out[i]), rank(priority, out[j])
			if pi > pj || (pi == pj && out[i] > out[j]) {
				out[i], out[j] = out[j], out[i]
			}
		}
	}
	return out
}

func rank(p map[string]int, k string) int {
	if v, ok := p[k]; ok {
		return v
	}
	return 1000
}
