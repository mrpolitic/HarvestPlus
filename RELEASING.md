# Releasing HarvestPlus

End-to-end procedure for shipping a new version of HarvestPlus to coworkers.
The output is **one file**: an ad-hoc-signed `.pkg` uploaded to GitHub
Releases. The installed app auto-detects future releases and self-updates.

This flow deliberately avoids the Apple Developer Program ($99/year) — the
trade-off is that the `.pkg` is not notarised, so on first install each
coworker does a one-time **right-click → Open** on the installer. After that
the installed app launches without any prompts, because the postinstall
script strips the `com.apple.quarantine` attribute.

---

## TL;DR

```bash
# 1. Bump version in Xcode (MARKETING_VERSION), update CHANGELOG.md, commit.
# 2. Build the installer
./Scripts/build.sh --clean

# 3. Tag + publish
git tag v<version> && git push origin v<version>
gh release create v<version> build/HarvestPlus-<version>.pkg \
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
content into a new dated `## [1.1.0] — 2026-04-22` section. These notes
appear on the GitHub release page and inside the in-app update prompt.

Commit: `git commit -am "Bump version to 1.1.0"`.

---

## Step 2 — Build the installer

```bash
./Scripts/build.sh --clean
```

Pipeline:

1. `xcodebuild archive` with `CODE_SIGN_IDENTITY=-` (ad-hoc)
   → `build/HarvestPlus.xcarchive`
2. Pulls `.app` directly from the archive's `Products/Applications/` —
   no `xcodebuild -exportArchive` step (that one needs a Developer ID).
3. Stages the app in `build/pkgroot/Applications/` with `postinstall.sh`
   that strips `com.apple.quarantine` on install.
4. `pkgbuild` → `build/HarvestPlus-<version>.pkg` (unsigned).

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

gh release create v<version> build/HarvestPlus-<version>.pkg \
    --title "HarvestPlus <version>" \
    --notes-file CHANGELOG.md
```

**Release hygiene:**

- Upload exactly one `.pkg` asset — the updater picks the first one it finds.
- The tag and the `MARKETING_VERSION` in the app must agree, or users will
  either miss the update (their version > tag) or get flagged as outdated
  after a fresh install.
- If you publish a draft/prerelease, the updater skips it — only
  `/releases/latest` is consulted.

---

## Step 4 — Verify the update appears

On a second Mac that already has the previous HarvestPlus version installed:

1. Menu-bar → Settings → **General** → **About** → **Check for Updates**.
2. You should see "Version `<new>` is available" with the release notes.
3. "Download & Install" saves the `.pkg` to `~/Downloads` and reveals it in
   Finder.
4. Right-click → **Open** → authenticate → done. (The right-click is only
   needed because the `.pkg` is unsigned; the installed app itself launches
   silently on subsequent runs.)

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
| `xcodebuild: error: tool 'xcodebuild' requires Xcode` | `xcode-select` pointed at CLI tools | `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` |
| `xcodebuild archive` fails with a signing error | Xcode trying to auto-sign against a team you don't have | The script passes `CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=-` — check you haven't re-enabled "Automatically manage signing" in Xcode and saved a team into the project |
| `pkgbuild` fails with "postinstall not executable" | Script bit was stripped | `chmod +x Scripts/postinstall.sh` and rerun |
| Coworker says "the `.pkg` is damaged and can't be opened" | Gatekeeper blocking unsigned installer | Tell them to **right-click → Open** instead of double-click. One-time only. |
| App launches but immediately quits on a coworker's Mac | Architecture mismatch (e.g. Intel Mac, binary is Apple Silicon only) | Rebuild with `-arch x86_64 -arch arm64` or set `ONLY_ACTIVE_ARCH=NO` in Xcode Release config |
| Updater says "not configured" | `UpdateChecker.repository` still set to placeholder | Edit `HarvestPlus/Updates/UpdateChecker.swift`, replace `YOUR_GITHUB_USER/HarvestPlus` with your real `owner/repo` |

---

## Files involved

```
Scripts/
  build.sh             Archive + pkgbuild pipeline (ad-hoc signing)
  postinstall.sh       Runs as root on install → strips quarantine
  ExportOptions.plist  (unused — kept for future Developer ID path)

HarvestPlus/Updates/
  UpdateChecker.swift  Polls GitHub Releases, downloads new .pkg
  UpdateSection.swift  "About" row in General Settings

build/                 (git-ignored) build output
  HarvestPlus.xcarchive
  HarvestPlus-<version>.pkg   ← ship this
```

---

## Upgrading to the signed/notarised path later

If you ever do join the Apple Developer Program, the path forward is:

1. Set `INSTALLER_IDENTITY` to your Developer ID Installer cert name.
2. Re-add the `xcodebuild -exportArchive` step using
   `Scripts/ExportOptions.plist` (kept in the repo for this reason).
3. Add a notarytool step after pkgbuild.
4. Drop the `xattr -cr` from `postinstall.sh` — notarised packages don't
   need it (Gatekeeper trusts them directly).

No Swift code changes required; the updater and the in-app experience stay
identical.
