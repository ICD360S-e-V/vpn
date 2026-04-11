# Architecture Notes

> Status: M0 — design draft. Subject to revision before M1 starts.

## Why an HTTP agent instead of SSH

The naive design is "the macOS app SSH-es into vpn.icd360s.de and runs
`wg show`". This was rejected for the following reasons:

1. **No safe place to ship the SSH key.** Anything in the app bundle
   can be extracted with `strings`. Anything in Keychain is recoverable
   by any process running as the user.
2. **No fine-grained authorization.** SSH gives the app root or
   nothing. There is no way to say "this admin can list peers but
   cannot delete them".
3. **No audit trail.** SSH command history is poor. We want a
   server-side log of every API call: who, when, what, success/fail.
4. **Brittle output parsing.** `wg show` output format has changed
   between versions; parsing it from Swift is fragile.
5. **No rate limiting.** SSH gives unrestricted shell access.
6. **No replay protection.** A captured SSH session can be replayed
   from any host that holds the key.

## What `vpn-agent` is

A small HTTP daemon written in Go (single static binary, no runtime
dependencies). It runs as root on `vpn.icd360s.de` and exposes a typed
JSON API over **mTLS only**. It listens on the **wg0 interface IP**
(`10.8.0.1:8443`), so it is reachable **only through the VPN tunnel
itself**, just like AdGuard Home. There is no public listener.

### Why bind to wg0 and not eth0

Defense in depth. The agent has root and can mutate the WireGuard
config; it must not be exposed to the public internet. If the admin
needs to manage the server, they first connect via WireGuard, then
the macOS app talks to the agent over the tunnel.

This means: **you must already be a WG client to be able to manage
the server.** First-time bootstrap requires SSH (port 36000) or
console access.

### mTLS

- Server cert: long-lived (1 year), self-signed CA stored in
  `/etc/vpn-agent/ca.pem`. Issued automatically on first run by the
  agent itself.
- Client certs: one per admin device, issued by the same CA via the
  agent's `/v1/admin/enroll` flow. The first client cert is bootstrapped
  via a one-time enrollment token printed by the agent on first run.
  Subsequent clients are enrolled by an existing admin.
- Revocation: the agent maintains an in-memory CRL persisted to
  `/etc/vpn-agent/revoked.txt`. Revoked certs are rejected at the
  TLS handshake layer.

### Authorization

There is **no role system in M1**. Any client cert that passes mTLS
gets full access. We will add roles in M3 if needed.

## API conventions

- All endpoints under `/v1/...` — versioned from day one.
- All responses are JSON with `Content-Type: application/json`.
- Errors follow RFC 7807 (Problem Details for HTTP APIs):
  ```json
  { "type": "/problems/peer-not-found",
    "title": "Peer not found",
    "status": 404,
    "instance": "/v1/peers/abc..." }
  ```
- Timestamps are RFC 3339 UTC.
- Bandwidth values are in **bytes**, not GB or KB. The app converts.
- Pagination via `?limit=&cursor=` (cursor-based, not offset).

## Server-side state

The agent owns `/etc/wireguard/wg0.conf`. The macOS app **never**
writes to this file directly.

When a peer is created via the API:
1. Agent generates keys and PSK with `wg genkey` / `wg genpsk`.
2. Agent picks the next free `10.8.0.x` (scans existing peers).
3. Agent appends a `[Peer]` block to `wg0.conf`.
4. Agent runs `wg syncconf wg0 <(wg-quick strip wg0)` to apply
   without disrupting existing connections.
5. Agent persists the peer metadata (display name, created-at,
   created-by-cert) in a sqlite DB at `/var/lib/vpn-agent/peers.db`.
6. Returns the rendered client `.conf` and a base64 PNG QR code
   to the caller.

When a peer is revoked:
1. Agent removes the `[Peer]` block.
2. Agent runs `wg syncconf wg0 ...`.
3. Agent marks the peer as revoked in the DB (soft delete, for audit).

## Bandwidth tracking

WireGuard exposes per-peer RX/TX byte counters via `wg show wg0
transfer`. These reset to zero on every interface restart, so for
historical data we need to:

- Sample the counters every 60 seconds.
- Detect counter resets (current value < last value).
- Store deltas in sqlite as `(peer_pubkey, ts, rx_delta, tx_delta)`.
- Aggregate to hour / day / week / month at query time.

Storage cost: ~200 peers × 1440 samples/day × 32 bytes ≈ 9 MB/day.
We retain 90 days of raw samples plus indefinite hourly rollups.

## AdGuard Home integration

AdGuard Home exposes a REST API at `http://10.8.0.1:3000/control/...`
with HTTP Basic auth (`admin:admin` currently). The agent acts as a
**proxy**: it accepts authenticated mTLS calls from the macOS app,
calls AdGuard internally, and forwards the response. Why proxy
instead of letting the app talk to AdGuard directly:

- The app doesn't need to know AdGuard's password.
- We can normalize the response shape.
- We can rate-limit and audit.
- We can later switch AdGuard for another resolver without changing
  the app.

## Threat model

**In scope:**
- Stolen admin laptop: revoke its client cert, attacker locked out.
- Compromised home network of an admin: mTLS protects against
  passive interception. Bind to wg0 means attacker also needs WG
  credentials.
- Buggy app sends a malformed request: agent validates everything
  server-side. App-side validation is for UX, not security.

**Out of scope:**
- Compromise of the agent itself (root on the VM): there is no
  cryptographic defense. Operational security and patching apply.
- Insider threat from someone with valid SSH on the VM: same as
  above. We rely on SSH being key-only and tightly held.
- Side-channel timing attacks against the bcrypt comparison in
  the AdGuard proxy path: not in scope, AdGuard's own concern.
