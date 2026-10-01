# Changelog for Punctual

Punctual (formerly MeetingBarNG) is built on [MeetingBar](https://github.com/leits/MeetingBar)
by Andrii Leitsius and the MeetingBar contributors. This file lists Punctual's own releases.
Versions 0.2.0 and 0.3.0 shipped under the name MeetingBarNG.

## 1.0.2 (2026-10-01)

* **Punctual stays running.** It had inherited a setting that let macOS quit it whenever it
  looked idle, which a menu-bar app almost always does. That could make Punctual vanish from
  the menu bar, and could send first-run setup back to the first screen after signing in to
  Google. macOS can no longer do that.
* **No extra pop-up during setup.** Signing in to Google during first-run setup no longer
  shows a "Google account connected" dialog on top of the browser's confirmation page. It
  still confirms when you connect Google later from Preferences.
* Setup now records each step in the system log, so a setup problem can be traced.

## 1.0.1 (2026-10-01)

* **Built-in Google Calendar sign-in.** Connect Google directly from Preferences ▸ Calendars
  with no setup. 1.0.0 needed your own Google OAuth client for this; that option is still
  there for anyone whose workplace requires it.
* **Until Google finishes reviewing the app,** its sign-in page shows "Google hasn't verified
  this app". Choose **Advanced ▸ Go to Punctual** to continue. Access is read-only either
  way, and the warning goes away once the review completes, with no app update needed.
* Screenshots in the README and on the website are now the real Punctual UI.

## 1.0.0 (2026-10-01)

### Now called Punctual

* **MeetingBarNG is now Punctual**, with a new app icon. The repository moves to
  [github.com/Chykalophia/Punctual](https://github.com/Chykalophia/Punctual); GitHub redirects
  the old address.
* **New bundle id: `com.chykalophia.Punctual`** (was `com.chykalophia.MeetingBarNG`, and
  `leits.MeetingBar` before that). The app is now `Punctual.app`.
* **New URL scheme: `punctual://`** (was `meetingbar://`, which collided with upstream
  MeetingBar when both were installed).
* **First signed and notarized release.** Download the dmg from
  [GitHub Releases](https://github.com/Chykalophia/Punctual/releases/latest), drag it to
  Applications, and it opens without a Gatekeeper warning. Earlier tags carried release notes
  only.

### Calendars and the menu bar

* **Bring your own Google credentials.** Preferences ▸ Calendars ▸ "Use my own Google
  credentials" points the app at your own OAuth client, so calls run on your project's
  quota under your consent screen. That is for anyone whose employer requires it, or who would
  rather not trust the shipped client. It also makes Google usable in a build that ships no
  credentials at all, which is why the Google row is now always listed rather than hidden
  when a build carries none. Switching clients discards the previous client's tokens
  instead of replaying a refresh token it cannot use.
* **The Google sign-in redirect moved to a loopback listener** (`127.0.0.1`, random port,
  torn down after the flow) from the reversed-domain URL scheme. Google documents loopback
  as the recommended redirect for macOS desktop apps and is retiring custom schemes, which
  any other app on the Mac could register and intercept. It is also what makes a
  user-supplied client possible at all: a URL scheme has to be declared at build time.
  Adds the `com.apple.security.network.server` entitlement, scoped to that listener.
  **OAuth clients must now be of type "Desktop app", not "iOS".**
* **Connect Apple and Google Calendar at the same time.** The two sources used to be
  either/or, so anyone with an iCloud or Exchange calendar in Calendar.app plus a Google
  work account could only ever see half their day. Preferences ▸ Calendars now shows a
  toggle per source instead of a picker, and meetings from every connected source are
  merged into one list. Calendar selection is kept per source, so turning one off and back
  on does not lose its choices, and the last connected source cannot be switched off.
  Requires a build carrying Google OAuth credentials (see README). One Google account at a
  time.
* **A meeting on both sources is shown once.** Cross-calendar deduplication now knows which
  source a meeting came from and keeps the Google copy, which carries real attendee
  response status and Google's own conferencing data where EventKit's mirror routinely has
  neither. Duplicate grouping is also transitive now: three copies linked in a chain (A and
  B by title/time, B and C by shared identifier) collapse to one row instead of leaving a
  third. The existing "Hide duplicate events" opt-out still shows every copy.
* **One broken source no longer hides the other's meetings.** An expired Google token used
  to fail the whole refresh; a failing source is now reported next to its own toggle, with
  a Reconnect button when it is an auth lapse, while the working source keeps syncing.
* Menu-bar **Join chip**: a one-click Join button on the status item for upcoming or active
  meetings that have a link. A left-click on the chip joins directly instead of opening the
  dropdown; everywhere else on the item still opens it.
* **Countdown lead time**: a new preference controls how many minutes before an event the
  countdown appears, so a meeting hours away no longer occupies the menu bar.
* **DEBUG-only harness** for injecting synthetic events and toggling menu-bar settings, to
  exercise display states without real calendar data. Excluded from release builds.

## 0.3.0 (2026-07-29, as MeetingBarNG)

### Timeline

* **Timeline style**: *Track* (hour grid, overlapping meetings stacked), *Bar* (one rail with
  meetings inline and hours beneath, about half the height), or *Minimal* (the rail alone).
* **Timeline covers**: *Around now* frames the bar on the meetings it is actually drawing, so it
  no longer opens on hours of empty morning; *Whole day* gives every meeting a fixed place.
* Turning the timeline off lives in the same picker, so there is one control rather than two that
  can disagree.

### Meeting card

* Choose what it shows: the "Next meeting" line, start and end times, the meeting service, the
  calendar and account, and the countdown bar, each independently.
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
* The live preview updates when any setting changes. Previously, adding Month Calendar appeared to
  do nothing until an unrelated toggle forced a refresh.

### Dropdown polish

* Rules only where they separate something, inset rather than full-bleed. Agenda rows on the
  design's grid, with long titles fading under the Join button instead of a hard ellipsis.
* A `+ ⌘N` chip beside today's heading, which creates a calendar event, matching the shortcut it
  names. The date moved to the greeting so the day is named once.
* Hover and selection are translucent glass rather than a saturated accent bar. Row density now
  moves card padding too, not just rows.

## 0.2.0 (2026-07-28, as MeetingBarNG)

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

* **Reduce Transparency is now respected**: the panel goes opaque when the system asks. It
  previously was not honoured anywhere in the app.
* **The panel holds contrast over pale wallpapers.** Behind-window vibrancy takes its lightness
  from the desktop while text and icons take theirs from the appearance; over a light background
  the two disagreed and the faintest elements washed out. There is now a contrast floor, and the
  edge treatments adapt to light and dark instead of assuming dark.

### Removed

* **The classic macOS menu dropdown**, and the "Use the classic macOS menu instead" switch in
  Preferences ▸ General ▸ Troubleshooting. It was a second, feature-frozen renderer of the same
  content that every new dropdown feature had to be designed around. The right-click quick-actions
  menu is unaffected; it is still a native menu, which is the right shape for a short list of
  verbs. Your stored preference is left in place and simply ignored; nothing needs migrating.

### Under the hood

* ~3,100 net lines removed. The meeting-card copy, the agenda's visibility rules, and the
  quick-actions menu were extracted out of the deleted menu builder first, so nothing shared was
  lost with it. End-to-end tests that drove an `NSMenu` were ported rather than dropped. They
  were always asking "given these settings, does the dropdown show this meeting?", so they now ask
  that directly.

---

## Before the fork

For MeetingBar's history before the fork (5.0.0 and earlier), see
[MeetingBar's releases](https://github.com/leits/MeetingBar/releases).
