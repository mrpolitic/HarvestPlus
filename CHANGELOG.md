# Changelog

All notable changes to HarvestPlus will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
