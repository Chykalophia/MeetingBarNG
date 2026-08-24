# MeetingBarNG — New Features & How to Test

A testing companion for the Dot-parity work, all of which is now on `master`. Every
feature below is built, unit-tested, and shipped. Several have **opt-in toggles or
unassigned keyboard shortcuts** — that's by design (nothing changes behavior on
upgrade until you turn it on), but it means you won't see them until you enable
them. This is the map.

> **Waves 1–3 were written against the pre-0.2.0 app.** Two things have changed since:
> Preferences was rebuilt into an 8-pane IA, so a pane named below may now live
> elsewhere (use the settings search); and the classic `NSMenu` dropdown was deleted
> in 0.2.0, so there is only one dropdown to test. Wave 4 below covers everything
> shipped after that.

> Tip: keyboard shortcuts are all **unassigned by default**. Set them in
> **Preferences ▸ General ▸ Keyboard Shortcuts**.

---

## Wave 1 — menu-bar modernness

### 1. Composable menu-bar tokens: progress / week / world-clock
- **Where:** Preferences ▸ **Menu Bar** ▸ menu-bar title composer → **Add token**.
- **Test:** Add **Progress bar** (pick Day or Year), **Week number**, and **World clock**
  (choose a time zone + a short label like "SF"). Watch the menu-bar title update.
  Progress refreshes each minute; the bar is a Unicode block (e.g. `███▍░░░░`).

### 2. Day-summary greeting header
- **Where:** Preferences ▸ Display & Events ▸ Menu → **Show greeting header** (on by default);
  optional name override.
- **Test:** Open the dropdown — top card reads e.g. *"Good morning, Peter · 3 meetings today · 4h 30m free"*.
  Greeting changes by time of day; "free" is unbooked minutes until end of day.

---

## Wave 2 — search & command surface

### 3. Ranked event search + 4. Command Bar
- **Where:** Assign **"Open command bar"** shortcut first.
- **Test:** Trigger the shortcut → a Spotlight-style palette. Type part of a meeting
  title, attendee name, or location — results rank by relevance (diacritic/case
  insensitive). Empty query shows quick actions + upcoming events. Actions:
  Join next, Create meeting, Copy today's agenda, Refresh, Open Preferences.
  Arrow keys navigate, Enter runs, Esc/click-away closes.

---

## Wave 3

### 5. Apple Reminders in the menu  ⚠️ opt-in (new permission)
- **Where:** Preferences ▸ Display & Events ▸ Menu → **Show reminders due today**.
  Toggling it **on triggers the macOS Reminders permission prompt** (the only place it asks).
- **Test:** Grant access → reminders due today/overdue appear under the Today section.
  Use the row submenu to **Complete**, **Snooze** (Later today / This evening / Tomorrow),
  or **Open in Reminders**. Snooze/complete write back to Apple Reminders.

### 6. Right-click quick-actions menu
- **Test:** **Right-click** the menu-bar icon → compact menu: Join next · Create meeting ·
  Copy today's agenda · Refresh · Preferences · Quit. (Left-click still opens the full dropdown.)

### 7. Onboarding: preferred meeting service
- **Where:** First-run onboarding, **Essentials** step (or re-run onboarding).
- **Test:** The "Create meetings via" picker (Meet / Zoom / Teams / …) now appears during
  setup, so you pick Google Meet vs the Zoom default up front instead of discovering it in Preferences.

