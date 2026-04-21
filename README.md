# HarvestPlus

A macOS menu-bar companion for [Harvest](https://www.getharvest.com) that
keeps your time tracking honest without pulling you out of flow. It lives in
the menu bar, shows the running timer, surfaces your day at a glance, folds in
your calendar meetings, and lets you stop / switch / review entries without
ever touching the Harvest web UI.

HarvestPlus is **not** affiliated with or endorsed by Harvest / Iridesco. It's
a community-built client that talks to the public [Harvest API
v2](https://help.getharvest.com/api-v2/).

---

## What it does

Open HarvestPlus from the menu bar and you get:

- **Today's running timer** with a live elapsed clock.
- **Today's time entries** as a scrollable list, grouped by project, with a
  timeline bar showing how your hours are distributed.
- **Calendar meetings** from macOS Calendar overlaid on the same timeline —
  so you can see at a glance which meetings you've already logged and which
  you haven't.
- **Dashboards** for today / this week / this month / this year with summary
  cards (hours logged, target, overtime, break usage).
- **PDF reports** for any of those ranges, signed off with a clean layout.
- **Banners** (optional) that nag you when you forget to stop the timer or
  when a meeting you haven't logged has just finished.
- **Auto-updates** from GitHub Releases — one click, one signed installer,
  back to work.

---

## Features and why they're here

| Feature | Rationale |
|---|---|
| **Menu-bar only** (no Dock icon) | Time tracking is ambient — it should sit in the corner, not take up a full app window or a Dock slot. `LSUIElement = YES`. |
| **Live timer in the menu bar icon** | The icon state (green / red / grey) tells you at a glance whether a timer is running, so you don't have to click in just to check. |
| **Today's entries in a popover** | The 80% case ("what am I working on, what have I logged, stop the timer") happens without ever opening a window. One click, done. |
| **Calendar integration** | Meetings are the #1 source of untracked time. HarvestPlus reads your Calendar with `EventKit`, maps events to Harvest projects via your mapping rules, and lets you convert a meeting into a time entry with two clicks. |
| **Meeting → Project mapper** | Calendars are messy. You decide per-meeting (or via rules on organizer / title keyword) which Harvest project+task a calendar event should log against. |
| **Daily / Weekly / Monthly / Yearly dashboards** | Harvest's own reports are good but heavyweight. These are fast, keyboard-less, and always current because they're driven off the same cache as the popover. |
| **Overtime calculator** | If you set per-weekday targets (e.g. 7.5h Mon–Thu, 7.0h Fri), HarvestPlus rolls up overtime/undertime against those targets including a configurable lunch window. It respects public holidays and your manually-defined PTO. |
| **PDF export** | Because sometimes "send me the timesheet" means "literally send me a PDF". Built-in `PDFKit` output, no third-party dependency. |
| **Banners** | Two flavours: "timer still running after hours" and "meeting just ended — log it?". Both are optional and can be dismissed/deferred. |
| **Idle detection** | If you walk away from the Mac for N minutes, HarvestPlus can auto-pause or prompt. Configurable threshold. |
| **Keychain-backed token** | Your Harvest personal access token is stored in the login Keychain, not in UserDefaults. Never touches the app bundle or iCloud. |
| **Sandboxed + Hardened Runtime** | The app is sandboxed and uses the hardened runtime — the same security posture Apple requires for notarised apps. The binary is ad-hoc signed (no Apple Developer Program membership required). |
| **Quarantine-strip installer** | The `.pkg` runs a postinstall step that strips `com.apple.quarantine` from the installed `.app`, so day-to-day launches are prompt-free — no "app downloaded from the internet" dialog. |
| **Self-updating** | Internal distribution shouldn't mean manually chasing coworkers down to install a new build. The app polls GitHub Releases daily and offers the new `.pkg` inline. |

---

## Installing HarvestPlus

### For coworkers (you just want the app)

1. Download `HarvestPlus-<version>.pkg` from the
   [latest release](https://github.com/mrpolitic/HarvestPlus/releases/latest).
2. **First-time install only:** the installer is not Apple-notarised (this is
   an internal tool, not App Store software), so macOS will block the first
   open with *"'HarvestPlus-X.Y.Z.pkg' can't be opened because Apple cannot
   check it for malicious software."*
   **Right-click the `.pkg` → Open → Open anyway** to dismiss it once.
3. Authenticate with your Mac password. The installer finishes in a couple of
   seconds. After install, the app launches without any further prompts —
   the postinstall script strips the quarantine flag so Gatekeeper leaves
   it alone.
4. A small green icon appears in your menu bar. Click it → **Settings** (⌘,)
   → **Integrations** → paste your **Harvest Account ID** and a
   **Personal Access Token** from
   [id.getharvest.com/developers](https://id.getharvest.com/developers)
   (the *Personal Access Tokens* section — **not** OAuth2 applications).
5. Click the icon → **Calendar** → grant access when macOS prompts, if you
   want meeting overlays.

> **Note on subsequent updates.** The in-app updater downloads new `.pkg`
> files the same way a browser would, so the "can't check it for malicious
> software" dialog appears on each update. One right-click → Open per
> update and you're through — the installed app itself never prompts.

**System requirements**

- macOS 14 (Sonoma) or later — tested on macOS 26 (Tahoe).
- Apple Silicon or Intel.
- A Harvest account with API access.

**Keeping up to date**

HarvestPlus checks for new releases automatically once per 24 hours. You can
also force a check at any time from *Settings → General → About →
Check for Updates*. Updates are delivered as `.pkg` files; click
*Download & Install*, right-click → Open the downloaded `.pkg` (see
above), and you're running the new version a minute later.

---

## Under the hood

This section is for the nerds. Skip it if you just want to track time.

### Tech stack

- **Swift 5.10 / SwiftUI** on **macOS 14+**
- `MenuBarExtra` with `.menuBarExtraStyle(.window)` for the popover
- `Combine` for timer streams, `async/await` for API calls
- `EventKit` for Calendar
- `Security` framework for Keychain (via a thin `KeychainHelper`)
- `PDFKit` for report export
- No third-party dependencies. No SPM packages. No Sparkle.

### Project layout

```
HarvestPlus/
  App/            # Entry point, AppDelegate, AppState, design tokens
  API/            # Harvest REST client, Keychain, Calendar, meeting→project mapping
  Banner/         # Floating NSPanel banners (reminders, nudges)
  Dashboard/      # Daily/Weekly/Monthly/Yearly views + timeline + summary cards
  Data/           # HolidayEngine (public holidays + PTO)
  Popover/        # Menu-bar popover and the menu-bar icon itself
  Reporting/      # PDF export, overtime calculator
  Resources/      # Assets.xcassets (icons, colour tokens)
  Settings/       # Six Settings tabs (General/Integrations/Schedule/...)
  Timer/          # TimerMonitor (poll state) + IdleDetector
  Updates/        # GitHub Releases update checker + Settings UI
  Info.plist

Scripts/
  build.sh            # archive → export → pkgbuild pipeline
  postinstall.sh      # strips com.apple.quarantine on install
  ExportOptions.plist # Developer ID export config
```

### App architecture

HarvestPlus is a single scene graph hosted by `MenuBarExtra`, plus two
on-demand `Window` scenes and the standard `Settings` scene.

```
HarvestPlusApp (@main)
├── @NSApplicationDelegateAdaptor AppDelegate
├── @StateObject AppState                     ← single source of truth
├── MenuBarExtra                              ← always alive
│   ├── MenuBarIconView(state: timerState)
│   └── PopoverView().environmentObject(appState)
├── Window "Dashboard"                        ← opened via command
├── Window "Log Meeting"                      ← opened from popover
└── Settings → SettingsView (6 tabs)
```

**`AppState`** is an `ObservableObject` that owns:

- `timerState: TimerState` — `.running(TimeEntry) | .stopped | .offline`
- `todayEntries`, `todayMeetings`, `weekSummary`, `monthSummary`, `yearSummary`
- `schedule: WorkSchedule` — weekday targets, lunch window, working hours
- `settings: AppSettings` — user preferences persisted to UserDefaults
- `updateChecker: UpdateChecker` — GitHub Releases poller

Views observe `AppState` via `@EnvironmentObject`. Mutations flow back into
`AppState` which in turn triggers the Harvest API client and updates the
published properties. No Redux, no TCA — plain `ObservableObject`.

### Data flow

```
 ┌──────────────┐  async/await   ┌───────────────────┐   @Published
 │ Harvest API  │ ◄──────────── │ HarvestAPIClient │ ──────────────►  AppState
 └──────────────┘                └───────────────────┘                   │
                                                                         │ @EnvironmentObject
 ┌──────────────┐  EventKit      ┌───────────────────┐                   ▼
 │ macOS Cal    │ ◄──────────── │ CalendarService  │ ──────────►  SwiftUI views
 └──────────────┘                └───────────────────┘
                                         │
                                         ▼  mapping rules
                                 ┌────────────────────┐
                                 │ MeetingProjectMap │
                                 └────────────────────┘
```

`TimerMonitor` polls `HarvestAPIClient.getRunningTimer()` on an interval and
pushes state changes into `AppState`. `IdleDetector` uses `IOKit` to watch
user-input events and fires an action when the idle threshold is crossed.

The popover is cheap to re-render because expensive bits (DateFormatters,
holiday calendars, cache keys) are hoisted to file-scope `private let`
constants rather than constructed per-frame.

### Integrations

**Harvest API** (`API/HarvestAPIClient.swift`)
- Base: `https://api.harvestapp.com/v2`
- Auth: `Authorization: Bearer <token>` + `Harvest-Account-Id: <accountId>`
- Pagination handled inline (`per_page=2000`, walks `total_pages`).
- Uses `JSONDecoder` with `snake_case` → `camelCase` key strategy.

**macOS Calendar** (`API/CalendarService.swift`)
- `EKEventStore` with `requestFullAccessToEvents` (macOS 14+).
- Reads today's window on demand, cached until next fetch.
- The `NSCalendarsFullAccessUsageDescription` string is in `Info.plist`.

**Keychain** (`API/KeychainHelper.swift`)
- Generic-password items under service name `com.qampo.HarvestPlus`.
- Two items: `harvest.account.id` (text) and `harvest.token` (text).
- `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` — not synced to iCloud.

**GitHub Releases** (`Updates/UpdateChecker.swift`)
- Polls `api.github.com/repos/mrpolitic/HarvestPlus/releases/latest` once
  per 24h (and manually on demand).
- Semver compares the tag (or `name`) against `CFBundleShortVersionString`,
  handling prerelease tails (`1.2.0-beta.1 < 1.2.0`).
- Downloads the first `.pkg` asset to `~/Downloads` and reveals it in
  Finder via `NSWorkspace.activateFileViewerSelecting`.

### Security & privacy

- **App Sandbox**: ON (`ENABLE_APP_SANDBOX = YES`).
- **Hardened Runtime**: ON (`ENABLE_HARDENED_RUNTIME = YES`).
- **Code signing**: the `.app` is **ad-hoc signed** (`codesign --sign -`) so
  it satisfies macOS's launch requirements without requiring an Apple
  Developer Program membership. The `.pkg` is **unsigned**. Neither is
  Apple-notarised.
- **Why that's OK for this use case**: this is an internal tool distributed
  to known coworkers via a known GitHub repository. Users verify
  authenticity out-of-band (you pointed them at this repo). In exchange for
  the "right-click → Open once per install" friction, you skip the $99/year
  Apple Developer Program fee and the 5-10 minute notarise step per release.
- **Entitlements** (auto-managed by Xcode based on build settings + Info.plist):
  - `com.apple.security.network.client` — Harvest API calls.
  - `com.apple.security.personal-information.calendars` — EventKit.
  - Keychain access group for storing credentials.
- **What leaves your Mac**
  - HTTPS calls to `api.harvestapp.com` (authenticated with your token).
  - HTTPS calls to `api.github.com` and `objects.githubusercontent.com`
    (unauthenticated, for update checks).
  - Nothing else — no analytics, no telemetry, no crash reporter.
- **What's stored locally**
  - Harvest credentials in the login Keychain.
  - User preferences in `~/Library/Preferences/com.qampo.HarvestPlus.plist`.
  - Cached Harvest responses in-memory only; nothing written to disk.

### Build & release

For the full release procedure, see [`RELEASING.md`](./RELEASING.md). The
short version:

```bash
./Scripts/build.sh --clean       # xcodebuild archive (ad-hoc) → pkgbuild
gh release create v<v> build/HarvestPlus-<v>.pkg \
    --title "HarvestPlus <v>" --notes-file CHANGELOG.md
```

The auto-updater in the installed app picks up the new release on next
daily poll (or when the user clicks *Check for Updates*).

---

## Configuration

All configuration lives in **Settings** (⌘, from the popover, or right-click
the menu-bar icon → Settings).

| Tab | What it does |
|---|---|
| **General** | App-wide preferences, Check for Updates, version/build info. |
| **Integrations** | Harvest Account ID + Personal Access Token. Links to id.getharvest.com/developers and explicitly points to Personal Access Tokens (not OAuth2). |
| **Schedule** | Working hours, per-weekday hour targets, lunch break window. Feeds the overtime calculator. |
| **Notifications** | Banner preferences — idle reminders, meeting-log nudges. |
| **Export** | PDF export defaults (date range, destination folder). |
| **Holidays** | Country/region for public holidays + manual PTO days. |

---

## Development

Requirements:

- Xcode 16 or later (Swift 5.10).
- macOS 14 SDK or later.
- A Developer ID for signed builds (not needed for local runs).

```bash
git clone https://github.com/mrpolitic/HarvestPlus.git
cd HarvestPlus
open HarvestPlus.xcodeproj
# Press ⌘R to run in debug. The app appears in the menu bar.
```

The Xcode project uses **filesystem-synchronized root groups** (Xcode 16+),
so new `.swift` files under `HarvestPlus/<SubfolderName>/` are picked up
automatically without editing `project.pbxproj`. The `Scripts/` folder is
explicitly excluded from the bundle via a `membershipExceptions` entry —
if you add more release scripts there, they won't accidentally end up
inside `HarvestPlus.app/Contents/Resources`.

---

## Contact

Maintainer: Razvan Politic — [@mrpolitic](https://github.com/mrpolitic)

Bug reports and feature requests: open an issue on this repo.
