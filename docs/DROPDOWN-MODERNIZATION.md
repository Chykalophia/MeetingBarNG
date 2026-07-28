# MeetingBarNG — Dropdown & Menu Bar Modernization

**Status:** in progress. Started 2026-07-27. This is the progress note of record for the
visual overhaul of the dropdown panel and the menu-bar item.

**Reference:** [Dot](https://www.trydot.app)'s dropdown, supplied by the owner as a demo
screenshot. Copied selectively — see §2 for what was deliberately not copied.

**Scope constraint (absolute, inherited):** no AI, no LLM features, no natural-language
event creation, no voice-to-text.

---

## 0. Owner decisions — these OVERRIDE anything below

| # | Question | Decision |
|---|---|---|
| 1 | Which chrome | **Glass where the OS supports it, modernized material where it does not.** Not either/or. |
| 2 | Inline month calendar | **Keep as an option** — a user might really want it. |
| 3 | Year/day progress bars | **Rejected as shown** ("those don't look useful"). But the *concept* survives, re-aimed at time-to-meeting-start/end. |
| 4 | Menu-bar progress style | **Offer all four, plus none.** "All of them are really cool." |
| 5 | Row density | **Small / Medium / Large, default Medium.** |
| 6 | Component treatment | **Cards for widgets, flat for lists** (owner's own question, confirmed). |

---

## 1. Locked design rules

These are decided. Anything new should conform or explicitly argue otherwise.

**One glass layer.** The panel is the glass surface. Inner cards use a plain fill, never
`glassEffect`, even on macOS 26. Stacked translucency does not compound refraction — it
accumulates haze and eats the contrast the agenda needs.

**Card = widget, flat = list.** A component with its own internal coordinate system (timeline,
month grid, meeting card) gets a bounded frame. Rows-as-the-unit (agenda, actions, footer) stay
flat: full-bleed hover targets, unbroken left edge for scanning. A card costs ~24pt of the
panel's 330 — a grid absorbs that, a truncating event title cannot.

**System surfaces, not hand-built ones.** `glassEffect` / `.regularMaterial`, never a
hand-rolled blur. The OS then tracks light/dark, accent and reduce-transparency for us, and the
look ages with the platform instead of freezing at one release.

**Radius follows the surface.** 20pt glass, 16pt material. `WindowStylePolicy.applyRoundedCorners`
masks the window layer from the *same* property, so the AppKit mask and the SwiftUI shape cannot
disagree — a tighter mask clips the shape, a looser one leaks window past the corner.

**One notion of "now-ish".** `eventActionHighlightMinutes` drives the muted/bright Join button,
the menu-bar bolding, and (planned) the progress colour shift. One threshold, every surface —
never a second setting that can disagree.

**Density is vertical only.** Panel width is identical across all three densities, so the hosting
window never resizes underneath the user. Type scales with padding; padding alone reads as broken.

---

## 2. Deliberately NOT copied from Dot

- **Year / day progress bars.** Lowest information-per-pixel thing on the reference panel.
  "1.2% of today" is trivia. Replaced by the meeting-relative idea (§3, item 6).
- **Dim-until-imminent in the menu bar.** The literal mirror of the dropdown treatment, and
  wrong here: the menu bar's job is to be readable all day, and `.inactive` already means
  "past/declined" there. Emphasise-when-close was chosen instead.
- **A date-only day header.** Our greeting (`Good afternoon, Peter · 13 meetings today · 8h 25m
  free`) carries more than Dot's `Mon, Feb 16 · 6 events today`. Kept, and given Dot's inline
  actions.

---

## 3. Status

| # | Item | Status | Notes |
|---|---|---|---|
| 1 | Panel chrome — glass + material fallback | **Done** `d60c6c4c` | `glassEffect` on macOS 26, `.regularMaterial` below. Radius follows surface. |
| 2 | Row density — Small/Medium/Large | **Done** `d60c6c4c` | `DropdownDensity` + environment-injected grid. 10 hostless tests. |
| 3 | Cards (`PanelCard`) | **Done** `d60c6c4c` | Timeline carded. Container ready for reuse. |
| 4 | Day header quick actions | **Done** `d60c6c4c` | Create / command bar / preferences. Three, not four. |
| 5 | Calendar — window reachable from panel | **Done** `d60c6c4c` | Closed a parity gap: it was right-click-only. |
| 6 | Calendar — inline month module | **Done** `8611e7b2` | `CompactMonthGridView`, OFF by default. Limitations in §4. |
| 7 | Meeting-relative progress — dropdown card | **Not started** | Bar filling toward start; full exactly when Join un-mutes. |
| 8 | Menu-bar progress — 4 styles + none | **Done** `2007165e`+ | `MeetingProgressStyle`. All four verified in the menu bar. See §5. |
| 9 | Meeting card — card treatment | **Done** `2007165e` | Adopts `PanelCard`; `MeetingSummaryView` takes its inset as a parameter. |
| 10 | Density applied to cards | **Not started** | Cards use fixed padding; should read the grid. |

---

## 4. Known limitations of what has shipped

Recorded so they are not rediscovered as bugs.

- **Inline calendar dots cover today and tomorrow only.** The panel's state holds those two days.
  A month of dots needs a month-range fetch and its async lifecycle threaded through
  `DropdownPanelHandlers`. Tapping a day opens the calendar window, which has the whole month.
- **Inline calendar is not keyboard-navigable.** A grid needs four directions;
  `DropdownPanelNavigation` has two. Wiring day cells into Up/Down would steal those keys from
  the list.
- **Inline calendar is panel-only.** The classic `NSMenu` skips it. It *could* be hosted via
  `NSHostingView` like the timeline, but a month grid is the least menu-shaped thing in the app.
- **Panel shadow is derived from content alpha.** `WindowStylePolicy` notes AppKit derives the
  drop shadow from *opaque* SwiftUI content, and the content is now translucent. If the panel
  ever reads as flat against the desktop, the fix is an explicit window shadow. Verified visually
  on macOS 26 (see §6): the desktop reads through the panel and the shadow is present.
- **Density does not yet reach `PanelCard`.** Its padding is fixed; item 10 above.

---

## 5. Menu-bar progress — design notes for item 8

The one surface with no visual precedent in the app. Mocked and reviewed; four styles were
liked, so all four ship as options with `none` as the default.

**Why it is the biggest remaining piece:** the menu bar renders as an `NSAttributedString`
today, which is why the existing day/year progress token is drawn with Unicode block characters
(coarse, 8 discrete steps, glyph width varies by font). Any drawn bar means a custom `NSView`
inside the status item. That is achievable — the menu bar is already tokenised, so it is a
renderer swap rather than a model change — but it is a different order of work from the panel.

| Style | Width cost | Note |
|---|---|---|
| Underline | 0pt | Subtlest; easy to miss. |
| **Ring around the icon** | 0pt | *Recommended default when enabled.* Reads instantly, nothing truncates, survives any wallpaper. |
| Capsule fill | 0pt | Most Dot-like, most visible, loudest. |
| Leading mini-bar | ~32pt | Clearest as "progress", but menu-bar width is the scarcest resource in the app. |

Modelled as a **style**, not four new `MenuBarTokenKind` cases: underline/ring/capsule are
renderings of the title and icon that already exist, not independent tokens that could be added
twice or reordered nonsensically.

Colour follows §1's shared threshold: the accent colour inside `eventActionHighlightMinutes`, red
while the meeting runs, counting through it; secondary before that.

### How it shipped

`MeetingProgressPolicy` (hostless, 16 tests) decides how full and what phase; the renderer only
draws. Not to be confused with the pre-existing `MenuBarProgressStyle`, which says what the
event-independent `.progress` TOKEN measures (day or year) — different question, adjacent name.

- **Fill window is one hour**, not `eventActionHighlightMinutes`. That threshold answers "should
  the Join button shout" and defaults to two minutes, at which a bar snaps empty→full with no
  useful middle. Full means *now*: the fraction is exactly 1.0 at the start instant.
- **Nothing is drawn when no meeting is close** — `nil`, not a zero-fraction frame. An empty ring
  sitting there all morning says only "a meeting exists eventually".
- **Underline / ring / capsule are an overlay `NSView` on the status-item button**, not a re-render
  of the item. AppKit owns everything that makes menu-bar text look native (light/dark, the
  inversion while the menu is open, accessibility); compositing under it would mean reimplementing
  all of that. The cost is that region-filling styles are drawn *around* the text rather than
  behind it, and stay translucent so the text reads first.
- **The ring takes the image slot when there is no icon.** A ring needs something to encircle; with
  a title-only composition an overlay ring lands on the first letter. Then it becomes the icon.
- **The bar always takes the image slot**, which is why it is the one style that costs width.

---

## 6. Inspecting the panel (development)

The panel dismisses itself the instant anything else takes focus, which is correct for a menu and
makes it impossible to screenshot — `screencapture` takes focus by existing. Two aids, both
DEBUG-only:

```sh
open "meetingbar://dropdown-debug"     # panel in a window that STAYS OPEN; run again to close
defaults write com.chykalophia.MeetingBarNG debugPinDropdownPanel -bool true   # real panel, pinned
```

`DropdownInspectorWindow` is the same borderless surface the real panel uses — `WindowCoordinator`
builds both through one `installDropdownPanelSurface`, so what gets inspected cannot drift from
what ships. It simply omits the `resignKey` override. Prefer it over the pin: it needs no relaunch
and leaves the shipping panel's behaviour untouched.

> **If a `meetingbar://` link seems to do nothing, check which bundle answered it.**
> LaunchServices resolves the scheme across *every* registered copy, and a stale build wins on
> recency, not on being the one you launched. This masqueraded as a broken deep link for a whole
> session: `build/Build/Products/Debug/` (an old layout), `build/MeetingBarNG.app`, and a
> scratchpad copy were all still registered, and the old bundle predated the deep link, so it
> answered and did nothing. Diagnose with `ps -Ao pid,comm | grep MeetingBar` — more than one PID,
> or a path you did not expect, is the bug. Clear with `lsregister -u <path>` plus `rm -rf`.

---

## 7. Liquid Glass — what was measured

Every claim here was checked by screenshot against a real `NSMenu` over the same wallpaper. The
code compiles and looks plausible under all of these options, so reading it proves nothing.

**The rule that explains everything:** WWDC25 session 310 — *"glass can't directly sample other
glass."* SwiftUI's `glassEffect` samples content WITHIN the window. Anything not in SwiftUI's own
render tree — an `NSGlassEffectView` wrapper, an `NSVisualEffectView` backdrop — is invisible to
it, so a glass control over either finds nothing to refract and composites to a flat fill.

| Window surface | Panel density | SwiftUI glass controls |
|---|---|---|
| `NSGlassEffectView` wrapper | good | **flat** (glass on glass) |
| Clear window, SwiftUI `glassEffect` panel | **too clear** — desktop colour reads across the agenda | real glass |
| `NSVisualEffectView` `.menu` *(shipping)* | **matches native** by construction | **flat** |

Shipping the third row: the panel is the thing the eye judges, `.menu` is literally the material
AppKit gives menus, and matching it needs no tint constant that someone has to re-tune when Apple
retunes the material. The Join controls are drawn instead — fill, top-lit rim, tight shadow — which
renders on every version. `JoinControlSurface` and `DaySummaryHeaderButton` are that drawing.

Corrections to earlier notes in this file, all of which were wrong:
- "SwiftUI translucency cannot work in this window" — it can. `.regularMaterial` failed because the
  AppKit wrapper sat between it and the desktop, and that was over-generalised to all SwiftUI
  translucency including `glassEffect`.
- The `PanelCard` "never `glassEffect`" rule is right, but for a better reason than haze: glass on
  glass does not render at all.

Not yet tried: `GlassEffectContainer` (the documented way to make several glass elements share one
sampling pass) over the clear-window variant. It could change the density of row two, which is the
only combination that would give both.

---

## 8. Open questions

- **Dashboard or glance?** With header + progress + timeline + calendar all on, ~400pt precedes
  the first meeting. Currently answered by "composable, calendar off by default" — the user
  decides per install. Worth revisiting if the defaults feel wrong in use.
- **Default for menu-bar progress once built.** Currently planned as `none`; ring is the
  recommendation if a visible default is wanted.
- **Does `PanelCard` want a title slot?** Supported but unused — the timeline reads fine without
  one. Adding titles to every card would cost ~16pt each.
