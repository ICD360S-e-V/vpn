# ICD360S VPN — macOS Admin App

Native macOS application for managing the **ICD360S WireGuard VPN** server
running on `vpn.icd360s.de`.

## Goal

A SwiftUI desktop client that lets an admin manage the VPN server **from a
single window** without ever opening a terminal:

- 📊 **Live connections** — see who is currently connected, with IPs,
  endpoints, last handshake, and per-peer transfer counters (RX/TX).
- 👥 **Peer management** — add a new client (generates keys, PSK,
  next free `10.8.0.x`, writes `[Peer]` block server-side, returns a
  `.conf` + QR code locally) and revoke existing peers.
- 📈 **Bandwidth stats** — total ingress / egress per peer per day,
  per week, per month. Charts.
- 🛡️ **AdGuard Home integration** — number of queries served, percent
  blocked, top blocked domains, last queries (read-only mirror of the
  AdGuard query log).
- 🔔 **Alerts** — push notification (macOS Notification Center) when
  a new peer connects from a new country, or when bandwidth crosses
  a threshold.

## Architecture

```
┌──────────────────────────┐         ┌──────────────────────────────┐
│  macOS app  (SwiftUI)    │         │  vpn.icd360s.de              │
│                          │         │                              │
│  - SwiftUI views         │         │  ┌────────────────────────┐  │
│  - Combine / async-await │  HTTPS  │  │ vpn-agent              │  │
│  - Charts (Swift Charts) │ ◀─────▶ │  │ (small Go/Rust HTTP    │  │
│  - Keychain (mTLS cert)  │  +mTLS  │  │  daemon, runs as root) │  │
│                          │         │  └────────┬───────────────┘  │
│                          │         │           │                  │
│                          │         │           ▼                  │
│                          │         │  - wg show / wg syncconf     │
│                          │         │  - reads /etc/wireguard/     │
│                          │         │  - AdGuard Home REST API     │
│                          │         │  - nftables byte counters    │
└──────────────────────────┘         └──────────────────────────────┘
```

The macOS app **does not** SSH into the server. It talks to a small
HTTP service (`vpn-agent`) on the server, behind mTLS, that exposes a
typed REST/JSON API. Reasons:

1. SSH-based control is fragile, hard to authenticate, and requires
   shipping a private key inside an app bundle.
2. mTLS with a per-device cert lets us revoke individual admin clients.
3. The agent is the **single source of truth** for "is this action
   allowed", lets us audit, rate-limit, and replay-protect.
4. Splits concerns: server team owns the agent, app team owns the UI.

### Components in this repo

| Path | Description |
|---|---|
| `app/` | Xcode project, SwiftUI macOS app (target: macOS 14+) |
| `agent/` | `vpn-agent` HTTP daemon (Go, single static binary) |
| `proto/` | OpenAPI spec shared by app and agent |
| `docs/` | Architecture notes, threat model, deployment runbook |

## Endpoints (planned)

| Method | Path | Description |
|---|---|---|
| `GET`  | `/v1/peers` | list all peers + their last-handshake / RX / TX |
| `POST` | `/v1/peers` | create a new peer (server allocates IP, keys, PSK; returns .conf) |
| `DELETE` | `/v1/peers/{pubkey}` | revoke a peer |
| `GET`  | `/v1/connections` | currently active sessions |
| `GET`  | `/v1/stats/traffic?from=…&to=…` | per-peer bandwidth time series |
| `GET`  | `/v1/adguard/queries?since=…` | proxied AdGuard query log |
| `GET`  | `/v1/adguard/stats` | totals + top-blocked domains |
| `GET`  | `/v1/health` | server uptime, wg0 up, AdGuard up, disk free |

## Server requirements

- Reachable at `vpn.icd360s.de`
- WireGuard kernel module + `wireguard-tools` (already installed)
- AdGuard Home with REST API enabled (already installed, bound on `10.8.0.1:3000`)
- `vpn-agent` listening on `:8443/tcp`, behind mTLS only — **never on the public internet**:
  the agent listens on `10.8.0.1:8443` (the wg0 IP), so it is reachable
  **only through the VPN tunnel itself**. Same defense-in-depth pattern
  as AdGuard Home.

## Roadmap

- [ ] **M0** — repo scaffolding (this commit)
- [ ] **M1** — `vpn-agent` skeleton: `/v1/health`, mTLS bootstrap, systemd unit
- [ ] **M2** — `vpn-agent`: peer list / create / delete, integration with `wg` and `wg0.conf`
- [ ] **M3** — macOS app skeleton: connect to agent, show peer list
- [ ] **M4** — peer creation flow with QR code rendering
- [ ] **M5** — bandwidth stats (nftables counters or `wg show transfer`) + Swift Charts
- [ ] **M6** — AdGuard Home integration (proxy)
- [ ] **M7** — alerts + notifications
- [ ] **M8** — sign + notarize, distribute via DMG

## License

Proprietary — internal use by ICD360S e.V. only.
