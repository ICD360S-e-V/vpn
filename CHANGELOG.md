# Changelog

All notable changes to **ICD360S VPN** (server agent + admin app) are
recorded here. Format inspired by [Keep a Changelog](https://keepachangelog.com).

This file is the source of truth for the **app's auto-update
mechanism** as well: the bullets under each version land in the
"What's new" dialog rendered by `UpdateAvailableDialog`. Keep entries
short and user-facing.

**Maintenance policy (M7.5+)**: this file is **auto-generated** by
[release-please](https://github.com/googleapis/release-please) from
[Conventional Commit](https://www.conventionalcommits.org) messages.
Use `feat:` for new features (minor bump), `fix:` for bug fixes
(patch bump), `feat!:` or a `BREAKING CHANGE:` footer for major
bumps. `chore:`, `docs:`, `ci:`, `refactor:`, `style:`, `test:`,
`build:` do not produce a release. Manual editing of new entries
is discouraged — it will be overwritten the next time release-please
opens a release PR. Historical sections below v1.1.0 are preserved
verbatim from the manual era.

## [1.1.0] - 2026-04-11

### Added — short-code enrollment (M7.1, M7.3)
- New `vpn-agent issue-code <name>` subcommand prints a 16-char
  `XXXX-XXXX-XXXX-XXXX` one-time code (32-symbol unambiguous
  alphabet, no 0/O/1/I/L). The code maps to a bundle stored in
  `/var/lib/vpn-agent/enrollment_codes.json` with a 10-minute TTL,
  single-use semantics, and auto-pruning of expired entries.
- New plaintext HTTP listener on `127.0.0.1:8081` with the single
  endpoint `POST /v1/enroll`. Reverse-proxied by nginx as
  `https://vpn.icd360s.de/enroll`. The endpoint:
  - Accepts `{"code": "XXXX-XXXX-XXXX-XXXX"}` (case insensitive,
    dashes optional, whitespace stripped).
  - Rate-limits to 5 attempts per source IP per minute via the
    new `internal/api/ratelimit.go` fixed-window limiter.
  - Returns the bundle JSON on success, 404 on
    invalid/expired/already-used code (does not distinguish), 429
    on rate limit.
- The enrollment bundle is now **version 2** and includes EVERYTHING
  the admin app needs in one shot:
  - admin client cert + key + CA cert (mTLS to talk to vpn-agent)
  - **WireGuard peer config** (rendered .conf with allocated /32,
    PSK, endpoint vpn.icd360s.de:443) — the app can now bring up
    its own tunnel without the user having to import peer1.conf
    into a separate WireGuard.app first
  - The peer is created via the existing `wg.Manager.Add()` code
    path, so wg0.conf is updated atomically and the kernel state
    is in lockstep via wgctrl.
- Removed the legacy `vpn-agent issue-bundle` subcommand. The
  base64+gzip+json blob it printed was technically clean but
  user-hostile (1500-char paste). One way to enroll, one paste.

### Added — Go agent CI workflow (M7.1)
- New `.github/workflows/agent.yml` that builds the Go agent on
  ubuntu-latest with `actions/setup-go@v6`, runs `go vet` and
  `go test`, produces a static `vpn-agent` binary, and (on push to
  main or tag) rsyncs it via the existing `vpn-deploy` SSH user
  into `/var/www/html/_agent_drop/vpn-agent`. A systemd path unit
  on the server (`vpn-agent-deploy.path`) detects the file,
  validates it's an ELF, installs to `/usr/local/sbin/vpn-agent`,
  restarts `vpn-agent.service`, and removes the drop file.
- This eliminates "build the Go agent on alma + scp manually"
  from the workflow. End-to-end push → live in ~30 seconds.

### Added — auto-versioning + auto-CHANGELOG (M7.5)
- New `release-please` pipeline (`release-please-config.json` +
  `.release-please-manifest.json` + `.github/workflows/release-please.yml`).
  Every push to main runs release-please which reads commit messages
  since the last tag, decides on a semver bump (`feat:` → minor,
  `fix:`/`perf:` → patch, `feat!:` / `BREAKING CHANGE:` footer →
  major, anything else → no release), and opens a Release PR with
  the bumped version + auto-generated CHANGELOG entry. Merging the
  PR creates the `vX.Y.Z` tag which fires the existing `flutter.yml`
  + `agent.yml` build matrix.
- New composite action `.github/actions/set-build-number` derives a
  strictly-monotonic Flutter build number from the semver
  (`MAJ*10000 + MIN*100 + PAT`) in CI, immediately before
  `flutter build`. The source `app/pubspec.yaml` now carries only
  the semver — single source of truth, no manual `+N` bump risk
  of regressing the auto-update gate.
- The agent's Go binary continues to use `git describe --tags` so it
  picks up the same tag automatically — no extra config needed.

### Added — release notes viewer (M7.5)
- New `ChangelogScreen` reachable by tapping the version label in
  the footer (every screen) or in Settings → Version. Shows the full
  per-version release history with each version as an expandable
  card, the current version highlighted, dates parsed from the
  CHANGELOG headers, and `Refresh` to reload from the server.
- New `ChangelogService` fetches `https://vpn.icd360s.de/updates/CHANGELOG.md`
  (plaintext HTTPS, OS root store — no mTLS, works before enrollment)
  and parses both manual Keep a Changelog entries AND release-please's
  auto-generated format (`## [X.Y.Z](url) (date)` with `*` bullets and
  inline markdown). Inline markdown is stripped to plain text so the
  renderer doesn't pull in `flutter_markdown` for two screens.
- Release job now copies `CHANGELOG.md` into `out/updates/` alongside
  `version.json` so the rsync to nginx publishes both in one step.

## [1.0.2] - 2026-04-11

### Fixed
- Last remaining Node.js 20 deprecation warning. The
  `softprops/action-gh-release@v2` action's master branch was still
  on Node.js 20 as of April 2026 and the maintainer had not bumped
  it. Replaced with native `gh release create` / `gh release upload`
  CLI commands — gh CLI is pre-installed on every GitHub runner and
  uses no JavaScript runtime at all. Side benefit: idempotent, so
  re-running a release workflow refreshes the assets via
  `gh release upload --clobber` instead of failing.

## [1.0.1] - 2026-04-11

First successfully-published release of icd360svpn. (The earlier
v0.1.0 tag was an aborted dry-run — its release job failed at the
ios tar step before any artifact was uploaded; the tag was left
behind on GitHub as historical evidence.) This v1.0.1 covers
everything from the initial repo scaffold (M0) through the working
release pipeline (M6.5).

### Fixed in M6.5
- iOS build now packages `Runner.app` as a tarball BEFORE upload.
  Previously `actions/upload-artifact` flattened the directory
  contents, so `dist/ios/Runner.app/` did not exist at release time
  and the layout step's `tar` failed with "Cannot stat".
- "Read version from pubspec" step in the release job now reads
  `app/pubspec.yaml` from the workspace root (the release job no
  longer inherits the per-job `working-directory: app` default —
  it works from the repo root throughout).
- Bumped action versions to ones that ship Node.js 24 natively:
  `actions/checkout@v6`, `actions/upload-artifact@v7`,
  `actions/download-artifact@v8`. Removed the
  `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24` workflow env var — no
  longer needed.

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

[1.1.0]: https://github.com/ICD360S-e-V/vpn/compare/v1.0.2...v1.1.0
[1.0.2]: https://github.com/ICD360S-e-V/vpn/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/ICD360S-e-V/vpn/releases/tag/v1.0.1
[0.0.1]: https://github.com/ICD360S-e-V/vpn/releases/tag/v0.0.1
