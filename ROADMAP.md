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
      preview. Now the default path, not opt-in. Progress-bar and day-summary tokens
      shipped as tokens of their own (below).
- [x] Menu-bar calendar — browse, navigate, and pick dates (`UI/Calendar/CalendarGridView`).
- [ ] Month ⇄ week view toggle — the calendar window has one; the menu bar does not.
- [x] Day summary — event count and focus-time at a glance (`DaySummaryGreeting`,
      `DaySummaryHeaderView`).
- [x] Progress bars — day and year progress as a menu-bar token.
- [x] Countdown styles — `2h`, `2h 30m`, `2:30`.
- [x] Imminent-meeting emphasis — the menu bar boldens the next meeting once it is close
      enough to act on (`menuBarHighlightImminentEvent`, 2026-07-27).

### Meetings
- [x] One-click join (Zoom, Google Meet, Microsoft Teams, Webex, + 50 more) — already in MeetingBar.
- [x] Meeting prep — invite links surfaced automatically (`Meetings/MeetingPrepLinks`).
- [x] Camera / mic / lighting preview before joining (`UI/CameraPreview`, `Meetings/MicLevel`).
- [ ] Copy meeting ID.

### Calendar & event handling
- [x] Multi-calendar via macOS Calendar (iCloud/Google/Exchange/Office 365) — already in
      MeetingBar. NOTE: the *direct* Google provider is currently absent from onboarding —
      `CalendarSourcePresentation.all` ships macOS Calendar only, because the native Google
      path needs OAuth credentials this build does not carry. The code is retained for
      installs already on it; re-introduction is tracked as its own item below.
- [ ] Direct Google Calendar provider back in onboarding (needs shipped OAuth credentials).
- [x] Full event search (title, notes, location, attendees) — `Calendar/EventSearch`.
- [x] Inline event edit (title, time, duration) — `UI/EventEditor`, `EventDraftValidation`.
- [ ] Location autocomplete when creating/editing.
- [ ] Calendar picker via command/slash.
- [ ] Quick date jump.
- [x] Right-click event menu (join, copy, edit, delete) — full parity in both dropdowns.

### Reminders & focus
- [x] Apple Reminders integration alongside events (`Calendar/ReminderSelection`,
      `RemindersStore`; opt-in, requests its own TCC permission).
- [ ] Per-event custom reminder times.
- [ ] Snooze by time or location trigger.

### Customization & personalization
- [ ] Fully customizable interface (appearance + layout).
- [ ] System / custom themes.
- [ ] Date markers for important days.
- [ ] Hide empty days.

### Productivity tools
- [x] Command bar — create / search / settings from a single shortcut (`UI/CommandBar`).
- [ ] Keyboard-first navigation throughout — the dropdown panel has full arrow/Return
      travel (`DropdownPanelNavigation`); other surfaces are not there yet.
- [x] World clock — as a menu-bar token and its own panel (`UI/WorldClock`).

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
- [x] Bundle identifier `leits.MeetingBar` → `com.chykalophia.MeetingBarNG` (2026-07-23).
- [x] StoreKit product ids `leits.MeetingBar.patronage.*` — moot: the StoreKit patronage
      service was removed outright rather than renamed, so there are no product ids left
      to migrate (2026-07-23).
- [ ] Keychain and `UserDefaults`/`Defaults` suite names derived from the bundle id.
      Still open, and now the load-bearing one: the id changed, so anything that derived a
      suite or Keychain name from the OLD id needs a migration path for existing installs.
- [x] Xcode `PRODUCT_NAME` / scheme / `.app` name and `CFBundleName` → `MeetingBarNG`
      (2026-07-18, finished 2026-07-23).
- [ ] Mac App Store app id `1532419400` (belongs to the original app).
- [x] `Application Scripts/leits.MeetingBar` folder path referenced in localized strings —
      now `Application Scripts → com.chykalophia.MeetingBarNG` (2026-07-23).

### In-app strings & links
- [ ] Product-name strings across `MeetingBarNG/Resources /Localization /*.lproj` (20 languages;
      coordinate with Weblate rather than hand-editing translations). See the low-priority
      note below — fork-era keys are English-only by decision, so this is broader than a
      product-name sweep.
- [x] In-app support/funding URLs in `MeetingBarNG/Utilities/Constants.swift` — `telegram`,
      `twitter`, `patreon`, `buymeacoffee` and `rateAppInAppStore` were **deleted** rather
      than repointed; `github` and `emailMe` now point at Chykalophia (2026-07-23).
- [x] In-app "about"/attribution text — the old `preferences_general_meeting_bar_description`
      key is gone, replaced by `preferences_about_description`, which credits Chykalophia and
      Andrii Leitsius (2026-07-23).

### Housekeeping
- [ ] Per-file source headers still read `Copyright © <year> Andrii Leitsius`. These are
      **retained** by Apache-2.0 §4(c). As files are modified for MeetingBarNG, add a change
      notice (§4(b)) rather than removing the original.
- [x] `docs/ARCHITECTURE.md` referenced `CLAUDE.md` / `AGENTS.md` that are not present in the
      fork — reference dropped (2026-07-17).
- [ ] Upstream folder names with trailing spaces (`MeetingBarNG/Resources `,
      `.../Localization `) are an upstream quirk wired into the Xcode project and
      `Package.swift`; rename only as a deliberate, tested change.

### Deliberately deferred — low priority (2026-07-27)

Reviewed and consciously parked. Recorded so they are not rediscovered as if new.

- [ ] **Unit tests for the tomorrow look-ahead internals.** `today_n_tomorrow_next` and
      `today_n_tomorrow_summary` are covered end-to-end (`CalendarSettingsEndToEndFlowTests`
      asserts the rendered menu for both modes, including the singular/plural summary
      wording), but `DropdownPanelView.tomorrowRenderedEvents` and `isPreview` have no
      direct tests. Both are app-target symbols, so any coverage has to live in
      `MeetingBarNGTests` — `MeetingBarLogicTests` is a hostless SPM module whose
      `sources:` whitelist cannot see them. Low priority: the behaviour that matters is
      already pinned at the boundary.
- [ ] **Non-English localizations.** All 22 non-English `.lproj` files carry ~341 keys each,
      but only ~187 of those still match a live English key — **29.6% of the 632 English
      keys**, with ~154 orphans left over from strings English has since dropped and 445
      English keys untranslated. They contain **only** upstream-MeetingBar keys — every fork-era key
      (greeting, day summary, reminders, plurals, look-ahead modes, dropdown density) is
      English-only. This is not a bug: `I18N.localizedString(for:)` falls back to the
      English bundle on a miss, so those strings render in English rather than as raw keys.
      Deliberately all-or-nothing — topping up a handful would make them the only translated
      fork strings out of ~290, while changing nothing visible. "All" wants a real
      translation workflow, and the two-key `_one`/`_other` plural convention cannot express
      Slavic `_few`/`_many`, so `pl`/`cs`/`sk`/`hr`/`uk` would need more than a translation
      pass. Low priority until there is demand from non-English users.
