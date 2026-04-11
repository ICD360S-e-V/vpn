// Package enroll handles short-code based device enrollment for the
// admin app. The flow:
//
//  1. An admin runs `vpn-agent issue-code <name>` on the server.
//  2. That command generates a fresh client cert + WG peer + bundles
//     them, then stores the bundle under a 16-char code with a 10-min
//     TTL in /var/lib/vpn-agent/enrollment_codes.json.
//  3. The CLI prints the code formatted as XXXX-XXXX-XXXX-XXXX.
//  4. The admin texts/dictates that code to the user.
//  5. The user types the code into the app's 4-box input.
//  6. The app POSTs `{"code": "..."}` to `https://vpn.icd360s.de/enroll`.
//  7. nginx proxies to the agent's plaintext enroll listener on
//     127.0.0.1:8081, which looks up the code, deletes it (single-use),
//     and returns the bundle JSON.
//
// The whole point of this package is the file-based code store —
// the daemon and the issue-code CLI live in separate processes and
// share state through that file under a flock.
package enroll

import (
	"crypto/rand"
	"fmt"
	"math/big"
	"strings"
)

// codeAlphabet is 32 unambiguous characters: digits 2-9 plus uppercase
// letters minus the visually-confusable ones (0/O, 1/I/L). 32 symbols
// keep the math clean (5 bits per char) and 32^16 == 2^80 possible
// codes is enormously more entropy than the 5-attempts-per-minute
// rate limit can chew through in any plausible attacker timeframe.
const codeAlphabet = "23456789ABCDEFGHJKMNPQRSTUVWXYZ"
const codeChunks = 4
const codeChunkLen = 4
const codeLen = codeChunks * codeChunkLen // 16

// Generate creates a fresh code formatted XXXX-XXXX-XXXX-XXXX. Uses
// crypto/rand for the underlying entropy.
func Generate() (string, error) {
	raw := make([]byte, codeLen)
	for i := range raw {
		idx, err := rand.Int(rand.Reader, big.NewInt(int64(len(codeAlphabet))))
		if err != nil {
			return "", err
		}
		raw[i] = codeAlphabet[idx.Int64()]
	}
	var sb strings.Builder
	for i := 0; i < codeChunks; i++ {
		if i > 0 {
			sb.WriteByte('-')
		}
		sb.Write(raw[i*codeChunkLen : (i+1)*codeChunkLen])
	}
	return sb.String(), nil
}

// Normalize strips whitespace + dashes + uppercases the input. Validates
// length and alphabet. Returns the canonical 16-character form (no
// dashes) used as the storage key. Lower-case input and pasted-with-
// dashes input both work.
func Normalize(input string) (string, error) {
	s := strings.ToUpper(strings.TrimSpace(input))
	s = strings.ReplaceAll(s, "-", "")
	s = strings.ReplaceAll(s, " ", "")
	if len(s) != codeLen {
		return "", fmt.Errorf("expected %d characters, got %d", codeLen, len(s))
	}
	for _, c := range s {
		if !strings.ContainsRune(codeAlphabet, c) {
			return "", fmt.Errorf("character %q not in allowed alphabet", c)
		}
	}
	return s, nil
}
