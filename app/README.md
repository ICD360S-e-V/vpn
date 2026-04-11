# macOS App

Native SwiftUI application for managing the ICD360S VPN server.

> **Status: M0 — empty placeholder.** Real Xcode project lands at M3.

## Target

- **Platform:** macOS 14 (Sonoma) and later
- **Language:** Swift 5.10+
- **UI:** SwiftUI (no AppKit fallback unless absolutely needed)
- **Charts:** Swift Charts (built-in, requires macOS 13+)
- **Async:** structured concurrency (`async`/`await`, `Task`)
- **Networking:** `URLSession` with custom `URLSessionDelegate` for
  mTLS pinning. Do **not** use third-party HTTP libraries — security
  surface area must stay tiny.
- **Persistence:** SwiftData for cached peer list and stats. Keychain
  for the client cert and private key.

## Why macOS-only and not Catalyst / iOS

The audience for this is the small set of admins who manage the
server day-to-day. They all use macOS. Building Catalyst doubles
the QA matrix for negligible reach. iOS adds App Store review pain.
We will revisit if a real need appears.

## Project structure (planned)

```
app/
├── ICD360SVPN.xcodeproj
├── ICD360SVPN/
│   ├── ICD360SVPNApp.swift       # @main entry, scene setup
│   ├── Models/                   # Codable types from the OpenAPI spec
│   ├── Networking/
│   │   ├── APIClient.swift       # URLSession wrapper, mTLS delegate
│   │   ├── KeychainStore.swift   # cert/key storage
│   │   └── Endpoints.swift       # typed endpoint definitions
│   ├── Features/
│   │   ├── Connections/          # live connections view
│   │   ├── Peers/                # list, add, revoke
│   │   ├── Stats/                # bandwidth charts
│   │   └── AdGuard/              # query log viewer
│   ├── Components/               # reusable SwiftUI views
│   └── Resources/
│       ├── Assets.xcassets
│       └── Localizable.strings
└── ICD360SVPNTests/
```

## Mockups

TBD — start with wireframes in `docs/mockups/` before any UI code.
The first screen to design is **Peers** since it is the densest.

## First-run flow

1. App launches with no client cert in Keychain.
2. App shows a "Connect to your VPN server" screen with two fields:
   - Agent URL (default: `https://10.8.0.1:8443`)
   - One-time enrollment token (printed by `vpn-agent` on first run)
3. App POSTs `/v1/admin/enroll` with the token, receives a client
   cert + private key, stores both in Keychain.
4. App switches to the main window.

Subsequent launches read the cert from Keychain and connect directly.
