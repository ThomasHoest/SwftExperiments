# ADR-E54 — Bottom Bar Redesign (E-54): PlaybackBars Extraction and SpeakerSelectorPill Refactor

**Status:** Accepted
**Date:** 2026-05-11
**Deciders:** Engineering Lead
**Refs:** ADR-002-voxio-1.4-ios.md (D1, D2, D6), spec-home-screen-redesign.md v1.0 (US-62, TR Component table), design-spec-home-screen-redesign.md v1.2 (§2.2–§2.5), epics-and-tasks-home-screen-redesign.md v1.0 (E-54 T-5401–T-5410), VoxioSpecification-1.4.md v1.4.1 (Feature Dependencies § Recommended sequencing), CLAUDE.md

---

## 1. Decision

`PlaybackBars` is extracted from the `private` scope of `SpeakerCard.swift` into a new internal struct at `iOS/Voxio/Features/Home/Components/PlaybackBars.swift`, accepting an optional `height` parameter for reuse at both 20 pt (session card) and 10 pt (bottom bar pill). `SpeakerSelectorPill` is refactored in-place to accept a `Speaker` reference per pill (replacing the current name string), embed `PlaybackBars(height: 10)` for playing speakers, and draw a 1 pt connector line between adjacent pills that share a `SpeakerGroup`. A new `groups: [SpeakerGroup]` input is added to `SpeakerSelectorPill` to support the connector query. The bottom-bar visibility threshold in `HomeView` is lowered from `count > 1` to `count >= 1`.

---

## 2. Context

### Prior decisions this epic depends on

- **ADR-002 D1** — the session strip uses `ScrollView + scrollPosition(id:)` with a two-way `selectedSpeaker` binding. E-54 T-5407 ("tap-to-scroll wiring") is a zero-code confirmation task: the existing `selectedSpeaker` binding already flows from `HomeView` into both `SpeakerSelectorPill` and (after E-52 T-5202) `SessionStripView`. E-54 has no independent scroll position state.
- **ADR-002 Design-token lock** — no new `BeoColor`, `Spacing`, `Radius`, `BeoAnimation`, or `BeoType` tokens are introduced. All pill and connector values (`BeoColor.muted`, `BeoColor.accent`, `Spacing.s8`, `Spacing.s12`, `Spacing.s16`, `Radius.pill`) are from the existing token set.
- **VoxioSpecification-1.4.md Recommended sequencing** — E-54 T-5401 is the first task the team lands (standalone PR) to prevent merge conflicts between F1 and F3, because F1 also references `PlaybackBars` inside `SpeakerCard`.
- **`SpeakerGroup` and `Speaker` are `@Observable @MainActor`** — the connector helper `sameGroup(_:_:)` may only run on the main actor; it is a pure synchronous query against `SpeakerGroup.members` so no async hop is needed.
- **`PBXFileSystemSynchronizedRootGroup`** — dropping `PlaybackBars.swift` into `iOS/Voxio/Features/Home/Components/` auto-compiles it; no pbxproj edits required.

### Current state (observed from codebase)

- `PlaybackBars` is a `private struct` at the bottom of `SpeakerCard.swift` (lines 170–192). It has no public entry point and no `height` parameter.
- `SpeakerSelectorPill` takes `speakers: [Speaker]` and `selectedSpeaker: Binding<Speaker?>`. Its `pillButton(name:isActive:)` renders `Text(name)` only — no playback state, no connector line.
- `ConnectionStatusChip` takes `speakerCount: Int` only — no `isOnWifi` or `didSettle` inputs yet (those are E-55 T-5503/T-5504).
- `HomeView` shows the bar when `discovery.groups.flatMap(\.members).count > 1` — the off-by-one that E-54 T-5408 corrects to `>= 1`.
- `iOS/Voxio/Features/Home/Components/` does not exist; it must be created with `PlaybackBars.swift` as its first file.

---

## 3. Options Considered

### Option A — Extract to shared Components file (chosen)

Move `PlaybackBars` to `Features/Home/Components/PlaybackBars.swift` as `internal struct PlaybackBars: View`. Add `var height: CGFloat = 20`. F1 and F3 both consume from the same file. Merge conflict surface area is minimised because F1 edits `SpeakerCard.cardContent` internals while E-54 only removes the private struct — the delta is a one-line deletion after T-5401 lands.

Advantage: single source of truth; F1 gets the proportional-scale variant automatically. Disadvantage: requires the Components sub-folder to be created.

### Option B — Duplicate PlaybackBars inline in SpeakerSelectorPill

Keep the private struct in `SpeakerCard.swift`, add a second private copy in `SpeakerSelectorPill.swift`. No folder creation needed.

Disadvantage: two structs diverge immediately (different `height` params, potential Reduce Motion handling divergence). Rejected on DRY grounds and because F1 would face the same duplication.

---

## 4. Rationale

