# HarvestPlus

A macOS menu-bar companion for [Harvest](https://www.getharvest.com) that
turns raw Harvest data into dashboards, PDF reports, and smart reminders —
without pulling you out of flow. Runs quietly in the menu bar; no Dock icon,
no subscription, no setup beyond pasting your API token.

HarvestPlus is **not** affiliated with or endorsed by Harvest / Iridesco. It's
a community-built client that talks to the public [Harvest API
v2](https://help.getharvest.com/api-v2/).

---

## What it does

- **Dashboards** — daily, weekly, monthly, and yearly views with summary cards:
  hours logged, target, overtime, and break usage. Always current, no page
  reload.
- **PDF reports** — export any of those ranges to a clean, ready-to-send PDF
  in two clicks.
- **Smart banners** (optional) — get nudged when you forget to stop the timer,
  or when a calendar meeting has just ended without a logged entry. Dismissible
  and configurable.
- **Calendar integration** — your macOS Calendar events appear alongside your
  time entries so you can see which meetings are logged and which aren't, and
  convert any event to a Harvest entry in two clicks.
- **Overtime calculator** — set per-weekday hour targets (e.g. 7.5h Mon–Thu,
  7.0h Fri), a lunch window, and any public holidays or PTO days. HarvestPlus
  rolls up your real overtime and undertime against those targets.
- **Auto-updates** — the app polls GitHub Releases daily. When a new version is
  available, one click opens Terminal and installs it in place.
- **Menu-bar popover** — today's entries and running timer are always one click
  away, without opening a full app window.

---

## Installing HarvestPlus

Open **Terminal** (`⌘-Space`, type "Terminal", enter), paste this, hit Return:

```bash
curl -fsSL https://raw.githubusercontent.com/mrpolitic/HarvestPlus/main/Scripts/install.sh | bash
```

No admin password needed — this installs to `~/Applications` (your user's
private Applications folder). macOS treats `~/Applications` identically to
`/Applications` for Launchpad, Spotlight, Dock-pinning, and launch-at-login,
so the app works the same either way.

If you'd rather install to the system-wide `/Applications` (visible to other
users on the same Mac), append `--system` — you'll be asked for your admin
password once:

```bash
curl -fsSL https://raw.githubusercontent.com/mrpolitic/HarvestPlus/main/Scripts/install.sh | bash -s -- --system
```

Either way the script:

1. Downloads `HarvestPlus.app.zip` from the latest GitHub release.
2. Extracts it into `~/Applications/HarvestPlus.app` (or `/Applications` with
   `--system`), replacing any previous version.
3. Strips the `com.apple.quarantine` flag so macOS launches it without any
   "Apple cannot verify…" Gatekeeper prompt.
4. Launches the app. A small icon appears in your menu bar.

After first launch:

1. Click the menu-bar icon → **Settings** (`⌘,`) → **Integrations** → paste
   your **Harvest Account ID** and a **Personal Access Token** from
   [id.getharvest.com/developers](https://id.getharvest.com/developers)
   (the *Personal Access Tokens* section — **not** OAuth2 applications).
2. Click the icon → **Calendar** → grant access when macOS prompts, if you
   want meeting overlays.

> **Why Terminal and not a `.pkg`?** macOS 15 (Sequoia) tightened Gatekeeper
> so that double-clicking an unsigned `.pkg` or `.app` no longer offers a
> right-click → Open bypass — users would have to dig into System Settings →
> Privacy & Security → "Open Anyway" for every install. The `curl | bash`
> path avoids that friction: `curl` doesn't mark downloads with the
> `com.apple.quarantine` attribute, so macOS treats the installed app as a
> local binary and launches it silently. If you'd rather pay Apple $99/year
> and sign + notarise the build, see
> [`RELEASING.md`](./RELEASING.md#upgrading-to-the-signednotarised-path-later).

**System requirements**

- macOS 14 (Sonoma) or later — tested on macOS 26 (Tahoe).
- Apple Silicon or Intel.
- A Harvest account with API access.

**Keeping up to date**

HarvestPlus checks for new releases automatically once per 24 hours. You can
also force a check from *Settings → General → About → Check for Updates*.
When an update is available, click **Install Update** — Terminal opens and
runs the same `curl | bash` one-liner automatically. The running app is
replaced in-place.

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
  build.sh            # archive → ditto HarvestPlus.app.zip (ad-hoc)
  install.sh          # curl | bash installer run by coworkers
  postinstall.sh      # (unused today — kept for future signed .pkg path)
  ExportOptions.plist # (unused today — kept for future Developer ID path)
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
- On finding a newer release, uses `NSAppleScript` to tell Terminal to
  `do script` with the install one-liner — no file written, no quarantine
  issue. We don't download in-app: sandboxed apps can't replace their own
  bundle, and a `URLSession`-downloaded `.zip` would inherit the quarantine
  xattr.

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
- **Entitlements** (`HarvestPlus.entitlements`):
  - `com.apple.security.network.client` — Harvest API + update checks.
  - `com.apple.security.personal-information.calendars` — EventKit.
  - `com.apple.security.files.user-selected.read-write` — PDF export destination.
  - `com.apple.security.automation.apple-events` — tells Terminal to run the
    installer when you click *Install Update* (one-time consent dialog).
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
./Scripts/build.sh --clean       # xcodebuild archive (ad-hoc) → ditto .app.zip
gh release create v<v> \
    build/HarvestPlus.app.zip build/HarvestPlus-<v>.app.zip \
    --title "HarvestPlus <v>" --notes-file CHANGELOG.md
```

The fixed-name `HarvestPlus.app.zip` is what `install.sh` fetches from
`/releases/latest/download/…`; the versioned copy is for humans browsing the
Releases page. The auto-updater in the installed app picks up the new
release on the next daily poll (or when the user clicks *Check for Updates*).

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
