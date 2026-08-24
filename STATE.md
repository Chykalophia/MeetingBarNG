# STATE — MeetingBarNG

> Per-repo working state (Chykalophia convention). Durable plan lives in `ROADMAP.md`;
> attribution in `NOTICE`. This file is the "where are we / what's next" handoff so any
> fresh session is self-sufficient without chat history.

**Repo:** `/Users/peterkrzyzek/Development/MeetingBarNG` · remote `github.com/Chykalophia/MeetingBarNG` (fork of `github.com/leits/MeetingBar`, Apache-2.0)
**What it is:** a Swift 6 / AppKit + SwiftUI macOS menu-bar meeting app. Modernization fork by Peter Krzyzek / Chykalophia.

---

## ⚠️ Session setup (read first)
- **Root your session at this repo** (`/Users/peterkrzyzek/Development/MeetingBarNG`). A prior
  session was mis-rooted at a sibling (`SendBriefs`), which is why paths here are absolute.
- Build/test: `make build`, `make test`, `make test-logic`, `make lint` (needs Xcode + SwiftLint;
  local signing via git-ignored `XCConfig/DevTeamOverride.xcconfig`).
- **There is no ClickUp board for this project.** Verified 2026-08-24: no list, folder, or task
  anywhere in the Chykalophia workspace. `ROADMAP.md` + this file are the only tracking. Do not
  go looking for tickets, and do not create them without asking — repo-only is a deliberate choice.

---

## Current state — 2026-08-24
**Version `0.3.0` (build 21). `master` and `dev` are in sync; working tree clean; no open PRs.**

`make test-logic` passes (90.97% line / 96.74% region coverage on the hostless module). Zero
`TODO`/`FIXME`/`HACK` markers in Swift source. Not re-verified this session: `make build`,
`make test-app`, `make lint` — those need a full Xcode cycle.

**The two facts that orient everything else:**

- **There is ONE dropdown renderer.** The classic `NSMenu` path was **deleted** in `9c178efd`
  (2026-07-28) along with the `useSwiftUIDropdown` preference. `DropdownPanelView` (SwiftUI in a
  bespoke `NSWindow`) is the only dropdown. Any comment or doc implying a "land it twice"
  NSMenu-parity constraint is history — see the known-stale-comments note below. What survived
  the deletion, correctly, is the RIGHT-click `QuickActionsMenu`, still an `NSMenu`.
- **`MeetingBarLogicTests` cannot see app-target files.** `Package.swift` uses an explicit
  `sources:` allowlist, not a glob. A green `swift test` says nothing about `DropdownPanelView`
  or the Preferences panes — those need `MeetingBarNGTests`.

### 🚨 The gap that matters: nothing is distributable
`v0.2.0` and `v0.3.0` are public, non-draft GitHub releases with **zero attached assets**, and
there is no packaging anywhere — no dmg, no signing for distribution, no notarization, no release
workflow. CI (`ci.yml`) only builds and tests; `make build-release` merely compiles. `README.md`
has no Install or Download section, going straight from "Where we are headed" to "Build from
source". **Two versions have shipped and nobody without Xcode can run the app.** Every feature
below is currently invisible to users. This is the next work.

### Shipped since 0.2.0 (2026-07-28) — 33 commits
- **Dropdown polish pass** (2026-07-28, ~20 commits) — the whole plan of record in
  `docs/DROPDOWN-POLISH.md`: timeline styles (Track / Bar / Minimal) and coverage (Around now /
  Whole day) as two separate settings; one merged "Next meeting" card with per-field switches;
  date moved to the greeting; agenda rows on the design grid with a fading title edge; glass
  hover/selection; density reaching card padding; rules only where they separate something.
- **Month calendar** — dots on every day with meetings, not just today; self-fetching month,
  keeps known days in flight, preserves dots on a failed fetch, hover highlight.
- **Menu-bar meeting progress** (`286fa425` + three fixes) — four styles plus none, drawn in the
  menu bar's own text colour so it survives any wallpaper. `MeetingProgressPolicy`, 16 tests.
- **Legibility** — Reduce Transparency now respected (it was honoured nowhere before); contrast
  floor so the panel holds up over pale wallpapers.
- **Preferences** — sidebar pinned to 215pt and non-resizable, search field under the title bar,
  live preview updates on any setting change.
- **`meetingbar://dropdown` deep link** + a debug panel pin (`d5344add`, `c62f3b8c`).
- **2026-08-05 (`4b48d42b`)** — menu-bar **Join chip** (`MenuBarJoinActionPolicy`,
  `MenuBarActionChipGeometry`, `MenuBarActionChipOverlayView`; left-click hit-tests the chip before
  opening the panel), **countdown lead-time control** (`menuBarCountdownLeadMinutes`), and a
  **DEBUG-only harness** (`DebugHarnessWindow` / `DebugHarnessView` / `DebugScenario`) for injecting
  synthetic events. Excluded from release builds. This work is not yet reflected in
  `docs/MEETINGBARNG-FEATURES.md`.

### Doc accuracy, as of this reconciliation
- `docs/DROPDOWN-MODERNIZATION.md` — **accurate.** 9 of 10 items done; item 7 (meeting-relative
  progress in the dropdown card) is the only one not started. Read it before touching the panel;
  it carries the locked design rules.
