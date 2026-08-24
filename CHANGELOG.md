# Changelog for MeetingBarNG

MeetingBarNG is a fork of [MeetingBar](https://github.com/leits/MeetingBar) by Andrii
Leitsius. MeetingBarNG's own releases are listed first; the history from 5.0.0 down is
inherited from upstream MeetingBar and kept for attribution and reference.

For upstream releases, see <https://github.com/leits/MeetingBar/releases>.

> **Note:** MeetingBarNG releases are currently source-only — the tags carry release notes
> but no built artifact. Building a signed, notarized dmg is tracked as the next work in
> `STATE.md`.

## Unreleased

* Menu-bar **Join chip** — a one-click Join button on the status item for upcoming or active
  meetings that have a link. A left-click on the chip joins directly instead of opening the
  dropdown; everywhere else on the item still opens it.
* **Countdown lead time** — a new preference controls how many minutes before an event the
  countdown appears, so a meeting hours away no longer occupies the menu bar.
* **DEBUG-only harness** for injecting synthetic events and toggling menu-bar settings, to
  exercise display states without real calendar data. Excluded from release builds.

## 0.3.0 (2026-07-29)

### Timeline

* **Timeline style** — *Track* (hour grid, overlapping meetings stacked), *Bar* (one rail with
  meetings inline and hours beneath, about half the height), or *Minimal* (the rail alone).
* **Timeline covers** — *Around now* frames the bar on the meetings it is actually drawing, so it
  no longer opens on hours of empty morning; *Whole day* gives every meeting a fixed place.
* Turning the timeline off lives in the same picker, so there is one control rather than two that
  can disagree.

### Meeting card

* Choose what it shows — the "Next meeting" line, start and end times, the meeting service, the
  calendar and account, and the countdown bar — each independently.
* The countdown hides itself when the meeting is more than an hour out, instead of drawing an
  empty track.

### Month calendar

* Dots now appear on every day with meetings, not only today. The grid fetches its own month,
  keeps the days it already knows while that is in flight, and leaves previous dots alone if a
  fetch fails. Day cells highlight on hover.

### Legibility

* The menu-bar progress indicator draws in the menu bar's own text colour, which macOS already
  guarantees is legible against any wallpaper. Earlier attempts in grey and in the accent colour
  disappeared against tinted menu bars.

### Preferences

* Sidebar pinned to the standard 215pt and no longer resizable; the search field sits under the
  title bar where it belongs.
* The live preview updates when any setting changes — previously adding Month Calendar appeared to
  do nothing until an unrelated toggle forced a refresh.

### Dropdown polish

* Rules only where they separate something, inset rather than full-bleed. Agenda rows on the
  design's grid, with long titles fading under the Join button instead of a hard ellipsis.
* A `+ ⌘N` chip beside today's heading, which creates a calendar event — matching the shortcut it
  names. The date moved to the greeting so the day is named once.
* Hover and selection are translucent glass rather than a saturated accent bar. Row density now
  moves card padding too, not just rows.

## 0.2.0 (2026-07-28)

A substantial pass over the dropdown and the menu bar.

### The dropdown

Rebuilt around a `.menu` vibrancy surface with carded modules, so it reads as one sheet rather
than a stack of strips.

* **One "Next meeting" card.** The card and a separate "up next" progress bar described the same
  meeting and could both appear at once. The countdown bar is now an option on the card. Existing
  settings carry across.
* **Density reaches the cards.** Small/Medium/Large move card padding and corner radius, not just
  rows.

### Menu bar

* **Meeting progress**, off by default, in four styles: underline, ring, capsule, and a standalone
  mini bar. Fills over the hour before a meeting, is exactly full when it starts, then counts
  through it. Nothing is drawn when no meeting is close.

### Accessibility and legibility

* **Reduce Transparency is now respected** — the panel goes opaque when the system asks. It
  previously was not honoured anywhere in the app.
* **The panel holds contrast over pale wallpapers.** Behind-window vibrancy takes its lightness
  from the desktop while text and icons take theirs from the appearance; over a light background
  the two disagreed and the faintest elements washed out. There is now a contrast floor, and the
  edge treatments adapt to light and dark instead of assuming dark.

### Removed

* **The classic macOS menu dropdown**, and the "Use the classic macOS menu instead" switch in
  Preferences ▸ General ▸ Troubleshooting. It was a second, feature-frozen renderer of the same
  content that every new dropdown feature had to be designed around. The right-click quick-actions
  menu is unaffected — it is still a native menu, which is the right shape for a short list of
  verbs. Your stored preference is left in place and simply ignored; nothing needs migrating.

### Under the hood

* ~3,100 net lines removed. The meeting-card copy, the agenda's visibility rules, and the
  quick-actions menu were extracted out of the deleted menu builder first, so nothing shared was
  lost with it. End-to-end tests that drove an `NSMenu` were ported rather than dropped — they
  were always asking "given these settings, does the dropdown show this meeting?", so they now ask
  that directly.

---

## 5.0.0 (2026-06-19)

MeetingBar 5 is an architecture and product refresh. It improves the
first-run experience and day-to-day meeting controls while establishing
a safer foundation for calendar providers and future integrations.

### Product refresh

* Added a clearer onboarding flow for calendar source selection,
  authorization, calendar selection, meeting-opening preferences, and
  final daily-essentials setup.
* Improved the meeting menu around the current or next meeting, with a
  clear Join action, source-aware secondary actions, and actionable
  empty and error states.
* Moved the optional day timeline above the current or next meeting
  summary so the menu opens with a compact today overview and clear
  meeting actions.
* Reorganized Preferences around General, Calendars, Meeting Opening,
  Menu Bar, Notifications, and Advanced.
* Added provider health and refresh information to application state so
  onboarding, the menu, and Preferences show consistent status.

### Calendar reliability

* Calendar provider setup and switching are transactional. Cancelling or
  failing Google authorization keeps the previous provider and calendar
  selection active.
* Selected calendars are stored per provider, so Apple Calendar and
  Google Calendar selections are preserved when switching.
* Successful provider setup keeps already-fetched calendars available
  for onboarding instead of briefly showing an empty selection state.
* Google sessions use the persisted OAuth refresh token rather than only
  the latest token response, preventing unnecessary reauthorization.
* Refresh failures preserve last-known calendars and events and surface
  stale or reconnect warnings instead of silently showing empty data.
* Provider warnings remain visible in the menu even when a cached next
  meeting is available.

### Meeting reliability

* Open in Calendar is source-aware: Apple Calendar events use their
  EventKit identifier, while Google events use the Google Calendar web
  link when available.
* Native conference data is preferred over unrelated links in event
  notes, with custom meeting-link regexes retained as a fallback.
* Microsoft Teams short meeting links such as
  `teams.microsoft.com/meet/...?...` are detected alongside legacy
  `meetup-join` links, including supported government hosts.
* Zoom personal-room `/my/` links open once in the browser instead of
  also attempting a native Zoom deep link.
* Dismissed meetings remain hidden until their modification date changes,
  allowing updated meetings to appear again.
* Added a defensive status bar fallback icon when a settings combination
  would otherwise render neither an icon nor text. This does not override
  third-party menu bar item hiding tools.

### Architecture

* `AppModel`, `AppState`, `AppAction`, and `AppEnvironment` now provide
  the central application-state boundary.
* Calendar providers are isolated behind `CalendarRepository`,
  `CalendarSync`, and provider health state.
* Meeting providers and link detection use a shared descriptor registry.
* Testable policies for event selection, meeting links, notifications,
  status presentation, and Google Calendar behavior live in the
  hostless `MeetingBarLogic` package.
* Notification planning and delayed actions are managed per event, so
  back-to-back meetings do not suppress one another.
* Existing browser, calendar-selection, and bookmark settings retain
  compatibility migrations.
* Contributor documentation now consolidates architecture, dependency,
  and release-sensitive guidance, with obsolete planning, migration, and
  checklist drafts removed.

### Validation

* Added focused hostless and app-hosted regression tests for provider
  switching, Google authentication, shared calendar selection, menu
  status, meeting-link priority, ongoing meetings, and automatic join.
* English source strings are validated with `make validate-strings`.
  Non-English translations will be refreshed through Weblate after the
  V5 string freeze.

## Version 4.11.0

> (released)

* Added action to dismiss the event from the notification

## Version 4.0.0

> (released)

> Direct integration with Google Calendar API

*   Added integration with Pop, Livestorm, Chorus & Gong
*   Fix readability of the statusbar text in multi-screen setups (#354)
*   Detect hidden menubar icon (#429)
*   Added feature to snooze the notification
*   Fix crash due to meeting attendees without an email address (#460)

## Version 3.10.0

> (released 25 Jan 2022)

*   Added translations into Turkish
*   Integrations with Facetime, Vimeo Showcases, and oVice
*   New "Refresh source" Quick Action

## Version 3.9.0

> (released 20th Nov 2021)

*   Added translations into Hebrew
*   Advanced feature to filter out events by regex
*   Added integration with Zhumu/WeMeeting, Lark, and Feishu
    and small bug fixes

## Version 3.8.0

> (released 15th Sep 2021)

*   Added translations into Polish
*   Support MeetInOne for Google Meet links
*   Support Jitsi native app for Jitsi links
*   Open the link from the event link field if the meeting service is not recognized

## Version 3.7.0

> (released 19th Aug 2021)

*   Added copy meeting link & email attendees from event submenu
*   Round the timer up, not down
*   Made event start soon notification more specified
*   Added translations into Japanese

## Version 3.6.0

> (released 15th Jun 2021)

*   Added translations into Czech
*   Added integration with Vowel
*   Fixed zoom link detection bug from 3.5 version

## Version 3.5.0

> (released 11th Jun 2021)

*   Added translations into Croatian, German, French, and Norwegian Bokmål
*   Improve RingCentral and Zoom links Detection
*   All app notifications are now removed after all meetings are over
*   Open link from clipboard in configured browser
*   Fixed a bug with the inability to change shortcuts
*   Fixed disappearing app icon when no calendar selected
*   Fixed opening ZoomGov links in the native app

## Version 3.4.0

> (released 12th May 2021)

*   📋 New view of notes in the event submenu with selectable text and clickable links
*   🧭 Fixed a bug with opening meetings in a new browser instance

and small bug fixes

## Version 3.3.0

> (released 1st May 2021)

*   Fixed bug with timer freeze ⏱️
*   Browser management 🧰
*   Quick Actions ⚡
    *   Show/hide meeting title in status bar
    *   Open meeting from clipboard
*   Customizable appearance for events without meeting links
*   Localization (Ukrainian and Russian)
*   Create meetings in Jam
*   Open event in Fantastical from event submenu
*   Integration with subscribed calendars

## Version 3.2.1

> (released 30th Mar 2021)

*   Fixed showing the "What's New" at the first opening.

## Version 3.2.0

> (released 25th Mar 2021)

*   Added setting to only show events starting in x minutes.
*   Recognize outlook safe links
*   Added Safari as a browser option.
*   New integrations: Discord, Jam, and Blackboard Collaborate.

and small bug fixes

## Version 3.1.2

> (released 20th Feb 2021)

Fixed blurry image and text truncating in about section

## Version 3.1.1

> (released 18th Feb 2021)

Added Contact and GitHub buttons in Preferences

Fixed:

*   Facebook Workplace links redirecting to Facebook profiles
*   Trimming special symbols at the beginning of event title
*   Text alignment issue in the menu while in 12 hr time
*   Excessive notification if next meeting is changed

## Version 3.1

> (released 11th Feb 2021)

*   Add Around integration
*   Hide show time under title option for Big Sur
*   Fix issues with service icons
*   Fix URLs for Firefox and Microsoft Edge

## Version 3.0

> (released 7th Feb 2021)

*   Patronage via In‑App Purchase

#### New features

*   ⭐ Bookmarks ⭐
    *   Add meeting links as bookmarks and join them from the menu
*   Full control of the **app appearance**:
    *   Customize icon, title, and time in the status bar
    *   Show event end time and icon in the menu
    *   Limit event title length in the menu
*   Wider settings for **displaying events**. Configure pending events, all-day events, and events without guests.
*   **Custom link** for ad hoc meeting
*   Global shortcut to open the app
*   Support new browsers as an executable for Google Meet: Chromium, Firefox, Edge, Brave, Vivaldi, and Opera.
*   Showing alerts if notification disabled for warnings
*   Pretty rendering HTML description for events

#### New integrations

Recognize links for:

*   Facetime scheme
*   Telephone scheme
*   Zoom native app
*   Youtube
*   TeamViewer Meeting
*   Google Meet Stream
*   Vonage Meetings

#### Bugfixes

*   Fixed opening links twice on click
*   Fixed regex for self-hosted skype
*   Fixed regex for zoom
*   Fixed app icon for Big Sur

## Version 2.0.5

> (released 1st Dec 2020)

#### Bugfixes

*   Fix double menu bar icons

## Version 2.0.4

> (released 1st Dec 2020)

#### Bugfixes

*   Fixed sticking status bar icon

## Version 2.0.3

> (released 1st Dec 2020)

#### Bugfixes

*   Make notification persistent

## Version 2.0.2

> (released 27th Nov 2020)

#### New features

*   Brand new App Icon by Miroslav Rajkovic.

## Version 2.0.1

> (released 25th Nov 2020)

#### Bugfixes

*   Fixed status bar icon to match dark/light appearance

## Version 2.0

> (released 25th Nov 2020)

#### New features

*   Advanced settings! Run custom AppleScript on join to event and apply custom regexes to meeting links search
*   Small language tweak for date header
*   Creating a meeting in Google Calendar and Outlook (both personal and office 365)
*   Lifesize and Facebook Workspace integrations
*   Next event visibility time extended to 15 min
*   "3 minutes before" option for join event notification
*   Open event in the calendar from the submenu
*   New status bar icon for Big Sur

For previous versions see https://github.com/leits/MeetingBar/releases
