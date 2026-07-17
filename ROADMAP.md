# MeetingBarNG Roadmap

MeetingBarNG is a fork of [MeetingBar](https://github.com/leits/MeetingBar) that is being
overhauled and modernized in code, UI, UX, and features. The launch goal is close
**productivity feature parity** with [Dot](https://www.trydot.app), paired with a modern,
deeply customizable look and feel — while staying local-first, private, and open source.

This document is the source of truth for what we are building and what we are deliberately
deferring. It is intentionally opinionated about scope.

---

## Guiding principles

- **Reliability first** (inherited from MeetingBar): show the correct meeting, stay fresh,
  stay visible, open the right link.
- **Customizability over configuration sprawl:** make the defaults excellent, then let
  users compose the experience (menu-bar tokens, themes) rather than bury them in toggles.
- **Local-first & private:** no account, no servers, calendar data stays on the Mac.
- **Modern, native feel:** SwiftUI-forward UI, keyboard-first navigation.

---

## Launch goal — Dot productivity parity

Target feature set for parity with Dot. Items are grouped by area. This list is the "close
to 1:1 on the productivity side" target; it is a goal, not a guarantee of scope for any
single release.

### Menu bar & display
- [x] Composable menu bar — mix-and-match tokens instead of one fixed format.
      v1 ships icon / event-title / countdown / date / clock, reorderable with a live
      preview; opt-in (classic settings still drive the bar until enabled). Progress-bar
      and day-summary tokens tracked separately below.
- [ ] Menu-bar calendar — browse, navigate, and pick dates from the menu bar.
- [ ] Month ⇄ week view toggle.
- [ ] Day summary — event count and focus-time at a glance.
- [ ] Progress bars — day and year progress as menu-bar tokens.
- [x] Countdown styles — `2h`, `2h 30m`, `2:30`.

### Meetings
- [x] One-click join (Zoom, Google Meet, Microsoft Teams, Webex, + 50 more) — already in MeetingBar.
- [ ] Meeting prep — surface invite links automatically in an at-a-glance view.
- [ ] Camera / mic / lighting preview before joining.
- [ ] Copy meeting ID.

### Calendar & event handling
- [x] Multi-calendar via macOS Calendar (iCloud/Google/Exchange/Office 365) + direct Google — already in MeetingBar.
- [ ] Full event search (title, notes, location, attendees).
- [ ] Inline event edit (title, time, duration).
- [ ] Location autocomplete when creating/editing.
- [ ] Calendar picker via command/slash.
- [ ] Quick date jump.
- [ ] Right-click event menu (join, copy, edit, delete).

### Reminders & focus
- [ ] Apple Reminders integration alongside events.
- [ ] Per-event custom reminder times.
- [ ] Snooze by time or location trigger.

### Customization & personalization
- [ ] Fully customizable interface (appearance + layout).
- [ ] System / custom themes.
- [ ] Date markers for important days.
- [ ] Hide empty days.

### Productivity tools
- [ ] Command bar — create / search / settings from a single shortcut.
- [ ] Keyboard-first navigation throughout.
- [ ] World clock.

### System & privacy (mostly already true)
- [x] No account required.
- [x] Local-first, privacy-first.
- [ ] Native SwiftUI performance pass (Apple Silicon + Intel).

### Explicitly out of scope
- **Natural-language event creation** — MeetingBarNG will NOT parse free text into events.
  This is a deliberate non-goal.

---

## Rebrand / overhaul backlog (deferred from the initial cleanup)

These were intentionally left untouched during the initial identity/attribution cleanup
because they are functional, break-prone, or ripple widely. They belong to the overhaul,
each with its own migration care.

### App identity (breaks OAuth / Keychain / StoreKit / defaults — needs a migration plan)
- [ ] Bundle identifier `leits.MeetingBar` → a Chykalophia-owned identifier.
- [ ] StoreKit product ids `leits.MeetingBar.patronage.*`.
- [ ] Keychain and `UserDefaults`/`Defaults` suite names derived from the bundle id.
- [ ] Xcode `PRODUCT_NAME` / scheme / `.app` name and `CFBundleName`.
- [ ] Mac App Store app id `1532419400` (belongs to the original app).
- [ ] `Application Scripts/leits.MeetingBar` folder path referenced in localized strings.

### In-app strings & links
- [ ] Product-name strings across `MeetingBar/Resources /Localization /*.lproj` (20 languages;
      coordinate with Weblate rather than hand-editing translations).
- [ ] In-app support/funding URLs in `MeetingBar/Utilities/Constants.swift` (`Links.github`,
      `telegram`, `twitter`, `emailMe`, `patreon`, `buymeacoffee`, `rateAppInAppStore`) —
      currently point to the original author. Update before any public release so funding
      and support are not misdirected.
- [ ] In-app "about"/attribution text (`preferences_general_meeting_bar_description`).

### Housekeeping
- [ ] Per-file source headers still read `Copyright © <year> Andrii Leitsius`. These are
      **retained** by Apache-2.0 §4(c). As files are modified for MeetingBarNG, add a change
      notice (§4(b)) rather than removing the original.
- [x] `docs/ARCHITECTURE.md` referenced `CLAUDE.md` / `AGENTS.md` that are not present in the
      fork — reference dropped (2026-07-17).
- [ ] Upstream folder names with trailing spaces (`MeetingBar/Resources `,
      `.../Localization `) are an upstream quirk wired into the Xcode project and
      `Package.swift`; rename only as a deliberate, tested change.
