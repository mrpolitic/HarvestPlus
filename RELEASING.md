# Releasing HarvestPlus

End-to-end procedure for shipping a new version of HarvestPlus to coworkers.
The output is **one file**: a signed, notarised `.pkg` uploaded to GitHub
Releases. The installed app auto-detects future releases and self-updates.

---

## TL;DR

```bash
# 1. Bump version in Xcode (MARKETING_VERSION), commit.
# 2. Build the installer
./Scripts/build.sh --clean

# 3. Notarise + staple
xcrun notarytool submit build/HarvestPlus-<version>.pkg \
    --apple-id  <your@appleid> \
    --team-id   PA8H58YHD6 \
    --password  <app-specific-password> \
    --wait
xcrun stapler staple build/HarvestPlus-<version>.pkg

# 4. Tag + publish
git tag v<version> && git push origin v<version>
gh release create v<version> build/HarvestPlus-<version>.pkg \
    --title "HarvestPlus <version>" \
    --notes-file CHANGELOG.md
```

---

## Prerequisites (one-time)

1. **Xcode** with your Apple Developer account signed in
   (Xcode → Settings → Accounts → `+ Add Apple ID…`).
2. Two certificates in the login keychain:
   - **Developer ID Application** — signs the `.app` binary.
   - **Developer ID Installer** — signs the `.pkg`.

   Generate them in Xcode → Settings → Accounts → Manage Certificates if you
   don't have them. The build script auto-detects the installer certificate;
   you can override with `INSTALLER_IDENTITY=…` if you have multiples.
3. **App-specific password** for `notarytool`. Create one at
   <https://appleid.apple.com> → Sign-in & Security → App-Specific Passwords.
   Store it in the keychain once:
   ```bash
   xcrun notarytool store-credentials "HarvestPlus-Notary" \
       --apple-id  <your@appleid> \
       --team-id   PA8H58YHD6 \
       --password  <app-specific-password>
   ```
   After this you can use `--keychain-profile "HarvestPlus-Notary"` instead of
   passing the Apple ID / password every time.
4. **GitHub CLI** (`gh auth login`) — used by the release command.

---

## Step 1 — Bump the version

Open the project in Xcode → select the `HarvestPlus` target → **General** tab →
update **Version** (the "marketing version", e.g. `1.1.0`) and **Build** (a
monotonic integer). Follow [semver](https://semver.org): bump major for
breaking changes, minor for new features, patch for bug fixes.

Commit: `git commit -am "Bump version to 1.1.0"`.

Update `CHANGELOG.md` with a human-readable summary. These notes appear in the
in-app update prompt and on the GitHub release page.

---

## Step 2 — Build the installer

```bash
./Scripts/build.sh --clean
```

Pipeline:

1. `xcodebuild archive` → `build/HarvestPlus.xcarchive`
2. `xcodebuild -exportArchive` with `Scripts/ExportOptions.plist`
   → `build/Export/HarvestPlus.app` (Developer ID signed, hardened runtime)
3. Stages the app in `build/pkgroot/Applications/` with `postinstall.sh`
   that strips `com.apple.quarantine` on install
4. `pkgbuild` → `build/HarvestPlus-<version>.pkg`
   (auto-signed with your Developer ID Installer cert)

Output summary is printed at the end of the run.

If the script warns about "No Developer ID Installer identity found", import
your installer certificate into the login keychain and re-run.

---

## Step 3 — Notarise

Apple needs to bless the `.pkg` before Gatekeeper will trust it without a
right-click-Open dance.

```bash
xcrun notarytool submit build/HarvestPlus-<version>.pkg \
    --keychain-profile "HarvestPlus-Notary" \
    --wait
```

Typical turnaround: 2–10 minutes. On success, staple the ticket to the .pkg so
offline machines don't need to phone home:

```bash
xcrun stapler staple build/HarvestPlus-<version>.pkg
```

Verify with `spctl --assess --type install -vv build/HarvestPlus-<version>.pkg`.
You want `accepted` and `source=Notarized Developer ID`.

---

## Step 4 — Tag and publish on GitHub

Git tags are the source of truth for the in-app updater — the tag name must
match the marketing version (optionally prefixed with `v`).

```bash
git tag v<version>
git push origin v<version>

gh release create v<version> build/HarvestPlus-<version>.pkg \
    --title "HarvestPlus <version>" \
    --notes-file CHANGELOG.md
```

**Release hygiene:**

- Upload exactly one `.pkg` asset — the updater picks the first one it finds.
- The tag and the `MARKETING_VERSION` in the app must agree, or users will
  either miss the update (their version > tag) or get flagged as outdated
  after a fresh install.
- If you publish a draft/prerelease, the updater skips it — only `/releases/latest`
  is consulted.

---

## Step 5 — Verify the update appears

On a second Mac that already has the previous HarvestPlus version installed:

1. Menu-bar → Settings → **General** → **About** → **Check for Updates**
2. You should see "Version `<new>` is available" with the release notes.
3. "Download & Install" saves the .pkg to `~/Downloads` and reveals it in Finder.
4. Double-click → authenticate → done.

Automatic checks run **once per 24h** on launch. The interval is
`UpdateChecker.autoCheckInterval` if you need to tune it.

---

## Rolling back a bad release

1. On GitHub, **mark the bad release as a draft** (don't delete — the tag
   stays, but the "latest" endpoint skips drafts).
2. Users who already have it keep working — `.pkg` installs are idempotent,
   so re-running the previous version's installer downgrades cleanly.
3. Ship the fix as a new patch version. Don't reuse a version number.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `xcodebuild archive failed` with signing error | Wrong team in keychain | `DEVELOPMENT_TEAM` in `ExportOptions.plist` and Xcode Accounts must match |
| `xcodebuild -exportArchive` fails with "no matching provisioning profile" | Developer ID Application cert missing | Generate via Xcode → Settings → Accounts → Manage Certificates |
| `pkgbuild` says "No Developer ID Installer found" | Cert not in keychain | Same as above, pick "Developer ID Installer" |
| Notarisation rejected, `hardened-runtime` error | Build config wrong | Confirm `ENABLE_HARDENED_RUNTIME = YES` in Release |
| App still shows the "downloaded from the internet" prompt after install | `postinstall.sh` didn't run | Inspect `/var/log/install.log` for script errors — usually a missing execute bit on the script; `./Scripts/build.sh --clean` always re-chmods |
| Updater says "not configured" | `UpdateChecker.repository` still set to placeholder | Edit `HarvestPlus/Updates/UpdateChecker.swift`, replace `YOUR_GITHUB_USER/HarvestPlus` with your real `owner/repo` |

---

## Files involved

```
Scripts/
  build.sh             Archive + export + pkgbuild pipeline
  postinstall.sh       Runs as root on install → strips quarantine
  ExportOptions.plist  Developer ID export config for xcodebuild

HarvestPlus/Updates/
  UpdateChecker.swift  Polls GitHub Releases, downloads new .pkg
  UpdateSection.swift  "About" row in General Settings

build/                 (git-ignored) build output
  HarvestPlus.xcarchive
  Export/HarvestPlus.app
  HarvestPlus-<version>.pkg   ← ship this
```
