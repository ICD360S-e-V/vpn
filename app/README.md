# icd360svpn — Flutter desktop admin app

Cross-platform Flutter app for managing the ICD360S WireGuard VPN
server. Talks to `vpn-agent` on `vpn.icd360s.de` over mutual TLS, on
the WireGuard tunnel itself.

> **Status:** M5 — first cut. Single SwiftPM-style scaffold with no
> committed platform directories. Build verification happens in
> GitHub Actions on `macos-latest`, `ubuntu-latest`, and
> `windows-latest`. See `.github/workflows/flutter.yml`.

## Targets

| Platform | Status | Build runner |
|---|---|---|
| **macOS** | primary | `macos-latest` |
| Linux desktop | secondary | `ubuntu-latest` |
| Windows | tertiary | `windows-latest` |
| iOS / Android | not yet | — |

## Stack

| Concern | Package | Reason |
|---|---|---|
| HTTP client + interceptors | `dio ^5.7.0` | mTLS via `IOHttpClientAdapter` |
| State management | `flutter_riverpod ^3.0.0` | small-app sweet spot in 2026 per research agent |
| Secure cert storage | `flutter_secure_storage ^10.0.0` | Keychain / libsecret / DPAPI / Keystore |
| Bandwidth charts | `fl_chart ^0.70.0` | smallest binary impact, BSD-3 |
| QR rendering | `qr_flutter ^4.1.0` | pure-Dart, no native deps |
| Lints | `flutter_lints ^5.0.0` | strict-casts + strict-inference + strict-raw-types |

JSON parsing is **hand-rolled** — no `json_serializable` / `build_runner`
in the dependency graph. Six small models is below the threshold
where code-gen pays for itself.

## Layout

```
app/
├── pubspec.yaml
├── analysis_options.yaml
├── README.md (you are here)
└── lib/
    ├── main.dart                    Entry point, ProviderScope
    └── src/
        ├── app.dart                 AppPhase machine + ContentRouter + Material theme
        │
        ├── models/
        │   ├── peer.dart                  GET /v1/peers element
        │   ├── health.dart                GET /v1/health
        │   ├── peer_create_response.dart  POST /v1/peers response
        │   ├── traffic_series.dart        GET /v1/peers/{pubkey}/bandwidth
        │   ├── enrollment_bundle.dart     base64+gzip+json from `vpn-agent issue-bundle`
        │   └── api_error.dart             RFC 7807 problem+json + transport / decoding
        │
        ├── api/
        │   ├── api_client.dart      Dio wrapper, one method per endpoint
        │   ├── mtls_context.dart    SecurityContext factory (PEM bytes)
        │   └── secure_store.dart    flutter_secure_storage wrapper
        │
        ├── common/
        │   ├── status_badge.dart    Coloured capsule for `ok` / `degraded`
        │   └── qr_code_view.dart    Thin wrapper around qr_flutter
        │
        └── features/
            ├── enrollment/enrollment_screen.dart   Paste 1 base64 blob, hit Connect
            ├── main/main_shell.dart                NavigationRail Peers / Health / Settings
            ├── main/error_screen.dart              Generic error + Reset
            ├── peers/peers_screen.dart             List + refresh + create + revoke
            ├── peers/peer_tile.dart                Row with switch (enable/disable)
            ├── peers/create_peer_dialog.dart       Name → POST → result + QR + copy
            ├── health/health_screen.dart           5s polling, status + uptime + version
            └── settings/settings_screen.dart       Logout + about
```

## Why no `macos/`, `linux/`, `windows/` committed?

`flutter create --platforms=$X .` regenerates the platform-specific
scaffold (Xcode project, CMakeLists, MSBuild solution) cleanly each
build. Committing them would lock us into a specific Flutter SDK
version's template AND make the diff noisy when Flutter ships
template updates. We don't customise any of those files yet, so
generating them on-the-fly in CI is strictly better.

**When this stops being the right call:** the moment we need to
customise `Info.plist` (entitlements for code signing), the macOS
`.entitlements` file (network client capability), or
`linux/CMakeLists.txt` (extra system deps). At that point, commit
the platform dir.

## First run

1. **Server side:** SSH to vpn.icd360s.de and issue an enrollment bundle:
   ```bash
   ssh -i ~/.ssh/id_ed25519_vpn_icd360s_de -p 36000 icd360sev@vpn.icd360s.de
   sudo /usr/local/sbin/vpn-agent issue-bundle andrei-mac
   ```
   Copy the single base64 line printed to stdout.

2. **Client side:** Launch the app. On first run it shows the
   enrollment screen with one TextField. Paste the base64 blob, hit
   **Connect**. The app:
   - decodes (base64 → gzip → JSON),
   - extracts cert / key / CA / agent URL,
   - writes them into the OS secure store via `flutter_secure_storage`,
   - builds a `dart:io` `SecurityContext` and a Dio client,
   - flips into the connected state.

3. On every subsequent launch, `AppPhaseController.bootstrap()` reads
   the saved identity and goes straight to the connected state.

## Build locally (on a Mac)

```bash
cd app
flutter create --platforms=macos --project-name icd360svpn --org de.icd360s .
flutter pub get
flutter run -d macos
```

Or just `flutter build macos --no-codesign`. Linux/Windows builds
work with the analogous commands.

## CI

`.github/workflows/flutter.yml` runs four jobs on every push that
touches `app/`:

| Job | Runner | Steps |
|---|---|---|
| `analyze` | ubuntu-latest | `flutter analyze` (and `flutter test` if any tests exist) |
| `build_linux` | ubuntu-latest | install gtk + libsecret deps, then `flutter build linux --release` |
| `build_macos` | macos-latest | `flutter build macos --release --no-codesign` |
| `build_windows` | windows-latest | `flutter build windows --release` |

Each build job uploads the resulting bundle as a workflow artifact.
There is no flutter SDK on the alma server: we never compile here.

## Known limitations (M5 first cut)

- **No bandwidth chart screen yet.** The model + endpoint client
  exist (`TrafficSeries`, `ApiClient.peerBandwidth`); the chart UI
  will land in M5.1.
- **No peer detail screen yet.** Tapping a peer doesn't navigate
  anywhere — the row is the source of truth.
- **No tests.** `flutter test` is run by CI if `test/**/*.dart`
  files exist; they don't yet.
- **No app icon.** Will land when we customise the platform
  directories.
- **No code signing.** macOS build runs with `--no-codesign`. M8 will
  set up notarisation.
