# vpn-agent

Single-binary HTTP daemon that runs on `vpn.icd360s.de` and exposes a
typed JSON API over mTLS for the macOS admin app to call.

> **Status: M0 — empty placeholder.** Real implementation starts at M1.

## Layout (planned)

```
agent/
├── cmd/vpn-agent/main.go         # entry point, CLI flags, config loading
├── internal/
│   ├── api/                      # HTTP handlers, one file per resource
│   ├── wg/                       # wrapper around `wg` and wg0.conf
│   ├── adguard/                  # proxy to AdGuard Home REST API
│   ├── stats/                    # bandwidth sampler, sqlite storage
│   ├── mtls/                     # CA, cert issuance, revocation
│   └── auth/                     # client cert validation, audit log
├── go.mod
├── go.sum
└── systemd/vpn-agent.service     # systemd unit
```

## Build

```bash
cd agent
go build -trimpath -ldflags='-s -w' -o vpn-agent ./cmd/vpn-agent
```

Output: a single ~12 MB static binary. Drop into `/usr/local/sbin/`
on the server, install the systemd unit, done.

## Run (dev)

```bash
sudo ./vpn-agent --config /etc/vpn-agent/config.toml --log-level debug
```

## Configuration

`/etc/vpn-agent/config.toml`:

```toml
[server]
listen = "10.8.0.1:8443"      # bind to wg0 only — never 0.0.0.0
cert   = "/etc/vpn-agent/server.pem"
key    = "/etc/vpn-agent/server.key"
ca     = "/etc/vpn-agent/ca.pem"

[wireguard]
config_path = "/etc/wireguard/wg0.conf"
interface   = "wg0"
subnet      = "10.8.0.0/24"

[adguard]
url      = "http://10.8.0.1:3000"
username = "admin"
password = "admin"

[stats]
db_path        = "/var/lib/vpn-agent/stats.db"
sample_period  = "60s"
retention_raw  = "90d"
```

## Security checklist for M1

- [ ] Bind ONLY to `10.8.0.1:8443`. Refuse to start if `0.0.0.0` or
      a public IP is configured.
- [ ] Validate that `cert` is the cert for the CA in `ca`.
- [ ] mTLS: require client cert (`tls.RequireAndVerifyClientCert`).
- [ ] All requests logged with cert SN, path, status, latency,
      caller IP. Logs to journald.
- [ ] systemd unit: `ProtectSystem=strict`, `ProtectHome=true`,
      `PrivateTmp=true`, `NoNewPrivileges=true`, `ReadWritePaths=`
      only for `/etc/wireguard`, `/var/lib/vpn-agent`.
- [ ] No CGO. Static link with `CGO_ENABLED=0`.
- [ ] `go vet`, `staticcheck`, `gosec` clean before merging.
