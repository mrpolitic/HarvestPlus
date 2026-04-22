# Changelog

All notable changes to HarvestPlus will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
