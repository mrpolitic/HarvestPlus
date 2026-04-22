# Changelog

All notable changes to HarvestPlus will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.8] — 2026-04-22

### Fixed

- Settings → Integrations no longer asks for the keychain password every
  time the tab is opened. `loadCredentials()` was calling `SecItemCopyMatching`
  on both keychain items on every `.onAppear`, triggering an ACL check each
  visit. Fix: `AppState` already reads the token from the keychain exactly once
  at launch — it now keeps it in a `harvestToken` property in memory.
  `IntegrationsSettingsTab` reads that in-memory value instead of going back to
  the keychain. Zero keychain calls on subsequent visits to the tab.

## [1.0.7] — 2026-04-22

### Fixed

- "Install Update" button no longer shows "is damaged and can't be opened".
  The previous approach wrote a `.command` script to the sandbox temp
  directory, then opened it in Terminal. macOS automatically applies
  `com.apple.quarantine` to executable files created by sandboxed apps, and
  Gatekeeper blocks them even after `removexattr` — the xattr is re-applied
  after the write. Fix: drop the file entirely. The button now uses
  `NSAppleScript` to send `do script` directly to Terminal via Apple Events.
  No file = no quarantine. macOS shows a one-time consent dialog
  ("HarvestPlus wants to control Terminal.") on first use; after clicking
  OK it is never asked again. Requires the new
  `com.apple.security.automation.apple-events` entitlement (added to
  `HarvestPlus.entitlements` and wired up in the Xcode build settings).

## [1.0.6] — 2026-04-22

### Fixed

- Keychain prompts reduced from 4 to 2 (one-time, on first launch after
  install). `save()` previously used delete-then-add: `SecItemDelete` carries
  its own ACL check, so macOS prompted once for the read and again for the
  delete — 2 prompts per credential × 2 credentials = 4 prompts. Replaced
  with `SecItemUpdate`+add (update in place if the item exists, add fresh if
  not). A single update operation reuses the session-level access already
  granted by the preceding read, eliminating the extra delete prompts.
  Removed the now-unused `migrateToAllowAllAccess()` helper.

## [1.0.5] — 2026-04-22

### Fixed

- "Install Update" button now works. The `.command` script written to the
  sandbox temp dir was getting `com.apple.quarantine` applied automatically
  by macOS (sandboxed apps that create executable files trigger this).
  Gatekeeper then blocked Terminal from opening it with "is damaged and
  can't be opened". Fix: call `removexattr(path, "com.apple.quarantine", 0)`
  on the file immediately after writing it — permitted on files the app
  owns in its own sandbox container.

## [1.0.4] — 2026-04-22

### Fixed

- Keychain prompts on install reduced from up to 4 (per install) to at most
  2 (one-time migration only). The 1.0.3 fix read credentials twice on launch
  — once in `AppState.init()` and again in the AppDelegate migration — so
  macOS could prompt for each item on both reads. The migration is now inlined
  into `AppState.init()` as an immediate re-save after the existing read,
  so there is only ever one read pass. After the migration runs once, future
  installs prompt zero times.

## [1.0.3] — 2026-04-22

### Changed

- Update button now opens Terminal directly and runs the installer — no more
  copying and pasting a command. Clicking **Install Update** in Settings →
  General → About opens a Terminal window that downloads and installs the new
  version in one step.
- Keychain items are now saved with an "allow all" access ACL
  (`SecAccessCreate` with an empty trusted-application list). Previously
  each new build's ad-hoc code signature was baked into the item's ACL,
  so macOS prompted for the login keychain password on every update.
  With this fix the credentials survive binary replacements without any
  prompt. A one-time migration at first launch re-saves existing items with
  the new ACL (may prompt once per item for items created by an older build).

## [1.0.2] — 2026-04-22

### Changed

- Installer now defaults to `~/Applications` instead of `/Applications`, so
  no admin password is ever requested. macOS treats `~/Applications` as a
  first-class app location — Launchpad/Spotlight/launch-at-login all still
  work. Pass `--system` to the install command for the old `/Applications`
  behaviour (still prompts for admin once).
- `install.sh` now detects a leftover copy in the other location after
  install and prints a one-line removal hint, so users who migrate don't
  end up with two HarvestPlus icons in Launchpad.

## [1.0.1] — 2026-04-22

### Changed

- Distribution switched from `.pkg` double-click to a `curl | bash` installer
  (`Scripts/install.sh`). macOS 15 (Sequoia) removed the right-click → Open
  Gatekeeper bypass for unsigned installers, so a downloaded `.pkg`/`.app`
  now requires a trip to System Settings → Privacy & Security on every
  install. The new flow avoids that entirely: `curl`-fetched files aren't
  marked with `com.apple.quarantine`, so macOS treats the installed app as
  a trusted local binary and launches it without any prompt.
- In-app updater no longer downloads the `.pkg` in-process. Instead it
  copies the `curl | bash` one-liner to the clipboard; the user pastes it
  into Terminal, which replaces the running app in place.
- Release assets are now `HarvestPlus.app.zip` (fixed name, fetched by the
  installer) plus a `HarvestPlus-<version>.app.zip` human-friendly copy.

### Removed

- `.pkg` installer output. `Scripts/postinstall.sh` and
  `Scripts/ExportOptions.plist` are kept in the repo as scaffolding for a
  future signed/notarised pipeline but are unused today.

## [1.0.0] — 2026-04-22

### Added

- Menu-bar macOS app (no Dock icon) with a live timer-state indicator.
- Popover showing today's running timer, time entries, and calendar meetings
  on a single timeline.
- Daily / weekly / monthly / yearly dashboards with summary cards
  (hours logged, target, overtime, break usage).
- Calendar integration via `EventKit` with a meeting → Harvest-project mapper.
- PDF report export for any range, powered by `PDFKit`.
- Banner notifications for idle timer and unlogged meetings (opt-in).
- Work-schedule settings: per-weekday hour targets, lunch window, working hours.
- Overtime / undertime calculation honouring public holidays and PTO.
- Harvest Personal Access Token stored in the macOS Keychain
  (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, not synced to iCloud).
- GitHub Releases auto-updater: polls daily, downloads `.pkg`, reveals in Finder.
- Ad-hoc-signed `.pkg` installer with a postinstall step that strips the
  `com.apple.quarantine` xattr so the app launches without Gatekeeper prompts.
