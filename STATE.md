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
- **The rebrand changes are already applied on disk** — verify with `git status`, do NOT re-apply.
- Build/test: `make build`, `make test`, `make test-logic`, `make lint` (needs Xcode + SwiftLint;
  local signing via git-ignored `XCConfig/DevTeamOverride.xcconfig`).

---

## Current state — 2026-07-27
**Shipped and pushed. `master` and `dev` are both at the same commit; working tree clean.**
Version `0.2.0` (build 20). The dated blocks below are kept as history — read this one first.

Everything since 2026-07-17 has landed on `master`, so the "committed locally, not pushed"
notes further down are historical, NOT current. `make build`, `make lint`,
`make validate-strings`, `swift test` (568 hostless) and the app-target suites all pass here.

**The two facts that orient everything else:**
- **The SwiftUI dropdown is the DEFAULT.** `useSwiftUIDropdown` ships `true`;
  `DropdownPanelView` (SwiftUI in a bespoke `NSWindow`) is what users see, and
  `MenuBuilder`'s classic `NSMenu` is the opt-out fallback. **Both are maintained** — a
  change to dropdown content usually has to land twice. Source comments call this
  "NSMenu parity".
- **`MeetingBarLogicTests` cannot see app-target files.** `Package.swift` uses an explicit
  `sources:` allowlist, not a glob. A green `swift test` says nothing about
  `DropdownPanelView`, `MenuBuilder`, or the Preferences panes — those need
  `MeetingBarNGTests`.

**Shipped since the Phase 2 slice below:** Preferences rebuilt as an 8-pane
`PreferencesShellV2` (the old `PreferencesView` is dead code) with settings search and
per-pane reset; command bar; month calendar grid; camera/mic preview; world clock; Apple
Reminders; in-app event editor; event search; meeting prep links.

**Landed 2026-07-27** (this session):
- **More actions** — was a SwiftUI `Menu` that would not sit on the shared row grid; now a
  plain `PanelRow` that flies out a native `NSMenu`, with hover-dwell and a watchdog that
  hands the panel back when the pointer returns.
- **Dedup fix** — copies of one meeting no longer survive on differences the user cannot
  see (exact-second starts, differing end times, invisible whitespace).
- **Dropdown density** — agenda sections cap at `dropdownMaxEventRows` (10) with a
  "+N more" row; row action buttons mute beyond `eventActionHighlightMinutes` (2).
- **Menu bar** — boldens the next meeting once it is imminent
  (`menuBarHighlightImminentEvent`, on by default). Shared rule: hostless
  `EventActionProminence`, used by all four surfaces that draw it.
- **Preferences window** — real `NSToolbar` (so the titlebar draws chrome and the OS
  supplies its own material), opens at its intended size rather than its minimum, the
  Dropdown pane drops its preview instead of clipping it, and window geometry now
  persists.
- **Docs/comment sweep** — see "Open decisions" below for what the audit found.

---

## Current state — 2026-07-17 (historical)
**Phase 1 (identity + attribution cleanup): DONE — committed locally on branch `chore/rebrand-meetingbarng` (not pushed).**

Scope was deliberately repo-identity / docs / metadata only — the code/UI/UX/feature overhaul
is future work (see `ROADMAP.md`). No Swift source, localization, or Xcode project files changed,
so the build is unaffected.

Changed (11 modified, 2 new):
- **New:** `NOTICE` (Apache-2.0 derivative attribution), `ROADMAP.md` (Dot-parity launch goal + deferred backlog).
- **Rebranded:** `README.md` (full rewrite), `CHANGELOG.md`, `CONTRIBUTING.md`, `CONTACT.md`,
  `SECURITY.md`, `.all-contributorsrc`, `.github/FUNDING.yml`, `.github/pull-request-template.md`,
  `.github/ISSUE_TEMPLATE/bug_report.yaml`, `docs/ARCHITECTURE.md`, `MeetingBarNG/Info.plist`
  (`NSHumanReadableCopyright` retains Andrii Leitsius © + adds Chykalophia ©).

## Phase 2 — Slice 1: Composable menu bar — DONE locally (branch `feat/composable-menu-bar`)
Metadata cleanups landed as `1a8148d` on `chore/rebrand-meetingbarng`; the feature branch
`feat/composable-menu-bar` is cut from that. **Opt-in** — the classic menu bar is byte-for-byte
unchanged until a user enables a composition.

