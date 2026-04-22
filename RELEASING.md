# Releasing HarvestPlus

End-to-end procedure for shipping a new version of HarvestPlus to coworkers.
The output is **one file**: `HarvestPlus.app.zip`, uploaded to GitHub Releases.
Coworkers install with a single Terminal command; the installed app
auto-detects future releases and copies the same install command to the
clipboard on demand.

This flow deliberately avoids the Apple Developer Program ($99/year). The
trade-off: the `.app` inside the zip is ad-hoc signed, not notarised. We
sidestep Gatekeeper by distributing via `curl | bash` — `curl` doesn't set
`com.apple.quarantine` on downloaded files, and the installer strips any
residual xattr before launch. End user sees no Gatekeeper dialog at all.

---

## TL;DR

```bash
# 1. Bump version in Xcode (MARKETING_VERSION), update CHANGELOG.md, commit.
# 2. Build the zip
./Scripts/build.sh --clean

# 3. Tag + publish
git tag v<version> && git push origin v<version>
gh release create v<version> \
    build/HarvestPlus.app.zip build/HarvestPlus-<version>.app.zip \
    --title "HarvestPlus <version>" \
    --notes-file CHANGELOG.md
```

---

## Prerequisites (one-time)

1. **Xcode** with any valid Apple ID signed in
   (Xcode → Settings → Accounts → `+ Add Apple ID…`). A free Apple ID is
   fine — we don't use the paid Developer Program.
2. **`xcode-select`** must point at the full Xcode app, not the command-line
   tools:
   ```bash
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   xcodebuild -version   # → "Xcode <major>.<minor>"
   ```
3. **GitHub CLI** (`gh auth login`) — used by the release command.

That's it. No certificates, no notarytool credentials, no keychain setup.

---

## Step 1 — Bump the version

