# MeetingBarNG — Preferences UX Overhaul

**Status:** plan of record. Supersedes the Phase 1–3 Preferences work described in `ROADMAP.md`.
**Scope constraint (absolute, inherited):** no AI, no LLM features, no natural-language event creation, no voice-to-text. Nothing in this document proposes any. Every commit produced from this plan ends with `No AI/voice.`

---

## 0. Owner decisions — these OVERRIDE anything below

The plan was written with six open questions. The owner answered all six. Where a
later section disagrees with this one, **this section wins**; the affected rows
below have been amended in place.

| # | Question | Decision | Consequence |
|---|---|---|---|
| 1 | Name for the cross-surface filter tab | **"Filters"**, conditional on the tab being *only* about filtering — "one page = one purpose" | Tab 2 is renamed `Which Meetings` → **Filters** everywhere. The condition is met: every row on it removes or de-emphasises meetings. `ongoingEventVisibility` is reworded from "Count the meeting happening now as next" to the filter row **"Meetings already in progress — Still count as next / Treat as past"** so it reads as a filter like its neighbours. No style option ever lands here. |
| 2 | Keep or delete the classic NSMenu | **Keep as a fallback, lowest priority** | Unchanged from the plan: feature-frozen, no styling investment, reachable at General ▸ Troubleshooting. **Correction the owner should know:** the deployment floor is macOS 15 (`Package.swift`), and the SwiftUI panel needs nothing newer — so there is no "older OS" in the support range that requires it. It is a break-glass fallback, not an OS fallback. Phase 1 still ports its five missing visual states into the panel so nothing is lost if it is ever removed. |
| 3 | Six proposed deletions | **Approved, subject to the rule:** delete only where the capability is either dead or preserved elsewhere — no duplicates, no ambiguity about what lives where | Five of six approved (see §0.1). The sixth, "Dim weekends", is overturned by decision 4. |
| 4 | Where "Dim weekends" goes | **Stays in Preferences — it is a display option** | The demotion to the calendar window's header menu is **cancelled**. The calendar window is a real surface (`UI/Calendar/CalendarGridView.swift`) with its own header, so under this plan's own routing rule it earns a tab like Menu Bar and Dropdown. **An eighth tab, `Calendar Window`, is added** (see §2). It is deliberately thin in Phase 2 and is filled out in Phase 6. |
| 5 | Is Phase 6 optional | **No — do it, after 0–5** | Phase 6 is committed work, not a maybe. Order is unchanged: 0 → 1 → 2 → 3 → 4 → 5 → 6. |
| 6 | Expose duplicate blocks | **Yes, if genuinely useful** | Duplicate blocks ship in the builder rather than being modelled-but-hidden. Two world clocks (different cities) is the motivating real case and is supported. Where a duplicate is meaningless (a second Countdown of the same meeting), the block type declares itself single-instance rather than the builder banning duplicates globally. |

### 0.1 The deletions, re-checked against the owner's rule

The rule: *deleting is fine if the feature is dead, or if it is useful and genuinely
survives elsewhere — with no duplicates and no confusion about what is where.*

| Proposed deletion | Capability lost? | Verdict |
|---|---|---|
| Calendar-source picker (`eventStoreProvider`) | None — `CalendarSourcePresentation.all` has exactly one entry, so the control can never change anything | **DELETE.** Returns automatically if a second provider ships (it will, with Google). |
| `eventTimeFormat` as a control | None — `.show`/`.hide` become the presence of the **Countdown** block; `.showUnderTitle` becomes **One line / Two lines** on Menu Bar | **DELETE the control**, capability preserved in two clearer places. Migration seeds both. |
| `showEventDetails` | None — the panel's inline chevron is always available and costs nothing collapsed; *which* detail fields appear stays configurable on the Agenda gear | **DELETE.** |
| `shortenEventTitle`'s Events-tab twin | None — it is a literal duplicate of the Menu Bar control | **DELETE the twin.** This is exactly the de-duplication the owner asked for. |
| Language picker (`preferredLanguage`) | **Yes — but the capability is already broken.** 16 entries against one maintained catalog (en 659 lines vs de 391, ja 410); `ukrainian` maps to `"ua"` while the bundle is `uk.lproj`, so choosing it silently does nothing; seven shipped bundles have no entry at all | **DELETE the control**, keep the key, follow macOS. The one deletion that removes a real (if non-functional) capability — flagged rather than buried. Restore when catalogs are maintained. |
| Dim weekends (`dimWeekendsInCalendar`) | — | **OVERTURNED by decision 4.** Kept in Preferences, on the new Calendar Window tab. |

Also deleted, all dead or duplicated, consistent with the same rule: two static
onboarding lines styled as live status, the duplicate sync caption
(`preferences_status_sync_help` vs `preferences_calendar_macos_notice` — the literal
"why are there two of these?"), the unreferenced `AccessDeniedBanner`, the
unreachable Google `Reconnect` / `Change Google Account` actions (the provider was
removed; the direct-Google work will add real ones), the blanket "for advanced
users" warning, and the `menuBarTokens`-emptiness pseudo-toggle that destroyed the
user's arrangement with no undo.

---

## 1. The problem, in the owner's words, and the design north star

### 1.1 What the owner said

> "It is a cluster fuck and mess and really hard to understand" — wording, layout, **and** organization.

> "I have a REALLY REALLY hard time understanding most of what is in our WHOLE preferences panels and how it is setup and organized."

> "There is also lots of confusion between the display panel and the events panel … it is a bit weird."

> "Why do we have two preview areas for the display area in preferences?"

> "For the agenda maybe a user would like to have left bordered lines rather than dots, or the dots/lines/accent being all the way to left rather than inbetween time and title … etc."

> "The dropdown menu could/should potentially be drag-and-drop editable (in preferences) and with gear icons on each component (block) to configure that live one."

> "A proper UX overhaul to simplify for most users, while giving power users as much fun as they would like."

### 1.2 What is actually wrong (measured, not asserted)

| Fact | Evidence |
|---|---|
| 92 `Defaults` keys | `MeetingBarNG/Extensions/DefaultsKeys.swift` — 92 `Key<…>` declarations |
| No reset anywhere | `Defaults.reset` returns **zero** hits repo-wide. Every one of the 92 keys is a one-way door. |
| No search anywhere | `.searchable` returns **zero** hits repo-wide. |
| Seven settings are inert for nearly every user | `useSwiftUIDropdown` defaults `true` (`DefaultsKeys.swift:130`), and `DropdownPanelView` never reads `showEventCalendarColor`, `showMeetingServiceIcon`, `showEventEndTime`, `shortenEventTitle`, `menuEventTitleLength`, `pastEventsAppereance`, `showEventDetails`. All seven are honoured by `MenuBuilder.swift`, the *non-default* renderer. |
| The Display/Events boundary is cosmetic | Every control on **both** tabs still draws from the `preferences_appearance_*` prefix, because both came from one former Appearance tab. `preferences_tab_menu_bar` is still literally defined as `"Display & Events"`. |
| The code disagrees with the UI in both directions | `showEventEndTime` is typed under `StatusBarSettings` (`MeetingBarNG/Settings/AppSettings.swift:42`) but rendered on Events under a header saying "in the dropdown". `showEventMaxTimeUntilEvent*` and `ongoingEventVisibility` are typed under `EventDisplaySettings` (`AppSettings.swift:32-33`) but rendered on Display. |
| A "reorder" affordance that does nothing | `MeetingsTab.swift:146` calls `.onMove` inside `PreferencesGroupedForm`, which is `Form { }.formStyle(.grouped)` (`Preferences.swift:172-186`). `onMove` requires a real `List`. Bookmark reordering is a dead no-op today. |
| ~50 lines of unreachable code in the two files anyone reads first | Deployment floor is macOS 15 (`Package.swift:8`), yet `Preferences.swift:23-31` branches on `#available(macOS 13.0, *)`, `:35-72` maintains a full macOS 12 `legacyLayout`, `:172-186` keeps a macOS 12 `ScrollView` fallback. |
| One tab taxes all seven | `minWidth: 1100` at `Preferences.swift:71` and `:97`, with the comment stating it exists "for the Display tab's two-pane (settings + ~340pt preview)". |
| The preview is a second renderer | `DisplayPreviewPane.swift:359 agendaRow` hand-copies the agenda row at a **76pt** time column; the real one (`DropdownPanelView.swift:567`) is **66pt**. Padding, formatter allocation and icon lookups are all duplicated. |
| The preview lies about what it teaches | `DisplayPreviewPane` hardcodes `showEventMaxTimeUntilEventEnabled: false` and `hasSelectedCalendars: true`, so the two hardest menu-bar controls produce **zero** visible change in the one surface meant to explain them. |

**The inline previews are already gone.** `DisplayTab.swift:344-346` and `:558-561` now carry comments recording their deletion. What remains — and what the owner's question actually points at today — is that the single surviving pane renders **two labelled sub-previews** in one column (`DisplayPreviewPane.swift:67` "Menu bar", `:72` "Dropdown"), and that pane is itself a duplicate implementation of the thing it previews. Deleting a duplicate view did not fix that; only rendering the real view does.

### 1.3 North star

> **Simple and calm by default, deep on demand.**
> The default view must not overwhelm. Power must be reachable, not omnipresent.

Operationalised into four rules that are testable in review:

1. **One thought lives in exactly one place.** If a user can phrase a single wish ("hide meetings I declined"), there is exactly one control for it, on exactly one tab. No setting is ever split into a filter half and a style half across two panes.
2. **Depth is hidden by scope, never by rarity.** A setting that is only meaningful *if you have component X* lives on X's gear. A setting that is app-wide stays visible. Nothing is hidden merely for being uncommon.
3. **Every one-way door becomes a two-way door.** Reset at every level: per block, per section, whole app. Exploration must be free.
4. **Nothing hidden is unfindable.** Settings search ships *before* anything is put behind a gear, and a search hit can force-open a disclosure and a gear popover.

---

## 2. The final tab structure

Seven tabs in a **flat** sidebar — no group headers. Today's `Setup → General → General Settings` is three stacked labels that all mean "miscellaneous" (`PreferencesPresentation.swift:107-130`); grouping seven concrete names under abstract nouns rebuilds exactly that. `PreferencesSidebarSection` is deleted.

**About & Support** is a pinned sidebar *footer* item, not a settings tab, so it can never become a leftovers bin.

The routing rule, stated in one sentence and applied with **zero exceptions**:

> **Which meetings exist → "Filters". How one surface draws them → that surface's tab. What happens when you act → "Joining" or "Alerts". The app itself → "General".**

