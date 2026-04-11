# macOS App

Native SwiftUI desktop app for managing the ICD360S VPN server. Talks
to `vpn-agent` over the WireGuard tunnel via mutual TLS.

## Quick start (on a Mac)

```bash
git clone https://github.com/ICD360S-e-V/vpn.git
cd vpn/app
swift build           # builds the executable target
swift run ICD360SVPN  # launches the app

# Or open Package.swift in Xcode 15+ for SwiftUI previews and code completion.
```

Requires **macOS 14 (Sonoma)** and **Swift 5.9+**. Zero third-party
dependencies — only Foundation, SwiftUI, Security, CoreImage, and
AppKit (for `NSPasteboard`/`NSImage`).

## First run — enrollment

The app stores no credentials by default, so on first launch you see
the **Enroll this Mac** screen. To populate it, ssh to the VPN server
and run `vpn-agent issue-cert` to mint a fresh client certificate
signed by the agent's local CA:

```bash
ssh -i ~/.ssh/id_ed25519_vpn_icd360s_de -p 36000 icd360sev@vpn.icd360s.de
sudo /usr/local/sbin/vpn-agent issue-cert \
    --cert-dir /etc/vpn-agent \
    --out /tmp/admin-andrei \
    andrei-laptop
sudo cat /tmp/admin-andrei/andrei-laptop-ca.pem
sudo cat /tmp/admin-andrei/andrei-laptop.pem
sudo cat /tmp/admin-andrei/andrei-laptop.key
```

Copy each of those three PEM blobs into the matching field in the
EnrollmentView, leave the agent URL at the default `https://10.8.0.1:8443`,
and press **Connect**. The app will:

1. Convert the cert + key into a PKCS#12 envelope using the system
   `/usr/bin/openssl` (we shell out for M3 — see KeychainStore.swift's
   TODO).
2. Import the resulting identity into the macOS Keychain under the
   label `ICD360SVPN.admin`.
3. Store the CA cert separately under `ICD360SVPN.ca`.
4. Build an `APIClient` using a URLSession bound to a custom
   `MTLSDelegate` that pins the server cert to your CA and presents
   the client identity for client-cert challenges.
5. Switch to the main UI.

On every subsequent launch, `AppState.bootstrap()` fetches the
identity from Keychain and goes straight to the connected state — no
re-enrollment.

> ⚠️ **Reachability**: the agent listens on `10.8.0.1:8443`, which is
> the WireGuard server's tunnel address. Your Mac must already be a
> connected WireGuard client (with `AllowedIPs` covering `10.8.0.0/24`)
> for the API call to even make TCP. The app intentionally has no path
> through the public internet — defense in depth.

## Architecture

```
ICD360SVPNApp (@main)
   ├─ owns AppState (@Observable)
   │      ├─ phase: AppPhase = .needsEnrollment | .connected(APIClient) | …
   │      ├─ bootstrap() async  ─ Keychain probe at launch
   │      ├─ enroll(...)  async  ─ PEM → PKCS12 → Keychain → APIClient
   │      └─ logout()             ─ wipe Keychain, back to enrollment
   │
   └─ ContentView (env: AppState)
          └─ switch state.phase
                ├─ .needsEnrollment → EnrollmentView
                ├─ .connecting      → ProgressView
                ├─ .connected(c)    → MainView(client: c)
                │      └─ NavigationSplitView
                │            ├─ Sidebar: Peers / Health / Settings
                │            └─ Detail:
                │                  ├─ PeersView    (list / create / revoke)
                │                  ├─ HealthView   (5s polling)
                │                  └─ SettingsView (logout / about)
                └─ .error(msg)      → ErrorView
```

## Network layer

Everything HTTP lives in `Networking/`:

