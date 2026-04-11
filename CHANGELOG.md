# Changelog

All notable changes to **ICD360S VPN** (server agent + admin app) are
recorded here. Format inspired by [Keep a Changelog](https://keepachangelog.com).

This file is the source of truth for the **app's auto-update
mechanism** as well: the bullets under each version land in the
"What's new" dialog rendered by `UpdateAvailableDialog`. Keep entries
short and user-facing.

## [Unreleased]

### Added — server infrastructure (M6.2 / M6.3)
- nginx 1.20 + Let's Encrypt cert on vpn.icd360s.de.
- Public download tree at `https://vpn.icd360s.de/download/vpn-management_icd360sev/<platform>/`.
- `https://vpn.icd360s.de/updates/version.json` (auto-update manifest).
- **wstunnel v10.5.2** running on `127.0.0.1:8444` plain WebSocket.
  nginx terminates TLS at `vpn.icd360s.de:443` and proxies the
  `/wg-tcp/` location to wstunnel, which forwards UDP to the WG
  kernel socket. Result: WireGuard now also reaches the server
  through any firewall that allows HTTPS — hotel WiFi, eduroam,
  corporate proxy, captive portal — without losing the existing
  UDP/443 happy path.
- Restricted `vpn-deploy` user (forced rrsync, no shell, write-only
  to `/var/www/html`) for the GitHub Actions release pipeline. Four
  GitHub secrets configured: `VPN_DEPLOY_SSH_{KEY,HOST,PORT,USER}`.
- Documentation: `docs/vpn-server-setup.md` server runbook.

### Removed
- Empty 'tunnel.vpn.icd360s.de' SNI-routing plan from the M6 design.
  Path-based routing in a single nginx vhost turned out to be
  cleaner — no second cert SAN needed, no DNS A record needed (the
  one we added at inwx is harmless and stays as a future fallback).

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
