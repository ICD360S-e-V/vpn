# vpn.icd360s.de — server-side setup runbook

This file documents the **non-application** infrastructure on the
production VPN server (`vpn.icd360s.de`, Azure VM running AlmaLinux
9.7) that supports the icd360svpn admin app's release pipeline +
the WireGuard-over-TCP fallback for restrictive firewalls.

It is the **runbook** — useful when rebuilding the box from scratch
or onboarding a second admin. The actual `vpn-agent` Go daemon is
documented in `agent/README.md`; this file covers everything around
it.

## Topology overview

```
              Internet
                 │
        ┌────────┼─────────┐
        │        │         │
   TCP/36000  TCP/80    TCP/443
        │   (LE+redir)      │
        │        │     ┌────┴────┐
       SSH     nginx   │  nginx  │ ← LE cert vpn.icd360s.de
                       └────┬────┘
                            │ path-routed
              ┌─────────────┼─────────────┐
              │             │             │
         /download/    /updates/      /wg-tcp/
         (static)      (static)        proxy_pass
                                       127.0.0.1:8444
                                            │
                                       wstunnel server
                                       (DynamicUser, 12 MB Rust binary)
                                            │ UDP forward
                                            ▼
                                  127.0.0.1:443 (wg0 kernel)

   UDP/443 ─────────────────────────────► wg0 (direct happy path)

   tunnel-internal only:
   - 10.8.0.1:8443  vpn-agent (mTLS HTTPS API)
   - 10.8.0.1:53    AdGuard Home (DNS)
   - 10.8.0.1:3000  AdGuard Home (web UI)
```

## Azure NSG inbound rules

| Priority | Name | Port | Protocol | Source | Action |
|---|---|---|---|---|---|
| 140 | ssh-server | 36000 | TCP | Any | Allow |
| 150 | vpn | 443 | UDP | Any | Allow |
| 160 | http | 80 | TCP | Any | Allow |
| 170 | https | 443 | TCP | Any | Allow |

## Server-side firewalld

```
public (active)
  interfaces: eth0
  services: cockpit dhcpv6-client http https
  ports: 36000/tcp 443/udp
  forward: yes
  masquerade: yes

trusted (active)
  interfaces: wg0
```

## Software inventory

| Package | Version | Source | Notes |
|---|---|---|---|
| `vpn-agent` | M4.4 (`0.0.1-m4.4`) | self-built Go binary | `/usr/local/sbin/vpn-agent`, systemd `vpn-agent.service` |
| `nginx` | 1.20.1 | dnf (AlmaLinux 9 base) | M6.2 |
| `certbot` + `python3-certbot-nginx` | latest | dnf (EPEL) | M6.2 |
| `wstunnel` | 10.5.2 | direct download from upstream `github.com/erebe/wstunnel/releases` | M6.2, `/usr/local/bin/wstunnel` |
| `rrsync` | upstream | `curl -fsSL .../support/rrsync` | M6.3, `/usr/local/bin/rrsync` |
| `rsync` | 3.2.5 | dnf | M6.3 |
| `AdGuardHome` | 0.107.73 | direct download | `/opt/AdGuardHome/` |
| `wireguard-tools` | 1.0.20210914 | dnf (EPEL) | kernel module is in-tree |

## SELinux state

Enforcing. Required booleans:

```bash
setsebool -P httpd_can_network_connect on   # nginx → wstunnel
setsebool -P httpd_can_network_relay on
```

Required fcontext rules (added by M6.3):

```bash
semanage fcontext -a -t httpd_sys_content_t '/var/www/html(/.*)?'
restorecon -R /var/www/html
```

Without the fcontext rule, files uploaded by `vpn-deploy` via rsync
inherit `var_t` (since `/var/www/` doesn't exist by default in the
base AlmaLinux SELinux policy) and nginx returns 403.

## nginx vhost layout

`/etc/nginx/conf.d/vpn.icd360s.de.conf`:

- `server` on `:80` — ACME challenge passthrough + 301 redirect to
  HTTPS.
- `server` on `:443 ssl http2` with the LE cert from
  `/etc/letsencrypt/live/vpn.icd360s.de/`. Locations:
  - `/` — `200 text/plain` landing
  - `/download/` — autoindex on, immutable Cache-Control
  - `/updates/version.json` — short cache, application/json
  - `/wg-tcp/` — `proxy_pass http://127.0.0.1:8444` with WebSocket
    Upgrade headers and `proxy_read_timeout 86400s`. Routes to the
    wstunnel server.

HTTP/2 syntax on nginx 1.20 uses the **legacy form**
`listen 443 ssl http2;`, NOT the standalone `http2 on;` directive
(that one is nginx 1.25+).

## wstunnel server

`/etc/systemd/system/wstunnel.service`:

```
ExecStart=/usr/local/bin/wstunnel server \
    --restrict-to 127.0.0.1:443 \
    ws://127.0.0.1:8444
DynamicUser=yes
```

Key facts:
- **Plaintext WebSocket** on `127.0.0.1:8444`. nginx terminates TLS
  upstream and proxies the Upgrade through. wstunnel never sees
  the LE cert.