| # | Tab | One-line purpose | What it holds |
|---|---|---|---|
| 1 | **Calendars** | Where your meetings come from, and whether macOS is actually syncing them. | Sync status headline + last-success time · Grant Calendar Access (only pre-prompt) · **Refresh now** (rewired to the real `.forceCalendarSync`) · always-visible "Calendars to show" header · per-calendar checkboxes grouped by account, with account email under duplicate names, search field, All/None, live "6 of 14 selected" count · action-bearing empty state · **Allow access to Reminders** (moved here — all permissions in one place) · `Calendar isn't updating?` disclosure holding ONE merged sync explanation, "Newest change the app can see", raw EventKit error, Open Privacy Settings, Open Internet Accounts (error states only) · Reset this section |
| 2 | **Filters** | The one place that decides which meetings exist — in the menu bar, the dropdown and the calendar window alike. | Permanent scope banner: "These choices apply everywhere." · Look ahead (Today / Today and tomorrow) with help stating it is the fetch window · Merge duplicates across calendars · Preset chips **Everything / Meetings only / Only what I accepted / Custom** · under Custom: seven 3-way rows (Show / Dim / Hide) for all-day, no-link, solo blocks, unanswered, maybe, declined, ended · "Meetings already in progress — Still count as next / Treat as past" · "Hide meetings whose title matches a pattern" (+ live tester) · Reset this section |
| 3 | **Menu Bar** | What you see in the macOS menu bar all day. | Live **wide strip** preview pinned at the top + time scrubber (2h before / 25m before / in a meeting / nothing today) · Preset cards (Classic / Minimal / Agenda / Info / Custom) · **Block builder** (Icon · Title · Countdown · Clock · Date · Progress bar · Week number · World clock) with drag, switch, gear · Keep the menu bar quiet until a meeting is close + minutes chips · Space between blocks · One line / Two lines · Reset this section |
| 4 | **Dropdown** | What you see when you click MeetingBarNG. | Live **real-panel** preview on the right + the same time scrubber · Preset cards (Simple / Standard / Everything / Custom) · **Block builder** (Greeting · Timeline · Meeting card · Agenda · Reminders · Join & actions · Bookmarks, plus a pinned locked "Settings & Quit" row) with drag, switch, gear, and a Hidden tray · Row spacing (Comfortable / Compact) · Reset this section |
| 5 | **Calendar Window** | The month/week window MeetingBarNG opens — not Apple's Calendar app. | Dim weekends · Open in — Month / Week *(the stored default; the window's own header still switches the view you're looking at right now)* · Reset this section · **Phase 6 fills this out**: first day of the week, show week numbers, how many events a day cell lists before "+2 more" |
| 6 | **Joining** | What happens when you click Join, and where new meetings get created. | Open meeting links in · `Send some services somewhere else` disclosure (picker split into **Apps** and **Browsers** groups, explanation above the control) · Set up browsers and apps… · New meetings use + custom web address · Open new meetings in · My saved links (bookmarks, three columns, real drag handle) · `Find meeting links in unusual formats` disclosure (text patterns + a tester that works before you save and scans notes + location + URL) · Reset this section |
| 7 | **Alerts** | When MeetingBarNG interrupts you. | Preset chips (Off / Gentle / Standard / Insistent / Custom) · Notify me before a meeting starts + **labelled** "How early" · Take over the screen + How early + include link-less blocks · Notify me before a meeting ends + How early · Open the meeting for me + How early + jump button to Joining · macOS permission rows with real **buttons** · Snooze duration · `Run a script around meetings` disclosure (both AppleScript hooks, distinct button labels, unsaved-script warning) · Reset this section |
| 8 | **General** | The app itself: how it starts, how it reads time, and the way back to calm. | Whole-app preset chips (Calm / Standard / Everything / Custom) · Open MeetingBarNG when I log in · Time format (12/24-hour) with "Used everywhere in the app" · **Keyboard shortcuts** in four labelled groups, every row with a one-line description · `Troubleshooting` disclosure (Use the classic macOS menu instead; Reset all settings…) |
| — | **About & Support** *(sidebar footer, not a tab)* | Who made this, what changed, how to get unstuck. | App icon, name, version, credit line · GitHub · Contact · What's New · Copy diagnostics (with visible "Copied" confirmation) |

**Deleted as tabs:** `Display` (every setting in a calendar app is display — the word carries zero disambiguating information, which is precisely why it cannot be told from Events), `Events` (events are content, not a place), `Advanced` (a category defined by developer anxiety; it accretes forever, and "Advanced" must never be the answer to "where does this go?").

**Settings search** (`.searchable` over a hostless index) is present on every tab from Phase 2 onward.

**Why eight and not seven.** The owner's decision 4 keeps "Dim weekends" in Preferences on the grounds that it is a display option. The calendar window (`UI/Calendar/CalendarGridView.swift`) is a genuine surface with its own header, so under this plan's own routing rule — *how one surface draws them → that surface's tab* — it earns a tab exactly as Menu Bar and Dropdown do. Folding its one setting into General instead would have made General the leftovers bin this plan explicitly forbids, and would have been the routing rule's first exception. It is a thin tab in Phase 2 (two rows); Phase 6 promotes the window's remaining hardcoded choices into it. If it still reads as thin after Phase 6, merging it into Dropdown is the fallback — **not** merging it into General.

---

## 3. Complete settings migration table

Every row in the inventory appears below. `→` reads "moves to". **Verdict** is one of KEPT · RENAMED · MOVED · MERGED · DISCLOSED (behind a named disclosure) · GEAR (behind a block gear) · DELETED · PROMOTED (was hardcoded, now a setting).

### 3.1 From General

| Current label | Key | New home | New label | Verdict |
|---|---|---|---|---|
| About card (icon/version/credits) | — | About & Support footer | *(unchanged)* | MOVED — opening Preferences must not show credits before a setting; it also needs 3 modifiers to fight the grouped form it sits in (`GeneralTab.swift:26-30`) |
| GitHub | — | About & Support | GitHub | MOVED |
| Contact | — | About & Support | Contact | MOVED |
| What's New | — | About & Support | What's New | MOVED |
| Copy diagnostics | — | About & Support | Copy a report for support | MOVED + gains visible confirmation (`DiagnosticsClipboard.copy()` writes in a detached Task with no acknowledgement today) |
| Open MeetingBarNG automatically when you log in | LaunchAtLogin / SMAppService | General | Open MeetingBarNG when I log in | MOVED — and `LaunchAtLoginANDPreferredLanguagePicker` (`UI/Views/Shared.swift:173`, name literally contains "AND") is dissolved |
| Language: | `preferredLanguage` | — | — | **DELETED.** 16 entries against one maintained catalog (en 659 lines vs de 391, ja 410); `ukrainian` is `"ua"` while the bundle is `uk.lproj` so it silently no-ops; seven shipped bundles (bg, hu, ko, ta, pt, zh-Hans, enm) have no entry. The app follows macOS. Key retained; restore the picker when catalogs are maintained. |
| Time format: | `timeFormat` | General | Time format — 12-hour (3:30 PM) / 24-hour (15:30) | KEPT, MOVED. Genuinely app-wide (menu bar, dropdown, timeline, calendar window, world clock, alerts). Its key is namespaced `preferences_appearance_menu_time_format_*` — renamed. The Clock block gear links here rather than duplicating it. |
| Open menu: | `openMenuShortcut` | General ▸ Shortcuts ▸ *Open something* | Open the dropdown | RENAMED (+ description) |
| Open calendar: | `calendarShortcut` | General ▸ Shortcuts ▸ *Open something* | Open the calendar window — *"MeetingBarNG's own month view, not Apple's Calendar app"* | RENAMED |
| Open command bar: | `commandBarShortcut` | General ▸ Shortcuts ▸ *Open something* | Open the search bar — *"A Spotlight-style box for finding meetings and running actions"* | RENAMED. Nothing in Preferences defines "command bar" today. |
| Open world clock: | `worldClockShortcut` | General ▸ Shortcuts ▸ *Open something* | Open the world clock | RENAMED |
| Join next meeting: | `joinEventShortcut` | General ▸ Shortcuts ▸ *Get into a meeting* | Join my next meeting | RENAMED |
| Join meeting from clipboard: | `openClipboardShortcut` | General ▸ Shortcuts ▸ *Get into a meeting* | Join the link on my clipboard | RENAMED |
| Camera & mic check: | `cameraPreviewShortcut` | General ▸ Shortcuts ▸ *Get into a meeting* | Check my camera and mic | RENAMED |
| Create meeting: | `createMeetingShortcut` | General ▸ Shortcuts ▸ *Make something* | Start a new call — *"On the service you picked in Joining"* | RENAMED |
| New event: | `newEventShortcut` | General ▸ Shortcuts ▸ *Make something* | Add an event to my calendar | RENAMED |
| Toggle title visibility in status bar: | `toggleMeetingTitleVisibilityShortcut` | General ▸ Shortcuts ▸ *Privacy* | Hide the meeting title in the menu bar — *"For blanking it before you screen-share"* | RENAMED |

All ten shortcut rows lose their trailing colons (they route through raw `.loco()` today, not `preferenceLabel()`, so they are the only rows in Preferences that keep them).

### 3.2 From Calendars

| Current label | Key | New home | New label | Verdict |
|---|---|---|---|---|
| Select calendar source | `eventStoreProvider` | — | — | **DELETED.** `CalendarSourcePresentation.all` holds exactly one entry, so the most prominent row of the tab is a dropdown that can never change anything. Key retained; returns automatically if a second provider ships. |
| Status headline + time | ProviderHealth (read-only) | Calendars | *"Up to date · refreshed 2 minutes ago"* — one sentence, one timestamp | MERGED (headline + lastSuccess were two rows) |
| Most recent calendar change | ProviderHealth (read-only) | Calendars ▸ *Calendar isn't updating?* | Newest change the app can see — *"If this is hours old, macOS has probably stopped syncing"* | RENAMED, DISCLOSED |
| Uses the macOS Calendar app as the data source | static | — | — | **DELETED** — onboarding boilerplate styled like a live status line |
| All configured accounts: iCloud, Google, Exchange… | static | — | — | **DELETED** — same |
| macOS Calendar reliability notice | static | Calendars ▸ *Calendar isn't updating?* | *(one merged paragraph)* | MERGED + DISCLOSED. The roadmap promise *"A direct Google Calendar connection is coming…"* is **deleted** — settings copy is not a changelog. |
| Sync help caption | static | — | — | **DELETED (duplicate).** `preferences_status_sync_help` says the same thing as `preferences_calendar_macos_notice`, in the same section, ~60 lines apart. This is the literal answer to "why do we have two of these?" |
| Raw error text | ProviderHealth | Calendars ▸ *Calendar isn't updating?* | *(plain first line, raw text below)* | DISCLOSED |
| Grant Calendar Access | action | Calendars | Grant calendar access | KEPT |
| Reconnect | action | — | — | **DELETED** — unreachable; the Google provider was removed |
| Change Google Account | action | — | — | **DELETED** — same |
| Re-authenticate Account… | action | Calendars ▸ *Calendar isn't updating?* | Open Internet Accounts | RENAMED + **conditional**. `canReauthenticateAccount` is `activeProvider == .macOSEventKit` (`PreferencesPresentation.swift:305`) — always true, so a scary recovery action sits on screen forever, including when the status is "Up to date". Now shown only on an error state, and the disclosure **auto-expands** when `ProviderHealth` reports an error. |
| Open Calendar Settings | action | Calendars ▸ *Calendar isn't updating?* | Open Calendar privacy settings | RENAMED — it opens Privacy & Security ▸ Calendars, not the Calendar app's settings |
| Force Sync | action | Calendars | **Refresh now** | RENAMED **and rewired**. Today it sends `.refreshCalendars` (plain re-fetch); the action that actually nudges macOS is `.forceCalendarSync` (`AppModel.swift:102-107`) and only ever fires automatically. The most-clicked recovery button now does what its name says. |
| "Select calendars to show meetings…" header | — | Calendars | **Calendars to show** — always rendered | KEPT + fixed. Today it renders **only** when the list is empty, i.e. it vanishes the moment it becomes useful. |
| Per-calendar checkboxes | `selectedCalendarIDsByProvider` | Calendars | *(unchanged)* + account email under duplicate names, search field, All/None, "6 of 14 selected" | KEPT + augmented. `selectedCalendarCount` / `availableCalendarCount` are already computed at `PreferencesPresentation.swift:291-292` and never displayed. Raw source `"unknown"` renders as **Other**. |
| Empty-state text | read-only | Calendars | *(unchanged wording)* + an action button | KEPT + fixed |
| `AccessDeniedBanner` | — | — | — | **DELETED (dead code).** Declared at `CalendarsTab.swift:282-293`, referenced nowhere; a third unused variant of messaging that already exists twice in the same file. |
| *(new)* | Reminders permission | Calendars | Allow MeetingBarNG to read Apple Reminders | MOVED from a Display-tab toggle. All permission UI now lives in one place, with "macOS will ask you" stated **before** the flip and a real denied state instead of the switch silently springing back. |

### 3.3 From Display — menu bar

