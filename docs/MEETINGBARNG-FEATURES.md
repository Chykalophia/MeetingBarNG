# MeetingBarNG — New Features & How to Test

A testing companion for the Dot-parity work on `feat/composable-menu-bar`. Every
feature below is built, unit-tested, and pushed. Several have **opt-in toggles or
unassigned keyboard shortcuts** — that's by design (nothing changes behavior on
upgrade until you turn it on), but it means you won't see them until you enable
them. This is the map.

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

## Status
The full Dot-parity plan (Waves 1–3) is shipped. Open threads are cosmetic/scope
questions only — raise anything you'd like changed after testing.

## Not in scope (by request)
No AI/LLM, no natural-language event creation, no voice-to-text — anywhere.
