# Changelog

All notable changes to **ICD360S VPN** (server agent + admin app) are
recorded here. Format inspired by [Keep a Changelog](https://keepachangelog.com).

This file is the source of truth for the **app's auto-update
mechanism** as well: the bullets under each version land in the
"What's new" dialog rendered by `UpdateAvailableDialog`. Keep entries
short and user-facing.

## [Unreleased]

## [0.1.0] - 2026-04-11

First tagged release. Covers everything from the initial repo
scaffold (M0) through the working release pipeline (M6.4). After
this tag, the GitHub Actions release job runs end-to-end: build,
SHA256, version.json, GitHub Release upload, and rsync to
vpn.icd360s.de.

### Admin app (M3 → M5)
- Native Flutter desktop app for macOS, Linux, Windows.
- Android (universal APK + AAB + 3 split per ABI), iOS (unsigned).
- One-paste enrollment from `vpn-agent issue-bundle <name>`.
- Peers screen: list, create with QR code, suspend/resume, revoke.
- Health screen: live status of WireGuard + AdGuard, polled every 5s.
- Settings: logout, version display, "Check for updates" button.
- Auto-update flow: polls `https://vpn.icd360s.de/updates/version.json`
  once a day, offers a one-click download with SHA256 verification,
  opens the new DMG in Finder, and quits the old app on confirm.
- Footer "VPN Management — ICD360S e.V." pinned to every screen.

### Server agent (M0 → M4)
- Single static Go binary `vpn-agent` (~11 MB, zero CGo, modernc sqlite).
- mTLS HTTP API on `10.8.0.1:8443` (wg0-only, defense in depth).
- Endpoints: `/v1/health`, `/v1/peers` (GET / POST / PATCH / DELETE),
  `/v1/peers/{pubkey}/bandwidth`.
- WireGuard kernel I/O via `wgctrl-go` (no shell-out to `wg` or
  `wg-quick`, no temp-file race in syncconf).
- Peer enable/disable: suspend without revoke (wg-portal pattern).
- Bandwidth sampler: 60-second polling, sqlite store, 90-day retention,
  per-peer time-series API.
- `vpn-agent issue-bundle <name>`: one-line base64+gzip+json
  enrollment payload, replaces the M3-era 3-PEM-blob ceremony.
- systemd unit with hardening (ProtectSystem=strict, NoNewPrivileges,
  MemoryDenyWriteExecute, ReadWritePaths scoped to state dirs).
- Audit log: every API call recorded with the calling client cert's
  CommonName.

### Server-side infrastructure (M0 → M6.3)
- Hostname `vpn.icd360s.de` (Azure VM, AlmaLinux 9.7).
- SSH on tcp/36000 only (key-only, no password, root login disabled).
- WireGuard listening on udp/443 (bypasses port-22-only firewalls).
- AdGuard Home bound to wg0 with Quad9 DoH upstream.
- nginx 1.20 + Let's Encrypt cert (M6.2). Public file host at
  `https://vpn.icd360s.de/download/vpn-management_icd360sev/`.
- **wstunnel v10.5.2 (M6.2)**: WireGuard reaches the server through
  any firewall that allows HTTPS — hotel WiFi, eduroam, corporate
  proxy, captive portal — by tunneling UDP over a WebSocket on
  TCP 443. Path-routed via `/wg-tcp/` in the same nginx vhost; no
  extra subdomain or cert SAN needed.
- **Restricted `vpn-deploy` user (M6.3)**: forced rrsync write-only
  to `/var/www/html`, used by GitHub Actions to publish releases.

### Release pipeline (M6.1 → M6.4)
- GitHub Actions workflow `.github/workflows/flutter.yml` triggers on
  every push to main (smoke build) AND on every `v*` tag (full
  release).
- Build matrix: 6 jobs (analyze, linux, macos, windows, android, ios)
  on `ubuntu-latest`, `macos-latest`, `windows-latest` runners.
- Release job: downloads every artifact, computes SHA256, generates
  `version.json` with the live URLs, uploads to GitHub Releases via
  `softprops/action-gh-release@v2`, and rsyncs to vpn.icd360s.de.
- Forced Node.js 24 on every JavaScript action via env var (Node 20
  is deprecated effective June 2026).

## [0.0.1] - 2026-04-11
- Initial repo scaffold (M0). README, OpenAPI spec, architecture
  notes, agent + app placeholders.

[Unreleased]: https://github.com/ICD360S-e-V/vpn/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/ICD360S-e-V/vpn/releases/tag/v0.1.0
[0.0.1]: https://github.com/ICD360S-e-V/vpn/releases/tag/v0.0.1
