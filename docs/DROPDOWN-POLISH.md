# Dropdown polish pass — plan of record

Owner review of the shipping panel against the approved HTML mockup, 2026-07-28. The mockup is
`dropdown-mockup.html`; where this document says "the demo", that is what it means.

Scope note: this is a POLISH pass over a panel that already works. Nothing here is a rewrite.
Two items (P3, P5) are structural and need a decision before they are built.

---

## 0. Decisions needed before building

| # | Question | Recommendation |
|---|---|---|
| D1 | Merge "Next meeting" card and the "Next · … in 3h" progress bar into ONE module? | **Yes.** See P5. |
| D2 | Move the date out of the agenda header ("Today (Tue, 28 Jul)") up to the greeting line? | **Yes**, with a setting. See P4. |
| D3 | Timeline: keep the relative −3h/+6h window, add a full-day style, or both as options? | **Both, as a style option.** See P3. |
| D4 | "Join next meeting" when the next meeting has no link: keep hiding it, or show it disabled? | **Keep hiding.** See §Answers. |

---

## 1. Answers to the questions raised

**"Why does the demo have *Join next meeting* and mine doesn't?"**
Not a bug and not a regression. `joinSectionEvent` returns `nil` unless the next event actually has
a meeting link; the demo's next meeting had one, and "Evening Journaling" does not. A disabled row
would be honest too, but a permanently greyed row in a short list is noise — the action reappears
the moment there is something to join.

**"Why is the left of the timeline empty?"**
The timeline is a RELATIVE window: three hours behind, six ahead. The left third is the past, and
nothing was scheduled there. The demo draws a compressed full DAY (9→9), which always has content
on both sides. So this is a difference in model, not padding — fixing it means offering the day
style, not nudging insets. (The right-edge clipping at "10 PM" IS a padding bug, and is separate.)

**"Is the date in the agenda header configurable?"**
No. Today the header is always `Today (Tue, 28 Jul)`. See P4.

**"Is the plain-row spacing different because of my density setting?"**
Partly. Rows read `metrics.rowVerticalPadding`, so density does move them. But the action rows
("Create meeting", "More actions…", "Preferences…") also inherit the agenda row's grid, which the
demo does not — it gives action rows their own, tighter rhythm. Both need checking against the
demo at Medium before changing numbers.

---

## 2. Work packages

Ordered so the cheap, high-visibility structural fixes land first.

**Done:** P1 `c369207e` · P2 `c369207e` · P3 `5df99a15` · P5 `(this commit)`.
Plus two items raised mid-review: the row hover restyle (`3128663d`) and the card
fill/rim, measured against the mockup's CSS rather than adjusted by eye — it is
`rgba(255,255,255,.09)` on a dark glass card and the app shipped `0.06`.

**Remaining:** P4, P6, P7, P8, P9.

### P1 — Dividers and container padding *(highest visual impact, low risk)*
- Dividers currently sit between EVERY module and run edge to edge (`Divider().padding(.vertical, 4)`).
- The demo has dividers ONLY above the plain-text action rows — the header, timeline, up-next,
  calendar and agenda run together without rules.
- Dividers must be inset to the row grid, not full-bleed.
- Revisit the panel's outer padding at the same time; the rules currently disguise its absence.

### P2 — Card inner padding
- Content must never touch a card's border. "10 PM" is clipped by the timeline card's right edge.
- Optional flourish: fade the timeline's leading/trailing edges rather than hard-clipping.

### P3 — Timeline styles *(structural, needs D3)*
- Today: one relative window (−3h/+6h) with capsule segments.
- Demo: compressed full-day bar with a marker per meeting.
- Proposal: a `TimelineStyle` preference — `relative` (today's) and `day` (the demo's) — modelled
  the same way `MeetingProgressStyle` was: hostless enum, policy decides, renderer draws.

### P4 — Agenda header and the date *(needs D2)*
- Demo: a small, uppercase, letter-spaced `TODAY` label. App: `Today (Tue, 28 Jul)` in body type.
- Proposal: agenda header becomes the demo's label; the date moves to the greeting's secondary
  line, which already reads "11 meetings today · 7h 42m free" and is the natural home for it.
- Setting to control whether the greeting shows the date.

### P5 — Merge the two "next" components *(structural, needs D1)*
- `meeting` module renders the "Next meeting" card; `upNext` module renders the "Next · … in 3h"
  progress bar. They describe the SAME event and are configured independently, so both can show at
  once — which is what happened in the review screenshot.
- Proposal: one Next module. The progress bar becomes a display option INSIDE it (off / bar /
  ring), not a second module. Retire `upNext` from the composer, migrating anyone who had it on to
  the merged module with the bar enabled.

### P6 — Agenda row polish
- Alignment, time-column weight, and row rhythm to match the demo.
- Join button: title currently truncates hard next to it. Replace with a gradient mask so the title
  fades UNDER the button.
- Add the demo's `+ ⌘N` button to the agenda section header.

### P7 — Greeting header
- Icon tile is oversized against the demo.
- Match the demo's greeting and secondary-line type scale and weights.
- Settings for what the greeting shows (name, counts, free time, date — see P4).

### P8 — Footer and action rows
- Action rows and the pinned footer (`Preferences…`, `Quit`) need the demo's spacing, which is
  tighter than the agenda grid they currently inherit.

### P9 — Type pass
- A general weight/size sweep against the demo once P1–P8 have settled the layout. Doing it earlier
  means measuring type against padding that is about to change.

### Deferred
- **More vibrancy / colour in the surface.** Owner flagged it as a maybe. The current surface is
  `.menu` vibrancy, which matches native menus by construction (see DROPDOWN-MODERNIZATION §7).
  Adding colour means leaving that guarantee, so it is a deliberate later decision, not polish.
- **Coloured calendar dots.** Blocked upstream: EventKit-only integration, no per-calendar colour
  from Google.
