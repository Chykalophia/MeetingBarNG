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

## Current state — 2026-07-17
**Phase 1 (identity + attribution cleanup): DONE — committed locally on branch `chore/rebrand-meetingbarng` (not pushed).**

Scope was deliberately repo-identity / docs / metadata only — the code/UI/UX/feature overhaul
is future work (see `ROADMAP.md`). No Swift source, localization, or Xcode project files changed,
so the build is unaffected.

Changed (11 modified, 2 new):
- **New:** `NOTICE` (Apache-2.0 derivative attribution), `ROADMAP.md` (Dot-parity launch goal + deferred backlog).
- **Rebranded:** `README.md` (full rewrite), `CHANGELOG.md`, `CONTRIBUTING.md`, `CONTACT.md`,
  `SECURITY.md`, `.all-contributorsrc`, `.github/FUNDING.yml`, `.github/pull-request-template.md`,
  `.github/ISSUE_TEMPLATE/bug_report.yaml`, `docs/ARCHITECTURE.md`, `MeetingBar/Info.plist`
  (`NSHumanReadableCopyright` retains Andrii Leitsius © + adds Chykalophia ©).

## Attribution model (keep intact)
- Original **MeetingBar © Andrii Leitsius (`leits`)** stays credited: per-file source headers are
  **untouched** (Apache-2.0 §4(c)), plus `NOTICE`, README credits, and contributors list.
- When you later modify a source file, retain its header and add a change notice (§4(b)).

---

## Open decisions / follow-ups (need Peter)
- [x] `.all-contributorsrc` login corrected to **`PiotrKrzyzek`** (verified via `gh api user`); avatar + profile now point at that GitHub account.
- [x] `.github/FUNDING.yml` enabled with `custom: ["https://chykalophia.com"]` (maintainer's own domain; no upstream-author handles). Add a GitHub Sponsors handle later if desired.
- [ ] GitHub repo **"About" blurb** is server-side metadata (not a file) — set via `gh repo edit` if wanted (not touched; no remote changes made).
- [x] **Committed** on `chore/rebrand-meetingbarng` (Phase 1). Not pushed. Next:
      `git push -u origin chore/rebrand-meetingbarng` then open a PR into `master`.

## Next work
- **Phase 2 = the overhaul.** See `ROADMAP.md` for the Dot productivity-parity feature set
  (natural-language event creation is an explicit non-goal) and the deferred **rename backlog**
  (bundle id `leits.MeetingBar`, StoreKit ids, keychain/defaults suites, `PRODUCT_NAME`/scheme,
  MAS app id, 20-language in-app strings, in-app support/funding URLs in
  `MeetingBar/Utilities/Constants.swift`) — each needs its own migration care.