Open the project in Xcode → select the `HarvestPlus` target → **General** tab
→ update **Version** (the "marketing version", e.g. `1.1.0`) and **Build** (a
monotonic integer). Follow [semver](https://semver.org): bump major for
breaking changes, minor for new features, patch for bug fixes.

Update `CHANGELOG.md` with a human-readable summary. Move `[Unreleased]`
content into a new dated `## [1.1.0] — YYYY-MM-DD` section. These notes
appear on the GitHub release page and inside the in-app update prompt.

Commit: `git commit -am "Bump version to 1.1.0"`.

---

## Step 2 — Build the zip

```bash
./Scripts/build.sh --clean
```

Pipeline:

1. `xcodebuild archive` with `CODE_SIGN_IDENTITY=-` (ad-hoc)
   → `build/HarvestPlus.xcarchive`
2. Pulls `.app` directly from the archive's `Products/Applications/` —
   no `xcodebuild -exportArchive` step (that one needs a Developer ID).
3. `ditto -c -k --sequesterRsrc --keepParent` zips the `.app` →
   - `build/HarvestPlus.app.zip` (fixed name — the installer fetches this)
   - `build/HarvestPlus-<version>.app.zip` (versioned copy, for humans)

Output summary is printed at the end of the run.

The script does `codesign --verify --deep --strict` on the built `.app` as
a sanity check — ad-hoc signatures pass that just fine.

---

## Step 3 — Tag and publish on GitHub

Git tags are the source of truth for the in-app updater — the tag name must
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
  copy is optional — upload it for humans browsing the Releases page.
- The tag and the `MARKETING_VERSION` in the app must agree, or the in-app
  updater will either miss the update (their version > tag) or flag the
  user as outdated after a fresh install.
- If you publish a draft/prerelease, the updater (and the `/releases/latest`
  redirect used by `install.sh`) skips it.

---

## Step 4 — Verify the install on a clean Mac

On a second Mac (or a Mac that's never run HarvestPlus before), open
Terminal and paste:

```bash
curl -fsSL https://raw.githubusercontent.com/mrpolitic/HarvestPlus/main/Scripts/install.sh | bash
```

Expected: the script prints progress, launches the app, a menu-bar icon
appears. No Gatekeeper dialog, no System Settings visit.

### Verifying the in-app updater

On a Mac that already has a previous version installed:

1. Menu-bar → Settings → **General** → **About** → **Check for Updates**.
2. You should see "Version `<new>` is available" with the release notes.
3. Click **Copy Install Command** — the `curl | bash` one-liner is copied
   to the clipboard.
4. Open Terminal, paste, hit Return. The running HarvestPlus quits, the
   new version is installed in place, and it relaunches automatically.

Automatic checks run **once per 24h** on launch. The interval is
`UpdateChecker.autoCheckInterval` if you need to tune it.

---

## Rolling back a bad release

1. On GitHub, **mark the bad release as a draft** (don't delete — the tag
   stays, but both the `/releases/latest` redirect and the updater skip
   drafts). `install.sh` will then fetch whichever release is now "latest".
2. Users who already have the bad version keep working. Re-running the
   install command pulls the now-latest (previous) version and installs it
   in place — effectively a downgrade.
3. Ship the fix as a new patch version. Don't reuse a version number.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `xcodebuild: error: tool 'xcodebuild' requires Xcode` | `xcode-select` pointed at CLI tools | `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` |
| `xcodebuild archive` fails with a signing error | Xcode trying to auto-sign against a team you don't have | The script passes `CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=-` — check you haven't re-enabled "Automatically manage signing" in Xcode and saved a team into the project |
| `install.sh` says "Download failed" | Release has no `HarvestPlus.app.zip` asset (or the release is a draft/prerelease) | Check the latest release on GitHub. The asset filename must be exactly `HarvestPlus.app.zip`. |
| App launches but immediately quits on a coworker's Mac | Architecture mismatch (e.g. Intel Mac, binary is Apple Silicon only) | Rebuild with `-arch x86_64 -arch arm64` or set `ONLY_ACTIVE_ARCH=NO` in Xcode Release config |
| Coworker gets a Gatekeeper dialog anyway | They downloaded the zip via a browser instead of `curl | bash` | Browsers tag downloads with `com.apple.quarantine`. Either re-install via the Terminal command, or `xattr -cr /Applications/HarvestPlus.app` once. |
| Updater says "not configured" | `UpdateChecker.repository` still set to placeholder | Edit `HarvestPlus/Updates/UpdateChecker.swift`, replace `YOUR_GITHUB_USER/HarvestPlus` with your real `owner/repo` |

---

## Files involved

```
Scripts/
  build.sh             Archive → ditto .app.zip pipeline (ad-hoc)
  install.sh           curl | bash installer run by coworkers
  postinstall.sh       (unused — kept for future signed .pkg path)
  ExportOptions.plist  (unused — kept for future Developer ID path)

HarvestPlus/Updates/
  UpdateChecker.swift  Polls GitHub Releases, exposes install command
  UpdateSection.swift  "About" row in General Settings

build/                 (git-ignored) build output
  HarvestPlus.xcarchive
  HarvestPlus.app.zip                  ← ship this (fixed name)
  HarvestPlus-<version>.app.zip        ← ship this (human-friendly copy)
```

---

## Upgrading to the signed/notarised path later

If you ever do join the Apple Developer Program, the clean upgrade path is:

1. Set `CODE_SIGN_IDENTITY` to your Developer ID Application cert name
   when running `build.sh`.
2. Re-add a `xcodebuild -exportArchive` step using
   `Scripts/ExportOptions.plist` (kept in the repo for this reason).
3. Either stick with the `.app.zip` distribution (just notarise the zip) or
   swap to `pkgbuild` + notarytool, reinstating `Scripts/postinstall.sh`.
4. Drop the `xattr -cr` step in `install.sh` — notarised binaries don't
   need it.

No Swift code changes required; the updater and the in-app experience stay
identical. Coworkers could then double-click the zip/pkg instead of running
a Terminal command, but the `curl | bash` path keeps working either way.