| Current label | Key | New home | New label | Verdict |
|---|---|---|---|---|
| Menu bar icon | `eventTitleIconFormat` | Menu Bar ▸ **Icon** block gear | Which icon — Calendar / MeetingBarNG / The meeting's app | GEAR. The `None` value is **deleted**: the block's switch is the off state. A block can no longer be present and render nothing. |
| Menu bar text | `eventTitleFormat` | Menu Bar ▸ **Title** block gear | Show — The meeting's title / The word "Meeting" / A dot | GEAR. The `Nothing` value is **deleted** for the same reason. |
| shorten to %d characters | `statusbarEventTitleLength` | Menu Bar ▸ **Title** block gear | Shorten long titles to N characters (20 / 30 / 50 / Custom) | GEAR + **default changed 55 → 30**. 55 is the range max and not a preset, so `PresetNumberPicker` seeds `isCustom = true` (`PresetNumberPicker.swift:68`) and every new user meets an expanded "Custom" stepper for a setting that effectively never fires. |
| Time next to the title | `eventTimeFormat` | — | — | **DELETED as a control.** Read only by the classic status-bar path (`StatusBarPresentation.swift:196, 220-235`); the composed path hardcodes `time: ""` / `.inline(showTime: false)` (`:764, :768`), so it is already dead once the builder is on while staying fully enabled directly above it, under a caption that is wrong. `.show` / `.hide` are now expressed by the presence of the **Countdown** block. `.showUnderTitle` is **preserved as a capability**: a Menu Bar tab control "One line / Two lines", implemented in the composed renderer. Migration appends a Countdown block for anyone on `.show`, and sets two-line for anyone on `.showUnderTitle`. |
| Only show the next meeting … within: | `showEventMaxTimeUntilEventEnabled` | Menu Bar | Keep the menu bar quiet until a meeting is close | RENAMED, KEPT. Stays on Menu Bar because it changes nothing but this strip. |
| %d minutes | `showEventMaxTimeUntilEventThreshold` | Menu Bar | within 15m / 30m / 1h / 2h / 4h / Custom | MERGED into the row above. Its help line is the best copy in the app and is kept verbatim as the template for all help text. |
| Hide the current meeting from the menu bar: | `ongoingEventVisibility` | **Filters** | Count the meeting happening now as "next" — Until it ends / For 5 minutes / Never | MOVED + RENAMED. It is consumed by event selection (`Calendar/EventSelection.swift:131-143`), so it changes the dropdown's meeting card too — an Events rule wearing a Display label. |
| Customize menu bar layout | `menuBarTokens` emptiness | — | — | **DELETED.** Not a stored boolean: turning it off runs `menuBarTokens = []` (`DisplayTab.swift:487`), silently destroying the arrangement with no undo, and turning it back on reseeds from legacy rather than from what you had. The builder is always on; blocks have an `isOn` flag. |
| Layout (Classic/Minimal/Agenda/Info/Custom) | derived | Menu Bar | *(preset cards)* | KEPT, restyled as cards. `Custom` stops being a mode you *enter* — it is the label shown when no preset matches, so it can never be lost on window close (`forceCustom` is `@State`, `DisplayTab.swift:210`). |
| Token list rows + "Add token" | `menuBarTokens` | Menu Bar | *(block builder)* — "block", never "token" | RESHAPED (§4) |
| Countdown style | `menuBarCountdownStyle` | Menu Bar ▸ **Countdown** gear | Write it as — 2h / 2h 30m / 2:30 | GEAR |
| Date style | `menuBarDateStyle` | Menu Bar ▸ **Date** gear | Write it as — Mon / Mon, Jul 17 / 7/17/26 | GEAR |
| Progress style | `menuBarProgressStyle` | Menu Bar ▸ **Progress bar** gear | Tracks — Today / This year | GEAR |
| Time zone | `menuBarWorldClockTimeZone` | Menu Bar ▸ **World clock** gear | Time zone — **searchable** | GEAR + fixed. Today it is ~600 raw IANA identifiers (`America/Argentina/Catamarca`) in a flat popup. |
| Label | `menuBarWorldClockLabel` | Menu Bar ▸ **World clock** gear | Short label (e.g. SF) | GEAR |
| Preview (inline chip) | — | — | — | **ALREADY DELETED** (`DisplayTab.swift:344-346`) |

### 3.4 From Display — dropdown