Option A is required by the master spec's Recommended sequencing (standalone T-5401 PR) and by the F1/F3 shared-file dependency table (VoxioSpecification-1.4.md §Shared platform changes). The `height` parameter is a one-line addition that preserves all existing animation behaviour while enabling the 10 pt pill variant. The connector line is a pure layout computation (`sameGroup(_:_:)` against the injected `[SpeakerGroup]` array) with no new network calls or asynchronous work — entirely compatible with the `@MainActor` model invariant. No new design tokens are needed; all values are existing token references.

---

## 5. Consequences

- **F1 merge risk eliminated** — once T-5401 lands, F1 can delete the private struct from `SpeakerCard.swift` without conflicting with any E-54 work.
- **F2 draggable wiring** — F2 / E-59 T-5903–T-5904 attaches `.draggable(speaker.identifier)` to the refactored pill. The new `pillButton(speaker:isActive:isPlaying:)` signature is the surface F2 attaches to. F2 cannot attach until T-5403 exists.
- **`SpeakerSelectorPill` call-site change** — `HomeView` must pass `groups: discovery.groups` in addition to `speakers:` and `selectedSpeaker:`. This is a compile-time contract change; any other caller must be updated. Current callers: `HomeView` body only (one call site, confirmed).
- **Bottom-bar condition correction** — changing `> 1` to `>= 1` means a single discovered (idle) speaker now shows the bar. This is the correct spec behaviour (US-62) and removes the existing bug where a solo idle speaker did not appear in the bar.
- **`Components/` directory** — test writers targeting `PlaybackBars` should import from `iOS/Voxio/Features/Home/Components/PlaybackBars.swift`. No module boundary change.

---

## 6. File-Level Plan

### New files

| Path | Type | Description |
|---|---|---|
| `iOS/Voxio/Features/Home/Components/PlaybackBars.swift` | `internal struct PlaybackBars: View` | Extracted from `SpeakerCard.swift`. Adds `var height: CGFloat = 20` param and Reduce Motion static variant. |

### Modified files

| Path | Change | Task |
|---|---|---|
| `iOS/Voxio/Features/Home/SpeakerCard.swift` | Remove `private struct PlaybackBars` (lines 170–192). `nowPlayingPanel` call `PlaybackBars()` unchanged — resolves from new shared file. | T-5402 |
| `iOS/Voxio/Features/Home/SpeakerSelectorPill.swift` | Add `var groups: [SpeakerGroup]` input. Rename/replace `pillButton(name:isActive:)` with `pillButton(speaker:isActive:isPlaying:)`. Add `PlaybackBars(height: 10)` inside pill `HStack`. Add `connectorLine(currentSpeaker:nextSpeaker:)` helper. Change `ForEach(speakers)` to indexed `ForEach(speakers.indices)` with interleaved connector segments. Update accessibility labels/hints. | T-5403, T-5404, T-5405, T-5406 |
| `iOS/Voxio/Features/Home/HomeView.swift` | (a) Change bar visibility from `count > 1` to `count >= 1`. (b) Pass `groups: discovery.groups` to `SpeakerSelectorPill`. (c) Confirm `selectedSpeaker` binding wires through without new code for tap-to-scroll (T-5407 is a zero-code confirmation). | T-5407, T-5408 |

---

## 7. Public Interface Contract

The Implementer must expose exactly the following public/internal surfaces. The Test Writer may write tests against these without seeing the implementation.

```swift
// MARK: - PlaybackBars
// File: iOS/Voxio/Features/Home/Components/PlaybackBars.swift

internal struct PlaybackBars: View {
    /// Full-height (20 pt) by default; pass 10 for the bottom-bar pill variant.
    var height: CGFloat = 20

    // body is not part of the contract — View conformance only.
    // @Environment(\.accessibilityReduceMotion) consumed internally.
    // Renders static bars at midpoint heights when reduceMotion == true.
    // .accessibilityHidden(true) applied internally.
}
```

```swift
// MARK: - SpeakerSelectorPill
// File: iOS/Voxio/Features/Home/SpeakerSelectorPill.swift

struct SpeakerSelectorPill: View {
    var speakers: [Speaker]              // discovery order; unchanged
    @Binding var selectedSpeaker: Speaker?
    var groups: [SpeakerGroup]           // NEW — used by connector helper only

    // Internal helpers (not exposed to callers; listed here for Test Writer reference):

    /// Returns true when speakers a and b share any SpeakerGroup in `groups`.
    /// Must be called on @MainActor. Pure sync query — no async.
    private func sameGroup(_ a: Speaker, _ b: Speaker) -> Bool

    /// Builds the pill button label for one speaker.
    @ViewBuilder
    private func pillButton(speaker: Speaker, isActive: Bool, isPlaying: Bool) -> some View

    /// Draws a 1 pt muted connector (BeoColor.muted.opacity(0.3), width 8 pt, height 1 pt)
    /// when sameGroup returns true, otherwise a transparent placeholder of the same size.
    @ViewBuilder
    private func connectorLine(currentSpeaker: Speaker, nextSpeaker: Speaker) -> some View
}
```

