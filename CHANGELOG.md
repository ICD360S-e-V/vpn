# Changelog

All notable changes to **ICD360S VPN** (server agent + admin app) are
recorded here. Format inspired by [Keep a Changelog](https://keepachangelog.com).

This file is the source of truth for the **app's auto-update
mechanism** as well: the bullets under each version land in the
"What's new" dialog rendered by `UpdateAvailableDialog`. Keep entries
short and user-facing.

## [Unreleased]

## [0.1.0] - 2026-04-11

First public release of the Flutter admin app + the M0–M5 server
milestones. Tagged `v0.1.0`.

### Added — admin app (M5)
- Native Flutter desktop app for macOS / Linux / Windows.
- One-paste enrollment from `vpn-agent issue-bundle <name>` output.
- Peers screen: list, create with QR code, suspend/resume, revoke.
- Health screen: live status of WireGuard + AdGuard, polled every 5s.
- Settings screen with logout + about.
- Auto-update dialog (M5.3): polls `version.json` once a day, offers
  to download + open the new DMG in Finder, and quits the old app
  on confirm.
- Footer "VPN Management — ICD360S e.V." on every screen.

### Added — server agent (M0–M4)
- Single static Go binary `vpn-agent` (~11 MB, no CGo).
- mTLS HTTP API on `10.8.0.1:8443` (wg0-only, defense in depth).
- Endpoints: `/v1/health`, `/v1/peers` (GET / POST / PATCH / DELETE),
  `/v1/peers/{pubkey}/bandwidth`.
- WireGuard kernel I/O via `wgctrl-go` (no shell-out to `wg` /
  `wg-quick`).
- Peer enable/disable: suspend without revoke.
- Bandwidth sampler: 60s polling, sqlite store, 90-day retention.
- `vpn-agent issue-bundle <name>`: one-line base64+gzip+json
  enrollment payload.
- systemd unit with hardening (ProtectSystem=strict, NoNewPrivileges,
  MemoryDenyWriteExecute, ReadWritePaths scoped to state dirs).
- Audit log: every API call recorded with the calling client cert's
  CommonName.

### Server-side infrastructure
- Hostname pinned to `vpn.icd360s.de`, A record cleaned up.
- SSH on tcp/36000 only (key-only, no password).
- WireGuard listening on udp/443 (bypasses port-22-only firewalls).
- AdGuard Home bound to wg0 with Quad9 DoH upstream.

## [0.0.1] - 2026-04-11
- Initial repo scaffold (M0). README, OpenAPI spec, architecture
  notes, agent + app placeholders.

[Unreleased]: https://github.com/ICD360S-e-V/vpn/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/ICD360S-e-V/vpn/releases/tag/v0.1.0
[0.0.1]: https://github.com/ICD360S-e-V/vpn/releases/tag/v0.0.1