- `ROADMAP.md` — **parity checkboxes verified against the code.** No unchecked item has secretly
  shipped: there is no code for themes, date markers, hide-empty-days, location autocomplete,
  quick date jump, or per-event reminder times. Reminder snooze exists; location-trigger snooze
  does not.
- **Known stale comments (not yet fixed):** ~20 comments across `DropdownPanelView.swift`,
  `DaySummaryHeaderView.swift`, `DaySummaryGreeting.swift` and `MeetingSummaryPresenter.swift`
  still cite `MenuBuilder`, several in present tense ("Mirrors `MenuBuilder.buildJoinSection`",
  "so the two dropdowns can never…"). The type is deleted. Treat them as historical notes on where
  behaviour came from, not as a live constraint.

---

## Current state — 2026-07-27 (historical)
Version 0.2.0 groundwork. Preferences rebuilt as an 8-pane `PreferencesShellV2` (the old
`PreferencesView` is dead code) with settings search and per-pane reset; command bar; month
calendar grid; camera/mic preview; world clock; Apple Reminders; in-app event editor; event
search; meeting prep links. Cross-calendar dedup tightened so copies of one meeting no longer
survive on differences the user cannot see. Menu bar boldens the next meeting once imminent
(`menuBarHighlightImminentEvent`); the shared rule is hostless `EventActionProminence`, used by
every surface that draws it.

A doc/comment audit that session fixed four actively misleading claims and found a REAL bug: the
default AppleScript template declared 11 parameters while the app sends 14, so the stock template
would have been rejected.

## Phase 1 / Phase 2 Slice 1 (historical)
Identity + attribution cleanup landed on `chore/rebrand-meetingbarng`; the composable menu bar
landed on `feat/composable-menu-bar`. Both branches merged to `master` and were **deleted
2026-08-24** along with their stale PR #2. The composable menu bar is now the default path, not
opt-in: `MenuBarTokenKind`, `CountdownStyle`, `MenuBarDateStyle`, `MenuBarComposition`,
`MenuBarCompositionPolicy` in `UI/StatusBar/StatusBarPresentation.swift`.

---

## Attribution model (keep intact)
- Original **MeetingBar © Andrii Leitsius (`leits`)** stays credited: per-file source headers are
  **untouched** (Apache-2.0 §4(c)), plus `NOTICE`, README credits, and contributors list.
- When you modify a source file, retain its header and add a change notice (§4(b)).

---

## Shipping: `master` is protected
Set up 2026-08-24. Direct pushes are rejected — every `dev` → `master` ship goes through a PR, and
every commit must be signed. SSH commit signing is configured repo-locally; the full mechanism,
including two GitHub API gotchas that will otherwise cost an hour, is in the project memory note
`shipping-dev-to-master`. Short version: open a PR, then `gh pr merge <n> --merge --admin`.

---

## Next work
1. **Ship an installable build — pipeline BUILT 2026-08-24, never yet run.**
   `.github/workflows/release.yml` archives → signs (Developer ID, hardened runtime) →
   exports → packages a dmg → notarizes → staples → uploads the dmg plus a `.sha256` to the
   tag's release. `make release-local` drives the same chain locally. Runbook and
   troubleshooting: [`docs/RELEASING.md`](docs/RELEASING.md).
   **Blocked on Peter only:** four repo secrets — `MACOS_CERTIFICATE_P12`,
   `MACOS_CERTIFICATE_PASSWORD`, `AC_APPLE_ID`, `AC_PASSWORD`. Then either re-run the
   workflow against `v0.3.0` or tag `v0.4.0`.
   **One decision embedded there:** without a `MACOS_PROVISIONING_PROFILE` secret the build
   drops `com.apple.developer.usernotifications.time-sensitive` (Apple gates it behind a
   profile), so meeting alerts stop breaking through Focus. The workflow ships either way and
   logs a warning when the profile is absent. For a meeting app this is worth fixing properly —
   see RELEASING.md §1.
2. **Defaults migration for upstream MeetingBar users.** The bundle id changed
   `leits.MeetingBar` → `com.chykalophia.MeetingBarNG` (2026-07-23) and `UserDefaults` is
   bundle-id-scoped. Nothing in the source reads the old domain — the four existing migrations
   (`StatusBarTitleFormatMigration`, `TimeFormatDefaultMigration`, `DropdownModuleMergeMigration`,
   `MenuBarTimeFormatMigration`) all move NG's *own* keys forward. A switcher loses every setting.
   Coupled to item 1: it only bites once people can install.
3. **Dropdown item 7** — meeting-relative progress on the dropdown card. Bar fills toward start,
   full exactly when Join un-mutes, reusing `MeetingProgressPolicy` and the shared
   `eventActionHighlightMinutes` threshold.
4. **Dot-parity leftovers**, smallest first: copy meeting ID, month⇄week toggle *in the menu bar*
   (the calendar window has one), hide empty days, date markers, per-event reminder times,
   location autocomplete, quick date jump, themes, keyboard-first nav beyond the panel.
5. **Rename backlog still open:** Keychain / `Defaults` suite names derived from the old bundle id
   (see item 2), and the Mac App Store app id.
6. **Re-enable the direct Google provider:** onboarding is hard-limited to macOS Calendar
   (`CalendarSourcePresentation.all`); credentials alone are not enough.

**Explicitly parked as low priority** (see `ROADMAP.md` → "Deliberately deferred"): unit tests for
the tomorrow look-ahead internals, and non-English localization.