| Current label | Key | New home | New label | Verdict |
|---|---|---|---|---|
| Dropdown layout: module rows + "Add section" | `dropdownModuleOrder` + 6 booleans | Dropdown | *(block builder)* — "block", never "section"/"module" | RESHAPED (§4) |
| Preview (inline card) | — | — | — | **ALREADY DELETED** (`DisplayTab.swift:558-561`) |
| Hide finished meetings from the dropdown | `hideFinishedEventsInMenu` | **Filters** | *(merged into "Meetings that have ended — Show / Dim / Hide")* | MERGED with `pastEventsAppereance`. They overlap, can contradict, lived on two tabs, nothing stated precedence, and in the shipping panel only this one works. |
| Greeting name | `greetingName` | Dropdown ▸ **Greeting** gear | Your name | GEAR. Today it lives in a different section, greyed out, with the only explanation in 11pt grey saying "Add the greeting under Dropdown layout above". |
| Show today's reminders in the dropdown | `showRemindersInMenu` | Dropdown ▸ **Reminders** block switch | Reminders | PROMOTED to a real block. Permission request moves to Calendars; the block switch announces it. |
| Include overdue reminders | `remindersIncludeOverdue` | Dropdown ▸ **Reminders** gear | Include overdue | GEAR |
| Use the new SwiftUI dropdown (preview) | `useSwiftUIDropdown` | General ▸ *Troubleshooting* | **Use the classic macOS menu instead** | MOVED + INVERTED + DISCLOSED. Defaults `true`; its own `DefaultsKeys.swift:125-129` comment says the panel is the default while `DisplayTab.swift:807-808` claims it is off by default and the label calls the shipping default a "(preview)". It is a renderer escape hatch, not a display preference. Help text states plainly that block styling does not apply to the classic menu. |
| Dim weekends in the calendar | `dimWeekendsInCalendar` | **Calendar Window** | Dim weekends | **KEPT in Preferences** (owner decision 4 — it is a display option). The plan originally demoted it into the calendar window's header overflow menu; that is cancelled. It anchors the new Calendar Window tab instead. |
| *(the window's current view)* | `calendarGridMode` | **Calendar Window** | Open in — Month / Week | **PROMOTED to a visible preference.** The key already exists and is written by the window's header fold (`CalendarGridView.swift`), but nothing in Preferences ever mentions the window. Preferences sets the **default** the window opens in; the header still switches the view you are looking at now. Distinct meanings, so this is not the duplication the owner ruled out — same relationship as Finder's default view versus the per-window control. |
| Preview (sticky right pane) | — | Dropdown | *(one preview, the real panel)* | RESHAPED (§4.6) |

### 3.5 From Events

| Current label | Key | New home | New label | Verdict |
|---|---|---|---|---|
| Show meetings for | `showEventsForPeriod` | Filters | Look ahead — Today / Today and tomorrow — *"'Today' means tomorrow's meetings are never loaded at all."* | MOVED + RENAMED. It sets the fetch window (`CalendarRepository.swift:142`), which help text now states. |
| Merge the same meeting when it's on more than one calendar | `deduplicateEvents` | Filters | Merge duplicates across calendars | KEPT + **bug fixed**: absent from `CalendarSync.swift:261-269` observers and `StatusBarItemController.swift:136-153` redraw list, so flipping it changes nothing until the next scheduled refresh and reads as broken. |
| All-day events | `allDayEvents` | Filters ▸ Custom | All-day entries (birthdays, OOO) — Show / Only with a meeting link / Hide | RENAMED |
| Events without a meeting link | `nonAllDayEvents` | Filters ▸ Custom | Calendar blocks with no meeting link — Show / Dim / Hide | RENAMED |
| Meetings with no other guests | `personalEventsAppereance` | Filters ▸ Custom | Blocks you booked for yourself (focus time, lunch) — Show / Dim / Hide | RENAMED + **retyped**. Currently typed `PastEventsAppereance` and sharing picker tags with "Past events" two rows below, so changing one silently changes the other. |
| Pending (not yet accepted) events | `showPendingEvents` | Filters ▸ Custom | Invites you haven't answered — Show / Dim / Hide | RENAMED |
| Tentative (maybe) events | `showTentativeEvents` | Filters ▸ Custom | Invites you answered Maybe — Show / Dim / Hide | RENAMED |
| Declined events | `declinedEventsAppereance` | Filters ▸ Custom | Meetings you declined — Show / Dim / Hide | RENAMED + gains the plain **Show** option it is the only picker in the group to lack |
| Past events | `pastEventsAppereance` | Filters ▸ Custom | Meetings that have ended — Show / Dim / Hide | RENAMED + MERGED with `hideFinishedEventsInMenu` |
| *(the option vocabulary)* | — | — | — | **"show as underlined" and "show with strikethrough" are DELETED.** Every filter becomes the same three words — **Show / Dim / Hide** — used identically in all seven rows. "Dim" is honest because Phase 1 implements dimming in the shipping panel. This collapses three vocabularies into one and removes the asymmetry where Declined had no "Show". |
| *(hidden coupling)* | — | Filters | *"The menu bar picks its next meeting from this same list."* | **DISCLOSED.** Today, choosing "show as inactive" for pending/tentative *also* silently removes them from menu-bar selection (`EventSelection+MeetingBar.swift:87-96`) — a second, undocumented effect of an option whose wording only describes styling. Behaviour preserved, now stated. |
| Show each meeting's end time | `showEventEndTime` | Dropdown ▸ **Agenda** gear | Time column — Start only / Start and end / Hidden | GEAR + **made to work** (Phase 1) |
| Show the meeting app's icon | `showMeetingServiceIcon` | Dropdown ▸ **Agenda** gear (+ **Meeting card** gear) | Show the Zoom / Teams / Meet logo | GEAR + **made to work** |
| Show the calendar's color dot | `showEventCalendarColor` | Dropdown ▸ **Agenda** gear | *(becomes the `None` case of "Calendar colour marker")* | MERGED into the marker picker + **made to work**. The panel draws the dot unconditionally at `DropdownPanelView.swift:568-570`, so this switch does nothing today. |
| Show event details in a submenu | `showEventDetails` | — | — | **DELETED.** Names an NSMenu implementation detail; `DropdownPanelView.swift:612-618` deliberately ignores it with a reasoned comment while the switch still ships. The panel's inline chevron is always available and costs nothing collapsed. Which detail **fields** appear stays configurable on the Agenda gear. |
| Show prep links from the invite | `showMeetingPrepLinks` | Dropdown ▸ **Agenda** gear ▸ details field list | Prep links (Figma, Docs, GitHub…) | GEAR + **improved**: rendered inline in the expandable detail area, not only in a right-click submenu |
| Shorten long meeting titles in the dropdown | `shortenEventTitle` | Dropdown ▸ **Agenda** gear | *(merged into "Long titles")* | MERGED + **made to work** |
| Title-length chips | `menuEventTitleLength` | Dropdown ▸ **Agenda** gear | Long titles — Cut to one line / Wrap to two lines / Shorten to N characters | MERGED. Removes the near-identical twin of `statusbarEventTitleLength` that sat on another tab with a different chip set (20/30/50/80 vs 20/30/50) for no stated reason. |

### 3.6 From Meetings

| Current label | Key | New home | New label | Verdict |
|---|---|---|---|---|
| Default browser for meeting links | `defaultBrowser` | Joining | Open meeting links in | RENAMED |
| Per-service overrides | `providerBrowsers` + `providerOpeningModes` | Joining ▸ *Send some services somewhere else* | *(picker split into labelled **Apps** and **Browsers** groups; explanation moved above the control)* | DISCLOSED + fixed. Today opening modes ("Zoom App", "Google Meet PWA") and browsers are flat siblings, with nothing saying that picking a mode bypasses the browser choice, and the explanation appears only *after* you select. |
| Configure Browsers… | `browsers` | Joining | Set up browsers and apps… | RENAMED |
| New meetings use | `createMeetingService` | Joining | New meetings use | KEPT |
| Custom URL | `createMeetingServiceUrl` | Joining | Web address for new meetings | RENAMED |
| Use web browser | `browserForCreateMeeting` | Joining | **Open new meetings in** | RENAMED. Its label never mentioned creating, so it read as a second, contradictory copy of the setting 60 lines above. |
| Bookmarks | `bookmarks` | Joining | **My saved links** | RENAMED + fixed. Rows become name / service / address in columns instead of one truncated `name (service): url` string; reordering gets a **real drag handle** in a real `List` (the current `.onMove` at `MeetingsTab.swift:146` is a dead no-op inside a Form); help text says where they appear and links to the Bookmarks block. The section header stops reusing `preferences_tab_bookmarks`, so "Bookmarks" now names only the dropdown block. |

### 3.7 From Notifications

| Current label | Key | New home | New label | Verdict |
|---|---|---|---|---|
| Send a system notification | `joinEventNotification` | Alerts | Notify me before a meeting starts | RENAMED |
| *(unlabelled timing picker)* | `joinEventNotificationTime` | Alerts | **How early** — When it starts / 1 / 3 / 5 minutes before | KEPT + **labelled**. Four pickers on this tab are `.labelsHidden()` and three read "when event starts"; indentation is the only cue about what each modifies. |
| "Notifications are set to Banners…" tip | — | Alerts | *(kept)* + **[Open notification settings]** button | KEPT + fixed — dead-end advice becomes an action |
| "⚠️ Your macOS notification settings are off" | — | Alerts | *(kept)* + the same button | KEPT + fixed |
| Show a fullscreen notification | `fullscreenNotification` | Alerts | Take over the screen before a meeting | RENAMED |
| *(unlabelled timing picker)* | `fullscreenNotificationTime` | Alerts | How early | KEPT + labelled |
| Also show fullscreen … without meeting links | `fullscreenNotificationsForEventsWithoutMeetingLink` | Alerts | Include blocks with no meeting link | RENAMED (10-word negative exception clause → 6 words) |
| *(its help line)* | — | Alerts | *(kept)* | KEPT |
| Send a notification when event ends | `endOfEventNotification` | Alerts | Notify me before a meeting ends | RENAMED |
| *(unlabelled timing picker)* | `endOfEventNotificationTime` | Alerts | How early | KEPT + labelled |
| Automatically open the next meeting when it starts | `automaticEventJoin` | Alerts | Open the meeting for me, without clicking | RENAMED. Stays on Alerts (it is an interruption, not a link preference) despite being typed under `AdvancedSettings`. |
| *(unlabelled timing picker)* | `automaticEventJoinTime` | Alerts | How early | KEPT + labelled |
| Auto-join tip ("…chosen under Meetings") | — | Alerts | *"Opens in Chrome"* + **[Change in Joining]** button | KEPT + fixed |
| *(new)* | snooze duration | Alerts | Snooze for — 5 / 10 / 15 minutes | **PROMOTED.** The runtime already ships "Snooze for %@ min" and "Snooze until start time" notification actions with no setting anywhere. |
| *(section headers)* | — | Alerts | *(all four sections get headers)* | FIXED. Three of four `Section`s are bare today (`NotificationsTab.swift:15, :19`), so two toggles float as orphans under "Alerts". The header word **"Alerts"** is retired as a *section* name — it collided with macOS's own "Alerts" notification **style** named in a tip inside the same section — and survives only as the tab name. |
| *(disclosure rule)* | — | Alerts | *(one rule)* | FIXED. Today timing pickers stay visible-but-greyed while their captions are conditionally hidden — two rules side by side. New rule: dependent controls and captions are **both** always visible; dependent controls are disabled. |

### 3.8 From Advanced (tab deleted)

| Current label | Key | New home | New label | Verdict |
|---|---|---|---|---|
| "These settings are intended for advanced users." | — | — | — | **DELETED.** Blanket orange warning stamped across the whole tab including "hide meetings named X", an ordinary everyday wish. Warning-as-wallpaper stops meaning anything. |
| Run AppleScript before joinable meetings | `runEventStartScript` | Alerts ▸ *Run a script around meetings* | Run a script **before a meeting starts** | RENAMED + DISCLOSED (timer-vs-click was unconveyed) |
| *(unlabelled timing picker)* | `eventStartScriptTime` | Alerts ▸ same | How early | KEPT + labelled |
| Test on next event | — | Alerts ▸ same | Test on my next meeting | RENAMED + **real feedback** when there is no upcoming linked meeting (it posts `.nextMeetingMissing` and silently does nothing today) |
| Edit script *(#1)* | `eventStartScript` / `eventStartScriptLocation` | Alerts ▸ same | **Edit the before-meeting script…** | RENAMED — two identically-labelled buttons editing two different files, distinguishable only by position |
| Run AppleScript when joining | `runJoinEventScript` | Alerts ▸ same | Run a script **the moment I click Join** | RENAMED |
| Edit script *(#2)* | `joinEventScript` / `joinEventScriptLocation` | Alerts ▸ same | **Edit the on-join script…** | RENAMED |
| "Runs only for events with meeting links." | — | Alerts ▸ same | *(attached to **each** row, indented)* | FIXED — unindented after both rows today, so it is ambiguous which it qualifies (it is true of both) |
| *(new)* | — | Alerts ▸ same | ⚠️ warning when a script toggle is on but no file has been saved | **PROMOTED.** The scheduler requires `runEventStartScript && eventStartScriptLocation != nil`; the UI lets you flip the toggle without ever saving a file, so it reads ON and does nothing with zero feedback. |
| *(sandbox path recited as instructions)* | — | Alerts ▸ same | **[Choose folder]** button | FIXED |
| *(new)* | — | Alerts ▸ same | *(the 14 positional script parameters documented in the editor)* | PROMOTED — currently documented only in a source comment (`Scripts.swift:18-35`) |
| Custom regexes to filter out meetings | `filterEventRegexes` | **Filters** | Hide meetings whose title matches a pattern — *"Matches the title only, not notes or location."* | MOVED + RENAMED. The only event filter in the app that is not with the other event filters; the code shows the seam — it is the only advanced setting not in `AdvancedSettings`, read straight from Defaults at `EventFiltering+MeetingBar.swift:12`. |
| Custom regexes for meeting link | `customRegexes` | **Joining** ▸ *Find meeting links in unusual formats* | Find meeting links in unusual formats | MOVED + RENAMED + DISCLOSED |
| Test meeting link regex + button | — | Joining ▸ same | Test a pattern | KEPT + **three fixes**: works *before* a pattern is saved (disabled while the list is empty today, so you must ship to production to try one); feeds notes **and location and event URL** like the real detector (`MeetingLinkDetector.swift:410+`), not just notes; and states the rule documented nowhere — the whole match must itself parse as a valid URL (`MeetingLinkDetector.swift:205-207`). |
| Enter regex modal | — | Joining / Filters | Add a text pattern — with an example placeholder and a plain-language error | KEPT + improved. The word **"regex" is banned** from user-facing copy; it becomes **"text pattern"**. |
| edit *(lowercase)* | — | — | Edit | RENAMED — the only lowercase button label in the app |

### 3.9 Hardcoded values promoted to settings

All were frozen in code, several with comments admitting they should be settings.

| Value | Where it is hardcoded | New home | New label |
|---|---|---|---|
| Menu-bar block spacing (two literal spaces) | `StatusBarPresentation+MeetingBar.swift:205` | Menu Bar | Space between blocks — Tight / Normal / Wide |
| Progress bar width (8 cells) | `StatusBarPresentation.swift:555` (comment: "not a user setting yet") | Menu Bar ▸ Progress bar gear | Bar width — Short / Medium / Long |
| Week-number prefix ("W") | a **localization string**, `en.lproj/Localizable.strings:302` | Menu Bar ▸ Week number gear | Prefix *(a German user wanting "KW" had to edit a translation)* |
| Timeline window (−3h / +6h) | `UI/Views/DayTimelineView.swift:38-39` | Dropdown ▸ Timeline gear | Hours shown — Next 2h / Next 6h / Whole day |
| Timeline hour lines (every hour) | `DayTimelineView.swift:133-141` | Dropdown ▸ Timeline gear | Hour lines — Every hour / Every 2 hours / Off |
| Timeline bar shape / fill | `DayTimelineView.swift:155-163` | Dropdown ▸ Timeline gear | Bar shape — Rounded / Square |
| Timeline titles (hover tooltip only) | `DayTimelineView.swift:169` | Dropdown ▸ Timeline gear | Show titles on bars |
| Timeline day scope | `DropdownPanelView.swift:382-396` | Dropdown ▸ Timeline gear | Covers — Today only / Everything the agenda shows |
| Agenda time-column width (66pt) | `DropdownPanelView.swift:567` | derived from `DropdownMetrics`, not exposed | *(internal)* |
| Row density (four independent padding sites) | `PanelRow` `:1125-1126`, headers `:1037-1039`, details `:679-681`, separator `:229` | Dropdown | Row spacing — Comfortable / Compact |
| Calendar marker shape / size / position | `DropdownPanelView.swift:564, 568-570` | Dropdown ▸ Agenda gear | Calendar colour marker + Where it sits |
| Join button visibility | `DropdownPanelView.swift:588-609` | Dropdown ▸ Agenda gear | Join button — Always / On hover / Never |
| Title line limit (always 1) | `DropdownPanelView.swift:577` | Dropdown ▸ Agenda gear | Long titles — Cut to one line / Wrap to two lines / Shorten to N |
| Attendee list (uncapped, arbitrary sort) | `DropdownPanelView.swift:685-696` | Dropdown ▸ Agenda gear | Guests — show first N, then "+more"; Sort by Answer / Name |
| Notes preview (6 lines) | `DropdownPanelView.swift:719` | Dropdown ▸ Agenda gear ▸ Customise details | Notes preview length |
| Detail field order | `DropdownPanelView.swift:663-682` | Dropdown ▸ Agenda gear ▸ Customise details | *(reorderable list: Time · Location · Organizer · Guests · Notes · Prep links)* |
| "Tomorrow" as its own section | `DropdownPanelView.swift:506-527` | Dropdown ▸ Agenda gear | Tomorrow — Its own section / One continuous list |
| Date beside Today/Tomorrow (hardcoded `"E, d MMM"`) | `DropdownPanelView.swift:531, 1101-1106` | Dropdown ▸ Agenda gear | Show the date next to Today and Tomorrow *(+ the format becomes `setLocalizedDateFormatFromTemplate` — a latent localization bug)* |
| Dismissed-meeting marker (invisible in the panel) | `MenuBuilder.swift:1036-1038` only | Dropdown ▸ Agenda gear | Mark meetings I've dismissed |
| Running-meeting emphasis (always semibold) | `DropdownPanelView.swift:573-576` | Dropdown ▸ Agenda gear | Happening now — Bold / Highlighted / Normal |
| Overdue reminder colour (red text only) | `DropdownPanelView.swift:897` | Dropdown ▸ Reminders gear | Overdue looks — Red text / Dimmed / Badge *(colour is the only signal today, which fails colour-vision deficiency)* |
| Reminder tick box (11pt circle) | `DropdownPanelView.swift:888-891` | Dropdown ▸ Reminders gear | Tick box — Circle / Square |
| Greeting summary separator (" · ") and content | `DropdownPanelView.swift:351-368` | Dropdown ▸ Greeting gear | Second line shows — Meeting count / Free time / Both / Nothing |
| Join-block row set (2 of 4 handlers surfaced) | `DropdownPanelView.swift:940-958`; unused handlers at `:58-59` | Dropdown ▸ Join & actions gear | Rows — Join next meeting · Create meeting · Open the calendar window · Open the search bar |
| Dropdown width (330pt, read by 4 files) | `MeetingSummaryView.swift:38` | *(not exposed in this plan — see §8)* | — |
| Dividers between blocks (unconditional) | `DropdownPanelView.swift:228-230` | *(not exposed in this plan — see §8)* | — |
| Panel background (flat, not vibrant) | `DropdownPanelView.swift:156-163` | *(not exposed in this plan — see §8)* | — |
| Global font size (`MenuStyleConstants.defaultFontSize`, read by 9 files) | `StatusBarItemController.swift:44` | *(not exposed in this plan — see §8)* | — |

---

## 4. The live builder

### 4.1 One word: **block**

Not "token" (menu bar UI), not "section" (dropdown UI), not "module" (code), not "composer". Both builders use identical vocabulary, identical row anatomy and identical interactions, so learning one teaches the other. `DropdownModule` keeps its **raw values** for storage compatibility; only the user-facing word changes.

### 4.2 The data model — concrete, and it typechecks

The blocker is not the drag gesture. `MenuBarTokenKind` (`StatusBarPresentation.swift:433`) and `DropdownModule` (`DropdownComposition.swift:18`) are bare `String` enums with no associated value, so **a gear icon has literally nowhere to open.**

Two concrete, non-generic types (a generic `LayoutBlock<Kind>` with a single non-generic `config` does not typecheck; a sum-type config for eight kinds forces an exhaustive switch at every gear, preview and migration site). Both live in **MeetingBarLogic**, in a new file `MeetingBarNG/UI/StatusBar/LayoutBlocks.swift`, which **must be added to the `sources:` array in `Package.swift:26-57`** — that array is an explicit allowlist, not a glob, so a new file silently stays app-target-only and untestable.

```swift
// MeetingBarNG/UI/StatusBar/LayoutBlocks.swift  (MeetingBarLogic)

public struct DropdownBlock: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID                 // stable identity: required for drag, and for future duplicates
    public var kind: DropdownModule     // existing enum, existing raw values
    public var isOn: Bool               // replaces "remove" — nothing is ever destroyed
    public var config: DropdownBlockConfig
}

public struct MenuBarBlock: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var kind: MenuBarTokenKind
    public var isOn: Bool
    public var config: MenuBarBlockConfig
}
```

`DropdownBlockConfig` and `MenuBarBlockConfig` are **flat structs of small enums with defaults**, not sum types:

```swift
public struct DropdownBlockConfig: Codable, Hashable, Sendable {
    // Greeting
    public var showDaySummary: Bool = true
    public var summaryShows: SummaryContent = .both
    // Timeline
    public var timelineWindow: TimelineWindow = .nextSixHours
    public var timelineHourLines: HourLineDensity = .everyHour
    // Agenda
    public var marker: AgendaMarker = .dot                    // .none | .dot | .leftBorderBar
    public var markerPosition: MarkerPosition = .betweenTimeAndTitle   // .farLeft | .betweenTimeAndTitle
    public var timeColumn: TimeColumn = .startOnly
    public var showServiceIcon: Bool = true
    public var titleOverflow: TitleOverflow = .clipOneLine
    public var joinButton: JoinButtonVisibility = .onHover
    …
}
```

**Why flat.** A few fields are irrelevant to a given kind. That is a smaller cost than eight-way exhaustive switches, and it buys free `Codable` synthesis, free `Hashable`, and trivial forward tolerance: a hand-written `init(from:)` that uses `decodeIfPresent(_:) ?? default` for every field and **never throws**. A newer build's config decodes on an older build; an older build's config decodes on a newer one.

**Storage.** Two keys replace eleven:

- `menuBarBlocks: [MenuBarBlock]` replaces `menuBarTokens` + `menuBarCountdownStyle` + `menuBarDateStyle` + `menuBarProgressStyle` + `menuBarWorldClockTimeZone` + `menuBarWorldClockLabel`
- `dropdownBlocks: [DropdownBlock]` replaces `dropdownModuleOrder` + `showGreetingInMenu` + `showTimelineInMenu` + `showMeetingControlInMenu` + `showAgendaInMenu` + `showJoinSectionInMenu` + `showBookmarksInMenu`

`MeetingBarLogic` declares **zero dependencies** (`Package.swift`), so `Defaults.Serializable` cannot be declared there. Conformance is declared in the app target, in `MeetingBarNG/Extensions/DefaultsKeys.swift`, and under Swift 6 both the protocol and the type are from other modules, so it must be retroactive:

```swift
extension DropdownBlock: @retroactive Defaults.Serializable {}
extension MenuBarBlock: @retroactive Defaults.Serializable {}
```

**Three defects die with the old shape:**

1. Turning the menu-bar composer off stops being a destructive, unwarned, un-undoable delete (`DisplayTab.swift:487` writes `menuBarTokens = []`).
2. "Remove" stops meaning two different things behind the same minus icon — permanent delete in the menu bar, boolean flip in the dropdown, both using the same `..._composer_remove` help string. Now it means one thing in both: `isOn = false`, move to the Hidden tray.
3. The two different reorder algorithms collapse into one. Menu bar used `swapAt` on the visible list (losing hidden items' slots); the dropdown swapped then re-projected onto the stored full order (`DisplayTab.swift:740-753`). Both become `blocks.move(fromOffsets:toOffset:)` on one array where `isOn == false` blocks keep their slot.

**Resolution policy** stays in `DropdownCompositionPolicy` and keeps its degrade-gracefully contract exactly: unknown kinds dropped, missing kinds re-appended in `standard` order, unknown config fields ignored. A downgrade or a hand-edited plist can never break the menu.

**Duplicates are permitted by the model** (`id` is per-instance) but **not exposed in the UI in this plan.** See §8.

### 4.3 Reorder mechanics

`List` + `ForEach(...).onMove(perform:)`. **Not** `.draggable`/`.dropDestination` on rows — Apple Developer Forums thread 730367 documents that per-row `dropDestination` inside a `List` silently never fires (neither the action nor `isTargeted`); FB12980427, unresolved as of April 2025. `onMove` gives the system insertion indicator, auto-scroll and drop animation for free.

The builder must **not** live inside `PreferencesGroupedForm`. Two verified reasons: `onMove` only works inside a real `List`, and macOS 15 clamps `GroupedFormStyle` content width to 600pt. The Menu Bar and Dropdown tabs host their builder in a dedicated container styled as an inset card so it reads as deliberate rather than inconsistent.

`EditMode` and `EditButton` are `@available(macOS, unavailable)` — verified in this machine's SDK. On macOS `onMove` is **always live** and installs a drag recognizer over the whole row, which would delay or swallow clicks on the gear and the switch.

**The fix, which is not optional polish:**

```swift
@State private var handleHovered = false
…
Image(systemName: "line.3.horizontal")
    .onHover { handleHovered = $0 }
    .pointerStyle(.grabIdle)                               // macOS 15+, free at the floor
…
row.moveDisabled(!handleHovered)
   .contentShape(.dragPreview, RoundedRectangle(cornerRadius: 10, style: .continuous))
```

SwiftUI does not re-evaluate `onHover` during an in-flight drag, so a drag begun on the handle completes normally while every click elsewhere in the row is immediate. `.contentShape(.dragPreview, …)` is what makes the dragged thing a **card** rather than a ragged full-width bitmap.

Write to Defaults **exactly once**, inside the `onMove` closure. Never bind a Defaults key to a continuous gesture: every write round-trips UserDefaults + an async sequence + `objectWillChange`.

**Row anatomy** (resting state is calm — a handle, an icon, a word, a summary):

```
⠿  ▤  Agenda        time · dot marker · join on hover        ⚙  ◉
```

The one-line config summary is load-bearing: it tells you what the gear holds without opening it, which is what makes the gear discoverable without a tour.

**Keyboard and accessibility ship in the same commit as the drag gesture, not after.** Drag-only reorder is hostile to the stated user.

- ⌥↑ / ⌥↓ on the focused row (`keyboardShortcut`)
- Right-click → Move up / Move down / Hide / Configure…
- `.accessibilityAction(named: "Move Up" / "Move Down" / "Hide" / "Configure")`
- `.accessibilityValue("Agenda, showing, block 4 of 8")`

The chevron buttons that occupy every row today move into the context menu — still available, no longer permanent chrome. Note `onMoveCommand` (already used at `DropdownPanelView.swift:172`) is arrow-key *navigation*, not reorder; it will not do this.

**Menu-bar strip** reorders horizontally, so it uses `.draggable` + `dropDestination(for:action:)` **on the ForEach** — the List-aware variant that yields an insertion index. macOS supports only icon-left or icon-far-right on a status item, so dropping the Icon block mid-list snaps it to an end; the strip must show that snap with an inline note rather than pretending otherwise.

**Hidden tray.** The eye/switch sets `isOn = false` and animates the block into a dimmed **"Hidden — drag back in to use"** tray at the bottom of its builder. Config and identity survive. This replaces the destructive minus *and* the "Add token"/"Add section" menus, and it makes the builder show the complete inventory of what the surface can contain — which the current list does not (Reminders were content inside Agenda; the pinned footer was not a block at all, so "Dropdown layout" showed six rows for a dropdown that holds eight kinds of thing).

**Locked block.** `Settings & Quit` renders as a real, dimmed, `moveDisabled(true)` row with a lock glyph. The pinning is correct — you must not be able to hide your way out of Settings — and the builder should say so rather than omit it.

### 4.4 The gear popover — one mechanism, with a hard cap

`.popover(isPresented:attachmentAnchor:arrowEdge:)` anchored to the gear, opening **toward the settings column and away from the preview**, 320pt wide.

Explicitly rejected: inline `DisclosureGroup` row expansion (expanded rows change height, so drop targets move under the cursor mid-drag — actively hostile); a separate `.inspector` column (competes for width with the preview and pushes the window back toward 1100pt); and "simple blocks get a popover, complex ones get an inspector" (two mechanisms for one icon is the disease being cured).

**Hard rules, enforced in review:**

1. **A block's options appear behind its gear and nowhere else.** No mirror row in a flat section. That duplication is exactly how the greeting and timeline ended up rendered twice before Phase 3.
2. **Maximum six rows visible at once.** The Agenda gear exceeds this, so — and this is the one structural concession — it opens with a two-item segmented control at the top: **Row** / **Contents**. Six rows under each. Same mechanism, same icon, same popover; no second surface is invented.
3. **Every popover ends with "Reset this block."**
4. **The block being configured is spotlighted in the preview** (everything else dims ~15%) so cause and effect read even though the popover sits beside it.
5. **Live.** Changes repaint immediately, `.animation(.snappy, value: blockConfigHash)`, gated on `@Environment(\.accessibilityReduceMotion)` — which nothing in the panel consults today despite five separate `easeOut(0.12)` calls.
6. **Close the popover on any reorder, and disable dragging while a popover is open.** A popover anchored to a row in a mutating `List` can otherwise be orphaned or mis-anchored.

### 4.5 Per-block gear options, enumerated

#### Menu Bar blocks

| Block | Gear options |
|---|---|
| **Icon** | Which icon — Calendar / MeetingBarNG / The meeting's app · *(footnote: macOS puts the icon at the far left or far right only; it follows whichever end this block sits at)* |
| **Title** | Show — The meeting's title / The word "Meeting" / A dot · Shorten long titles to — 20 / 30 / 50 / Custom characters |
| **Countdown** | Write it as — 2h / 2h 30m / 2:30 · *(summary: counts down to the start before a meeting, to the end during one)* |
| **Clock** | *(no options)* — summary line reads "Uses your time format from General" with a jump button |
| **Date** | Write it as — Mon / Mon, Jul 17 / 7/17/26 |
| **Progress bar** | Tracks — Today / This year · Bar width — Short / Medium / Long |
| **Week number** | Prefix *(text field, default "W")* |
| **World clock** | Time zone *(**searchable**)* · Short label *(e.g. "SF")* |

#### Dropdown blocks

| Block | Gear options |
|---|---|
| **Greeting** | Your name · Show the day summary · Second line shows — Meeting count / Free time / Both / Nothing · Size — Full / One line |
| **Timeline** | Hours shown — Next 2 hours / Next 6 hours / Whole day · Hour lines — Every hour / Every 2 hours / Off · Bar shape — Rounded / Square · Show titles on bars · Covers — Today only / Everything the agenda shows |
| **Meeting card** | Show the meeting app's logo · Show the Join button · Show location · Show organizer |
| **Agenda ▸ Row** | **Calendar colour marker — None / Dot / Left border bar** · **Where it sits — Far left, at the row edge / Between the time and the title** · Time column — Start only / Start and end / Hidden · Show the Zoom / Teams / Meet logo · Long titles — Cut to one line / Wrap to two lines / Shorten to N characters · Join button — Always / On hover / Never |
| **Agenda ▸ Contents** | Happening now — Bold / Highlighted / Normal · Meetings I haven't accepted — Dimmed / Normal · Mark meetings I've dismissed · Tomorrow — Its own section / One continuous list · Show the date next to Today and Tomorrow · **Customise details…** *(sub-sheet: reorderable field list — Time · Location · Organizer · Guests · Notes · Prep links; guest cap + sort; notes preview length)* |
| **Reminders** | Include overdue · Overdue looks — Red text / Dimmed / Badge · Tick box — Circle / Square |
| **Join & actions** | Rows *(checklist, reorderable)* — Join next meeting · Create meeting · Open the calendar window · Open the search bar · Show icons |
| **Bookmarks** | Show as — Name only / Name and service · Hide when empty · **Edit my saved links…** *(jumps to Joining)* |
| **Settings & Quit** *(locked)* | Show What's New when there is one |

#### The agenda marker, worked out

The row is hardcoded as `HStack(spacing: 8) { time(66pt) · Circle(7pt) · title }` (`DropdownPanelView.swift:563-581`). The owner's ask is not one setting; it is three that must ship together or the result is another incoherent screen:

```swift
public enum AgendaMarker: String, Codable, Sendable, CaseIterable {
    case none, dot, leftBorderBar
}
public enum MarkerPosition: String, Codable, Sendable, CaseIterable {
    case farLeft, betweenTimeAndTitle
}
```

Implementation constraints, stated so they are not discovered late:

- `.leftBorderBar` implies `.farLeft`. The position picker is **disabled with an inline note** in that combination rather than offering an impossible pairing.
- A true far-left marker must escape `PanelRow`'s 10pt inner + 6pt outer padding (`DropdownPanelView.swift:1125, :1132`) to reach the real row edge. It is an `.overlay(alignment: .leading)` on the row **container before padding**, not another `HStack` child.
- There is **no grid to be left OF** today: agenda rows indent to 66pt, action/footer rows to 18pt (`:1021`), expanded details to a magic 32pt (`:679`), section headers to 16pt (`:1037`). Phase 1 introduces a single `DropdownMetrics` source of truth first.
- Marker and the meeting-app icon are **one combined choice**. `MenuBuilder.swift:1138-1157` already models icon-badged-with-calendar-colour; the panel simply dropped it. Offer them as a coherent set in one gear tab.
- Every marker option must survive greyscale. Colour is currently the only signal in three places (overdue reminders red-only `:897`, finished meetings grey-only `:577`, calendar identity a 7pt dot `:568-570`), which fails colour-vision deficiency. `.dot` and `.leftBorderBar` are genuinely different shapes, not recolourings.

### 4.6 How the live preview binds to the builder

**Three rules.**

**Rule 1 — one preview per surface, owned by that surface's tab.** The Menu Bar tab gets a **wide strip pinned at the top** (a menu bar is a wide, short thing; a 340pt vertical column was always the wrong shape). The Dropdown tab keeps a right-hand column, which is the right shape for a dropdown. No tab shows two previews, and no preview is labelled with the same word twice.

**Rule 2 — the preview renders the *real* view.** `DropdownPanelView`'s entire input surface is three values:

```swift
let state: StatusBarMenuState
let handlers: DropdownPanelHandlers
var now: Date = Date()
```

So the Dropdown preview mounts **`DropdownPanelView` itself** against a fixture `StatusBarMenuState` and a no-op handler set. The menu-bar strip calls `StatusBarPresenter.composedPresentation`, which it already does. `DisplayPreviewPane`'s hand-copied `agendaRow`, `moduleBlock`, sample data and duplicated composition math are **deleted**. Any per-block style option then costs one implementation, and the preview cannot drift.

**Where fixtures live — and where they cannot.** `StatusBarMenuState` imports `Defaults`; `MBCalendar` imports `AppKit` and holds an `NSColor`. Neither is in `Package.swift`'s `sources:` allowlist. Therefore `PreviewFixtures` lives in the **app target**, at `MeetingBarNG/Preferences/PreviewFixtures.swift`. What *does* go in MeetingBarLogic is the deterministic offset math (`PreviewSampleDay`: a fixed reference date plus the meeting offsets), which is unit-testable; the app target turns that into `MBEvent`/`MBCalendar` values.

**Builder rows are not real block views.** Each dropdown block is a `private` computed property or func inside the ~1200-line `DropdownPanelView`, closing over shared `@State selectionIndex`, `@State expandedEventIDs` and `@FocusState`. Rendering each as an independently draggable row would require decomposing the app's largest and most recently-churned UI file into eight standalone `View`s **and** rewriting `DropdownPanelNavigation` to carry block ids. That is not worth it and is not needed: a builder row is a **control**, not a rendering. Rows get a lightweight schematic thumbnail plus the one-line config summary; the authoritative rendering is the single real-panel preview two inches to the right. This is the deliberate scope cut that makes §4 shippable.

**Rule 3 — builder and preview are one object.** A shared `selectedBlockID` on the layout model. Hovering or focusing a builder row spotlights the matching region of the preview; clicking a preview region selects its builder row and scrolls to it (`ScrollViewReader.scrollTo`); opening a gear also selects. Reordering animates with `.animation(.snappy, value: blocks.map(\.id))`, downgraded to a cross-fade under reduce-motion. Reordering that teleports silently is the single biggest source of "I don't understand what that did."

**The time scrubber.** Above both previews: **2 hours before · 25 minutes before · in a meeting · nothing today.** This is what finally makes "Keep the menu bar quiet until a meeting is close", "Count the meeting happening now as next", and the countdown's start→end flip *visible*. Today `DisplayPreviewPane.swift:207-210` hardcodes `showEventMaxTimeUntilEventEnabled: false` and `hasSelectedCalendars: true`, so the two hardest controls on the tab produce zero preview change and a fresh install with no calendars sees a preview that disagrees with reality.

**Fixed sample data, with an opt-out.** Deterministic by default, so the canvas looks identical at 3am with an empty calendar and is snapshot-testable. A **"Preview with my real meetings"** toggle at the top of the pane swaps in live data.

**Preview performance.** Replace `DisplayPreviewPane`'s ~20 `@Default`s (`:27-55`) with one `@Observable final class LayoutModel` read by both the builder and the preview, loaded from Defaults when Preferences opens. Observation tracks per-property, so editing the agenda marker re-renders the agenda and nothing else — versus today, where any one of 20 keys re-runs the entire body, re-deriving sample dates, allocating ~5 `DateFormatter`s (`:504`) and re-fetching `NSImage`s (`:143-157`) on every keystroke in the greeting-name field. Seed one `let previewNow: Date` in `@State`; hoist the formatter to a cached `static`; memoize the icon lookups. Use `let _ = Self._printChanges()` while tuning.

**Preset safety.** Applying a preset when the current layout is Custom stashes the previous array in `layoutUndoSnapshot` and shows an inline **Undo** for 10 seconds. A preset card is the largest, most clickable element on the pane; it must not be able to silently destroy a hand-built layout.

---

## 5. How the two named complaints are resolved

### 5.1 "Lots of confusion between the display panel and the events panel"

**Why it happens.** The Phase 1 split relabelled the containers without re-deriving the boundary. The old axis was *"is this an event, or is it display?"* — and it does not survive contact with reality, because **every dropdown row is both**. The code admits it three ways:

1. Both tabs still draw from `preferences_appearance_*`, because both came from one former Appearance tab (the file headers still say "moved here from AppearanceTab.swift").
2. `preferences_tab_menu_bar` is still literally `"Display & Events"` — an `&` in a tab name is a reliable tell that one tab is doing two jobs.
3. The type system disagrees with the UI **in both directions**: `showEventEndTime` is in `StatusBarSettings` but rendered on Events under "…in the dropdown"; `showEventMaxTimeUntilEvent*` and `ongoingEventVisibility` are in `EventDisplaySettings` but rendered on Display.

**The fix.** Both words are deleted as pane names and replaced with an axis the data model already agrees with:

| Question | Tab | Zero exceptions because… |
|---|---|---|
| Does this change **which meetings exist**? | Filters | It is genuinely cross-surface (fetch window + menu-bar next-event selection + dropdown + calendar window), so filing it on any one surface would be a lie. It holds **no** style options. |
| Does this change **how one surface draws them**? | Menu Bar / Dropdown | Each surface tab holds **no** filters. Every appearance setting sits on the block that renders it. |
| Does this change **what happens when I act**? | Joining / Alerts | |
| Is this about **the app itself**? | General | |

**The exception the winning proposal shipped, and why it is not here.** That plan split declined/pending/tentative/past into a Show-Hide switch on one tab *and* a "looks like" picker on another — which is the Display-vs-Events fork wearing new names. This plan does not split them. Each RSVP/lifecycle state is **one row, one place**: a 3-way `Show / Dim / Hide` in Filters ▸ Custom. "Dim" is honest because Phase 1 makes the shipping renderer actually dim. The only appearance option that remains is a single uniform Agenda-gear row — *"Meetings I haven't accepted — Dimmed / Normal"* — which is a rendering choice about one block, not a per-state fork.

**And the confusion's real fuel is removed.** The reason those settings *felt* arbitrary is that **seven of them do nothing** on the default renderer. Phase 1 fixes that before anything moves, so no setting is ever re-homed twice and none ships unreachable.

### 5.2 "Why do we have two preview areas?"

**What is true right now.** The two inline previews are already deleted (`DisplayTab.swift:344-346`, `:558-561`). Three things remain wrong:

1. **The surviving pane still renders two labelled sub-previews in one column** — `DisplayPreviewPane.swift:67` "Menu bar" and `:72` "Dropdown" — under a header also called "Preview". So on one screen the user still sees a preview containing two previews.
2. **The pane is a second renderer.** `agendaRow` (`:359`) uses a 76pt time column against the real 66pt (`DropdownPanelView.swift:567`), 14/3 padding against the real 16/5, and duplicates `MenuBarComposition.currentIfEnabled` and `MenuBarComposedSettings.current` outright. Deleting a duplicate *view* does not stop the next person re-copying it.
3. **The word "preview" means three things** — the pane title, the "(preview)" beta label on the SwiftUI dropdown toggle, and the deleted section headers.

**The fix.**

- **One preview per pane, scoped to that pane's surface.** Menu Bar → a wide strip at the top, nothing else. Dropdown → the real panel on the right, nothing else. Neither pane contains two previews, so the question cannot recur.
- **The preview *is* the shipping renderer** (§4.6), so drift is structurally impossible rather than something someone must remember.
- **"Preview" stops meaning "beta."** `useSwiftUIDropdown` becomes "Use the classic macOS menu instead" in General ▸ Troubleshooting.
- **`minWidth` drops 1100 → 860** (`Preferences.swift:71, :97`), because only one pane still needs a side column. Every other pane stops paying for it, and General's short rows stop rendering with a huge dead right margin that reads as "something is missing here."

---

## 6. Label rules, and the 15 worst labels

### 6.1 Rules

1. **Strip the surface suffix — the tab and the block carry scope.** Inside the Dropdown tab, "Hide finished meetings **from the dropdown**" is just "Hide meetings that have ended."
2. **Verb-first toggles, naming the state that is true when ON.** A toggle label describes what is true when it is on. "Customize menu bar layout" → gone. "Use the new SwiftUI dropdown (preview)" → "Use the classic macOS menu instead."
3. **Outcome-first pickers.** The label states the outcome; the options complete it. "Count the meeting happening now as next" + "Until it ends."
4. **Eight words maximum.** Anything longer moves to help text.
5. **Help text answers "what will I actually see?"** with a concrete example, states the default, and never restates the label. Template, kept verbatim from the best copy currently in the app: *"e.g. at 30m, a 2:00 meeting shows in the menu bar at 1:30 — before that you see an alarm icon."*
6. **Ban list, enforced in review.** No user-visible **token**, **module**, **composer**, **status bar**, **SwiftUI**, **submenu**, **regex**, **inactive**. Replacements: token/module/section → **block**; status bar → **menu bar**; regex → **text pattern**; "show as inactive" → **Dim**.
7. **One word per surface, everywhere.** **menu bar** and **dropdown** — the owner's own words. "Status bar" and "menu" are retired from all user-visible strings.
8. **Keep and extend the parenthetical glosses.** "Pending (not yet accepted)" is already the right accommodation. Extend: "Blocks you booked for yourself (focus time, lunch)."
9. **One colon policy: none.** Colons are removed **at source** in `en.lproj/Localizable.strings`, option values are rewritten as standalone sentence-case phrases rather than sentence continuations, and the runtime `preferenceLabel()` colon-stripper (`Preferences.swift:161-167`) is **deleted**. A runtime string patch is a smell that the content layer is inconsistent — and it silently defeats the design intent of the lowercase option values it strips the cue from.
10. **Key namespaces match the new panes.** `preferences_appearance_status_bar_*` → `preferences_menubar_*`; `preferences_appearance_menu_*` / `preferences_appearance_events_*` → `preferences_dropdown_*` / `preferences_whichmeetings_*`; plus `preferences_calendars_*`, `preferences_joining_*`, `preferences_alerts_*`, `preferences_general_*`. Done in the **same pass** as the IA change: the shared `appearance` prefix is precisely why the boundary keeps blurring for anyone reading the code. **Only `en.lproj` is edited** — the other 22 bundles already fall back to English for every MeetingBarNG-era key, so renaming there costs nothing and gains nothing. Directory names contain **real trailing spaces**: `MeetingBarNG/Resources /Localization /en.lproj/`.

### 6.2 The 15 worst labels

| # | Before | After |
|---|---|---|
| 1 | Use the new SwiftUI dropdown (preview) | **Use the classic macOS menu instead** *(inverted, moved to General ▸ Troubleshooting)* |
| 2 | Customize menu bar layout | *(deleted — the builder is always on)* |
| 3 | Add token | **Add block** *(then deleted — nothing is ever added or removed; blocks move between Showing and Hidden)* |
| 4 | Force Sync | **Refresh now** *(and rewired to actually force a sync)* |
| 5 | Open Calendar Settings | **Open Calendar privacy settings** |
| 6 | Only show the next meeting in the menu bar when it's within: | **Keep the menu bar quiet until a meeting is close** *(+ "within 30 minutes")* |
| 7 | Hide the current meeting from the menu bar: / as soon as it starts | **Count the meeting happening now as "next"** / *Until it ends · For 5 minutes · Never* |
| 8 | Show event details in a submenu | *(deleted — the panel's inline chevron is always there; the detail **fields** are configurable)* |
| 9 | Show the calendar's color dot | **Calendar colour marker — None / Dot / Left border bar** |
| 10 | Shorten long meeting titles in the dropdown: | **Long titles — Cut to one line / Wrap to two lines / Shorten to N characters** |
| 11 | Use web browser *(actually the browser for **creating** meetings)* | **Open new meetings in** |
| 12 | Open command bar: | **Open the search bar** — *"A Spotlight-style box for finding meetings and running actions"* |
| 13 | Run AppleScript before joinable meetings / Run AppleScript when joining | **Run a script before a meeting starts** / **Run a script the moment I click Join** |
| 14 | Custom regexes to filter out meetings | **Hide meetings whose title matches a pattern** — *"Matches the title only, not notes or location."* |
| 15 | Pending (not yet accepted) events: show / show as inactive / show as underlined / hide | **Invites you haven't answered — Show / Dim / Hide** |

---

## 7. Implementation plan

Seven phases. **Each leaves the app fully working and is independently shippable.** No phase depends on a later phase for a setting to be reachable.

Verification line for every phase (the project's existing convention):

```
xcodebuild -scheme MeetingBarNG build
swift test                                   # MeetingBarLogic
xcodebuild -scheme MeetingBarNG test         # app target
swiftlint
scripts/strings-lint                         # new in Phase 0
```

Every commit body ends with `No AI/voice.`

---

### Phase 0 — Truth pass *(no user-visible IA change)*

**Why first:** these are unreachable code and outright bugs sitting in the files every later phase edits. Cleaning them first makes every subsequent diff readable.

**Changes**
- Delete `Preferences.swift:23-31` (`#available(macOS 13.0, *)` dispatch), `:35-72` (`legacyLayout`), `:172-186` (`PreferencesGroupedForm`'s macOS 12 `ScrollView` fallback), and `pinnedSidebarToggleRemoved()`'s availability gate. Collapse `ModernPreferencesLayout` into `PreferencesView`. Floor is macOS 15 (`Package.swift:8`). ~50 lines.
- Raise the sidebar minimum 215 → 225 (`Preferences.swift:89`) per macOS 26 guidance; verify no custom `foregroundStyle` survives on sidebar `Label`s.
- Fix `deduplicateEvents`: add it to `CalendarSync.swift:261-269` observers and `StatusBarItemController.swift:136-153` redraw list.
- Fix `checkNotificationSettings()` (`UI/Views/Shared.swift:137-153`): it does a synchronous `group.wait()` on the main thread from a computed property SwiftUI re-evaluates every body render — which is why the two advisory captions flicker. Make it async, cached, refreshed on `didBecomeActive`.
- Add a visible "Copied" confirmation to `DiagnosticsClipboard.copy()`.
- Fix `Defaults.joinEventScript`'s default calling `.loco()` at key-declaration time (`DefaultsKeys.swift:259-260`), which bakes a localized placeholder into the stored default.
- Adopt `.pointerStyle` in `MeetingSummaryView.swift:89-97`, which uses the `NSCursor.push/pop` pattern that `PanelRow`'s own comment (`DropdownPanelView.swift:1134-1136`) documents as able to strand a pointing-hand cursor.
- Correct the stale header comments: `DropdownPanelView.swift:5-9` still says the panel is "an OPT-IN alternative" and "the menu stays the default"; `DisplayTab.swift:24-25, 807-808` still says `useSwiftUIDropdown` is off by default.
- **Add `scripts/strings-lint`**: fails if any key referenced in code is missing from `en.lproj/Localizable.strings`, or if any `en.lproj` key is referenced nowhere. Delete the orphans it finds: `preferences_tab_meeting_opening`, `preferences_tab_menu_bar` (value `"Display & Events"`), `preferences_tab_menu_builder`, `preferences_appearance_menu_show_timeline_toggle`, `preferences_appearance_menu_show_greeting_toggle`. Move the three About-card strings out of the "Status bar quick actions" MARK block.
- **Verify by hand** whether `MeetingsTab.swift:146`'s `.onMove` drags today. Expected: no. Record the result in the commit body — it settles the container question for Phase 5 and is a live bug fixed in Phase 2.

**Files:** `Preferences/Preferences.swift`, `Preferences/DisplayTab.swift` *(comments)*, `Calendar/CalendarSync.swift`, `UI/StatusBar/StatusBarItemController.swift`, `UI/Views/Shared.swift`, `UI/StatusBar/MeetingSummaryView.swift`, `UI/StatusBar/DropdownPanelView.swift` *(comments)*, `Extensions/DefaultsKeys.swift`, `Utilities/Diagnostics/DiagnosticsReport+MeetingBar.swift`, `scripts/strings-lint` *(new)*, `Resources /Localization /en.lproj/Localizable.strings`.

**Hostless logic:** none.

**Verify:** build + both test suites + lint + strings-lint pass. Preferences opens, all seven current tabs render, no visual change. Toggling "Merge the same meeting…" now changes the dropdown immediately.

---

### Phase 1 — Make the shipping renderer honest

**Why before the IA move:** seven settings visible in Preferences do nothing for nearly every user. Moving them first would either re-home them twice or ship them unreachable. Fixing the renderer first means every setting the IA touches is a setting that works.

**Changes**
- Introduce `DropdownMetrics` — one source of truth for the time-column width, marker slot, icon slot, row padding and gutter. Today there are four unrelated left grids in one 330pt panel: 66pt (`:567`), 18pt (`:1021`), 32pt (`:679`), 16pt (`:1037`). Without it, "move the marker all the way left" has no grid to be left of.
- Make `DropdownPanelView` honour, in `eventRowContent` / `visibleEvents`:
  - `showEventCalendarColor` — the dot is drawn unconditionally at `:568-570`
  - `showMeetingServiceIcon` — no provider icon is drawn on agenda rows at all
  - `showEventEndTime` — `eventStartText` (`:1083-1087`) only ever returns the start
  - `shortenEventTitle` + `menuEventTitleLength` — call the same `StatusBarTitlePolicy.shortenTitle` the NSMenu uses (`MenuBuilder.swift:1020-1035`)
  - `pastEventsAppereance` — `.hide` currently does not hide past meetings in the default dropdown
- Implement the five visual states the panel silently dropped, so **no capability is lost** when the classic menu is later frozen: dim/strikethrough for declined (`MenuBuilder.swift:1260-1267`), dim for past (`:1324-1331`), dim for pending/tentative (`:1275-1312`, replacing the dotted underline SwiftUI cannot draw with a hollow marker), the `[dismissed]` marker (`:1036-1038`), the running-meeting emphasis (`:1351-1356`).
- Honour `@Environment(\.accessibilityReduceMotion)` at all five `easeOut(0.12)` sites (`:144, 608, 633, 641, 1140`).
- Render prep links inline in `eventDetails` in addition to the right-click submenu.

**Files:** `UI/StatusBar/DropdownPanelView.swift`, `UI/StatusBar/MeetingSummaryView.swift`, new `UI/StatusBar/DropdownMetrics.swift`.

**Hostless logic + tests:** put `DropdownMetrics` and a new `AgendaRowLayout` (given metrics + marker + position + time-column mode, return the leading inset, marker frame and title origin) in **MeetingBarLogic** — new file `UI/StatusBar/DropdownMetrics.swift`, **added to `Package.swift` `sources:`**. New `MeetingBarLogicTests/AgendaRowLayoutTests.swift`: every marker × position × time-column combination produces a valid, non-overlapping layout; `.leftBorderBar` always resolves to `.farLeft`; the far-left inset is negative relative to `PanelRow` padding (i.e. it genuinely escapes it).

**Verify:** flip each of the seven settings on the default renderer and observe a change. Automated: extend `StatusBarPresentationPolicyTests` / add `AgendaRowLayoutTests`. Manual checklist in the commit body, one line per setting.

---

### Phase 2 — The IA restructure *(the phase the owner feels)*

**Changes**
- Replace `PreferencesTab` (`PreferencesPresentation.swift:55-104`) with the seven new cases; delete `PreferencesSidebarSection` entirely (flat sidebar); add the About & Support footer item.
- Split `DisplayTab.swift` (864 lines, three surfaces) into `MenuBarTab.swift` and `DropdownTab.swift`. Fold `EventsTab`'s `EventDetailSection` into the Dropdown tab as a plain "Meeting rows" section *(it becomes the Agenda gear in Phase 5 — until then it is a normal, fully reachable section, so nothing is ever unreachable)*. Move `EventsSection` into the new `WhichMeetingsTab.swift`. Delete `EventsTab.swift` and `AdvancedTab.swift` as tabs, redistributing their contents per §3.
- Apply **every** rename and re-home in §3, including the `.strings` key namespace migration (en.lproj only) and the colon removal at source, then delete `preferenceLabel()`.
- Collapse the six/eight-picker wall behind preset chips + a Custom disclosure, using the pattern already proven at `DisplayTab.swift:260` and in `PresetNumberPicker`.
- Move the bookmarks list into a real `List` so its drag handle works.
- Add **"Reset this section"** to every section header (`Defaults.reset(...)`) and **"Reset all settings…"** with confirmation in General.
- Add **settings search**: `.searchable` on the split view, backed by a hostless index.
- Auto-expand the Calendars troubleshooting disclosure whenever `ProviderHealth` reports an error, so the recovery path appears exactly when needed.
- Persist each disclosure's expanded state in Defaults; never auto-collapse one the user opened.

**Files:** `Preferences/Preferences.swift`, `PreferencesPresentation.swift`, new `MenuBarTab.swift` / `DropdownTab.swift` / `WhichMeetingsTab.swift` / `JoiningTab.swift` / `AlertsTab.swift` / `GeneralTab.swift` *(rewritten)* / `AboutSupportView.swift`, deleted `DisplayTab.swift` / `EventsTab.swift` / `AdvancedTab.swift`, `CalendarsTab.swift`, `MeetingsTab.swift` → `JoiningTab.swift`, `NotificationsTab.swift` → `AlertsTab.swift`, `UI/Views/Shared.swift`, `Resources /Localization /en.lproj/Localizable.strings`.

**Hostless logic + tests:** new `MeetingBarNG/Preferences/SettingsIndex.swift` in **MeetingBarLogic** (added to `Package.swift` `sources:`) — `SettingsIndexEntry { id, labelKey, helpKey, tab, sectionID, blockKind: String?, synonyms: [String] }` plus a `search(_:)` reusing `CommandBarSearch`'s existing `matchTier` (exact 4 / prefix 3 / word-boundary 2 / substring 1) over `TextNormalization.fold`. Author synonyms aggressively — *dot, bullet, colour, dark, 24 hour, am/pm, zoom, teams, declined, strikethrough*. New `MeetingBarLogicTests/SettingsIndexTests.swift`: every entry's `labelKey` resolves to a real key in `en.lproj`; no duplicate ids; **every one of the 92 Defaults keys is indexed at least once** (this test is the guard against a setting becoming unfindable); representative queries return the expected top hit.

**Verify:** every setting in §3 is reachable in at most three clicks from a cold open. Search for "dot", "strikethrough", "24 hour", "zoom" and land on the right control. `Defaults.reset` restores a section. Strings-lint passes with zero orphans.

---

### Phase 3 — One honest preview per surface

**Changes**
- Delete `DisplayPreviewPane.swift`'s hand-copied `agendaRow`, `moduleBlock`, `sampleEvents`, `timeString`, `icon`, and the duplicated `MenuBarComposition` / `MenuBarComposedSettings` math.
- Dropdown tab: mount the real `DropdownPanelView` against `PreviewFixtures` with no-op handlers and an injected `now`.
- Menu Bar tab: a wide strip pinned at the top, calling `StatusBarPresenter.composedPresentation`.
- Add the time scrubber and the "Preview with my real meetings" toggle.
- Replace the 20 `@Default`s with one `@Observable final class LayoutModel`; seed `previewNow`; cache the formatter; memoize icon lookups.
- Add `selectedBlockID` spotlight linking (preview ↔ section, before blocks exist; ↔ block rows in Phase 5).
- Drop `minWidth` 1100 → 860; use `ViewThatFits` so the Dropdown tab degrades gracefully below it.

**Files:** `Preferences/DisplayPreviewPane.swift` → `Preferences/SurfacePreview.swift`, new `Preferences/PreviewFixtures.swift` *(app target — see §4.6)*, `Preferences/MenuBarTab.swift`, `Preferences/DropdownTab.swift`, `Preferences/Preferences.swift`.

**Hostless logic + tests:** `PreviewSampleDay` in **MeetingBarLogic** (`UI/StatusBar/PreviewSampleDay.swift`, added to `sources:`) — a fixed reference date plus meeting/reminder offsets and a `scrub(to:)` returning the effective `now` for each scrubber position. `MeetingBarLogicTests/PreviewSampleDayTests.swift`: each scrubber position yields the intended state (one running meeting / next at 25m / next at 2h / nothing today), and the fixture is stable across time zones and DST.

**Verify:** change any setting in Phase 1's list and see the preview change. Set the scrubber to "2 hours before" with the quiet threshold at 30m and see the strip go quiet. No pane shows two previews. Window opens at 860pt without clipping.

---

### Phase 4 — The block model *(invisible to users)*

**Changes**
- Add `LayoutBlocks.swift` to MeetingBarLogic and to `Package.swift` `sources:`.
- Add `dropdownBlocks` / `menuBarBlocks` Defaults keys + the `@retroactive Defaults.Serializable` conformances in `DefaultsKeys.swift`.
- Write the one-shot, versioned, idempotent migration behind a `layoutBlocksMigrated` guard. **Do not delete the legacy keys** — keep reading them as a fallback for one release so a downgrade is survivable.
- Update `MeetingBarNG/Settings/AppSettings.swift` (493 lines, referenced by 13 files): `MenuSettings` and `StatusBarSettings` read the new keys; the sub-structs stay `Equatable`, and the single construction site is updated. **This is the real cost centre of the phase — budget for it explicitly.**
- Update `StatusBarItemController` and `DropdownPanelView` to resolve blocks via the policy. UI unchanged: chevrons still, no gears, no drag.

**Files:** new `UI/StatusBar/LayoutBlocks.swift`, `Package.swift`, `Extensions/DefaultsKeys.swift`, `Settings/AppSettings.swift`, `UI/StatusBar/DropdownComposition.swift`, `UI/StatusBar/StatusBarPresentation.swift`, `UI/StatusBar/StatusBarItemController.swift`, `UI/StatusBar/DropdownPanelView.swift`, `Preferences/MenuBarTab.swift`, `Preferences/DropdownTab.swift`.

**Hostless logic + tests:** the model, the migration, and `DropdownCompositionPolicy.resolve` extended to blocks — all in MeetingBarLogic. New `MeetingBarLogicTests/LayoutBlocksTests.swift` covering, at minimum: empty legacy order; `menuBarTokens == []` (the "composer off" state, which `MenuBarPreset.detect` maps to `.classic`); unknown raw values dropped; a partial order missing a module gets it re-appended in `standard` order; hidden modules keep their slot through a move; config round-trips; **a config with unknown extra fields decodes without throwing**; **a config missing fields decodes to defaults**; migration is idempotent (running it twice equals running it once); decode failure falls back to `.standard`. Extend `MenuBarPresetTests.swift` for block-shaped presets.

**Verify:** launch on a machine with pre-existing legacy Defaults and confirm the menu bar and dropdown render **identically** to Phase 3. Then delete the new keys and relaunch to confirm the migration re-runs cleanly.

---

### Phase 5 — The builder *(existing settings only)*

**Changes**
- Build the block `List` in its own container (not `PreferencesGroupedForm`) on both the Menu Bar and Dropdown tabs.
- `ForEach.onMove` + grab handle + `moveDisabled(!handleHovered)` + `.pointerStyle` + `.contentShape(.dragPreview, …)`.
- Hidden tray; locked `Settings & Quit` row; Reminders promoted to a real block.
- Gear popovers wired to **existing keys only** — Icon, Title (+ shorten), Countdown, Date, Progress, Week number, World clock (searchable), Greeting (name), Timeline *(existing on/off only)*, Meeting card, Agenda *(the Phase 1 settings: marker on/off, service icon, time column, title length)*, Reminders (overdue), Join, Bookmarks.
- Keyboard (⌥↑/⌥↓), context menu, `.accessibilityAction`, `.accessibilityValue` — **same commit**.
- Preset cards + the 10-second Undo snapshot.
- Builder ↔ preview spotlight linking.

**Files:** `Preferences/MenuBarTab.swift`, `Preferences/DropdownTab.swift`, new `Preferences/BlockRow.swift`, `Preferences/BlockGearPopover.swift`, `Preferences/SurfacePreview.swift`.

**Hostless logic + tests:** move/hide/show/reset-block mutations live on the model in MeetingBarLogic, not in the view — which also makes the eventual macOS 27 `reorderContainer(for:)` adoption a container-modifier swap rather than a rewrite. Extend `LayoutBlocksTests` for move-with-hidden-blocks, tray round-trip, and preset apply/undo. Extend `DropdownPanelNavigationTests` — `interactiveRows` identifies rows by content (`.bookmark(Int)` by index, `.event(String)` by id), and promoting Reminders out of the agenda's hardcoded Today→Reminders→Tomorrow position **changes arrow-key order**. Update those tests deliberately; do not patch until green.

**Verify:** drag a block and see the preview reorder. Click a gear and see only that block's options with the block spotlighted. Reorder by keyboard alone with VoiceOver announcing "block 4 of 8". Hide a block, quit, relaunch, drag it back — its config survives.

---

### Phase 6 — New style options

**Committed, not optional** (owner decision 5). The plan originally offered Phases 0–3 as a checkpoint; the owner chose the full run, in order.

**Also in this phase** (owner decision 6): duplicate blocks become creatable — two world clocks in different cities, a date on each side of the title. Requires `DropdownPanelContent` and every navigation row case to carry a block id, plus delete-with-confirmation. Block kinds for which duplication is meaningless declare themselves single-instance.

**Also in this phase:** the Calendar Window tab is filled out — first day of the week, show week numbers, and the per-day event cap before "+2 more", all currently hardcoded in `UI/Calendar/CalendarGridView.swift`.

**Changes:** every gear option in §4.5 not already present — the agenda marker enum and position, row density, timeline window/hour-lines/bar-shape/titles/scope, greeting summary content, join-block row set, reminder overdue style and tick box, guest cap/sort, notes length, detail field order, block spacing, progress-bar width, week-number prefix, one/two-line menu bar.

**Files:** `UI/StatusBar/DropdownPanelView.swift`, `UI/Views/DayTimelineView.swift`, `UI/StatusBar/DaySummaryHeaderView.swift`, `UI/StatusBar/MeetingSummaryView.swift`, `UI/StatusBar/StatusBarPresentation.swift`, `UI/StatusBar/StatusBarPresentation+MeetingBar.swift`, `Preferences/BlockGearPopover.swift`.

**Hostless logic + tests:** every new option is an enum on a `Config` struct in MeetingBarLogic. `DayTimelineLayout`'s `static let`s (`DayTimelineView.swift:38-45`) must become instance properties on a `DayTimelineLayoutCalculator` before any of it can vary — a prerequisite, not a detail. Extend `AgendaRowLayoutTests` for the full option matrix; add `DayTimelineLayoutTests`.

**Verify:** the owner's literal ask — set the agenda marker to a left border bar at the far-left edge, confirm it reaches the true row edge (outside `PanelRow`'s padding), and confirm it is legible in greyscale.

---

## 8. Risks, and what is deliberately not being done

### 8.1 Risks

| Risk | Mitigation |
|---|---|
| **The Phase 4 migration is the one-way door.** Eleven keys collapse into two Codable keys; every existing install has the old shape. | Versioned payload; `layoutBlocksMigrated` guard; write the new key only after a successful read of all legacy keys; **do not delete legacy keys for one release**; fall back to `.standard` on any decode failure; nine named test fixtures (§Phase 4). |
| **`AppSettings.swift` is the hidden cost centre.** 493 lines, 13 referencing files, every collapsed key inside an `Equatable` sub-struct. | Named explicitly as Phase 4 work with its own budget line. Do not discover it mid-phase. |
| **The builder cannot live in the existing Form.** `onMove` needs a `List`; macOS 15 clamps `GroupedFormStyle` to 600pt. | Verified in Phase 0 against the dead `MeetingsTab.swift:146` `.onMove`. The builder gets a deliberately styled inset-card container so the inconsistency reads as intentional. |
| **Hiding things behind gears can become hiding them forever.** | Settings search ships in **Phase 2**, three phases before the first gear exists, and the index test asserts all 92 keys are covered. A search hit must switch tab, force-expand the disclosure, open the gear popover, scroll to the control and flash it — build that navigation path in Phase 2 for sections and extend it to gears in Phase 5. |
| **The gear popover occludes part of the preview.** | Anchored `arrowEdge` toward the settings column; the edited block is spotlighted while everything else dims; tested at the new 860pt minimum. If it still occludes, the fallback is the block's own row expanding *below* the popover trigger — **not** an inspector column, which would re-inflate the window. |
| **Two renderers means style options cost double.** `MenuBuilder.swift` (69KB, NSMenu) structurally cannot express left-border markers, marker repositioning or density. | **Decision, written down now:** block styling is SwiftUI-panel-only. The classic menu is **feature-frozen for styling** but is *not* deleted and *not* degraded — Phase 1 ports its five missing visual states *into the panel* so nothing is lost. The Menu Bar / Dropdown tabs show a plain notice when the classic menu is selected in General ▸ Troubleshooting. |
| **Per-instance block ids change keyboard navigation.** `DropdownPanelNavigation.interactiveRows` identifies rows by content. | Handled in Phase 5 with deliberate test updates; duplicates are not exposed (below), which caps the blast radius. |
| **Removing settings generates complaints.** Six deletions plus three deleted option vocabularies. | Every deletion is listed in §3 with its reason. A plain-language **"What changed in Preferences"** entry in the What's New window names each removal and where its outcome now lives. Per-section reset makes the new structure safe to explore. |
| **Re-render storms are easy to reintroduce.** | State lives in `@Observable LayoutModel`; Defaults is written once on commit; never bind a key to a continuous control; `Self._printChanges()` while tuning. |
| **Preset cards can destroy a bespoke layout.** | `layoutUndoSnapshot` + a 10-second inline Undo. |
| **Eight tabs, not six.** | Accepted. `Filters` and `Calendar Window` are the two that keep the routing rule exception-free, and all six researched apps run 6–11 panes. The risk is real but it is the *right* risk: a rule with an exception is not a rule an overwhelmed user can hold, and eight predictable names beat six names plus a memorised exception list. Mitigations already in the plan: settings search from Phase 2, one-line purposes under each pane header, and presets so most users never scroll a pane. If Calendar Window still reads as thin after Phase 6, merge it into Dropdown — never into General. |

### 8.2 Deliberately not being done

- **No AI, no LLM, no natural-language input, no voice-to-text.** Absolute, and nothing above requires any.
- ~~**Duplicate blocks are modelled but not exposed.**~~ **Overturned by owner decision 6 — they ship.** `id: UUID` already makes two world clocks (different cities) or a date on each side of the title possible. Exposing it requires `DropdownPanelContent` and every navigation row case to carry a block id, plus a real delete with confirmation so the Hidden tray does not accumulate junk. That work lands in **Phase 6**, not Phase 5, so the builder ships first on the simpler one-instance-per-kind model and duplication is added deliberately rather than as a Phase 5 side effect. Blocks for which a duplicate is meaningless (a second Countdown of the same meeting) declare themselves single-instance on the block kind; the builder does not ban duplication globally.
- **The classic NSMenu renderer is not deleted.** It is feature-frozen for styling and kept as an escape hatch. Deleting it in the same release as this overhaul would remove the safety net and make previously-invisible losses newly attributable to this work.
- **Dropdown width, panel translucency, dividers, and global font size are not exposed.** All four are read as statics by three to nine files each (`MeetingSummaryView.swift:38`, `DropdownPanelView.swift:156-163`, `:228-230`, `StatusBarItemController.swift:44`) and would need to become injected environment values — plus the AppKit window sizing in `DropdownPanelPlacement.swift` also keys off the width. High cost, low ask. Deferred.
- **The other 22 `.lproj` bundles are not touched.** They already fall back to English for every MeetingBarNG-era key; renaming keys in `en.lproj` alone is correct and free.
- **Onboarding is not redesigned.** Out of scope, though two of its strings stop being reused as fake status text on the Calendars tab.
- **No macOS 26-only APIs are used for core behaviour.** `dragConfiguration(_:)` and `dragPreviewsFormation(.stack)` are cheap additive polish behind `#available` later. macOS 27's `reorderable()` / `reorderContainer(for:)` are confirmed absent from this machine's SDK; keeping reorder mutations in the model makes that adoption mechanical.
- **`.inspector` is not used anywhere.** One config mechanism only.
