# Releasing HarvestPlus

End-to-end procedure for shipping a new version of HarvestPlus to coworkers.
The output is **one file**: `HarvestPlus.app.zip`, uploaded to GitHub Releases.
Coworkers install with a single Terminal command; the installed app
auto-detects future releases and silently installs them on the next daily
check.

Every build is **signed with a Developer ID Application certificate and
notarized by Apple**, with the notarization ticket stapled to the `.app`.
Gatekeeper accepts the app offline – no "is damaged" dialog, no
"unidentified developer" wall, no System Settings → Privacy & Security trip
on install or launch. The `curl | bash` path is kept because it's a one-line
install and matches what the in-app auto-updater does, not because it's
needed to dodge Gatekeeper.

---

## TL;DR

```bash
# 1. Bump version in Xcode (MARKETING_VERSION), update CHANGELOG.md, commit.
# 2. Build, sign, notarize, staple, zip
./Scripts/build.sh --clean

# 3. Tag + publish
git tag v<version> && git push origin v<version>
gh release create v<version> \
    build/HarvestPlus.app.zip build/HarvestPlus-<version>.app.zip \
    --title "HarvestPlus <version>" \
    --notes-file CHANGELOG.md
```

---

## Prerequisites (one-time setup on the release machine)

1. **Xcode** with the Apple ID tied to the paid Developer Program signed in
   (Xcode → Settings → Accounts).
2. **`xcode-select`** must point at the full Xcode app:
   ```bash
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   xcodebuild -version   # → "Xcode <major>.<minor>"
   ```
3. **Developer ID Application certificate** installed in the login keychain.
   Verify with:
   ```bash
   security find-identity -v -p codesigning | grep "Developer ID Application"
   ```
   Should show one entry like
   `Developer ID Application: Martin Razvan Politic (PA8H58YHD6)`.
   If it isn't there: Xcode → Settings → Accounts → click the account →
   **Manage Certificates** → **+** → "Developer ID Application".
4. **`notarytool` profile** stored in the keychain under the name
   `AC_NOTARY`. Created once with:
   ```bash
   xcrun notarytool store-credentials AC_NOTARY \
       --apple-id  <your-apple-id> \
       --team-id   PA8H58YHD6 \
       --password  <app-specific-password-from-appleid.apple.com>
   ```
   The app-specific password lives in Apple's keychain; `build.sh` never
   sees it directly, it just references the profile name.
5. **GitHub CLI** (`gh auth login`) – used by the release command.

`build.sh` will fail fast at preflight if any of #3 or #4 is missing.

---

## Step 1 – Bump the version

