# Privacy Policy

**HarvestPlus** is a macOS menu-bar companion for
[Harvest](https://www.getharvest.com). This document explains, in plain
language, what data it touches, where that data lives, and what it sends off
your machine.

*Last updated: 2026-05-22*

---

## TL;DR

- HarvestPlus stores your Harvest credentials in the **macOS Keychain**, on
  your Mac, never synced to iCloud.
- It talks to **Harvest's own API** on your behalf, using the token you
  provided.
- It checks **GitHub Releases** for app updates and downloads them via
  Sparkle.
- It sends **feedback submissions to Web3Forms** only when you click "Send
  Feedback" – never in the background.
- It does **not** collect analytics, telemetry, usage data, crash reports,
  or anything else automatically. There is no tracking. There is no user
  ID. There is no "anonymous" aggregate data – there is no data.
- Calendar events you opt into are read **locally** via macOS's EventKit
  and never leave your Mac.

If that's all you needed to know, you can stop reading. Details below.

---

## What HarvestPlus stores on your Mac

| Data | Where | Notes |
|---|---|---|
| Harvest Account ID + Personal Access Token | macOS **login Keychain** | Protected by your macOS login password. Accessibility class: `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` – not synced to iCloud. |
| App preferences (work schedule, notification toggles, paper size, etc.) | `~/Library/Preferences/com.qampo.HarvestPlus.plist` | Standard macOS UserDefaults. |
| Last update check timestamp | UserDefaults (same file) | Used by Sparkle to throttle update checks to ~24h. |
| Cached Harvest API responses (time entries, projects, etc.) | **In memory only** | Cleared when the app quits. Nothing written to disk. |
| Sparkle's EdDSA public key + appcast URL | Inside the `.app` bundle (`Info.plist`) | Used to verify update authenticity. |

No HarvestPlus data leaves the Keychain or UserDefaults except as described
in the next section.

---

## What HarvestPlus sends over the network

HarvestPlus makes HTTPS requests to four endpoints, and **nothing else**:

### 1. Harvest's API – `api.harvestapp.com`
- **When:** continuously while the app is running (polling your running
  timer every 60 s by default; on demand when you start/stop a timer,
  fetch dashboards, etc.).
- **What:** the standard Harvest API v2. Authenticated with the Personal
  Access Token you entered in Settings → Integrations.
- **Who sees it:** Harvest (Iridesco LLC). Their privacy policy applies:
  [getharvest.com/policies/privacy](https://www.getharvest.com/policies/privacy).
- **Why:** that's the whole point of the app.

### 2. GitHub Releases – `raw.githubusercontent.com` and `github.com`
- **When:** once every 24 h while the app is running (Sparkle's auto-check),
  or when you click "Check for Updates" in Settings.
- **What:** a GET request for the
  [appcast.xml](https://raw.githubusercontent.com/mrpolitic/HarvestPlus/main/appcast.xml)
  file, and (if a newer release exists) a download of the new app zip.
- **Who sees it:** GitHub, Inc. They will know your IP address and that
  you fetched a HarvestPlus update file.
- **Why:** to keep you on the latest version without manual intervention.

### 3. Web3Forms – `api.web3forms.com`
- **When:** *only* when you fill in the Feedback form in
  Settings → Feedback and click **Send**.
- **What:** the category, subject, and message you typed, plus
  auto-collected metadata (app version, macOS version, architecture,
  locale, time zone). If you chose to attach a file, that file too.
- **Who sees it:** Web3Forms (a third-party form-relay service), which
  forwards the submission to the HarvestPlus maintainer's email. The
  maintainer's email address is not visible inside the app –
  Web3Forms hides it behind a public access key.
- **Why:** so bug reports and feature requests reach the maintainer
  without standing up a custom backend.
- **You always know it's happening:** the Send button is the only
  trigger. There is no background submission, no error-reporter that
  silently phones home.

### 4. Apple's notarization / Gatekeeper – *passive*
- When you first launch an updated HarvestPlus, macOS itself may make a
  request to Apple to verify the stapled notarization ticket. HarvestPlus
  doesn't initiate this; it's part of Gatekeeper. Apple's own privacy
  policy applies.

---

## What HarvestPlus does **not** do

- No analytics. No Mixpanel, no Amplitude, no Segment, no Google Analytics,
  no Apple App Analytics.
- No crash reporter that sends data automatically. (You can manually
  attach a crash log via the Feedback form.)
- No telemetry. No "feature flag" pings. No A/B testing infrastructure.
- No advertising IDs. The app doesn't read your `IDFV`/`IDFA` or anything
  similar.
- No third-party SDKs that phone home. The app's only dependencies are
  Apple frameworks and [Sparkle](https://sparkle-project.org/), an
  open-source updater that talks only to the appcast URL above.
- No background uploads of your time entries, calendar events, or
  preferences.

---

## Calendar access

If you grant Calendar access in Settings → Integrations, HarvestPlus reads
your events through macOS's **EventKit** framework on your Mac. The events
are used to:

- Show meetings on the daily timeline so you can spot unlogged ones.
- Let you convert a calendar event into a Harvest time entry with two clicks.

The event data **never leaves your Mac** unless you explicitly create a
time entry from a meeting – in which case it's sent to Harvest's API as
the entry's notes/project/task, the same as if you'd typed it in manually.

You can revoke Calendar access at any time via System Settings → Privacy &
Security → Calendars. HarvestPlus will fall back to a no-calendar mode and
keep working.

---

## Your control over your data

- **Disconnect your Harvest account:** Settings → Integrations → clear the
  Account ID and token fields, click Save. The Keychain items are
  overwritten with empty strings. To fully delete them: use Keychain Access
  → search "com.harvestplus" → delete both entries.
- **Reset preferences:** delete
  `~/Library/Preferences/com.qampo.HarvestPlus.plist`.
- **Wipe everything:** delete the app, the Keychain entries, the
  preferences file, and the sandbox container at
  `~/Library/Containers/com.qampo.HarvestPlus`. After that, no trace of
  HarvestPlus remains on your Mac.
- **Don't want updates auto-checked?** Open `Info.plist` (advanced) and set
  `SUEnableAutomaticChecks` to `false`, *or* file an issue and we'll add a
  toggle in the UI.

---

## Third-party services we rely on

| Service | What for | Their privacy policy |
|---|---|---|
| Harvest (Iridesco LLC) | Time tracking API | [getharvest.com/policies/privacy](https://www.getharvest.com/policies/privacy) |
| GitHub, Inc. | Release hosting + Sparkle appcast | [docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement) |
| Web3Forms | Feedback submission relay | [web3forms.com/privacy](https://web3forms.com/privacy) |
| Apple, Inc. | macOS, Gatekeeper, EventKit, Keychain | [apple.com/legal/privacy](https://www.apple.com/legal/privacy/) |

---

## Children

HarvestPlus is a workplace tool for tracking professional time. It is not
designed for or directed at children under 13, and we do not knowingly
collect any data from them.

---

## Changes to this policy

If we change how HarvestPlus handles data, we'll update this file and
mention it in the [CHANGELOG](./CHANGELOG.md). Significant changes will
be called out in release notes.

---

## Contact

Bug reports, privacy questions, or anything else: use the in-app feedback
form (Settings → Feedback) or open an issue on the
[GitHub repository](https://github.com/mrpolitic/HarvestPlus).
