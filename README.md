# HarvestPlus

A macOS menu-bar companion for [Harvest](https://www.getharvest.com) that
turns raw Harvest data into dashboards, PDF reports, and smart reminders,
without pulling you out of flow. Runs quietly in the menu bar; no Dock icon,
no subscription, no setup beyond pasting your API token.

HarvestPlus is **not** affiliated with or endorsed by Harvest / Iridesco. It's
a community-built client that talks to the public [Harvest API
v2](https://help.getharvest.com/api-v2/).

Source-available under the [PolyForm Shield License 1.0.0](./LICENSE):
free for any use, including at work, except for building a competing
product. See [PRIVACY.md](./PRIVACY.md) for what data the app touches and
where it goes (short answer: almost nothing leaves your Mac).

---

## What it does

- **Dashboards.** Daily, weekly, monthly, and yearly views with summary cards
  for hours logged, target, overtime, and break usage. Always current, no page
  reload.
- **PDF reports.** Export any of those ranges to a clean, ready-to-send PDF
  in two clicks.
- **Smart banners** (optional). A nudge when you forget to stop the timer,
  or when a calendar meeting has just ended without a logged entry. Configurable,
  with snooze and skip-for-today.
- **Calendar integration.** Your macOS Calendar events appear alongside your
  time entries so you can see which meetings are logged and which aren't, and
  convert any event to a Harvest entry in two clicks.
- **Overtime calculator.** Set per-weekday hour targets (e.g. 7.5h Mon–Thu,
  7.0h Fri), a lunch window, and any public holidays or PTO days. HarvestPlus
  rolls up your real overtime and undertime against those targets.
- **Auto-updates.** The app checks GitHub Releases daily and installs new
  versions silently in the background. No Terminal window, no clicks.
- **Menu-bar popover.** Today's entries and running timer are always one click
  away, without opening a full app window.

---

## Installing HarvestPlus

Open **Terminal** (`⌘-Space`, type "Terminal", enter), paste this, hit Return:

```bash
curl -fsSL https://raw.githubusercontent.com/mrpolitic/HarvestPlus/main/Scripts/install.sh | bash
```

No admin password needed: this installs to `~/Applications` (your user's
private Applications folder). macOS treats `~/Applications` identically to
`/Applications` for Launchpad, Spotlight, Dock-pinning, and launch-at-login,
so the app works the same either way.

If you'd rather install to the system-wide `/Applications` (visible to other
users on the same Mac), append `--system`, and you'll be asked for your admin
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

> The icon will be grey and show no data until you connect your Harvest
> account – see the next section.

---

## Connecting to Harvest

The app needs your Harvest Account ID and a personal access token before it
can do anything. This is a one-time step.

### 1. Get your credentials from Harvest

Go to **[id.getharvest.com/developers](https://id.getharvest.com/developers)**.

You'll see two things you need on that page:

- **Account ID**: shown at the top of the page next to your account name.
  It's a plain number (e.g. `1234567`).
- **Personal Access Token**: scroll to the *Personal Access Tokens* section
  and click **Create new personal access token**. Give it any name
  (e.g. "HarvestPlus"), click Create, and copy the token. You won't be able
  to see it again after closing that dialog.

> Make sure you're in the **Personal Access Tokens** section – not
> *OAuth2 Applications*. OAuth tokens won't work here.

### 2. Enter them in HarvestPlus

1. Click the HarvestPlus icon in your menu bar.
2. Open **Settings** – either press `⌘,` or click the gear icon.
3. Go to the **Integrations** tab.
4. Paste your **Account ID** and **Personal Access Token** into the two fields.
5. Click **Save** (or press Return).

The icon will update immediately to show your current timer state. If you see
an error, double-check that you copied the full token and the right Account ID.

### 3. Connect your calendar (optional)

Still in Settings, switch to the **Integrations** tab and scroll down to the
Calendar section. Click **Grant Access** and approve the macOS prompt. This
lets HarvestPlus show your calendar meetings alongside your time entries so
you can spot unlogged meetings.

> **Why Terminal and not a `.pkg`?** One Terminal command is shorter than a
> download-then-double-click flow, and it's the same line in this README, in
> the install script, and for everyone you share it with. The app is signed
> with a Developer ID Application certificate and notarized by Apple, so it
> also launches fine from a downloaded `.app`; `curl | bash` is just less
> typing. Updates after the first install are fully automatic (Sparkle, no
> Terminal); see "Keeping up to date" below.

**System requirements**

- macOS 14.6 (Sonoma) or later. Tested on macOS 26 (Tahoe).
- Apple Silicon or Intel.
- A Harvest account with API access.

**Keeping up to date**

HarvestPlus updates itself with [Sparkle](https://sparkle-project.org). It
checks for new releases once every 24 hours, downloads them in the background,
and installs the update the next time you quit the app. No Terminal, no
password, no clicks, nothing to dismiss.

To check manually, open *Settings → General → About → Check for Updates*. That
brings up Sparkle's standard "Update available" prompt with the release notes
and an Install button.

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
- One Swift Package Manager dependency: [Sparkle](https://sparkle-project.org)
  for auto-updates. Nothing else.

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
  Settings/       # Seven Settings tabs (General/Schedule/Notifications/Integrations/Holidays/Export/Feedback)
  Timer/          # TimerMonitor (poll state) + IdleDetector
  Updates/        # Sparkle updater wrapper + Settings UI
  Info.plist

Scripts/
  build.sh   # archive → Developer ID sign → notarize → staple → zip → sign appcast
  install.sh # curl | bash installer for first install (and the manual-update path)
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
└── Settings → SettingsView (7 tabs)
```

**`AppState`** is an `ObservableObject` that owns:

- `timerState: TimerState` – `.running(TimeEntry) | .stopped | .offline`
- `todayEntries`, `todayMeetings`, `weekSummary`, `monthSummary`, `yearSummary`
- `schedule: WorkSchedule` – weekday targets, lunch window, working hours
- `settings: AppSettings` – user preferences persisted to UserDefaults
- `updateChecker: UpdateChecker` – wraps Sparkle's updater

Views observe `AppState` via `@EnvironmentObject`. Mutations flow back into
`AppState` which in turn triggers the Harvest API client and updates the
published properties. No Redux, no TCA – plain `ObservableObject`.

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
- Uses the data-protection keychain (`kSecUseDataProtectionKeychain`) with the
  access group `PA8H58YHD6.com.qampo.HarvestPlus`, so every signed build reads
  the same items without a re-authorization prompt on each build switch.
- Two items: the Harvest account ID and the personal access token.
- `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`: not synced to iCloud.

**Updates** (`Updates/UpdateChecker.swift`)
- A thin wrapper around Sparkle 2's `SPUStandardUpdaterController`.
- Polls the appcast at
  `raw.githubusercontent.com/mrpolitic/HarvestPlus/main/appcast.xml` once per
  24h (and manually on demand).
- Each release zip is signed with an EdDSA key on the release machine; Sparkle
  verifies the signature against the public key in `Info.plist` before
  installing anything. The bundle swap runs in Sparkle's out-of-process XPC
  installer, which is what lets a sandboxed app update itself with no Terminal
  and no Apple Events.

### Security & privacy

- **App Sandbox**: ON (`ENABLE_APP_SANDBOX = YES`).
- **Hardened Runtime**: ON (`ENABLE_HARDENED_RUNTIME = YES`).
- **Code signing**: signed with a **Developer ID Application** certificate
  (`Developer ID Application: Martin Razvan Politic (PA8H58YHD6)`), so
  Gatekeeper accepts the binary as coming from an Apple-verified developer.
- **Notarization**: every release is submitted to Apple's notary service via
  `xcrun notarytool` and the returned ticket is **stapled** to the `.app`,
  so Gatekeeper can validate it offline – no "is damaged" / "unidentified
  developer" dialogs, no System Settings trip.
- **Entitlements** (`HarvestPlus.entitlements`):
  - `com.apple.security.network.client`: Harvest API + Sparkle update checks.
  - `com.apple.security.personal-information.calendars`: EventKit.
  - `com.apple.security.files.user-selected.read-write`: PDF export destination.
  - `keychain-access-groups`: shared credential access across signed builds.
  - `com.apple.security.temporary-exception.mach-lookup.global-name`
    (`org.sparkle-project.InstallerLauncher`): lets the sandboxed app reach
    Sparkle's out-of-process installer.
- **What leaves your Mac**
  - HTTPS calls to `api.harvestapp.com` (authenticated with your token).
  - HTTPS calls to `raw.githubusercontent.com` (the Sparkle appcast) and
    `github.com` / `objects.githubusercontent.com` (release downloads),
    unauthenticated, for updates.
  - A feedback submission, only if you send one from Settings → Feedback, via
    [Web3Forms](https://web3forms.com).
  - Nothing else. No analytics, no telemetry, no crash reporter.
- **What's stored locally**
  - Harvest credentials in the login Keychain.
  - User preferences in `~/Library/Preferences/com.qampo.HarvestPlus.plist`.
  - Cached Harvest responses in-memory only; nothing written to disk.

### Build & release

For the full release procedure, see [`RELEASING.md`](./RELEASING.md). The
short version:

```bash
./Scripts/build.sh --clean       # archive → sign → notarize → staple → zip → sign appcast
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
| **Notifications** | Banner preferences: idle reminders, meeting-log nudges, end-of-day and end-of-week summaries. |
| **Export** | Default format (PDF or CSV), paper size, project-name cleanup, and the report start-date cutoff. |
| **Holidays** | Country/region for public holidays + manual PTO days. |
| **Feedback** | In-app form for bug reports, ideas, and general feedback, sent to the maintainer. |

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
explicitly excluded from the bundle via a `membershipExceptions` entry –
if you add more release scripts there, they won't accidentally end up
inside `HarvestPlus.app/Contents/Resources`.

---

## Contact

Maintainer: Razvan Politic – [@mrpolitic](https://github.com/mrpolitic)

Bug reports and feature requests: open an issue on this repo.
