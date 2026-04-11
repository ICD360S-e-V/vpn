# Security Policy

## Reporting a vulnerability

If you discover a security vulnerability in `ICD360S-e-V/vpn`,
**please do not open a public issue**. Instead, use one of the
private channels below so we can confirm and ship a fix before
the details become public.

### Preferred: GitHub Private Vulnerability Reporting

The fastest path is the
[Security tab](https://github.com/ICD360S-e-V/vpn/security/advisories/new)
on this repo. It opens a private advisory thread visible only to
maintainers and (later) collaborators we explicitly invite.

### Backup: email

`security@icd360s.de` (PGP optional, will reply with a key on
request).

Please include:

- Affected component (`agent/`, `app/`, server-side infrastructure)
- Affected version(s) — `vpn-agent version` and the app's footer
  show the running version
- Reproduction steps or proof-of-concept
- Your assessment of the impact

We will acknowledge within **72 hours** and commit to a fix
timeline within **7 days**. Coordinated disclosure is appreciated;
we credit reporters in the changelog and the published advisory
unless asked otherwise.

## Scope

| In scope | Out of scope |
|---|---|
| `agent/` Go daemon (mTLS, enrollment, peer management) | Social engineering of administrators |
| `app/` Flutter admin app (enrollment flow, secure storage, auto-update verification) | Physical access to a machine running the app |
| `proto/openapi.yaml` API contract | DDoS / volumetric attacks against `vpn.icd360s.de` |
| GitHub Actions release pipeline | The user's own WireGuard client configuration choices |
| `.github/workflows/` build / deploy scripts | Vulnerabilities in unmaintained forks |

The production server `vpn.icd360s.de` is **also in scope**, but
please coordinate timing of any active testing with us via the
channels above to avoid triggering automated incident response.

## What we promise

- **Acknowledgement** within 72 hours of receipt
- **Triage decision** (fix / wontfix / out-of-scope) within 7 days
- **Fix shipped** within 30 days for high/critical, 90 days for
  medium, best-effort for low. Critical fixes ship out-of-band as
  patch releases (e.g. `v1.2.6`) without waiting for the next
  scheduled release.
- **Public advisory** published via GitHub Security Advisories
  after the fix is in users' hands (typically a week after the
  release)
- **Credit** in the advisory and CHANGELOG (unless you ask us not
  to)

## What is NOT a vulnerability

- The fact that the source code is public — that's intentional.
  Security relies on cryptographic keys (mTLS, WireGuard), not on
  source obscurity.
- The 16-character enrollment code length — at 32 symbols and 16
  characters that's ≈80 bits of entropy plus a 10-minute TTL plus
  a server-wide rate limit; brute forcing is not feasible.
- The macOS app being unsigned by Apple — we explicitly opted out
  of the Apple Developer Program; the app is distributed under
  user trust + SHA256 verification of the auto-update payload
  rather than under Apple's notarisation.
- The deploy SSH user `vpn-deploy` having a shell — its
  `authorized_keys` line forces `rrsync -wo`, so no other command
  can ever be invoked.

## Hall of fame

(Empty — be the first.)