- `--restrict-to 127.0.0.1:443` prevents the relay from being
  abused as an open TCP/UDP forwarder. The only allowed forward
  destination is the local WireGuard kernel listener.
- `DynamicUser=yes` runs the daemon as a fresh ephemeral UID with
  no home directory. Combined with `MemoryDenyWriteExecute=true`
  and the rest of the systemd hardening directives, the blast
  radius if wstunnel is ever 0-day'd is minimal.

### Client-side wstunnel (the fallback the user runs on their laptop)

```bash
wstunnel client \
  --http-upgrade-path-prefix wg-tcp \
  -L 'udp://51820:127.0.0.1:443?timeout_sec=0' \
  wss://vpn.icd360s.de:443
```

Then their WireGuard client config has `Endpoint = 127.0.0.1:51820`
and the rest of the [Peer] block is unchanged. The same pubkey,
PSK, and AllowedIPs work — only the transport differs.

## Release deploy user (`vpn-deploy`)

Created so GitHub Actions can rsync release artifacts into
`/var/www/html/` after every `v*` tag push.

| Setting | Value |
|---|---|
| Username | `vpn-deploy` |
| UID | system (~994) |
| Home | `/home/vpn-deploy` |
| Shell | `/bin/sh` (forced command takes over) |
| `~/.ssh/authorized_keys` | Single line with `command="/usr/local/bin/rrsync -wo /var/www/html",no-pty,no-agent-forwarding,no-port-forwarding,no-X11-forwarding,no-user-rc,restrict <ed25519 pubkey>` |
| Owns | `/var/www/html` recursively |

The forced command pins every accepted SSH session to `rrsync` in
write-only mode, scoped to `/var/www/html`. The user cannot:
- Get a shell prompt
- List files (no read mode)
- Run any other binary
- Open port forwards
- Use the agent

The shell is `/bin/sh` rather than `nologin` because `nologin`
refuses to spawn at all, which would also block the forced
`rrsync` invocation. Real security comes from the `command="..."`
directive, not from the shell.

### How GitHub Actions uses it

The `release` job in `.github/workflows/flutter.yml` reads four
secrets — `VPN_DEPLOY_SSH_{KEY,HOST,PORT,USER}` — and runs:

```bash
rsync -avz --no-times --no-owner --no-group \
  -e "ssh -i ~/.ssh/deploy -p 36000 -o StrictHostKeyChecking=accept-new" \
  ${{ github.workspace }}/out/ \
  vpn-deploy@vpn.icd360s.de:.
```

Note the **trailing `:.`** (relative to the rrsync root, NOT `:/`).
rrsync rejects absolute paths.

The remote ends up as:
```
/var/www/html/download/vpn-management_icd360sev/<platform>/<filename>
/var/www/html/updates/version.json
/var/www/html/SHA256SUMS.txt
```

### Rotating the deploy key

If the GitHub secret leaks:

```bash
# 1. Generate a new key on a build host
ssh-keygen -t ed25519 -a 100 -N '' -f vpn-deploy.key.new \
  -C 'github-actions@icd360s-vpn (rotated YYYY-MM-DD)'

# 2. Replace authorized_keys on vpn.icd360s.de
ssh root@vpn.icd360s.de "
  sudo bash -c 'cat > /home/vpn-deploy/.ssh/authorized_keys' <<EOF
command=\"/usr/local/bin/rrsync -wo /var/www/html\",no-pty,no-agent-forwarding,no-port-forwarding,no-X11-forwarding,no-user-rc,restrict $(cat vpn-deploy.key.new.pub)
EOF"

# 3. Update the GitHub secret
gh secret set VPN_DEPLOY_SSH_KEY --body "$(cat vpn-deploy.key.new)" \
  --repo ICD360S-e-V/vpn

# 4. Shred the old key locally and on the server.
```

## Let's Encrypt

Cert is issued for `vpn.icd360s.de` only (no SANs in the path-based
multiplexing design). Auto-renewal via the certbot systemd timer:

```
$ systemctl list-timers certbot-renew.timer
```

If the renewal ever fails, force a renew with:
```
sudo certbot renew --force-renewal
sudo systemctl reload nginx
```

## Manual sanity checks (after a rebuild)

```bash
# 1. Public HTTPS works
curl -fsS https://vpn.icd360s.de/ | head

# 2. WireGuard UDP listener
curl -fsS https://vpn.icd360s.de/updates/version.json | jq .

# 3. wstunnel HTTP Upgrade endpoint reachable through nginx
curl -sI -H 'Connection: Upgrade' -H 'Upgrade: websocket' \
     -H 'Sec-WebSocket-Version: 13' \
     -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' \
     https://vpn.icd360s.de/wg-tcp/  # expect 400 from wstunnel (good)

# 4. SSH deploy key works (from a build host that has it)
rsync -avz --no-times --no-owner --no-group \
  -e "ssh -i ~/.ssh/id_ed25519_vpn_deploy -p 36000" \
  /tmp/test/ vpn-deploy@vpn.icd360s.de:.

# 5. mTLS API on wg0 reachable from a connected WG client
curl -fsS --cacert ca.pem --cert client.pem --key client.key \
  https://10.8.0.1:8443/v1/health
```
