# Changelog

All notable changes to HarvestPlus will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.1.1] — 2026-06-01

### Fixed

- **App failed to launch on other Macs ("Launchd job spawn failed").** The
  release build re-signs the app after embedding Sparkle, and that step passed
  the raw entitlements file to `codesign`, which (unlike Xcode) doesn't expand
  `$(AppIdentifierPrefix)`. The shipped app ended up with a literal
  `$(AppIdentifierPrefix)com.qampo.HarvestPlus` keychain-access-group, which
  macOS (AMFI) rejects at launch — so 1.1.0 wouldn't open on any machine other
  than the build machine (whose running copy was an older build). The build
  script now resolves the prefix before re-signing, and verifies the embedded
  entitlements are fully expanded so this can't ship again. No app-code change.

## [1.1.0] — 2026-05-22

### Added

- **In-app feedback feature** under Settings → Feedback. Pick a category
  (Bug / Feature / General), write a message, optionally attach a file
  (≤ 5 MB), hit Send. Submissions go through [Web3Forms](https://web3forms.com)
  to the maintainer's inbox — the maintainer's email is not exposed in
  the app bundle. App version, macOS version, architecture, locale, and
  time zone are auto-attached so reporters don't have to dig for them.
- **`PRIVACY.md`** at the repo root, linked from the README and from the
  Feedback tab. Plain-language explanation of what data the app touches,
  where it lives, and what (very little) leaves your Mac.
- **License change.** Switched from MIT to **[PolyForm Shield 1.0.0](https://polyformproject.org/licenses/shield/1.0.0/)**.
  Any use is allowed (personal, internal at work, at any kind of company)
  *except* offering a competing time-tracking product based on the
  HarvestPlus source. Source-available, not strictly OSI-open-source, but
  free for ~every actual user case. Linked from the README.
- **"Skip for today" button on banners** — the nudge banner footer now
  has both a Snooze (X min) and a Skip-for-today control. The skip lasts
  until midnight local time and survives app quit/relaunch.
- **PDF reports show both `H:MM` and decimal hours.** Per Slack feedback,
  Harvest's web UI uses `7:30` style and that's easier to read than `7.5h`;
  the decimal is kept alongside it so anyone doing arithmetic still has
  the numeric form. Example: `7:30 (7.50h)`.
- **Report Start Date** — Settings → Export → "Exclude entries before a
  date". Useful if you tracked time wrong for a stretch: historical
  entries stay in Harvest but are ignored in dashboards and PDFs, so
  reports start clean from a chosen day. Toggle + DatePicker; off by default.
- **Holiday breakdown in weekly/monthly/yearly dashboards.** Holiday-
  task hours are surfaced as **days with decimals**, where 1 day = that
  date's actual daily target (so 3.75h on a 7.5h-target day = 0.5 days).
  Each holiday task type (configured via Settings → Holidays →
  `holidayTaskNames`) gets its own tile — e.g., with the Danish default
  setup you see separate "Holiday" and "Holiday (feriefridag)" cards
  with their own day counts. Tiles hide themselves when zero. Replaces
  the previous integer-count "Holiday days" stat that over-counted
  half-days and lumped all types together.
- **Public holidays and weekends are grayed out in dashboard charts.**
  The weekly bar chart and the monthly/yearly heatmaps render any non-
  working day in the neutral gray ramp — even if hours were logged —
  so you can tell at a glance which days the schedule expected work
  vs. didn't. Hours stay visible in the tooltip.

### Fixed

- **Running-timer total no longer shows ~2× the actual elapsed time**
  (reported by Michael in Slack). Harvest's API returns `entry.hours` as
  the **live total at poll time** for a running timer, not the saved-
  hours-without-the-current-session. The previous code in five separate
  display sites then added `(now - timer_started_at)` on top of `hours`,
  double-counting the period between timer start and the most recent poll.
  Now `TimeEntry.liveHours(now:polledAt:)` extrapolates from the poll
  moment forward, so the running timer ticks at real speed everywhere
  (popover, dashboards, end-of-day / end-of-week banner). End-of-week
  totals self-correct as a result.
- **Dashboards now stay in sync with the popover** for a running timer.
  Each dashboard now extrapolates live elapsed from the **fetch time of
  its own cached entries**, not the global `lastPolledAt` (which can be
  tens of seconds newer than the cached data, causing under-counting).
  New `AppState.fetchedAt(from:to:)` accessor.
- **"Snooze (15 min)" banner button actually snoozes for 15 min now.**
  Previously the banner reappeared roughly 30 s after clicking Snooze
  because `isSnoozed` was reset to `false` whenever the timer state
  re-emitted (e.g., on the next poll). And — separate latent bug —
  after a few snooze clicks the banner sometimes stopped appearing
  forever, because of stuck-Timer interactions. Both fixed by
  refactoring `BannerManager` from boolean+Timer state to absolute
  `snoozedUntil: Date?` / `skippedUntil: Date?` values persisted to
  UserDefaults. Date-based muting can't drift out of sync or get stuck.
- **Daily / period totals now match Harvest to the minute.** Decimal hours
  were split into `H` and `M` with the minutes **truncated**, so a day
  totalling ~5.4833h rendered as `5:28` (0.4833 × 60 = 28.9999, floored to
  28) while Harvest showed `5:29`. Totals now round to the nearest minute
  via a shared `TimeFormat.hoursAndMinutes(_:)` helper used by the popover,
  dashboards, banners, and PDF reports. This also resolves a self-
  inconsistency where the "Today" total and its "to go" delta didn't
  reconcile against the daily target.
- **Offline is now detected and surfaced.** A dropped connection used to
  throw a raw `URLError` that slipped past the error handling, leaving the
  app looking "connected" with stale numbers; it now flips to an Offline
  state. An expired or revoked token (HTTP 401 *or* 403) now reliably
  disconnects instead of being mistaken for a transient server error.
- **Background polling no longer stalls while the popover is open.** The
  poll, idle-check, and end-of-day/week timers now run in common run-loop
  modes, so they keep firing during menu/modal tracking instead of pausing
  exactly when you've opened the popover to check status.
- **Pasted Account ID / API token are trimmed** before validating and
  saving — a trailing newline or stray space (common on copy/paste) no
  longer causes a mystifying "invalid credentials" failure, and the token
  is written before the account id so a failed save can't leave a mismatched
  pair in the keychain.
- **Assorted hardening:** guards against duplicate Stop submissions, a stale
  poll overwriting fresher data, unbounded pagination, negative timeline-bar
  widths, off-grid schedule values blanking a picker, and an integer-overflow
  edge in project-color selection.
- **"Open Harvest" on the nudge banner now re-arms.** It used to launch Harvest,
  hide the banner, and never come back unless the timer state happened to
  transition — so a user who got distracted in Harvest and never started a
  timer went silently un-tracked for the rest of the day. The nudge now
  re-evaluates 3 minutes later; if a timer is started in the meantime the
  `.running` transition cancels the pending nudge.

### Changed

- **Auto-updates are now silent.** Replaced the previous NSAppleScript +
  Terminal install path with [Sparkle 2](https://sparkle-project.org/).
  Updates are checked daily in the background, downloaded automatically,
  and installed silently the next time you quit the app. No more
  "HarvestPlus wants to control Terminal" consent dialog, no more
  Terminal flash, no more banner-then-relaunch dance.
- Releases are now signed with both the existing Developer ID Application
  certificate (Gatekeeper) and a separate EdDSA key (Sparkle). The Sparkle
  public key is bundled in `Info.plist`; the private key lives in the
  maintainer's login keychain and never leaves the release machine.
- `Scripts/build.sh` now signs each release zip with `sign_update` and
  regenerates `appcast.xml` at the repo root after notarization. The
  release process commits `appcast.xml` to `main` alongside the GitHub
  release.

### Fixed

- **All keychain password prompts, including on Debug builds.** Migrated
  `KeychainHelper` from the legacy macOS keychain (`SecKeychain` + per-
  binary ACLs via `SecAccessCreate`) to the modern data-protection
  keychain (the iOS-style Keychain Services API). The legacy keychain
  prompted on every code-signature change because its ACLs are bound to
  specific binaries — even the "allow all" trick we tried earlier turned
  out to mean "only the creating binary" in practice. The data-protection
  keychain uses team-prefixed access groups instead: every binary signed
  with team `PA8H58YHD6` plus the `keychain-access-groups` entitlement
  reads the same items, regardless of which build (Debug, Release, Apple
  Development, Developer ID, ad-hoc) wrote them. Net effect: zero
  prompts forever.
- Resolves the `'SecAccessCreate' was deprecated in macOS 10.10` Xcode
  warning.

### Build infrastructure

- `build.sh` now embeds a Developer ID Provisioning Profile in the .app
  (`Contents/embedded.provisionprofile`). Required to use the data-
  protection keychain. Profile name is set via the
  `PROVISIONING_PROFILE_SPECIFIER` env var (default: "HarvestPlus
  Developer ID").

### Removed

- `com.apple.security.automation.apple-events` entitlement (Sparkle doesn't
  need it).
- `NSAppleEventsUsageDescription` Info.plist key (no longer used).
- `Scripts/install.sh`'s `osascript "tell ... to quit"` path (replaced
  with direct `killall`, avoiding a "Terminal wants to control HarvestPlus"
  consent dialog).
- `Scripts/postinstall.sh` and `Scripts/ExportOptions.plist` (vestigial
  from the abandoned .pkg distribution).

### Migration note

- Harvest credentials saved by 1.0.x live in the legacy keychain and
  won't be visible to 1.1.0. The app will behave as "not yet connected"
  on first launch — open Settings → Integrations and re-enter your
  Harvest Account ID and Personal Access Token once. From then on,
  launches are silent across all future builds.

## [1.0.10] — 2026-05-22

### Fixed

- Keychain "change access permissions" / "change the owner" password
  prompts on every launch (visible in 1.0.3 through 1.0.9). Two layered
  causes, both fixed:
  - `KeychainHelper.save()` attached a new `kSecAttrAccess` ACL to every
    `SecItemUpdate` call. macOS treats updating an item's ACL as a
    privileged operation and challenges the user unconditionally,
    regardless of whether the new ACL is identical to the old one. Fix:
    only set `kSecAttrAccess` on the initial `SecItemAdd` (item creation),
    never on update.
  - `AppState.init()` ran a "migration re-save" on every launch — it
    read both credentials and immediately wrote them back, which used to
    refresh the ad-hoc ACL. With a stable Developer ID signature this
    migration is unnecessary, and combined with the bug above it was
    triggering 2–4 ACL prompts on every single launch. The re-save has
    been removed entirely.
  Net effect: launches are now silent. The keychain ACL gets set exactly
  once, when the user first enters their credentials in Settings.

## [1.0.9] — 2026-05-21

### Changed

- App is now **signed with a Developer ID Application certificate and
  notarized by Apple**, with the notarization ticket stapled to the .app.
  Practical effects:
  - No more "is damaged and can't be opened" or "unidentified developer"
    walls. Gatekeeper accepts the app offline.
  - No System Settings → Privacy & Security trip on install.
  - Stable code signature across builds, so the keychain stops re-prompting
    on every update. (Existing users may see one final prompt on the upgrade
    from the ad-hoc-signed 1.0.8 to this build, then never again.)
  - Users who previously denied a Gatekeeper prompt for the unsigned build
    are unaffected — the new install replaces the rejected binary entirely.
- `Scripts/build.sh` now signs with the Developer ID Application cert,
  submits the zip to Apple's notary service via `xcrun notarytool`, waits
  for approval, and staples the returned ticket. Requires a one-time
  `notarytool store-credentials` setup (documented in the script header).

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
