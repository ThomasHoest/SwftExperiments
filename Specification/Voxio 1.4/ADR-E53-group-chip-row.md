# ADR-E53 — Session Card Group Chip Row (E-53): GroupChipRow, ChipData model, SpeakerCard extension

**Status:** Accepted
**Date:** 2026-05-11
**Deciders:** Engineering Lead
**Refs:** ADR-002-voxio-1.4-ios.md (§2 token-lock, §2 @MainActor invariant), ADR-E52-session-card-strip.md (§6 CF-4/CF-5, §7 public interface), ADR-E54-bottom-bar-redesign.md (§7 SpeakerSelectorPill connector pattern), spec-home-screen-redesign.md v1.0 (US-61, §Technical Requirements Component table, §Resolved Decisions UQ-3/UQ-6), design-spec-home-screen-redesign.md v1.2 (§3.4 chip anatomy, §3.7 accessibility), epics-and-tasks-home-screen-redesign.md v1.0 (E-53 T-5301–T-5310), VoxioSpecification-1.4.md v1.4.1 (Feature Dependencies §F3→F2), CLAUDE.md

---

## 1. Decision

A new file `iOS/Voxio/Features/Home/Components/GroupChipRow.swift` is introduced, containing both `struct ChipData` (the chip's pure-data model) and `struct GroupChipRow: View` (the row renderer). `SpeakerCard` gains a new optional parameter `var groupMembers: [Speaker] = []` (defaulting to empty, so all existing call sites remain valid) and renders a `GroupChipRow` at the bottom of `cardContent` when the array is non-empty. `SessionStripView` is the sole caller that passes a non-empty `groupMembers` array, derived as `group.members.filter { $0.id != group.hostSpeaker.id }`. Chip data is modelled as a value-type struct (`ChipData`) kept `internal` to the app target, carrying enough fields for F2 to layer `loading` state and a tap handler without changing E-53 call sites.

---

## 2. Context

### Prior decisions that constrain this epic

**ADR-002 design-token lock.** No new `BeoColor`, `Spacing`, `Radius`, `BeoAnimation`, or `BeoType` tokens may be introduced in v1.4. All chip styling values (`BeoType.caption`, `BeoColor.muted`, `Spacing.s8`/`s4`/`s16`/`s24`, `Radius.pill`) are pre-existing in `DesignTokens.swift` and `BeoColor.swift`. The chip background `.white.opacity(0.07)` is a literal opacity expression, not a token — consistent with the same pattern already used in `nowPlayingPanel` inside `SpeakerCard.swift` and with design spec §3.4 ("same surface as the now-playing panel").

**ADR-002 @MainActor invariant.** `Speaker` and `SpeakerGroup` are `@Observable @MainActor`. All rendering of chip data happens synchronously on the main actor inside SwiftUI `body` properties. No async hops are introduced. `ChipData` is a plain value type (`struct`) carrying only the speaker name string and `id`, so it is safe to pass across any boundary and is implicitly `Sendable`.

**ADR-E52 §6 CF-4 / CF-5 — `SpeakerCard` `groupMembers:` slot.** ADR-E52 explicitly reserved the `groupMembers:` parameter slot on `SpeakerCard` and documented that E-53 T-5304 adds it. The E-52 call site in `SessionStripView` already passes only the four original parameters (`speaker`, `isExpanded`, `roll`, `pitch`); the default value of `groupMembers: []` makes the E-52 call site forward-compatible before E-53 lands, and backward-compatible after. No change to the E-52 public interface contract is required.

**ADR-E54 §7 — `SpeakerSelectorPill` connector pattern as parallel.** ADR-E54 introduced a group-membership query helper (`sameGroup(_:_:)`) as an internal private function on `SpeakerSelectorPill` that operates on the injected `[SpeakerGroup]` array. E-53 follows the same pattern at the chip level: chip content is derived at the `SessionStripView` call site (`group.members.filter { $0.id != group.hostSpeaker.id }`) and passed in as a plain `[Speaker]` array. `GroupChipRow` does not perform its own group-membership query — the filtering is the caller's responsibility, just as with the connector helper in E-54.

**Resolved UQ-3 (no pill re-sort by group).** The `members` array order within `SpeakerGroup` is already stable (members are appended in discovery/join order and are not re-sorted). `GroupChipRow` renders chips in the order they are received. No sorting logic is added in E-53.

**Resolved UQ-6 ("+N more" overflow, tap deferred to F2).** When `members.count > 3`, the chip row shows the first 2 chips plus a `"+\(members.count - 2) more"` chip. Tapping the overflow chip is a no-op in F3. `GroupChipRow` must not attach a `Button` wrapper or `.onTapGesture` to the overflow chip in E-53. The overflow chip is visually identical to a member chip and carries a distinct `accessibilityLabel`.

**F3 → F2 hard dependency (VoxioSpecification-1.4.md §Feature Dependencies).** F2 / E-60 (T-6002) will add a `loading` chip variant to `GroupChipRow` for the in-flight join state. F2 / E-61 (T-6102) will add `onTap` per-chip for the tap-to-remove interaction. The `ChipData` model shape must support these additions without forcing any E-53 call site to change. This constraint is the primary driver of the model choice in §3.

### Current codebase state

- `SpeakerCard.swift` has four initialiser parameters: `speaker`, `isExpanded`, `roll`, `pitch`. No `groupMembers` parameter exists yet.
- `SessionStripView.swift` (E-52, shipped) passes `SpeakerCard(speaker:isExpanded:roll:pitch:)` — no `groupMembers` argument.
- `iOS/Voxio/Features/Home/Components/PlaybackBars.swift` already exists (E-54 T-5401, complete) — the `Components/` subdirectory is live and auto-compiled by `PBXFileSystemSynchronizedRootGroup`.
- No `GroupChipRow.swift` or `ChipData` type exists anywhere in the target.
- `Speaker.id` is of type `UUID` (from `Identifiable` synthesis in `Speaker.swift` via `let id = UUID()`). `SpeakerGroup.id` is `String` (from `makeId(for:)`).
- The codebase uses language-keyed string structs (`UIStrings`, `CommandStrings`) in `iOS/Voxio/Core/Strings/`; there is no `.strings` or `.xcstrings` localisation catalogue. New localised strings for E-53 must follow the same `UIStrings`-style pattern: add keys to the relevant `*Strings.swift` struct, not to a `.strings` file. This is a deviation from what design spec Appendix B implies — see §8 for the conflict flag.

---

## 3. Options Considered

### Option A — Struct-based chip model (`ChipData`) with `GroupChipRow` accepting `[ChipData]` (chosen)

Define:

```swift
internal struct ChipData: Identifiable {
    let id: UUID          // stable identity for ForEach diffing
    let speakerName: String
    let kind: ChipKind

    enum ChipKind {
        case member         // "+ Speaker Name"
        case overflow(Int)  // "+N more"
    }
}
```

`GroupChipRow` accepts `let chips: [ChipData]` and renders each according to its `kind`. The `SessionStripView` call site converts `[Speaker]` to `[ChipData]` in a local computed helper before passing to `SpeakerCard`. `SpeakerCard` itself converts its `[Speaker] groupMembers` to `[ChipData]` internally before handing to `GroupChipRow` (keeping the `groupMembers: [Speaker]` public surface, which is what ADR-E52 specified, while letting `GroupChipRow` remain decoupled from `Speaker`).

**F2 extension path:** F2 / E-60 adds `case loading` to `ChipKind`. F2 / E-61 adds `let onTap: (() -> Void)?` to `ChipData` (optional, defaults to `nil` so all E-53 construction sites compile without change). Both additions are additive to the struct — no existing field changes. `GroupChipRow` switches on `chip.kind` and renders the `loading` variant when present. The tap handler is wired inside `GroupChipRow` only when `chip.onTap != nil`.

**Advantages:**
- `GroupChipRow` is a pure-data view — testable without a live `Speaker` object.
- `ChipKind.overflow(Int)` makes overflow rendering an explicit enum case rather than a computed branch inside the view body. F2's `loading` variant slots in naturally as another case.
- E-53 call sites (`SessionStripView` / `SpeakerCard`) never need to change when F2 extends `ChipData` — `onTap: nil` is the safe default.
- Consistent with ADR-E54's approach: `PlaybackBars` accepts scalar typed inputs (`height: CGFloat`), not a live `Speaker` reference.

**Disadvantages:**
- Requires one conversion from `[Speaker]` to `[ChipData]` inside `SpeakerCard.cardContent`. This is a three-line computed property — not a meaningful cost.
- `ChipData` must be kept `internal` (not `private` to `SpeakerCard`), because `GroupChipRow` must access it. This is noted in §5.

### Option B — View-builder closure passing `[Speaker]` directly to `GroupChipRow`

`GroupChipRow` accepts `let members: [Speaker]` and performs its own overflow computation, name extraction, and rendering internally. No intermediate model type.

**Advantages:** fewer types; simpler at the call site.

**Disadvantages:**
- `GroupChipRow` is coupled to `Speaker` — the view cannot be tested or previewed with a plain `[String]` stub.
- F2 extension requires modifying `GroupChipRow`'s parameter surface to accept `loading` state and `onTap` per speaker. Because the binding is to `Speaker` (a reference type), F2 must either add a parallel `loadingSpeakers: Set<Speaker.ID>` parameter or add `onTap: (Speaker) -> Void`. Either approach changes `SessionStripView`'s call to `SpeakerCard` and `SpeakerCard`'s call to `GroupChipRow` in a way that affects E-53 callers — exactly what the prompt requires to avoid.
- `Speaker` is `@Observable @MainActor`. Passing a `Speaker` array into a `View` that is not itself `@MainActor` raises actor isolation warnings on iOS 26 Swift concurrency; the struct model avoids this entirely.

Option B is rejected because it forecloses clean F2 extension without callers changing.

---

## 4. Rationale

Option A wins on two axes: testability and F2 extensibility.

The `ChipData` struct decouples `GroupChipRow` from `Speaker`. A test or SwiftUI preview can construct `[ChipData]` with three lines of code; constructing a valid `Speaker` requires a `SpeakerClient` mock and an async `initialize()` call. The decoupling is the same principle that motivates E-54's `PlaybackBars(height:)` taking a scalar rather than a `Speaker` reference — the pattern is already established in the codebase.

For F2, the extension story is clean: `ChipKind.loading` is one new enum case. `ChipData.onTap: (() -> Void)? = nil` is one new optional property. Neither change alters any existing field, so all E-53 construction sites compile without modification. Inside `GroupChipRow.body`, a `switch chip.kind` already handles each case; F2 adds a `.loading { ... }` branch. The tap wiring is a `Button` wrapper inside `GroupChipRow` conditioned on `chip.onTap != nil` — absent in E-53, present in E-61, zero diff to the E-53 call site.

The `SpeakerCard` interface deliberately stays as `groupMembers: [Speaker]` (not `groupMembers: [ChipData]`) for two reasons: (a) ADR-E52 §6 CF-4 already documented the `[Speaker]` shape and the E-52 public interface contract names it; (b) the conversion from `[Speaker]` to `[ChipData]` (including overflow computation) is a single private computed property inside `SpeakerCard.cardContent`, making `GroupChipRow` unaware of the overflow threshold. If the overflow threshold ever changes, only `SpeakerCard`'s conversion property changes — not `GroupChipRow`'s interface. This is the right place for the policy.

The `ChipData` type is `internal` (not `public`, not `private`). It must be visible to `GroupChipRow.swift` and to `SpeakerCard.swift` — both in the same app target. Swift's default access level for a type in a single-target app without explicit access modifiers is `internal`, which is exactly the right scope.

---

## 5. Consequences

**`ChipData` is `internal` to the app target.** It is not `private` to `SpeakerCard.swift` because `GroupChipRow` (a separate file) must reference it. It is not `public` because there is no framework or module boundary. F2 engineers extending `ChipData` do so in the same file (`GroupChipRow.swift`) without any access modifier change.

**E-53 `SpeakerCard` call sites remain valid.** All existing callers of `SpeakerCard` (currently `HomeView.cardArea` idle branch, and `SessionStripView` after E-52) omit `groupMembers:` — the default `= []` handles them. The parameter is additive.

**F2 / E-60 will add `ChipKind.loading` to the enum.** This is a breaking change to `ChipKind` in the sense that any exhaustive `switch` on `ChipKind` must add a new case. The only exhaustive switch is inside `GroupChipRow.body` — one file, owned by F2 as the modifying epic. No E-53 callers switch on `ChipKind`. The Implementer should annotate the enum with a comment noting that `loading` is reserved for F2.

**F2 / E-61 will add `onTap: (() -> Void)?` to `ChipData`.** This is a stored property addition to a struct. All E-53 construction sites use positional or labelled initialisation; they must use the memberwise initialiser without `onTap` (i.e., `onTap` must default to `nil` in the init). The Implementer must declare it with a default: `var onTap: (() -> Void)? = nil`. Because `ChipData` contains a closure, it is not automatically `Sendable` once `onTap` is present — F2 must document this non-`Sendable` consequence in the E-61 ADR if Swift concurrency isolation becomes relevant.

**Localisation uses `UIStrings` pattern, not `.strings` files.** The codebase has no `.strings` or `.xcstrings` catalogue. New E-53 strings (`groupChip.prefix`, `a11y.alsoPlaying`, `+N more` / `+N flere`) must be added to the existing `UIStrings`-style structs in `iOS/Voxio/Core/Strings/`. T-5308 must be re-read in this light — see §8 for the conflict flag.

**`Components/` directory already exists.** `PlaybackBars.swift` was the first file dropped there (E-54 T-5401). `GroupChipRow.swift` lands as the second file. No directory creation required.

**Dynamic Type reflow.** The spec (US-61 acceptance criterion, T-5309) requires the chip row to "wrap gracefully or truncate at the trailing edge" at AX5. The `HStack(spacing: Spacing.s8)` layout does not automatically wrap. The Implementer must use `.lineLimit(1)` and `.truncationMode(.tail)` on each chip `Text`, allowing truncation at extreme sizes rather than overflow. Vertical wrapping is not achievable in a plain `HStack` without significant additional layout code — truncation is the correct approach for a display-only row. This is a clarification of the T-5309 requirement; it does not conflict with the spec but the Implementer must not attempt to reflow the row with a `FlowLayout`.

---

## 6. File-Level Plan

### New files

| Path | Type | Description |
|---|---|---|
| `iOS/Voxio/Features/Home/Components/GroupChipRow.swift` | `internal struct ChipData` + `internal struct GroupChipRow: View` | Chip data model and row view. Both live in this file. ChipData defines the member and overflow chip variants. GroupChipRow renders an HStack of Capsule chips from [ChipData]. |

### Modified files

| Path | Change | Tasks |
|---|---|---|
| `iOS/Voxio/Features/Home/SpeakerCard.swift` | Add `var groupMembers: [Speaker] = []` parameter. Add private `var chipData: [ChipData]` computed property (performs overflow gating). Add `GroupChipRow(chips: chipData).padding(.horizontal, Spacing.s24).padding(.bottom, Spacing.s16)` at the bottom of `cardContent`, guarded by `!groupMembers.isEmpty`. Extend `accessibilityDescription` to append `"Also playing: " + groupMembers.map(\.name).joined(separator: ", ")` when `!groupMembers.isEmpty`. | T-5304, T-5305 |
| `iOS/Voxio/Features/Home/SessionStripView.swift` | Pass `groupMembers: group.members.filter { $0.id != group.hostSpeaker.id }` to each `SpeakerCard` call. | T-5306 |
| `iOS/Voxio/Core/Strings/UIStrings.swift` (or a new `iOS/Voxio/Core/Strings/GroupChipStrings.swift`) | Add the two language-keyed chip strings: `groupChipAlsoPlaying` ("Also playing" / "Spiller også") for the accessibility label, and `groupChipOverflow` for the "+N more" / "+N flere" format string. The `groupChip.prefix` ("+" / "+") is a constant and does not need a language key. | T-5308 |

### No new design token files

No changes to `DesignTokens.swift` or `BeoColor.swift`. No new tokens are introduced.

---

## 7. Public Interface Contract

The Implementer must expose exactly the following surfaces. The Test Writer may write against this contract without seeing the implementation.

```swift
// MARK: - ChipData
// File: iOS/Voxio/Features/Home/Components/GroupChipRow.swift

internal struct ChipData: Identifiable {
    let id: UUID            // stable, synthesised on construction — used by ForEach
    let speakerName: String // display name; used for chip label and accessibilityLabel
    let kind: ChipKind

    // F2 RESERVED — do NOT implement in E-53:
    // var onTap: (() -> Void)? = nil   // added by E-61

    internal enum ChipKind: Equatable {
        case member           // renders "+ <speakerName>"
        case overflow(Int)    // renders "+<N> more" / "+<N> flere"; Int = remaining count
        // F2 RESERVED: case loading  // added by E-60
    }
}
```

```swift
// MARK: - GroupChipRow
// File: iOS/Voxio/Features/Home/Components/GroupChipRow.swift

internal struct GroupChipRow: View {
    /// Fully-resolved chip data including overflow chip when applicable.
    /// Caller is responsible for computing overflow — GroupChipRow renders
    /// chips exactly as provided, in order.
    let chips: [ChipData]

    // Behavioural contracts:
    //
    // 1. Returns EmptyView() when chips.isEmpty — no empty HStack, no zero-height space.
    // 2. Renders HStack(spacing: Spacing.s8) of Capsule() chips.
    // 3. Each chip:
    //    - .member:    label "+" + speakerName in BeoType.caption, BeoColor.muted foreground.
    //    - .overflow:  label "+\(N) more" (English) / "+\(N) flere" (Danish) via LanguageService.
    //    Chip background: .white.opacity(0.07) in Capsule().
    //    Padding: Spacing.s8 horizontal, Spacing.s4 vertical.
    // 4. Chip accessibilityLabel:
    //    - .member:   "Also playing: \(speakerName)" / "Spiller også: \(speakerName)"
    //    - .overflow: "\(N) more speakers in this group" / Danish equivalent
    // 5. No Button wrapper, no .onTapGesture — chips are display-only in E-53.
    //    (F2 / E-61 will add optional tap handling via ChipData.onTap.)
    // 6. Text within each chip: .lineLimit(1), .truncationMode(.tail).
    //    The row does NOT reflow vertically at large Dynamic Type sizes — truncation is
    //    the correct behaviour for a display-only row.
    // 7. @Environment(\.accessibilityReduceMotion) is not consumed — chips are static.
    // 8. The row does not carry its own horizontal or bottom padding.
    //    Padding is applied at the SpeakerCard call site:
    //      .padding(.horizontal, Spacing.s24).padding(.bottom, Spacing.s16)
}
```

```swift
// MARK: - SpeakerCard (updated initialiser)
// File: iOS/Voxio/Features/Home/SpeakerCard.swift

struct SpeakerCard: View {
    var speaker: Speaker
    var isExpanded: Bool
    var roll: Double
    var pitch: Double
    var groupMembers: [Speaker] = []   // NEW — E-53 T-5304; default keeps E-52 call sites valid

    // Internal computed property (listed for Test Writer reference — not exposed to callers):

    /// Converts groupMembers to ChipData, applying the overflow rule:
    /// when members.count > 3, produces 2 member chips + 1 overflow chip.
    /// When members.count <= 3, produces one chip per member.
    /// When members is empty, produces [].
    private var chipData: [ChipData] { ... }

    // Behavioural contracts:
    //
    // 1. When groupMembers.isEmpty: cardContent is unchanged from E-52 — no empty space
    //    below volumeTrack, no GroupChipRow rendered.
    // 2. When !groupMembers.isEmpty: GroupChipRow(chips: chipData) is rendered below
    //    volumeTrack with .padding(.horizontal, Spacing.s24).padding(.bottom, Spacing.s16).
    // 3. The chip row appears only when speaker.isPlaying (because volumeTrack only appears
    //    when isPlaying — the chip row follows the volumeTrack block in cardContent).
    //    If a non-playing speaker is somehow passed groupMembers, the row is not shown
    //    (it is inside the `if speaker.isPlaying { }` block).
    // 4. accessibilityDescription is extended:
    //    When !groupMembers.isEmpty, append "Also playing: " + groupMembers.map(\.name).joined(separator: ", ")
    //    as a final element of the parts array, using the localised "Also playing" string.
    //    The appended string uses speaker display names in the order they appear in groupMembers.
}
```

```swift
// MARK: - SpeakerCard.accessibilityDescription extension (T-5305)
// Exact behaviour:

private var accessibilityDescription: String {
    var parts = [speaker.name, speaker.stateDisplay]
    if p.isPlaying {
        if let primary = p.primaryLine, !primary.isEmpty { parts.append(primary) }
        if let secondary = p.secondaryLine, !secondary.isEmpty { parts.append(secondary) }
        if let badge = p.sourceBadge, !badge.isEmpty { parts.append(badge) }
    }
    if let vol = speaker.volume { parts.append("Volume \(vol)") }
    // E-53 addition:
    if !groupMembers.isEmpty {
        let names = groupMembers.map(\.name).joined(separator: ", ")
        parts.append("Also playing: \(names)")   // use localised string from UIStrings / GroupChipStrings
    }
    return parts.joined(separator: ", ")
}
```

```swift
// MARK: - SessionStripView call-site update (T-5306)
// File: iOS/Voxio/Features/Home/SessionStripView.swift

// Replace the existing SpeakerCard(...) call inside ForEach(groups) with:

SpeakerCard(
    speaker: group.hostSpeaker,
    isExpanded: isCommandActive,
    roll: isFrontmost ? roll : 0,
    pitch: isFrontmost ? pitch : 0,
    groupMembers: group.members.filter { $0.id != group.hostSpeaker.id }  // E-53 T-5306
)
.frame(width: cardWidth)
.id(group.hostSpeaker.id)

// Behavioural contracts:
// 1. The filter expression ensures the host speaker is never included in the chip row.
// 2. The filter result may be empty (solo session) — SpeakerCard's default handles this.
// 3. The members array order is the SpeakerGroup.members order (discovery/join order);
//    do NOT sort this array — resolved UQ-3 applies here too.
```

Key behavioural contracts the Test Writer should assert:

1. `GroupChipRow(chips: [])` renders no view — SwiftUI element tree contains no chip HStack.
2. With `chips` containing exactly one `.member` chip, one `Capsule` is rendered with label `"+ SpeakerName"`.
3. With `chips` containing three `.member` chips, three `Capsule` views are rendered; no overflow chip.
4. With `groupMembers` of count 4 on `SpeakerCard`, `chipData` produces exactly 3 `ChipData` items: 2 `.member` + 1 `.overflow(2)`.
5. The overflow chip renders as `"+2 more"` in English and `"+2 flere"` in Danish, switching on `LanguageService.shared.activeLanguage`.
6. The overflow chip's `accessibilityLabel` is `"2 more speakers in this group"` (English) / Danish equivalent.
7. A member chip's `accessibilityLabel` is `"Also playing: Stue"` (English) / `"Spiller også: Stue"` (Danish).
8. `SpeakerCard` with `groupMembers: [memberA, memberB]` produces an `accessibilityDescription` ending with `"Also playing: MemberA, MemberB"`.
9. `SpeakerCard` with `groupMembers: []` produces the same `accessibilityDescription` as the E-52 contract — no "Also playing" suffix.
10. The chip row is absent when `speaker.isPlaying == false` even when `groupMembers` is non-empty (because chip row rendering is gated inside the `if speaker.isPlaying` block in `cardContent`).
11. When `group.members.count == 1` (solo session), `SessionStripView` passes `groupMembers: []` to `SpeakerCard` — confirmed by the filter expression producing an empty array when the only member is the host.
12. `ChipData` is `Identifiable` via its `id: UUID` — `ForEach(chips)` can use `id: \.id`.
13. Each chip's background is `.white.opacity(0.07)` in a `Capsule()` shape — matching the `nowPlayingPanel` surface per design spec §3.4.
14. No `Button` wrapper and no `.onTapGesture` is attached to any chip in E-53. Tapping a chip produces no action.

---

## 8. Conflicts Flagged

### CF-1: Localisation pattern conflict — `.strings` files do not exist

The epics doc T-5308 instructs the implementer to add keys to `en.lproj/Localizable.strings` and `da.lproj/Localizable.strings`. These files do not exist in the codebase. The project uses `UIStrings.swift`, `CommandStrings.swift`, and similar struct-based, language-keyed string tables in `iOS/Voxio/Core/Strings/`. Design spec Appendix B key names (`groupChip.prefix`, `a11y.alsoPlaying`) are catalogue-style identifiers that do not map to any live mechanism.

**Resolution (no spec change required for E-53):** T-5308 must be implemented by adding new string properties to an appropriate existing `*Strings.swift` struct (or a new `GroupChipStrings.swift` if the Implementer judges the existing structs to already be wide). The Test Writer should assert on the `UIStrings`/struct-level property values, not on `NSLocalizedString` keys. This does not require a spec amendment — the epics doc is the secondary source; the design spec Appendix B describes intent, not mechanism. The implementer is responsible for adapting the mechanism to the codebase pattern.

### CF-2: Chip row only visible when `speaker.isPlaying == true`

The design spec §3.4 shows the chip row in the session card anatomy with no explicit gating on playback state. However, `SpeakerCard.cardContent` renders `nowPlayingPanel` and `volumeTrack` only inside `if speaker.isPlaying { ... }`. If the chip row is added after the volume track inside this same conditional block, it will not appear for non-playing speakers — even if they have `groupMembers`. This is the correct behaviour for the session strip (session cards only appear for playing hosts), but it is worth documenting explicitly: the chip row is inside the `if speaker.isPlaying { }` block, not after it. The test contract item 10 above reflects this.

If the design intent were to show group membership even for paused cards (no such case exists in the session strip, which only shows playing hosts, but theoretically possible in a future scenario), the chip row would need to be moved outside the `isPlaying` gate. E-53 does not open this question; it is noted here for F2's awareness.

### CF-3: F2 `ChipKind.loading` addition breaks exhaustive `switch` in `GroupChipRow.body`

When F2 adds `case loading` to `ChipKind`, the exhaustive `switch chip.kind` inside `GroupChipRow.body` will fail to compile until F2 adds the `.loading` branch. This is expected and intentional — the compiler error is the signal to F2 that `GroupChipRow.body` needs a new rendering branch. F2 engineers must not work around this by adding `@unknown default` in E-53, as that would hide future unhandled cases. The E-53 `switch` should be exhaustive with exactly `case .member` and `case .overflow`.

### CF-4: F2 `ChipData.onTap` closure breaks `Sendable` conformance

Once F2 adds `var onTap: (() -> Void)? = nil` to `ChipData`, the struct can no longer be implicitly `Sendable` (closures are not `Sendable` unless they are `@Sendable`). In E-53, `ChipData` is a pure value type used only on the main actor inside SwiftUI views, so there is no cross-actor transfer and no `Sendable` issue. F2 must annotate `onTap` as `var onTap: (@MainActor () -> Void)? = nil` if Swift concurrency strict concurrency checking is enabled, or mark `ChipData` as `@unchecked Sendable` with a documented reason. This is a F2 concern, not an E-53 concern, but F2 should be aware.

### CF-5: No new design tokens — confirmed

All token references in E-53 (`BeoType.caption`, `BeoColor.muted`, `Spacing.s8`, `Spacing.s4`, `Spacing.s16`, `Spacing.s24`, `Radius.pill`) are pre-existing in `DesignTokens.swift` and `BeoColor.swift`. The chip background `.white.opacity(0.07)` is a literal, consistent with ADR-002 token-lock and the existing `nowPlayingPanel` implementation in `SpeakerCard.swift`. **No platform constraint violation detected.**

### CF-6: F2 / E-60 and E-61 can layer on without rewriting E-53

Verified. F2's two additions to `GroupChipRow`:
- E-60 adds `ChipKind.loading` and a rendering branch in `GroupChipRow.body`. The E-53 call site (`SpeakerCard.chipData`) does not produce `.loading` chips — it is only produced by `SessionViewModel.joinsInFlight` in F2.
- E-61 adds `onTap` to `ChipData` and a conditional `Button` wrapper inside `GroupChipRow.body`. The E-53 construction sites pass no `onTap` (it defaults to `nil`).

In both cases, the only file touched outside `GroupChipRow.swift` is F2-owned `SessionViewModel.swift` and the F2 call site that produces the modified `[ChipData]`. The E-53-owned files (`SpeakerCard.swift`, `SessionStripView.swift`) are not modified by F2's E-60 or E-61. The architecture is confirmed layerable.

---

## 9. Task Gate Checklist

All E-52 tasks are complete (E-52 shipped). `Components/PlaybackBars.swift` exists (E-54 T-5401 complete). The `Components/` directory exists.

| Task | Can begin immediately? | Dependency |
|---|---|---|
| T-5301 — Create `GroupChipRow.swift`, define `ChipData` and `GroupChipRow` for member/overflow chips | YES — unblocked | Nothing; `Components/` directory already exists |
| T-5302 — Implement "+N more" overflow chip in `GroupChipRow` | YES — immediately after T-5301 | Depends on T-5301 only |
| T-5303 — Accessibility labels per chip in `GroupChipRow` | YES — immediately after T-5301 | Depends on T-5301 only |
| T-5304 — Add `groupMembers: [Speaker] = []` to `SpeakerCard`; render `GroupChipRow`; add `chipData` computed property | YES — unblocked | Depends on T-5301 (needs `ChipData` type to compile) |
| T-5305 — Extend `SpeakerCard.accessibilityDescription` to append "Also playing: A, B" | YES — immediately after T-5304 | Depends on T-5304 |
| T-5306 — In `SessionStripView`, pass `groupMembers: group.members.filter { $0.id != group.hostSpeaker.id }` | YES — unblocked; E-52 shipped | Depends on T-5301 and T-5304 (SpeakerCard must accept the param); `SessionStripView` already exists |
| T-5307 — Verify chip row updates in place on group composition change (no full card re-render) | YES — after T-5306 lands and a test device/network is available | Depends on T-5306 |
| T-5308 — Add localised strings to `UIStrings.swift` (or new `GroupChipStrings.swift`) | YES — unblocked | Depends on T-5301 (need to know what strings are required) |
| T-5309 — Manual verification (4-speaker group, 2-speaker group, 1-speaker group, Dynamic Type AX1/AX5) | YES — after T-5306 is in a testable state on device/simulator | Depends on T-5306 |
| T-5310 — VoiceOver verification: chip row absent from VO tree; card label includes "Also playing" | YES — after T-5305 and T-5306 | Depends on T-5305 |

**Summary: all 10 tasks are unblocked.** T-5301 through T-5308 can begin immediately in parallel with each other (subject to T-5301 landing before T-5302/T-5303/T-5304 compile). T-5309 and T-5310 are verification tasks that require a running build with T-5306 merged.

The recommended implementation order within E-53 is: T-5301 → (T-5302, T-5303, T-5308 in parallel) → T-5304 → T-5305 → T-5306 → T-5307 → (T-5309, T-5310 in parallel).

---

**Verdict: PROCEED**