### 8. Menu Builder (visual dropdown composer)
- **Where:** Preferences ▸ **Dropdown** (new tab).
- **Test:** Toggle + reorder the dropdown's sections (Greeting, Timeline, Meeting, Agenda,
  Join, Bookmarks) with a live preview; the Preferences footer stays pinned. Reopen the
  dropdown to see your layout. *(Note: in the default layout a hairline separator now sits
  between the timeline bar and the meeting card — tell me if you'd rather they stay flush.)*

### 9. Month calendar grid
- **Where:** Assign the **"Open calendar"** shortcut, or right-click ▸ **Open calendar**.
- **Test:** A month grid with event dots (calendar-colored, +N overflow), today ringed.
  Click a day to list its events; a meeting-link event shows **Join**. ‹ › navigate months,
  **Today** returns. It loads its own month of events on demand (doesn't affect the menu list).

### 10. In-app event create / edit / delete  ⚠️ writes to your calendar
- **Where:** **New event…** in the right-click menu (or its shortcut); **Edit…** / **Delete…**
  in an event's submenu in the dropdown. *(Only for macOS-EventKit events — includes
  Google calendars synced through macOS.)*
- **Test:** Create an event (title, all-day, start/end, calendar picker with color swatches,
  location, notes, URL) — Save is disabled until valid. Edit an existing one. **Delete asks
  for confirmation.** No new permission needed (existing full calendar access covers writes).
  For a **repeating event**, editing/deleting shows a **This event / This and future events**
  choice. ⚠️ These change your real calendar — test on throwaway events first.

### 11. Camera/mic pre-call preview  ⚠️ opt-in (new permissions)
- **Where:** **Camera check…** in the right-click menu (or its shortcut); **Preview camera…**
  in an event's submenu (gives a contextual Join).
- **Test:** Live self-view + mic level meter; switch camera/mic devices; grant/deny each
  independently. **Camera capture can't be verified in a headless build — this one needs your
  hands-on test** (confirm the preview renders, meter moves, and the camera light turns off
  when you close the window).

### 12. Multi-zone world-clock panel
- **Where:** **World clock…** in the right-click menu (or its shortcut).
- **Test:** Add/remove time zones; each row shows the current local time and a
  **Tomorrow/Yesterday** tag when that zone's day differs from yours. Refreshes each minute.

---

## Fixes

### "No icon" clarification
- Preferences ▸ Display & Events ▸ Status bar ▸ Icon = **No icon** now shows a help line:
  it only hides the icon *next to an event title*; when there's no meeting, a calendar icon
  stays so the menu-bar item remains clickable. (Was a labeling confusion, not a bug.)

---

## Wave 4 — after 0.2.0

### 13. Menu-bar meeting progress (0.2.0)
- **Where:** Preferences ▸ Menu Bar ▸ meeting progress. **Off by default.**
- **Test:** Pick each of the four styles — **underline**, **ring** (around the icon),
  **capsule**, **leading mini-bar**. The bar fills over the hour before a meeting, is
  exactly full at the start, then counts through it. Nothing draws when no meeting is
  close. It renders in the menu bar's own text colour, so check it against a light
  wallpaper, a dark one, and a tinted menu bar.

### 14. Timeline styles and coverage (0.3.0)
- **Where:** Preferences ▸ Dropdown ▸ timeline.
- **Test:** Two separate settings. **Style** — *Track* (hour grid, overlaps stacked),
  *Bar* (one rail, meetings inline, hours beneath), *Minimal* (rail alone). **Covers** —
  *Around now* vs *Whole day*. Turning the timeline off is in the same picker.

### 15. Meeting-card field switches (0.3.0)
- **Where:** Preferences ▸ Dropdown ▸ meeting card.
- **Test:** Toggle each field independently — the "Next meeting" line, start/end times,
  meeting service, calendar and account, countdown bar. A card that is just a title and a
  bar is now a valid configuration. The countdown hides when the meeting is >1h out.

### 16. Month dots (0.3.0)
- **Where:** the month calendar in the dropdown.
- **Test:** Days with meetings show a dot across the whole month, not just today. Hover
  highlights a day cell. Navigate months quickly — previously-known days should stay put
  while the next month loads, and a failed fetch should leave existing dots alone.

### 17. Menu-bar Join chip ⚠️ on by default
- **Where:** Preferences ▸ Menu Bar ▸ Join button.
- **Test:** For an upcoming or active meeting **that has a link**, a Join chip appears on
  the status item. Clicking the chip joins directly; clicking anywhere else on the item
  still opens the dropdown. A meeting with no link shows no chip. Also check the lead-time
  setting that controls how early it appears.

### 18. Countdown lead time
- **Where:** Preferences ▸ Menu Bar ▸ countdown.
- **Test:** Set a lead time in minutes; the countdown should stay hidden until the meeting
  is within it. `0` means always on, which is the previous behaviour and the default — so
  upgraders see no change.

### 19. DEBUG harness (developer tool)
- **Where:** DEBUG builds only — excluded from release builds entirely.
- **Test:** Opens a window for injecting synthetic events and toggling menu-bar settings,
  so display states can be exercised without waiting on a real calendar. Use it to check
  the Join chip and progress styles against edge cases (no link, meeting running, nothing
  today).

---

## Status
Waves 1–4 are shipped and on `master`. The Dot-parity plan is **not** complete — see
`ROADMAP.md` for what remains open (copy meeting ID, month⇄week toggle in the menu bar,
hide empty days, date markers, per-event reminder times, location autocomplete, quick date
jump, themes, keyboard-first navigation beyond the dropdown panel).

**Testing these requires building from source.** Releases carry notes but no artifact yet;
a signed, notarized dmg is the next work item in `STATE.md`.

## Not in scope (by request)
No AI/LLM, no natural-language event creation, no voice-to-text — anywhere.