- **Pure logic** — `MeetingBarNG/UI/StatusBar/StatusBarPresentation.swift`: `MenuBarTokenKind`
  (icon/title/countdown/date/clock), `CountdownStyle` (`2h` / `2h 30m` / `2:30`),
  `MenuBarDateStyle`, `MenuBarComposition`, `MenuBarComposedSettings`,
  `MenuBarCompositionPolicy`, `StatusBarPresenter.composedPresentation(...)`.
- **Persistence** — `Extensions/DefaultsKeys.swift`: `menuBarTokens`, `menuBarCountdownStyle`,
  `menuBarDateStyle`. Adapters + legacy derivation in `StatusBarPresentation+MeetingBar.swift`.
- **Render** — `UI/StatusBar/StatusBarItemController.swift`: `updateTitle()` uses the composed
  presenter when a composition exists; new keys wired into the Defaults observers.
- **UI** — `Preferences/AppearanceTab.swift`: `MenuBarComposerSection` (enable toggle seeded from
  the user's classic settings, add/remove/reorder, countdown/date pickers, live preview). +24 en keys.
- **Tests** — `MeetingBarLogicTests/StatusBarCompositionPolicyTests.swift` (26 cases).

Verified here: `swift build` (logic) green; all 26 logic assertions pass via a throwaway
`swift run` verifier (XCTest can't run without Xcode here); `make validate-strings` OK.
⚠️ **Could NOT run here (no Xcode/SwiftLint): `make build`, `make test`, `make lint`** — run these
on an Xcode machine before opening a PR. §4(b) change notices added to modified upstream-headered
files (`StatusBarItemController.swift`, `AppearanceTab.swift`, `DefaultsKeys.swift`).

## Attribution model (keep intact)
- Original **MeetingBar © Andrii Leitsius (`leits`)** stays credited: per-file source headers are
  **untouched** (Apache-2.0 §4(c)), plus `NOTICE`, README credits, and contributors list.
- When you later modify a source file, retain its header and add a change notice (§4(b)).

---

## Open decisions / follow-ups (need Peter)
- [x] `.all-contributorsrc` login corrected to **`PiotrKrzyzek`** (verified via `gh api user`); avatar + profile now point at that GitHub account.
- [x] `.github/FUNDING.yml` enabled with `custom: ["https://chykalophia.com"]` (maintainer's own domain; no upstream-author handles). Add a GitHub Sponsors handle later if desired.
- [ ] GitHub repo **"About" blurb** is server-side metadata (not a file) — set via `gh repo edit` if wanted (not touched; no remote changes made).
- [x] **Committed** on `chore/rebrand-meetingbarng` (Phase 1). Since merged; `master` and
      `dev` both carry it. The "not pushed" note above is historical.
- [x] **Doc/comment audit (2026-07-27).** Four things were actively misleading and are
      fixed: a comment claiming the classic `NSMenu` was still the default (it is the
      fallback); a header describing "More actions" as a SwiftUI `Menu` (it is a native
      `NSMenu`); `PreferencesShellV2` claiming to live in a SwiftUI `Settings` scene (there
      is none — `WindowCoordinator` hand-builds the window); and two Preferences files each
      claiming to be "the only place that requests Reminders access" while both call
      `requestAccess()`. Also found a REAL bug, not a doc nit: the default AppleScript
      template declared 11 parameters while the app sends 14, so any user enabling on-start
      scripts with the stock template would have had the script rejected.

## Next work
- **Nothing is mid-flight.** Both branches are pushed and in sync; there is no half-applied
  change to pick up. Start from `ROADMAP.md`.
- **Nearest unchecked Dot-parity items:** copy meeting ID, location autocomplete, calendar
  picker via command/slash, quick date jump, per-event custom reminder times, themes, date
  markers, hide empty days, month⇄week toggle *in the menu bar* (the calendar window
  already has one). Natural-language event creation stays a non-goal.
- **Rename backlog still open** (the rest is done): Keychain / `Defaults` suite names
  derived from the old bundle id — now the load-bearing one, since the id already changed
  and existing installs need a migration path — and the Mac App Store app id.
- **Re-enable the direct Google provider:** onboarding's picker is hard-limited to macOS
  Calendar (`CalendarSourcePresentation.all`); credentials alone are not enough.
- **Explicitly parked as low priority** (see `ROADMAP.md` → "Deliberately deferred"):
  unit tests for the tomorrow look-ahead internals, and non-English localization.
