# Release procedure

This file documents how a new version of the **icd360svpn** Flutter
admin app gets from a developer's laptop to a user's auto-updater.

## TL;DR — cutting `v1.2.3`

```bash
# 1. Bump the version in app/pubspec.yaml
sed -i 's/^version: .*/version: 1.2.3+10/' app/pubspec.yaml

# 2. Add a section to CHANGELOG.md
$EDITOR CHANGELOG.md
git add app/pubspec.yaml CHANGELOG.md
git commit -m "Release v1.2.3"
git push

# 3. Tag and push the tag
git tag v1.2.3
git push --tags
```

That's it. The GitHub Actions workflow does the rest:

1. `analyze` runs on the new commit.
2. `build_*` jobs build for Linux / macOS / Windows / Android / iOS.
3. `release` job (only fires for `v*` tags):
   - downloads every artifact,
   - computes SHA256 sums,
   - writes `out/updates/version.json`,
   - creates a GitHub Release at https://github.com/ICD360S-e-V/vpn/releases/tag/v1.2.3,
   - rsyncs the whole tree to `vpn.icd360s.de` if the deploy
     secret is configured.

The next time any user opens the app, `UpdateNotifier` polls
`https://vpn.icd360s.de/updates/version.json`, sees the higher
build number, and shows the update banner.

## Where the artifacts land

The release job lays the build outputs out as a tree under `out/`:

```
out/
├── download/
│   └── vpn-management_icd360sev/
│       ├── linux/   icd360svpn-1.2.3-amd64.deb
│       ├── macos/   icd360svpn-1.2.3.dmg
│       ├── windows/ icd360svpn-1.2.3-windows-x64.zip
│       ├── android/
│       │   ├── icd360svpn-1.2.3-universal.apk
│       │   ├── icd360svpn-1.2.3-arm64-v8a.apk
│       │   ├── icd360svpn-1.2.3-armeabi-v7a.apk
│       │   ├── icd360svpn-1.2.3-x86_64.apk
│       │   └── icd360svpn-1.2.3.aab
│       └── ios/     icd360svpn-1.2.3-ios-unsigned.tar.gz
├── updates/
│   └── version.json
└── SHA256SUMS.txt
```

The `out/` tree is rsync'd to the **document root** of nginx on
`vpn.icd360s.de`, so the public URLs become exactly:

```
https://vpn.icd360s.de/download/vpn-management_icd360sev/macos/icd360svpn-1.2.3.dmg
https://vpn.icd360s.de/updates/version.json
```

The same files are mirrored to a GitHub Release for redundancy and
for users who can't reach the VPN domain.

## Configuring the deploy SSH secret (one time)

Until you configure the deploy secret, the `release` job still
publishes to GitHub Releases — only the rsync to vpn.icd360s.de is
skipped. To enable rsync:

1. **On vpn.icd360s.de**, create a restricted user `vpn-deploy`
   whose only allowed command is rrsync against the document root.
   See `vpn-server-setup.md` (in this docs/ folder, M6.x).

2. **Generate an Ed25519 keypair** locally:
   ```bash
   ssh-keygen -t ed25519 -N '' -f vpn-deploy.key \
     -C 'github-actions@icd360s-vpn'
   ```

3. **Install the public key** on vpn.icd360s.de in
   `~vpn-deploy/.ssh/authorized_keys` with an `rrsync -wo` prefix
   that confines writes to `/var/www/html/`.

4. **Add four GitHub secrets** to the `ICD360S-e-V/vpn` repo
   (Settings → Secrets and variables → Actions):

   | Secret | Example |
   |---|---|
   | `VPN_DEPLOY_SSH_KEY` | contents of `vpn-deploy.key` (private) |
   | `VPN_DEPLOY_SSH_HOST` | `vpn.icd360s.de` |
   | `VPN_DEPLOY_SSH_PORT` | `36000` |
   | `VPN_DEPLOY_SSH_USER` | `vpn-deploy` |

5. Push another tag. The `release` job will detect the secret and
   run the rsync step.

## SHA256 verification

The auto-updater uses the SHA256 from `version.json` to verify the
download. If a checksum mismatches, the partial file is deleted
and the user sees an error in the dialog. Always confirm the
generated `SHA256SUMS.txt` matches the version.json before
publishing — the workflow does this automatically by sourcing the
hashes from the same files.

## Rollback

GitHub Releases lets you delete a release; the workflow's
`softprops/action-gh-release@v2` step refuses to overwrite a
published release without `make_latest: true` plus an explicit tag.
To roll back:

1. Delete the GitHub Release for the bad tag (UI or `gh release delete v1.2.3`).
2. SSH to vpn.icd360s.de and replace `version.json` with the
   previous good copy (kept in git history under
   `out/updates/version.json` of the previous release run).
3. Tag the previous good commit as a NEW patch release (e.g.
   `v1.2.4` reusing v1.2.2's binaries) so the auto-updater
   strictly increases. **Never re-publish a stale build number.**
