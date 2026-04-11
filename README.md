# ICD360S VPN

Cross-platform admin app + Go management agent for the **ICD360S e.V.**
WireGuard VPN deployment.

- **Agent** (`agent/`) — single static Go binary that runs on the
  WireGuard server, exposes a typed mTLS HTTPS API for peer
  management, health, and bandwidth stats.
- **App** (`app/`) — Flutter desktop + mobile client (macOS, Linux,
  Windows, Android, iOS) for non-technical admins. Connects to the
  agent over the WireGuard tunnel.

## Releases

Pre-built installers for every platform are published on every
`v*` tag:

- [GitHub Releases](https://github.com/ICD360S-e-V/vpn/releases)
- Auto-update endpoint: the running app polls
  `https://vpn.icd360s.de/updates/version.json` once a day and
  prompts the user when a new build is available.

## Documentation

- [`CHANGELOG.md`](CHANGELOG.md) — release notes per version
- [`docs/release.md`](docs/release.md) — how to cut a new release
- [`docs/vpn-server-setup.md`](docs/vpn-server-setup.md) — public
  infrastructure runbook for the VPN server (no credentials)
- [`proto/openapi.yaml`](proto/openapi.yaml) — API schema between
  agent and app

## Build

```bash
# Agent (Go ≥ 1.25)
cd agent
go vet ./... && go test ./... && go build ./cmd/vpn-agent

# App (Flutter ≥ 3.41)
cd app
flutter create --platforms=macos,linux,windows,android,ios --project-name icd360svpn --org de.icd360s .
flutter pub get
flutter build macos --release   # or linux / windows / apk / ios
```

CI runs the same steps on `ubuntu-latest`, `macos-latest`, and
`windows-latest` for every PR and every `v*` tag — see
[`.github/workflows/`](.github/workflows/).

## Versioning

Conventional Commits + [release-please](https://github.com/googleapis/release-please).
`feat:` commits bump the minor version, `fix:` commits bump the
patch version, `BREAKING CHANGE:` footers bump the major version.
Changelog entries are auto-generated from commit messages.

## License

[MIT](LICENSE) © 2026 ICD360S e.V.

The source is freely usable, modifiable, and redistributable under
the MIT license. Note that the **service** itself
(`vpn.icd360s.de`) requires a per-device enrollment code issued
out-of-band by an admin — anyone can build the app, but only
users with a valid code can connect to the production server.