```swift
// MARK: - HomeView call-site shape (updated signature for SpeakerSelectorPill)
// The Implementer must update the HomeView body to match this call:

SpeakerSelectorPill(
    speakers: discovery.groups.flatMap(\.members),
    selectedSpeaker: $selectedSpeaker,
    groups: discovery.groups
)

// Visibility condition updated from:
//   if discovery.groups.flatMap(\.members).count > 1
// to:
//   if discovery.groups.flatMap(\.members).count >= 1
```

Key behavioural contracts the Test Writer should assert:

1. `PlaybackBars(height: 10)` renders with `frame(height: 10, alignment: .bottom)` — bars are scaled proportionally, not clipped.
2. `PlaybackBars` is always `.accessibilityHidden(true)`.
3. When `reduceMotion == true`, `PlaybackBars` renders static `RoundedRectangle` bars at the midpoint of each bar's lo–hi range (`(lo + hi) / 2`), with no running animation.
4. `SpeakerSelectorPill.sameGroup(_:_:)` returns `true` iff both speakers appear in the `members` array of the same `SpeakerGroup` in `groups`; returns `false` when either speaker is absent from all groups.
5. The connector segment between pills i and i+1 has a clear placeholder frame (`width: 8, height: 1`) whether or not `sameGroup` is true, so pill spacing is stable regardless of group membership.
6. A playing pill's accessibility label is `"\(speaker.name), playing"`. A selected-and-playing pill's label is `"\(speaker.name), playing, selected"`. An idle selected pill's label is `"\(speaker.name), selected"`. An idle unselected pill's label is `"\(speaker.name)"`.
7. The bottom bar is rendered whenever `discovery.groups.flatMap(\.members).count >= 1`.

---

## 8. Conflicts Flagged

### Dependency: E-54 T-5407 ("tap-to-scroll wiring") requires E-52 T-5202

T-5407 is described in the epics doc as a "confirm no new code required" task — it only verifies that tapping a pill (which sets `selectedSpeaker`) causes `SessionStripView.onChange(of: selectedSpeaker?.id)` to scroll the strip. This `onChange` handler lives in `SessionStripView` and is introduced by E-52 T-5202. Until T-5202 exists, there is no `SessionStripView` to scroll — the strip tap-to-scroll behaviour is untestable end-to-end.

**Task gate summary:**

| Task | Can begin immediately (before E-52 T-5202)? | Reason |
|---|---|---|
| T-5401 — Extract `PlaybackBars` | YES — first task, standalone PR | Pure refactor; no dependency on any E-52 work |
| T-5402 — Remove duplicate from `SpeakerCard` | YES — immediately after T-5401 | Depends only on T-5401 |
| T-5403 — Refactor `pillButton` to `pillButton(speaker:isActive:isPlaying:)` | YES | Depends only on T-5401 (for `PlaybackBars`) |
| T-5404 — Wire `isPlaying` and bar transition | YES | Depends on T-5403 |
| T-5405 — Update accessibility labels/hints | YES | Depends on T-5403 |
| T-5406 — Group connector line | YES | Depends on T-5404; `sameGroup` is a self-contained query |
| T-5407 — Tap-to-scroll wiring confirmation | BLOCKED on E-52 T-5202 | The `SessionStripView.onChange` handler that responds to `selectedSpeaker` changes only exists after T-5202 |
| T-5408 — Always-visible bar condition | YES | Depends on T-5406 for the `groups:` param, but the condition change itself is a one-line fix independent of T-5202 |
| T-5409 — Manual verification | BLOCKED on E-52 T-5202 | End-to-end scroll verification requires the session strip |
| T-5410 — VoiceOver verification | YES (pill labels only); BLOCKED on E-52 T-5202 for scroll-related assertions | Pill a11y labels can be verified without the strip |

### No contradictions with ADR-002

All token usage, actor isolation, and API surface decisions in E-54 are consistent with ADR-002. Specifically:

- No new design tokens (ADR-002 constraint §2 preserved).
- `sameGroup(_:_:)` is a synchronous main-actor query — no off-actor access to `@Observable @MainActor Speaker` or `SpeakerGroup` (ADR-002 architecture invariant preserved).
- `PlaybackBars` height parameter is an additive, non-breaking change to an existing behaviour (ADR-002 §2 "existing card surface" preserved — `SpeakerCard.nowPlayingPanel` continues to call `PlaybackBars()` at the 20 pt default).

### Minor spec ambiguity (not a blocker)

T-5406 references `BeoColor.muted` for the connector line, but the design spec §2.3 says "1 pt line in `BeoColor.muted` at 0.3 opacity". The epics doc uses `BeoColor.muted.opacity(0.3)`. These are consistent; the implementation must apply `.opacity(0.3)` at the fill level, not on the `Rectangle` view modifier, to avoid double-compositing with any parent opacity.