| File | Purpose |
|---|---|
| `MTLSDelegate.swift` | URLSessionDelegate. Pins server trust to a single CA, presents the client identity for the cert challenge. |
| `APIClient.swift` | `actor APIClient`. Typed async methods: `health()`, `listPeers()`, `createPeer(name:)`, `deletePeer(publicKey:)`. JSON encoding uses `convertToSnakeCase` and decoding uses `convertFromSnakeCase`. Custom date strategy handles RFC 3339 with **fractional seconds** (the agent emits `2026-04-11T13:14:18.895571198Z`, which the standard `.iso8601` strategy refuses). |
| `KeychainStore.swift` | Wraps Security.framework: PKCS12 import, identity / CA add / load / delete, plus the M3 `pemBundleToPKCS12` helper that shells out to `openssl`. |

Errors are normalised into the `APIError` enum (`Models/APIError.swift`)
which speaks RFC 7807 `application/problem+json` natively.

## Layout

```
app/
├── Package.swift
├── README.md
└── Sources/
    └── ICD360SVPN/
        ├── ICD360SVPNApp.swift           ← @main
        ├── AppState.swift                ← lifecycle / phase machine
        ├── ContentView.swift             ← phase router
        │
        ├── Models/
        │   ├── Peer.swift
        │   ├── Health.swift
        │   ├── PeerCreateRequest.swift
        │   ├── PeerCreateResponse.swift
        │   └── APIError.swift            ← + nested ProblemDetails
        │
        ├── Networking/
        │   ├── APIClient.swift           ← actor + JSON wrapper
        │   ├── MTLSDelegate.swift
        │   └── KeychainStore.swift       ← + KeychainError enum
        │
        ├── Components/
        │   ├── StatusBadge.swift
        │   └── QRCodeView.swift          ← CoreImage CIQRCodeGenerator
        │
        └── Features/
            ├── Enrollment/EnrollmentView.swift
            ├── Main/
            │   ├── MainView.swift        ← NavigationSplitView
            │   └── ErrorView.swift
            ├── Peers/
            │   ├── PeersView.swift       ← list + delete
            │   ├── PeerRow.swift
            │   └── CreatePeerSheet.swift ← + QR display
            ├── Health/HealthView.swift
            └── Settings/SettingsView.swift
```

## Known limitations (M3)

- **PKCS#12 export shells out to `/usr/bin/openssl`.** Apple does not
  expose a public PKCS#12 export API. M4 should replace this with a
  pure-Swift implementation (e.g. swift-asn1) so the app has zero
  shell dependencies. Tracked in `KeychainStore.pemBundleToPKCS12`.
- **`SecPKCS12Import` returns `errSecAuthFailed (-25293)` on
  macOS Sequoia 15.x even with valid PKCS#12 blobs** ([Apple
  Developer Forums #697030][f697030], [#723242][f723242],
  [#764516][f764516]). This is a known regression in macOS Sequoia's
  Security framework — there is no client-side workaround. If you hit
  it, the bundled openssl PBE-SHA1-3DES blob is correct; the bug is
  inside Apple's importer. Workarounds users have reported:
  re-generating the PKCS#12 with explicit MAC iterations (`-macsaltlen
  20 -iter 2048`), or downgrading the macOS test machine to Sonoma
  14.x. Track [openradar FB8988319][rdar].

[f697030]: https://developer.apple.com/forums/thread/697030
[f723242]: https://developer.apple.com/forums/thread/723242
[f764516]: https://forums.developer.apple.com/forums/thread/764516
[rdar]:    https://openradar.appspot.com/FB8988319
- **No bandwidth charts yet.** That's M5.
- **No AdGuard Home query log view.** That's M6.
- **No new-peer-from-country alert.** That's M7.
- **App is unsigned and unsandboxed.** That's M8.
- **Enrollment is manual paste, not via an HTTP enrollment endpoint.**
  The agent does not yet expose `/v1/admin/enroll`. M3.5 / M4 will add
  it so admins enroll via a one-time token instead of pasting PEM.

## Verifying the build

Cannot be verified in CI on the alma server (no Swift toolchain on
AlmaLinux 10). Compilation must happen on a Mac. Run:

```bash
cd app
swift build 2>&1 | head -50
```

Any error here is a real issue — please report it.