Open the project in Xcode → select the `HarvestPlus` target → **General** tab
→ update **Version** (the "marketing version", e.g. `1.1.0`) and **Build** (a
monotonic integer). Follow [semver](https://semver.org): bump major for
breaking changes, minor for new features, patch for bug fixes.

Update `CHANGELOG.md` with a human-readable summary. Move `[Unreleased]`
content into a new dated `## [1.1.0] – YYYY-MM-DD` section. These notes
appear on the GitHub release page and inside the in-app update prompt.

Commit: `git commit -am "Bump version to 1.1.0"`.

---

## Step 2 – Build, sign, notarize, staple

```bash
./Scripts/build.sh --clean
```

Pipeline:

1. **Archive** – `xcodebuild archive` signed with the Developer ID
   Application identity, hardened runtime enabled, the entitlements in
   `HarvestPlus/HarvestPlus.entitlements` baked in. Output:
   `build/HarvestPlus.xcarchive`.
2. **Verify** – `codesign --verify --deep --strict` + a check that
   `flags=0x10000(runtime)` is set on the embedded binary. Notary would
   reject anything missing the hardened runtime; we fail fast.
3. **Notarize** – `ditto -c -k --sequesterRsrc --keepParent` zips the
   `.app`, then `xcrun notarytool submit … --wait` ships it to Apple's
   notary service and blocks until they reply. Typically 1–3 minutes. If
   rejected, `build.sh` fetches the detailed log via `notarytool log` and
   prints Apple's reason.
4. **Staple** – `xcrun stapler staple` attaches the notarization ticket to
   the `.app` so Gatekeeper can validate it offline (no notary roundtrip
   on every coworker's launch).
5. **Gatekeeper assess** – `spctl --assess --type execute` confirms the
   stapled bundle is accepted.
6. **Final zip** – `ditto -c -k --sequesterRsrc --keepParent` produces the
   two release assets:
   - `build/HarvestPlus.app.zip` (fixed name – `install.sh` and the
     in-app updater fetch exactly this filename from
     `/releases/latest/download/`)
   - `build/HarvestPlus-<version>.app.zip` (versioned copy for humans
     browsing the Releases page)

Output summary is printed at the end.

---

## Step 3 – Tag and publish on GitHub

Git tags are the source of truth for the in-app updater – the tag name must
match the marketing version (optionally prefixed with `v`).

```bash
git tag v<version>
git push origin v<version>

gh release create v<version> \
    build/HarvestPlus.app.zip build/HarvestPlus-<version>.app.zip \
    --title "HarvestPlus <version>" \
    --notes-file CHANGELOG.md
```

**Release hygiene:**

- The asset named **exactly** `HarvestPlus.app.zip` is what the installer
  curls from `/releases/latest/download/HarvestPlus.app.zip`. The versioned
  copy is optional – upload it for humans browsing the Releases page.
- The tag and the `MARKETING_VERSION` in the app must agree, or the in-app
  updater will either miss the update (their version > tag) or flag the
  user as outdated after a fresh install.
- If you publish a draft/prerelease, the updater (and the `/releases/latest`
  redirect used by `install.sh`) skips it.

---

## Step 4 – Verify the install on a clean Mac

On a second Mac (or a Mac that's never run HarvestPlus before), open
Terminal and paste:

```bash
curl -fsSL https://raw.githubusercontent.com/mrpolitic/HarvestPlus/main/Scripts/install.sh | bash
```

Expected: the script prints progress, launches the app, a menu-bar icon
appears. No Gatekeeper dialog, no System Settings visit, no password
prompt.

### Verifying the in-app auto-updater

On a Mac that already has a previous version installed:

1. Wait for the daily check to fire (or trigger it manually via Settings →
   **General** → **About** → **Check for Updates**).
2. The "Version `<new>` is available" banner appears for ~2 s in Settings.
3. Terminal flashes open, runs the install script, quits the old binary,
   relaunches the new one. The user doesn't have to click anything.
4. If you want to verify the manual-click path still works, force-quit the
   app before the 2 s timer fires and click **Install Update** in Settings
   on the new launch.

Automatic checks run **once per 24 h** on launch. The interval is
`UpdateChecker.autoCheckInterval` if you need to tune it.

---

## Rolling back a bad release

1. On GitHub, **mark the bad release as a draft** (don't delete – the tag
   stays, but both the `/releases/latest` redirect and the updater skip
   drafts). `install.sh` will then fetch whichever release is now "latest".
2. Users who already have the bad version keep working. Re-running the
   install command pulls the now-latest (previous) version and installs it
   in place – effectively a downgrade.
3. Ship the fix as a new patch version. Don't reuse a version number.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `xcodebuild: error: tool 'xcodebuild' requires Xcode` | `xcode-select` pointed at CLI tools | `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` |
| `build.sh` dies at preflight saying "signing identity not found" | Developer ID Application cert not in login keychain | See Prerequisite #3 above |
| `build.sh` dies at preflight saying "notarytool profile 'AC_NOTARY' not configured" | Notarytool credentials not stored | See Prerequisite #4 above |
| Notarization rejected | Usually a hardened-runtime / entitlement issue | `build.sh` automatically fetches and prints Apple's detailed log via `notarytool log`. Most common cause: a sandbox-incompatible entitlement was added to `HarvestPlus.entitlements`. |
| `install.sh` says "Download failed" | Release has no `HarvestPlus.app.zip` asset (or the release is a draft/prerelease) | Check the latest release on GitHub. The asset filename must be exactly `HarvestPlus.app.zip`. |
| App launches but immediately quits on a coworker's Mac | Architecture mismatch (e.g. Intel Mac, binary is Apple Silicon only) | Rebuild with `-arch x86_64 -arch arm64` or set `ONLY_ACTIVE_ARCH=NO` in Xcode Release config |
| Updater says "not configured" | `UpdateChecker.repository` still set to placeholder | Edit `HarvestPlus/Updates/UpdateChecker.swift`, replace `YOUR_GITHUB_USER/HarvestPlus` with your real `owner/repo` |

---

## Files involved

```
Scripts/
  build.sh             archive → sign → notarize → staple → zip pipeline
  install.sh           curl | bash installer run by coworkers

HarvestPlus/
  HarvestPlus.entitlements   sandbox + apple-events + calendar + …
  Info.plist                 NSAppleEventsUsageDescription etc.

HarvestPlus/Updates/
  UpdateChecker.swift  polls GitHub Releases, auto-installs new versions
  UpdateSection.swift  "About" row in General Settings

build/                 (git-ignored) build output
  HarvestPlus.xcarchive
  HarvestPlus.app.zip                  ← ship this (fixed name)
  HarvestPlus-<version>.app.zip        ← ship this (human-friendly copy)
  archive.log / notarize.log / staple.log    diagnostic logs
```
