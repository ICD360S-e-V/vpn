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

## [1.4.4](https://github.com/ICD360S-e-V/vpn/compare/v1.4.3...v1.4.4) (2026-04-12)


### Bug Fixes

* use split-route /1 subnets instead of /0 in client configs ([4fab1ff](https://github.com/ICD360S-e-V/vpn/commit/4fab1ffd8c1e9aca95d163426563f731fc447ab1))

## [1.4.3](https://github.com/ICD360S-e-V/vpn/compare/v1.4.2...v1.4.3) (2026-04-12)


### Bug Fixes

* add ISP/hostname lookup, fix IPv4 DNS detection ([30fc124](https://github.com/ICD360S-e-V/vpn/commit/30fc12415b2b9d148335b12a8f615fefea7e8b25))

## [1.4.2](https://github.com/ICD360S-e-V/vpn/compare/v1.4.1...v1.4.2) (2026-04-12)


### Bug Fixes

* use curl for IP detection, fix DNS parsing from scutil ([740135b](https://github.com/ICD360S-e-V/vpn/commit/740135b5d000ca552302cfa3507fe118f3e1233e))

## [1.4.1](https://github.com/ICD360S-e-V/vpn/compare/v1.4.0...v1.4.1) (2026-04-12)


### Bug Fixes

* rewrite DNS detection and separate IPv4/IPv6 IP checks ([bcaec84](https://github.com/ICD360S-e-V/vpn/commit/bcaec844b4559028f6e1863b656589ca89a8e8d7))

## [1.4.0](https://github.com/ICD360S-e-V/vpn/compare/v1.3.1...v1.4.0) (2026-04-12)


### Features

* 4-box short-code enrollment + Connect to VPN button (M7.2, M7.4) ([431b601](https://github.com/ICD360S-e-V/vpn/commit/431b60118a309ab8305176c35ce417b1fff3450a))
* add API request/error logging to debug console ([74cb747](https://github.com/ICD360S-e-V/vpn/commit/74cb7478c3cf8530695013757eaa407686916940))
* add collapsible debug console widget ([45b340e](https://github.com/ICD360S-e-V/vpn/commit/45b340ea2673dc9c74bd265eddaefa575ad8bf3e))
* add connection diagnostics (IP, DNS, IPv6 leak detection) ([55a4f59](https://github.com/ICD360S-e-V/vpn/commit/55a4f59a73d07edc9a6deef91b6ea80115824405))
* add Connection diagnostics screen ([694d621](https://github.com/ICD360S-e-V/vpn/commit/694d6211f97b6b852710899283a5523111705d9f))
* add Connection tab, debug console, and VPN logging ([9067f1f](https://github.com/ICD360S-e-V/vpn/commit/9067f1f8dcedcacfc4b31006856a0dad018f9959))
* add in-app debug console logger ([3f6c147](https://github.com/ICD360S-e-V/vpn/commit/3f6c147346ec8929f06816d1d704cbb717d312a9))
* auto-versioning with release-please + in-app release notes viewer (M7.5) ([85a47f0](https://github.com/ICD360S-e-V/vpn/commit/85a47f0682a01810e8bb23ef7262532c97de84f1))
* **ci:** auto-merge release PR after checks pass ([898d765](https://github.com/ICD360S-e-V/vpn/commit/898d7652882534aef860a07c94839627860d0b9c))
* DNS/IPv6 leak protection on macOS (ProtonVPN/Mullvad approach) ([7ec938e](https://github.com/ICD360S-e-V/vpn/commit/7ec938ed96a37731ca4d8c704624c6e98fd07f57))
* real Connect/Disconnect VPN + sidebar logout/dark mode + UX cleanup (v1.2.5) ([4733b40](https://github.com/ICD360S-e-V/vpn/commit/4733b404525cf70d5803d48bad434878a842fb3d))


### Bug Fixes

* **ci:** add continue-on-error to auto-merge step ([ea457fe](https://github.com/ICD360S-e-V/vpn/commit/ea457fe56ae6f23c8aec4c3610336a6b86ed6cb2))
* **ci:** add pull-request-title-pattern to fix component mismatch ([628c7fc](https://github.com/ICD360S-e-V/vpn/commit/628c7fcf510cf96690f19a306f2f38ca8db17ccc))
* **ci:** add workflow_dispatch trigger, replace deprecated manifest-release ([50bba57](https://github.com/ICD360S-e-V/vpn/commit/50bba577515e01e2c8bd4be26d3c2b14e623800c))
* **ci:** pin ossf/scorecard-action to v2.4.3 ([af2a080](https://github.com/ICD360S-e-V/vpn/commit/af2a080ff61a4b56df06fb90d93363d23304586b))
* **ci:** remove package-name, set empty component to stop mismatch ([e99ce2d](https://github.com/ICD360S-e-V/vpn/commit/e99ce2d4af2a8ed9b995b876157a432daddcbc49))
* **ci:** replace deprecated manifest-pr with release-pr ([65418b0](https://github.com/ICD360S-e-V/vpn/commit/65418b0236b08f476c45d4ea216fe7e429ceb6e2))
* **ci:** tolerate duplicate release tag in github-release step ([b8b4c9a](https://github.com/ICD360S-e-V/vpn/commit/b8b4c9a7d60e9e99b5b4ec4602bd1cd2c74ed1d7))
* **ci:** use PAT for release-please to bypass enterprise PR restriction ([78ac673](https://github.com/ICD360S-e-V/vpn/commit/78ac673bdb80f11f5e76ce54c7a6825622463f9c))
* drop flutter_secure_storage + real macOS auto-update + footer button (v1.2.4) ([d71c044](https://github.com/ICD360S-e-V/vpn/commit/d71c04420d94b1e2a215ef4876cfdaf1145453cd))
* drop macOS sandbox + distinguish invalid/expired/used codes (v1.2.3) ([87ad4c1](https://github.com/ICD360S-e-V/vpn/commit/87ad4c132ab9594ff8130cc5cf2d1093d3afe1fa))
* drop unused secure_store.dart import in main_shell ([ba30679](https://github.com/ICD360S-e-V/vpn/commit/ba3067968a8fa360fe7a9d80eceb3256d81af164))
* invoke wg-quick with Homebrew bash on macOS to avoid bash 3.2 shebang ([ee04a12](https://github.com/ICD360S-e-V/vpn/commit/ee04a12e7f2893d16253702e525a201502a73571))
* macOS network sandbox + UA header + drop alphabet hint (M7.6, v1.2.1) ([249ff6c](https://github.com/ICD360S-e-V/vpn/commit/249ff6c803357863beee0ab5177e47786296ea38))
* overwrite macOS entitlements with known-good plist (v1.2.2) ([7ccccb0](https://github.com/ICD360S-e-V/vpn/commit/7ccccb06af9b272cac4ca4d765f6e85fbed523eb))
* restore enrollment_bundle.dart still referenced by app.dart ([c3a4ea5](https://github.com/ICD360S-e-V/vpn/commit/c3a4ea5b9ee948d589cf6b6d695953ba212edea6))
* silence prefer_const_constructors lints in enrollment screen ([9f75e53](https://github.com/ICD360S-e-V/vpn/commit/9f75e53cb6780985407edd6ebbe29edc6fc4bc41))
* silence three analyze warnings in v1.2.5 ([18f5a7c](https://github.com/ICD360S-e-V/vpn/commit/18f5a7cc0d6e51f3af44d5ef14eb135ac7f46de9))
* silence two analyze lints in macos_updater ([8074847](https://github.com/ICD360S-e-V/vpn/commit/807484771cf3998c496dc5900d6d3c49ae7cdad4))


### Documentation

* scrub literal credential string from M7.10 changelog entry ([2e6192c](https://github.com/ICD360S-e-V/vpn/commit/2e6192c82dbc65f4eb1f234cc05f0a6ece56df73))

## [1.3.1](https://github.com/ICD360S-e-V/vpn/compare/v1.3.0...v1.3.1) (2026-04-12)


### Bug Fixes

* **ci:** add pull-request-title-pattern to fix component mismatch ([628c7fc](https://github.com/ICD360S-e-V/vpn/commit/628c7fcf510cf96690f19a306f2f38ca8db17ccc))
* **ci:** remove package-name, set empty component to stop mismatch ([e99ce2d](https://github.com/ICD360S-e-V/vpn/commit/e99ce2d4af2a8ed9b995b876157a432daddcbc49))
* **ci:** replace deprecated manifest-pr with release-pr ([65418b0](https://github.com/ICD360S-e-V/vpn/commit/65418b0236b08f476c45d4ea216fe7e429ceb6e2))
* **ci:** tolerate duplicate release tag in github-release step ([b8b4c9a](https://github.com/ICD360S-e-V/vpn/commit/b8b4c9a7d60e9e99b5b4ec4602bd1cd2c74ed1d7))

## [1.2.6](https://github.com/ICD360S-e-V/vpn/compare/v1.2.5...v1.2.6) (2026-04-12)


### Bug Fixes

* **ci:** pin ossf/scorecard-action to v2.4.3 ([af2a080](https://github.com/ICD360S-e-V/vpn/commit/af2a080ff61a4b56df06fb90d93363d23304586b))
* **ci:** use PAT for release-please to bypass enterprise PR restriction ([78ac673](https://github.com/ICD360S-e-V/vpn/commit/78ac673bdb80f11f5e76ce54c7a6825622463f9c))
* invoke wg-quick with Homebrew bash on macOS to avoid bash 3.2 shebang ([ee04a12](https://github.com/ICD360S-e-V/vpn/commit/ee04a12e7f2893d16253702e525a201502a73571))


### Documentation

* scrub literal credential string from M7.10 changelog entry ([2e6192c](https://github.com/ICD360S-e-V/vpn/commit/2e6192c82dbc65f4eb1f234cc05f0a6ece56df73))

## [Unreleased]

### Changed — repo cleanup for public release (M7.10)
- Removed `README.md` (top-level), `agent/README.md`,
  `app/README.md`, and `docs/architecture.md`. The first three
  duplicated/leaked operational details (SSH command line, key
  paths, AdGuard credential examples) and the architecture doc
  documented default credentials inline. All sensitive
  operational content was moved to `/root/CLAUDE.md` on
  vpn.icd360s.de itself, which is excluded from git via the
  new `.gitignore` rule `CLAUDE.md` / `**/CLAUDE.md`.
- Wrote a new minimal top-level `README.md` that only describes
  the project at a high level + points to the public docs
  (`docs/release.md`, `docs/vpn-server-setup.md`, OpenAPI spec).
  No SSH commands, no key paths, no credentials.
- The repo `ICD360S-e-V/vpn` is being published as **public**
  with this commit. Audit confirmed: zero PEM/key/cert files
  ever committed (current tree or git history), zero hardcoded
  tokens or passwords, all CI secrets accessed via
  `${{ secrets.X }}`.

## [1.2.5] - 2026-04-11

### Added — real Connect/Disconnect VPN via wg-quick + admin prompt (M7.9)
- The Connect to VPN button no longer just saves a `.conf` to
  `~/Documents` and asks the user to import it manually. It now
  performs a REAL `wg-quick up` via `osascript -e 'do shell script
  ... with administrator privileges'`, which produces the standard
  macOS Touch ID / password prompt. After the user authenticates,
  the WireGuard tunnel comes up and the app can immediately reach
  the agent at `https://10.8.0.1:8443`.
- Symmetric Disconnect via `wg-quick down`. The FAB cycles between
  "Connect to VPN" / "Disconnect VPN" and changes color depending
  on the live tunnel status.
- A 5-second background poller probes `wg show interfaces` to keep
  the FAB in sync with externally-induced state changes (user
  toggled the tunnel from a Terminal, etc.).
- Auto-installs wireguard-tools via Homebrew on first Connect if
  it's missing. The app detects Homebrew at the standard install
  paths (`/opt/homebrew/bin/brew` or `/usr/local/bin/brew`), pops
  a confirmation dialog ("Vrei să instalez wireguard-tools acum
  automat?"), and runs `brew install wireguard-tools` with a
  progress snackbar. If Homebrew itself is missing, the error
  points the user at https://brew.sh.
- Why not a Flutter NetworkExtension plugin: every Flutter
  WireGuard package on pub.dev (wireguard_flutter,
  wireguard_flutter_plus, wireguard_dart, flutter_wireguard_vpn)
  requires Apple's NetworkExtension entitlement, which in turn
  requires an Apple Developer Program membership ($99/year). The
  user explicitly opted out, so we use the same shell-out pattern
  as Tunnelblick / OpenVPN Connect.
- Linux: same flow via `pkexec wg-quick up`. Windows: not yet.

### Changed — clear "please connect to VPN" prompt on Peers / Health
- The Peers and Health screens used to display the raw dart:io
  exception ("Connection failed; this indicates an error which
  most likely cannot be solved by the library") when the agent
  was unreachable. The cause is invariably "the WireGuard tunnel
  is not active yet" — meaningless dart message, frustrating UX.
- New `lib/src/common/needs_vpn_view.dart` shows a friendly
  Romanian prompt: "Conectează-te la VPN. Datele se afișează doar
  prin tunelul WireGuard. Apasă butonul Connect to VPN..." with
  a Reîncarcă button. Both Peers and Health switch to this view
  on transport-level failures (`ApiError.kind ==
  ApiErrorKind.transport`).
- `api_client.dart` now produces a Romanian message body for any
  DioException so even screens that haven't migrated to
  NeedsVpnView yet show something readable instead of the raw
  dart:io text.

### Changed — sidebar gets logout + dark-mode toggle (M7.9)
- The Account / Logout card was moved out of Settings into the
  NavigationRail trailing actions in MainShell. One click to log
  out from anywhere instead of three.
- New theme-mode toggle icon button next to the logout button in
  the sidebar. Cycles System → Light → Dark → System. The choice
  is persisted to `prefs.json` in the app support dir via the
  new `lib/src/api/app_prefs.dart` so the next launch starts in
  the same theme.
- Settings screen now contains only About / Help content. The
  Version + Check-for-updates row was redundant with the footer
  (which has both controls on every screen) and is gone.

### Fixed — Connect to VPN button no longer overlaps the footer
- The default Material `floatingActionButtonLocation: endFloat`
  put the FAB at the bottom-right of the Scaffold body, which
  on screens with a custom footer (every screen here) means the
  FAB sat ON TOP OF the version label and check-updates button.
- New `_AboveFooterFabLocation` custom location lifts the FAB by
  `footerHeight + margin` pixels so it floats above the footer
  with clear separation.

## [1.2.4] - 2026-04-11

### Fixed — replace flutter_secure_storage with file-backed storage
- Even with `app-sandbox = false` shipped in v1.2.3, the
  `flutter_secure_storage` macOS plugin still hit
  `errSecMissingEntitlement -34018` because the package's Keychain
  path requires `keychain-access-groups` regardless of sandbox state,
  and `keychain-access-groups` requires a valid Apple Team ID prefix
  that we don't have (no Apple Developer Program membership).
  Documented in juliansteenbakker/flutter_secure_storage#804.
- Drop the `flutter_secure_storage` dependency entirely. Replace
  with a tiny file-backed JSON store at
  `~/Library/Application Support/de.icd360s.icd360svpn/identity.json`
  on macOS (equivalents on each OS via `path_provider`'s
  `getApplicationSupportDirectory`). The file is created with
  POSIX mode `0600` and the parent dir with `0700`. Atomic write
  via `.tmp` + rename. Cross-platform identical, zero plugin
  quirks, zero entitlement gymnastics.
- Threat model justification: the user IS the admin who installed
  the app on their own machine. Anything able to read this file
  already has full Keychain access too — the OS Keychain provides
  zero additional defense in this scenario, and the entitlement
  pain to use it is unbounded.

### Added — real macOS auto-update + footer Check Updates button (M7.8)
- New `lib/src/api/macos_updater.dart` performs a real self-update:
  mounts the downloaded DMG with `hdiutil`, `ditto`s the new .app
  to a per-update temp staging directory, unmounts the DMG, writes
  a small detached bash helper that polls until the parent process
  exits and then atomically replaces `/Applications/icd360svpn.app`
  via `ditto`, strips the Gatekeeper quarantine xattr, and `open`s
  the new .app. The parent app `exit(0)`s while the helper waits.
  Works for any app installed under `/Applications`. No Sparkle,
  no Apple Developer Program, no manual drag-drop.
- `update_service.dart::launchInstaller` now uses `MacosUpdater` on
  macOS and falls back to `open <DMG>` (the old manual flow) if
  the app is NOT in `/Applications` or the helper fails.
- New compact icon button in the footer next to the version label
  that triggers an on-demand version.json poll. Up-to-date → green
  snackbar. Update available → opens UpdateAvailableDialog. Errors
  → friendly Romanian snackbar.

### Added — CI verification of baked .app entitlements
- New step in `build_macos` runs
  `codesign -d --entitlements - build/macos/Build/Products/Release/icd360svpn.app`
  after `flutter build macos --release` and HARD FAILS the build
  if `app-sandbox` is somehow still `<true/>` in the signed binary.
  Catches future regressions where the entitlements file edit
  doesn't propagate through the Xcode build pipeline.

## [1.2.3] - 2026-04-11

### Fixed — drop macOS sandbox entirely (errSecMissingEntitlement -34018)
- v1.2.2 finally got DNS to resolve through the sandbox by adding
  `com.apple.security.network.client`, but the user immediately hit
  the next sandbox papercut: `flutter_secure_storage` failed with
  `errSecMissingEntitlement -34018` when trying to write the cert
  PEMs to the macOS Keychain. Sandboxed apps need
  `keychain-access-groups` to access Keychain, and we don't have it.
- We could keep adding entitlements one by one (next would be
  Documents file write for vpn_tunnel.dart, then probably another),
  but the sandbox is meaningless for a non-Apple-Developer-Program
  app distributed outside the App Store anyway. The user IS the
  admin who installed the app intentionally — the sandbox protects
  against zero threats in our model and creates a long tail of
  entitlement compatibility bugs.
- Drop `com.apple.security.app-sandbox` entirely
  (`<true/>` → `<false/>`). Network, Keychain, Files, child
  processes — all "just work" now like any other macOS desktop app.
  The CI step also hard-fails the build if app-sandbox somehow
  comes back to `<true/>`.

### Changed — distinguish invalid / expired / used codes (M7.7)
- The agent's enroll store now keeps Entry records around for 24h
  after they expire or get redeemed (instead of deleting them on
  the spot), so PopValid can return one of three specific errors:
  `ErrNotFound`, `ErrExpired`, `ErrAlreadyUsed`. The original
  "don't reveal which" stance was security theatre against a
  32^16 keyspace + 10-minute TTL + global rate limit; the UX cost
  was real.
- POST /v1/enroll now maps these to distinct HTTP statuses:
  404 (not found), 410 Gone (expired), 409 Conflict (already used).
  429 (rate limited) and 503 (disabled) are unchanged.
- The Flutter EnrollClient maps each status to a specific Romanian
  error message so the user knows whether to retype the code
  (404), ask for a new one (410/409), or wait a minute (429).

### Changed — drop hint text under the 4-box code entry
- The "Doar litere și cifre. Fără spații sau caractere speciale."
  hint is gone. The input filter still rejects everything outside
  the 32-symbol unambiguous alphabet — the user finds out at the
  first keystroke that diacritics / special chars are silently
  dropped, no need to spell it out under the boxes.

## [1.2.2] - 2026-04-11

### Fixed — actually-working macOS network.client entitlement
- The v1.2.1 attempt to add `com.apple.security.network.client` via
  `plutil -insert ... -bool YES` was rejected by macos-latest's
  plutil ("Value YES not valid for key path"), and the
  `|| echo "  network.client already present"` fallback masked the
  failure. The v1.2.1 DMG shipped with the same broken entitlements
  as v1.2.0 — the user got the EXACT same `Failed host lookup`
  error and reported it 30 seconds after install.
- Bulletproof fix: drop plutil entirely and overwrite both
  `Release.entitlements` and `DebugProfile.entitlements` with a
  known-good plist via `cat > ... <<'PLIST' ... PLIST` heredoc.
  We now control the full file content; no plutil quirks, no
  silent failures. The CI step also `grep`s the resulting files
  to hard-fail the build if `network.client` is somehow missing.

## [1.2.1] - 2026-04-11

### Fixed — macOS network sandbox blocked all outbound HTTPS
- Flutter's default `macos/Runner/Release.entitlements` only contains
  `com.apple.security.app-sandbox` — NO `network.client`. That meant
  the sandboxed macOS Flutter app could not make ANY outbound HTTP
  call: every Dio request died with `Failed host lookup: <host>`
  because the sandbox blocked the resolver. The build job in
  `.github/workflows/flutter.yml` now runs `plutil -insert
  com.apple.security.network.client -bool YES` on both
  `Release.entitlements` and `DebugProfile.entitlements` immediately
  after `flutter create --platforms=macos`. Auto-update, enrollment,
  and the release-notes viewer all work on macOS now.
- Removed the alphabet hint under the 4-box code entry. The previous
  text revealed the exact 32-symbol unambiguous alphabet which
  marginally narrowed an attacker's brute-force keyspace (from
  ~36^16 to 32^16, ~2 bits less entropy). Defense-in-depth: the
  filter still rejects everything outside the alphabet, we just no
  longer print it on screen.

### Added — client User-Agent on every outbound request (M7.6)
- New `lib/src/api/user_agent.dart` resolves the running version
  via `package_info_plus` and exposes a single string in the format
  `icd360sev_client_vpn_management_versiunea_X.Y.Z+B`. Cached after
  the first call so subsequent requests don't hit PackageInfo.
- All four Dio call sites (UpdateService, ChangelogService,
  EnrollClient, ApiClient) now set this header on every request.
- nginx access log captures `$http_user_agent` by default — grep
  `/var/log/nginx/access.log` on the server for
  `icd360sev_client_vpn_management` to see which client + which
  version is talking to the API. Useful for tracking adoption of
  new versions across the user base.

## [1.2.0] - 2026-04-11

### Added — 4-box enrollment UI + Connect to VPN button (M7.2, M7.4)
- The first-run screen now asks for the 16-char one-time code in
  four 4-character boxes (XXXX-XXXX-XXXX-XXXX) instead of a
  1500-char base64 paste. Auto-uppercase, alphabet filter (32
  unambiguous symbols, no 0/O/1/I/L matching the agent), auto-
  advance on the 4th character, backspace at empty position 0
  jumps back, paste a full 16-char code anywhere and it auto-
  spreads across all four boxes. Romanian-language UI strings.
- The app now POSTs the entered code directly to
  `https://vpn.icd360s.de/enroll` (new `EnrollClient`) and decodes
  the JSON bundle returned by the agent. The bundle includes the
  WireGuard peer config alongside the mTLS PEMs (M7.1 wire format
  v2), and we persist all of it in flutter_secure_storage.
- New floating-action **Connect to VPN** button on every screen.
  Pressing it writes the saved WireGuard `.conf` to ~/Documents
  (Downloads on Android) and asks the OS default handler to open
  it. On macOS this hands the file to WireGuard.app for one-tap
  import. No NetworkExtension entitlements, no Apple Developer
  Program — per the user's explicit constraint.

### Fixed — release-notes spinner that hung forever (M7.5)
- nginx serves `.md` files as `application/octet-stream` because the
  default mime.types ships no entry for markdown, and Dio's
  `ResponseType.plain` decoder stalled on binary content types in
  some configurations rather than just utf8-decoding regardless.
  ChangelogService now reads the body as bytes and decodes UTF-8
  manually + sets `validateStatus: (_) => true` so non-2xx
  responses raise an explicit Exception path. The matching nginx
  fix (force `text/plain; charset=utf-8` for `/updates/CHANGELOG.md`)
  is also deployed on the server.

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

[1.2.5]: https://github.com/ICD360S-e-V/vpn/compare/v1.2.4...v1.2.5
[1.2.4]: https://github.com/ICD360S-e-V/vpn/compare/v1.2.3...v1.2.4
[1.2.3]: https://github.com/ICD360S-e-V/vpn/compare/v1.2.2...v1.2.3
[1.2.2]: https://github.com/ICD360S-e-V/vpn/compare/v1.2.1...v1.2.2
[1.2.1]: https://github.com/ICD360S-e-V/vpn/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/ICD360S-e-V/vpn/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/ICD360S-e-V/vpn/compare/v1.0.2...v1.1.0
[1.0.2]: https://github.com/ICD360S-e-V/vpn/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/ICD360S-e-V/vpn/releases/tag/v1.0.1
[0.0.1]: https://github.com/ICD360S-e-V/vpn/releases/tag/v0.0.1
