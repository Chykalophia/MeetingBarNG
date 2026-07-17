# MeetingBarNG

**MeetingBarNG** is a modern, customizable rebuild of the macOS menu-bar meeting
companion — it keeps your current or next calendar meeting in the status bar and
lets you join it in one click.

It is created and maintained by **[Peter Krzyzek](https://peterkrzyzek.com)** under
**[Chykalophia](https://chykalophia.com)**, and is an actively-developed fork of the
excellent open-source [**MeetingBar**](https://github.com/leits/MeetingBar) by
[Andrii Leitsius](https://github.com/leits). MeetingBarNG stays free, open source,
and privacy-respecting.

> **Status: pre-release / in active development.** MeetingBarNG is being overhauled
> and modernized (code, UI, UX, and features). It is not yet distributed as a packaged
> app under its own identity — build it from source, or use the original
> [MeetingBar](https://github.com/leits/MeetingBar) if you want a shipping app today.

<img src="screenshot.png" width="700" alt="MeetingBarNG in the macOS menu bar">

---

## Why MeetingBarNG

MeetingBar is a rock-solid, reliability-first menu-bar app. MeetingBarNG builds on that
foundation with a deliberate goal: a **modern, deeply customizable look and feel** with
close **productivity feature parity** to modern menu-bar calendars like
[Dot](https://www.trydot.app), while keeping everything local, private, and open source.

See [`ROADMAP.md`](ROADMAP.md) for the full build-out plan.

---

## What it does today

### See what is next
* Show the current or next meeting in the macOS status bar.
* Display meeting title, time, countdown, icon, or meeting service.
* Show upcoming events from today and tomorrow in the menu.
* Filter all-day, declined, tentative, pending, or linkless events.
* Shorten long meeting titles to keep the menu bar readable.

### Join meetings faster
* Join the current or next online meeting with one click.
* Join the nearest meeting with a global keyboard shortcut.
* Create ad-hoc meetings from your preferred meeting service.
* Open meeting links in a preferred browser or native app per service.
* Open event details in macOS Calendar or Fantastical.

### Get meeting reminders
* Receive macOS notifications before meetings.
* Use full-screen reminders for important meeting starts.
* Dismiss meeting notifications when you no longer need them.

### Customize and automate
* Bookmark recurring meetings and access them quickly.
* Launch automatically at login.
* Use Shortcuts and AppleScript integrations (e.g. pause music when joining a meeting).

### Calendar providers
* **macOS Calendar** — any account synced with Calendar.app (iCloud, Google, Exchange,
  Office 365, Yahoo, AOL, and others).
* **Google Calendar** — connect Google Calendar directly.

### Supported meeting services
More than 50 services, including Google Meet, Zoom, Microsoft Teams, Webex, GoToMeeting,
Skype, Discord, Jitsi, RingCentral, BlueJeans, Whereby, Slack Huddle, FaceTime, LiveKit
Meet, Meetecho, and StreamYard.

---

## Where we are headed (launch goal)

The launch target is close **productivity parity** with [Dot](https://www.trydot.app),
paired with a modern, customizable UI. Highlights on the roadmap:

* **Composable menu bar** — mix-and-match tokens (date, next event, countdown, progress
  bars, clock) instead of a single fixed format.
* **Menu-bar calendar** — browse/navigate a month ⇄ week calendar and a day summary
  (event count + focus time) right from the menu bar.
* **Command bar & keyboard-first navigation** — one shortcut to create, search, and jump.
* **Meeting prep & camera preview** — surface invite links automatically and check
  camera/mic/lighting before joining.
* **Reminders & focus** — Apple Reminders alongside events, per-event reminders, and
  snooze (by time or location).
* **Deeper customization & theming** — countdown styles, date markers, hide-empty-days,
  system/custom themes.
* **Richer event handling** — full event search, inline edit, location autocomplete,
  calendar picker, quick date jump, right-click actions, multi-calendar
  (iCloud/Google/Outlook/Exchange).

**Explicitly out of scope:** natural-language event creation. MeetingBarNG will not parse
free-text into events.

The complete parity checklist and the deferred rename/overhaul backlog live in
[`ROADMAP.md`](ROADMAP.md).

---

## Build from source

MeetingBarNG requires **macOS 12.0 or later** and is built with Xcode, Swift 6, AppKit,
SwiftUI, and Xcode-managed Swift Package dependencies.

For local signing, create `XCConfig/DevTeamOverride.xcconfig` with your Apple development
team (this file is git-ignored):

```xcconfig
DEVELOPMENT_TEAM = <your development team id>
```

### Google Calendar in a local build (optional)

The **macOS Calendar** provider works out of the box (including Google accounts added
in System Settings → Internet Accounts). To use the native **Google Calendar** provider
in a local build, supply your own OAuth credentials — otherwise that provider fails
gracefully with a "not configured" message.

Copy `XCConfig/GoogleSecrets.xcconfig.example` to `XCConfig/GoogleSecrets.xcconfig`
(git-ignored) and follow the steps in that file to create an OAuth client in the
[Google Cloud Console](https://console.cloud.google.com/apis/credentials) and fill in
`GOOGLE_CLIENT_NUMBER`, `GOOGLE_CLIENT_SECRET`, and `GOOGLE_AUTH_KEYCHAIN_NAME`. Rebuild
and pick "Google Calendar" in onboarding.

Common commands:

```bash
make build            # Debug build
make test             # SwiftPM logic tests + Xcode app-hosted tests with coverage
make test-logic       # Hostless SwiftPM logic tests only
make lint             # SwiftLint
make validate-strings # Verify English localization keys used by .loco()
```

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) before changing app flow, calendar
providers, meeting-link detection, notifications, status-bar rendering, settings,
dependencies, entitlements, or release-sensitive configuration.

---

## Privacy

MeetingBarNG does not collect personal data. Calendar data is used only on your Mac to
show meetings, detect meeting links, and open the correct meeting action.

---

## Contributing

Contributions are welcome — focused fixes, meeting-service integrations, reliability
improvements, translations, and documentation. See [`CONTRIBUTING.md`](CONTRIBUTING.md).

---

## Credits & attribution

MeetingBarNG is a derivative work of [**MeetingBar**](https://github.com/leits/MeetingBar),
© 2020 [Andrii Leitsius](https://github.com/leits) and the MeetingBar contributors, used
under the Apache License 2.0. Enormous thanks to the original author and community — the
original app is [in the Mac App Store](https://apps.apple.com/us/app/id1532419400) and on
Homebrew (`brew install --cask meetingbar`). The original author is Ukrainian 🇺🇦 —
[Stand With Ukraine](https://stand-with-ukraine.pp.ua).

MeetingBarNG (and MeetingBar) rely on:

* [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) — global shortcuts
* [Defaults](https://github.com/sindresorhus/Defaults) — user settings
* [LaunchAtLogin](https://github.com/sindresorhus/LaunchAtLogin) — launch-at-login
* [AppAuth-iOS](https://github.com/openid/AppAuth-iOS) — Google Calendar OAuth

Original app logo by [Miroslav Rajkovic](https://www.rajkovic.co/).

See [`NOTICE`](NOTICE) for the full attribution notice.

---

## License

MeetingBarNG is licensed under the [Apache License 2.0](LICENSE), the same license as the
upstream project.
