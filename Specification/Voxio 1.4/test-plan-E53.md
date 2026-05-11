# Test Plan — E-53 Group Chip Row

**Status:** Draft
**Date:** 2026-05-11
**Refs:** ADR-E53-group-chip-row.md, spec-home-screen-redesign.md US-61, design-spec-home-screen-redesign.md §3.4/§3.7, epics-and-tasks-home-screen-redesign.md E-53

---

## 1. Scope

This plan covers the testable interface contract introduced by E-53: the `ChipData` value-type model (including `ChipKind` enum and `Identifiable` conformance), the `GroupChipRow` view (chip rendering, overflow rule, accessibility labels, no-tap guarantee), the updated `SpeakerCard` initialiser (`groupMembers: [Speaker] = []`), the `SpeakerCard.chipData` computed property (overflow gating), the `SpeakerCard.accessibilityDescription` extension, and the `SessionStripView` call-site filter that derives non-host members.

Tests assert against the 14 behavioural assertions in ADR-E53-group-chip-row.md §7 and every acceptance criterion in US-61. Overflow boundary cases are tested at 0, 1, 2, 3 (no overflow), 4 (first overflow: 2 members + `.overflow(2)`), 5 (2 members + `.overflow(3)`), and 10 (2 members + `.overflow(8)`) non-host members. Localisation is tested for English and Danish for both the "+N more" overflow string and the "Also playing" accessibility label.

What is out of scope:

- E-52 `SessionStripView` strip scroll mechanics and page-dot logic (separate plan: `test-plan-E52.md`).
- E-54 `SpeakerSelectorPill` and `PlaybackBars` (separate plan: `test-plan-E54.md`).
- E-55 discovery/offline state machine.
- F1 touch playback controls and F2 multiroom grouping chip interactions (`ChipKind.loading`, `ChipData.onTap`).
- Backend, telemetry, CI pipeline.
- The `.strings` / `.xcstrings` localisation mechanism — E-53 strings are delivered via `UIStrings`-style Swift structs, not `NSLocalizedString` keys (per ADR §8 CF-1). Tests assert on Swift struct property values, not on `NSLocalizedString` calls.

---

## 2. Test Environment

| Item | Value |
|---|---|
| Platform | iOS 26, iPhone (portrait) |
| Framework | SwiftUI, `@Observable @MainActor` |
| Test harness | XCTest (unit) + XCUITest (UI/acceptance) — no separate test target exists in the repo at plan-authoring time. Tests are written as specifications; an engineer creating the test target should place unit tests in a new `VoxioTests` target and UI tests in `VoxioUITests`. |
| Accessibility testing | Xcode Accessibility Inspector + VoiceOver on device/simulator |
| Dynamic Type | iOS Settings → Accessibility → Display & Text Size → Larger Text. Test at AX1 (smallest extra-large) and AX5 (largest). |
| Speaker doubles | Plain `SpeakerStub` value types for all unit-level TCs. `ChipData` can be constructed directly without a live `Speaker`. `SpeakerStub` must expose `id: UUID` and `name: String` to satisfy the `SpeakerCard` call-site contract. |
| Language switching | `LanguageService.shared.activeLanguage` — set to `.english` or `.danish` in test setup/teardown. |
| Source files under test | `iOS/Voxio/Features/Home/Components/GroupChipRow.swift`, `iOS/Voxio/Features/Home/SpeakerCard.swift`, `iOS/Voxio/Features/Home/SessionStripView.swift`, `iOS/Voxio/Core/Strings/UIStrings.swift` (or `GroupChipStrings.swift`) |

---

## 3. Unit-Level Test Cases (ChipData model + overflow rule)

These cases test the `ChipData` struct and the overflow computation logic inside `SpeakerCard.chipData` in isolation. No SwiftUI rendering is required — assertions operate on the returned `[ChipData]` array via `@testable import Voxio`.

---

### TC-E53-U01

**ID:** TC-E53-U01
**Target:** `ChipData` — `Identifiable` via `id: UUID`
**Setup:** Construct two `ChipData` instances with `.member` kind and distinct `speakerName` values. Construct one further instance by copying the `id` from the first.
**Action:** Compare `chipA.id == chipCopy.id` and `chipA.id != chipB.id`.
**Expected:** Instances with the same `id` UUID are equal by `id`; instances constructed independently have distinct UUIDs. `ForEach(chips)` can use `id: \.id` without collision when each `ChipData` is constructed with a fresh `UUID()`.
**Covers ADR contract assertion:** §7 #12 (`ChipData` is `Identifiable` via `id: UUID`)
**Covers spec AC:** N/A (structural invariant)

---

### TC-E53-U02

**ID:** TC-E53-U02
**Target:** `SpeakerCard.chipData` — 0 members
**Setup:** Construct a `SpeakerCard` stub with `groupMembers: []`.
**Action:** Read `chipData` (via `@testable import Voxio` or a test-hook accessor).
**Expected:** `chipData` is an empty array `[]`. No `ChipData` items are produced.
**Covers ADR contract assertion:** §7 #1 (`GroupChipRow(chips: [])` produces no chips; this tests the upstream source of that empty array)
**Covers spec AC:** US-61 AC-5 (solo session: chip row absent — no members means no chips)

---

### TC-E53-U03

**ID:** TC-E53-U03
**Target:** `SpeakerCard.chipData` — 1 non-host member (no overflow)
**Setup:** Construct a `SpeakerCard` stub with `groupMembers: [memberA]`.
**Action:** Read `chipData`.
**Expected:** `chipData` contains exactly one element: `ChipData(speakerName: memberA.name, kind: .member)`. No overflow chip. Count is 1.
**Covers ADR contract assertion:** §7 #2 (1-member group: one `.member` chip rendered)
**Covers spec AC:** US-61 AC-1 (chip row shows each non-host member)

---

### TC-E53-U04

**ID:** TC-E53-U04
**Target:** `SpeakerCard.chipData` — 2 non-host members (no overflow)
**Setup:** Construct a `SpeakerCard` stub with `groupMembers: [memberA, memberB]`.
**Action:** Read `chipData`.
**Expected:** `chipData` contains exactly 2 elements, both `.member` kind, in the order `[memberA, memberB]`. No overflow chip.
**Covers ADR contract assertion:** §7 #3 (3 or fewer members: one chip per member, no overflow)
**Covers spec AC:** US-61 AC-1; UQ-3 (array order preserved — no sorting)

---

### TC-E53-U05

**ID:** TC-E53-U05
**Target:** `SpeakerCard.chipData` — 3 non-host members (boundary: exactly at overflow threshold, no overflow)
**Setup:** Construct a `SpeakerCard` stub with `groupMembers: [memberA, memberB, memberC]`.
**Action:** Read `chipData`.
**Expected:** `chipData` contains exactly 3 elements: `.member`, `.member`, `.member`. No `.overflow(_)` chip. Count is 3. The overflow rule applies when `members.count > 3`, so 3 is the last no-overflow value.
**Covers ADR contract assertion:** §7 #3 (3 members: three `.member` chips, no overflow)
**Covers spec AC:** US-61 AC-1; US-61 AC-4 ("more than 3 non-host members" triggers overflow — 3 does not)

---

### TC-E53-U06

**ID:** TC-E53-U06
**Target:** `SpeakerCard.chipData` — 4 non-host members (first overflow case: 2 + `.overflow(2)`)
**Setup:** Construct a `SpeakerCard` stub with `groupMembers: [memberA, memberB, memberC, memberD]`.
**Action:** Read `chipData`.
**Expected:** `chipData` contains exactly 3 elements: `chipData[0]` is `.member` for `memberA`, `chipData[1]` is `.member` for `memberB`, `chipData[2]` is `.overflow(2)` (Int = `4 - 2 = 2`). Total count is 3. The overflow chip's `speakerName` may be empty string or a placeholder — the rendered label is derived from the `kind`, not from `speakerName`.
**Covers ADR contract assertion:** §7 #4 (`groupMembers.count == 4` → 2 `.member` + 1 `.overflow(2)`)
**Covers spec AC:** US-61 AC-4 (">3 non-host members: first 2 chips + `+N more`")

---

### TC-E53-U07

**ID:** TC-E53-U07
**Target:** `SpeakerCard.chipData` — 5 non-host members (2 + `.overflow(3)`)
**Setup:** Construct a `SpeakerCard` stub with `groupMembers: [memberA, memberB, memberC, memberD, memberE]`.
**Action:** Read `chipData`.
**Expected:** `chipData` has 3 elements: 2 × `.member` + `.overflow(3)` (Int = `5 - 2 = 3`).
**Covers ADR contract assertion:** §7 #4 (overflow Int = `remaining count`)
**Covers spec AC:** US-61 AC-4

---

### TC-E53-U08

**ID:** TC-E53-U08
**Target:** `SpeakerCard.chipData` — 10 non-host members (2 + `.overflow(8)`)
**Setup:** Construct a `SpeakerCard` stub with `groupMembers` of 10 distinct speakers.
**Action:** Read `chipData`.
**Expected:** `chipData` has 3 elements: 2 × `.member` + `.overflow(8)` (Int = `10 - 2 = 8`). The first 2 member chips correspond to the first 2 speakers in the `groupMembers` array order (UQ-3: no sorting). No 4th element.
**Covers ADR contract assertion:** §7 #4 (overflow at any N > 3: always 2 member chips + 1 overflow chip)
**Covers spec AC:** US-61 AC-4; UQ-3 (discovery order preserved for first 2 visible chips)

---

### TC-E53-U09

**ID:** TC-E53-U09
**Target:** `ChipKind` — `Equatable` conformance
**Setup:** Construct `ChipKind.member` twice and `ChipKind.overflow(2)` vs `ChipKind.overflow(3)`.
**Action:** Assert equality and inequality.
**Expected:** `.member == .member` is `true`. `.overflow(2) == .overflow(2)` is `true`. `.overflow(2) == .overflow(3)` is `false`. `.member == .overflow(2)` is `false`. The `Equatable` conformance is correct and complete.
**Covers ADR contract assertion:** §7 (ADR §3 defines `enum ChipKind: Equatable`)
**Covers spec AC:** N/A (structural invariant; enables test assertions elsewhere)

---

### TC-E53-U10

**ID:** TC-E53-U10
**Target:** `SpeakerCard.chipData` — member order matches `groupMembers` input order (UQ-3)
**Setup:** Construct `groupMembers = [speakerZ, speakerA, speakerM]` (intentionally non-alphabetical).
**Action:** Read `chipData`.
**Expected:** `chipData[0].speakerName == speakerZ.name`, `chipData[1].speakerName == speakerA.name`, `chipData[2].speakerName == speakerM.name`. No sorting has been applied. The output order equals the input order.
**Covers ADR contract assertion:** §7 (ADR §2 resolved UQ-3: chips render in the order received, no sorting)
**Covers spec AC:** US-61 AC-1 (implied — order matches `SpeakerGroup.members` discovery order)

---

## 4. Unit-Level Test Cases (GroupChipRow rendering)

These cases test the `GroupChipRow` struct in isolation using ViewInspector or equivalent snapshot infrastructure that can inspect the SwiftUI view hierarchy from `@testable import Voxio`. Where modifier values cannot be directly inspected, assertions are expressed as code-review invariants that must be confirmed during implementation review.

---

### TC-E53-U11

**ID:** TC-E53-U11
**Target:** `GroupChipRow` — empty chips array returns no view
**Setup:** Instantiate `GroupChipRow(chips: [])`.
**Action:** Inspect the rendered view type.
**Expected:** The view returns `EmptyView()` — no `HStack`, no `Capsule`, no zero-height container. The element count in the SwiftUI hierarchy is zero. No crash.
**Covers ADR contract assertion:** §7 #1 (`GroupChipRow(chips: [])` renders no view)
**Covers spec AC:** US-61 AC-5 (solo session: chip row absent, no empty space)

---

### TC-E53-U12

**ID:** TC-E53-U12
**Target:** `GroupChipRow` — one `.member` chip renders correct label
**Setup:** Construct `chips = [ChipData(id: UUID(), speakerName: "Stue", kind: .member)]`. Instantiate `GroupChipRow(chips: chips)`.
**Action:** Inspect the `Text` view inside the first (and only) chip.
**Expected:** The `Text` content is `"+ Stue"` — the `+` prefix is present, followed by a space, followed by the `speakerName`. Font is `BeoType.caption`. Foreground colour is `BeoColor.muted`. One `Capsule()` shape is present as the chip background with `.white.opacity(0.07)` fill.
**Covers ADR contract assertion:** §7 #2 (1 `.member` chip: label `"+ SpeakerName"`) and #3 (background `.white.opacity(0.07)` in `Capsule()`)
**Covers spec AC:** US-61 AC-1; design-spec §3.4 (chip label format, font, colour, background)

---

### TC-E53-U13

**ID:** TC-E53-U13
**Target:** `GroupChipRow` — three `.member` chips, no overflow chip
**Setup:** Construct 3 member `ChipData` items. Instantiate `GroupChipRow(chips: chips)`.
**Action:** Count the `Capsule` shapes in the rendered hierarchy. Inspect each chip label.
**Expected:** Exactly 3 `Capsule` shapes. Labels are `"+ SpeakerA"`, `"+ SpeakerB"`, `"+ SpeakerC"` respectively. No chip contains a `+N more` / `+N flere` pattern. The `HStack` spacing is `Spacing.s8`.
**Covers ADR contract assertion:** §7 #3 (3 `.member` chips: three `Capsule` views rendered)
**Covers spec AC:** US-61 AC-1, AC-4

---

### TC-E53-U14

**ID:** TC-E53-U14
**Target:** `GroupChipRow` — `.overflow(2)` chip renders correct English label
**Setup:** Set `LanguageService.shared.activeLanguage = .english`. Construct `chips` with 2 `.member` chips + 1 `.overflow(2)` chip. Instantiate `GroupChipRow(chips: chips)`.
**Action:** Inspect the `Text` content of the third chip (index 2).
**Expected:** The label is `"+2 more"` — the integer is 2, the suffix is " more" (English). The chip is visually identical to a member chip (same `Capsule`, same background, same `BeoType.caption`, same `BeoColor.muted` foreground).
**Covers ADR contract assertion:** §7 #5 (overflow chip renders `"+N more"` in English)
**Covers spec AC:** US-61 AC-4; design-spec §3.4 (overflow chip visually identical to member chip)

---

### TC-E53-U15

**ID:** TC-E53-U15
**Target:** `GroupChipRow` — `.overflow(2)` chip renders correct Danish label
**Setup:** Set `LanguageService.shared.activeLanguage = .danish`. Same `chips` as TC-E53-U14. Instantiate `GroupChipRow(chips: chips)`.
**Action:** Inspect the `Text` content of the third chip.
**Expected:** The label is `"+2 flere"` — the integer is 2, the suffix is " flere" (Danish). The English suffix "more" does not appear.
**Covers ADR contract assertion:** §7 #5 (overflow chip renders `"+N flere"` in Danish, switching on `LanguageService.shared.activeLanguage`)
**Covers spec AC:** US-61 AC-4 (localisation)

---

### TC-E53-U16

**ID:** TC-E53-U16
**Target:** `GroupChipRow` — `.overflow(8)` chip renders correct count in both languages
**Setup:** Construct `chips` with 2 `.member` chips + 1 `.overflow(8)` chip. Test once with `.english`, once with `.danish`.
**Action:** Inspect the overflow chip label in each language.
**Expected:** English: `"+8 more"`. Danish: `"+8 flere"`. The integer 8 is rendered correctly in both locales. No off-by-one (e.g. `+7` or `+9`) is present.
**Covers ADR contract assertion:** §7 #5 (overflow chip renders correct N for all values of the `Int` associated value)
**Covers spec AC:** US-61 AC-4

---

### TC-E53-U17

**ID:** TC-E53-U17
**Target:** `GroupChipRow` — chip padding tokens
**Setup:** Instantiate `GroupChipRow(chips: [ChipData(id: UUID(), speakerName: "Kitchen", kind: .member)])`.
**Action:** Inspect the `.padding` modifier applied to the chip's `Text` or inner content.
**Expected:** Horizontal padding is `Spacing.s8` (8 pt). Vertical padding is `Spacing.s4` (4 pt). These values match design-spec §3.4 exactly. No other padding values are used on the chip itself. (Outer row padding is applied at the `SpeakerCard` call site — not inside `GroupChipRow`.)
**Covers ADR contract assertion:** §7 #3 (padding `Spacing.s8` horizontal, `Spacing.s4` vertical — ADR §7 behavioural contract item 3)
**Covers spec AC:** design-spec §3.4 (chip anatomy — padding)

---

### TC-E53-U18

**ID:** TC-E53-U18
**Target:** `GroupChipRow` — no tap handler on `.member` chip
**Setup:** Instantiate `GroupChipRow(chips: [ChipData(id: UUID(), speakerName: "Kontor", kind: .member)])`.
**Action:** Inspect the chip view for `Button` wrappers or `.onTapGesture` modifiers. Simulate a tap gesture on the chip (via XCUITest hit-test or ViewInspector). Confirm no action is dispatched.
**Expected:** No `Button` wrapper and no `.onTapGesture` modifier are present on the chip. Tapping the chip produces no observable state change, no callback, and no navigation. The chip is display-only.
**Covers ADR contract assertion:** §7 #5 (no `Button` wrapper, no `.onTapGesture` — chips are display-only in E-53)
**Covers spec AC:** US-61 AC-6 (tapping a member chip is a no-op in F3)

---

### TC-E53-U19

**ID:** TC-E53-U19
**Target:** `GroupChipRow` — no tap handler on `.overflow` chip
**Setup:** Construct `chips` with 1 `.overflow(3)` chip. Instantiate `GroupChipRow(chips: chips)`. Simulate a tap.
**Action:** Same inspection as TC-E53-U18 but for the overflow chip.
**Expected:** No `Button`, no `.onTapGesture`. Tapping the overflow chip produces no action.
**Covers ADR contract assertion:** §7 #5 and ADR §2 resolved UQ-6 (overflow chip tap deferred to F2 — no tap handler in E-53)
**Covers spec AC:** US-61 AC-6

---

### TC-E53-U20

**ID:** TC-E53-U20
**Target:** `GroupChipRow` — `Text` truncation, not reflow, at large Dynamic Type
**Setup:** Set Dynamic Type size to AX5. Instantiate `GroupChipRow` with one `.member` chip whose `speakerName` is a long string (e.g. `"Badeværelse og Soveværelse"`).
**Action:** Render the chip inside a card-width container (≈ `screenWidth - Spacing.s24 * 2`). Inspect the `Text` modifier stack.
**Expected:** The `Text` view has `.lineLimit(1)` and `.truncationMode(.tail)`. The chip does not expand vertically to accommodate the larger text. The chip text is truncated with a trailing ellipsis if it exceeds the available horizontal space. The `HStack` containing the chips does NOT wrap to a second line (`FlowLayout` is not used).
**Covers ADR contract assertion:** §7 #6 (`.lineLimit(1)`, `.truncationMode(.tail)` — no vertical reflow; ADR §5 Consequences: "truncation is the correct behaviour")
**Covers spec AC:** US-61 AC-3 (chip row layout per design-spec §3.4); T-5309 (AX5 truncation verification)

---

### TC-E53-U21

**ID:** TC-E53-U21
**Target:** `GroupChipRow` — `.member` chip `accessibilityLabel` in English
**Setup:** Set language to English. Construct `chips = [ChipData(id: UUID(), speakerName: "Stue", kind: .member)]`. Instantiate `GroupChipRow(chips: chips)`.
**Action:** Inspect the `accessibilityLabel` modifier on the first chip view.
**Expected:** The `accessibilityLabel` is `"Also playing: Stue"`. The format matches design-spec Appendix B `a11y.alsoPlaying` in English. The chip's visible label (`"+ Stue"`) and its accessibility label (`"Also playing: Stue"`) differ intentionally.
**Covers ADR contract assertion:** §7 #7 (member chip `accessibilityLabel` = `"Also playing: \(speakerName)"` in English)
**Covers spec AC:** US-61 AC-8 (VoiceOver reads card including appended group members — per chip label)

---

### TC-E53-U22

**ID:** TC-E53-U22
**Target:** `GroupChipRow` — `.member` chip `accessibilityLabel` in Danish
**Setup:** Set language to Danish. Same chip as TC-E53-U21.
**Action:** Inspect the `accessibilityLabel`.
**Expected:** The `accessibilityLabel` is `"Spiller også: Stue"`. The English variant `"Also playing: Stue"` does not appear.
**Covers ADR contract assertion:** §7 #7 (member chip `accessibilityLabel` = `"Spiller også: \(speakerName)"` in Danish)
**Covers spec AC:** US-61 AC-8 (localisation)

---

### TC-E53-U23

**ID:** TC-E53-U23
**Target:** `GroupChipRow` — `.overflow(2)` chip `accessibilityLabel` in English
**Setup:** Set language to English. Construct a `.overflow(2)` `ChipData`. Instantiate `GroupChipRow(chips: [chipData])`.
**Action:** Inspect the `accessibilityLabel` on the overflow chip view.
**Expected:** The `accessibilityLabel` is `"2 more speakers in this group"`. The value `2` is the associated `Int` of the `.overflow(2)` case.
**Covers ADR contract assertion:** §7 #6 (overflow chip `accessibilityLabel`: `"\(N) more speakers in this group"` in English)
**Covers spec AC:** US-61 AC-8

---

### TC-E53-U24

**ID:** TC-E53-U24
**Target:** `GroupChipRow` — `.overflow` chip `accessibilityLabel` in Danish
**Setup:** Set language to Danish. Construct `.overflow(3)` `ChipData`. Instantiate `GroupChipRow`.
**Action:** Inspect the `accessibilityLabel` on the overflow chip.
**Expected:** The `accessibilityLabel` is the Danish equivalent of `"3 more speakers in this group"` — exact Danish string must match the value defined in the `UIStrings`/`GroupChipStrings` struct for that key. The English string is absent.
**Covers ADR contract assertion:** §7 #6 (overflow chip `accessibilityLabel` in Danish)
**Covers spec AC:** US-61 AC-8 (localisation)

---

### TC-E53-U25

**ID:** TC-E53-U25
**Target:** `GroupChipRow` — no outer padding; padding applied by `SpeakerCard` call site
**Setup:** Instantiate `GroupChipRow(chips: [ChipData(id: UUID(), speakerName: "X", kind: .member)])` directly (outside of `SpeakerCard`).
**Action:** Inspect for `.padding(.horizontal, Spacing.s24)` and `.padding(.bottom, Spacing.s16)` modifiers on the `GroupChipRow` root view itself.
**Expected:** No `.padding(.horizontal, Spacing.s24)` or `.padding(.bottom, Spacing.s16)` is applied inside `GroupChipRow`. The row's leading edge aligns to its parent's leading edge. This padding is the caller's responsibility (applied by `SpeakerCard`). Code-review assertion: confirm the padding modifiers are at the `SpeakerCard` call site.
**Covers ADR contract assertion:** §7 #8 ("The row does not carry its own horizontal or bottom padding. Padding is applied at the `SpeakerCard` call site.")
**Covers spec AC:** design-spec §3.4 (padding below chip row: `Spacing.s16` to card edge — owned by `SpeakerCard`)

---

## 5. Integration Test Cases (SpeakerCard with groupMembers)

These cases render `SpeakerCard` with a `groupMembers` parameter and assert on visible output, layout, and the `chipData` conversion. They require a `SpeakerStub` that implements the `Speaker` interface and sets `isPlaying = true` unless noted.

---

### TC-E53-I01

**ID:** TC-E53-I01
**Target:** `SpeakerCard` — empty `groupMembers` (default): no chip row, no empty space
**Setup:** Construct `SpeakerCard(speaker: playingSpeaker, isExpanded: false, roll: 0, pitch: 0)` — no `groupMembers` argument (uses default `= []`).
**Action:** Inspect the `cardContent` view hierarchy below the `volumeTrack` block.
**Expected:** No `GroupChipRow` is present. No empty `HStack` or zero-height container occupies the space below `volumeTrack`. The card's trailing edge (after `volumeTrack`) matches the E-52 contract — no visual regression. The call site compiles without providing `groupMembers:`.
**Covers ADR contract assertion:** §7 SpeakerCard behavioural contract #1 (empty `groupMembers`: `cardContent` unchanged from E-52)
**Covers spec AC:** US-61 AC-5 (no chip row when solo session); E-52 backward-compatibility

---

### TC-E53-I02

**ID:** TC-E53-I02
**Target:** `SpeakerCard` — non-empty `groupMembers`, `speaker.isPlaying == true`: chip row appears
**Setup:** Construct `SpeakerCard(speaker: playingSpeaker, isExpanded: false, roll: 0, pitch: 0, groupMembers: [memberA, memberB])`. `playingSpeaker.isPlaying = true`.
**Action:** Inspect `cardContent` below `volumeTrack`.
**Expected:** `GroupChipRow(chips: chipData)` is rendered with `.padding(.horizontal, Spacing.s24).padding(.bottom, Spacing.s16)`. Two chips are visible: `"+ <memberA.name>"` and `"+ <memberB.name>"`. The chips appear after the volume track block and before the card's bottom edge.
**Covers ADR contract assertion:** §7 SpeakerCard behavioural contract #2 (`!groupMembers.isEmpty` → `GroupChipRow` rendered below `volumeTrack` with correct padding)
**Covers spec AC:** US-61 AC-1, AC-3

---

### TC-E53-I03

**ID:** TC-E53-I03
**Target:** `SpeakerCard` — non-empty `groupMembers`, `speaker.isPlaying == false`: chip row absent
**Setup:** Construct `SpeakerCard(speaker: idleSpeaker, isExpanded: false, roll: 0, pitch: 0, groupMembers: [memberA, memberB])`. `idleSpeaker.isPlaying = false`.
**Action:** Inspect `cardContent`.
**Expected:** `GroupChipRow` is NOT rendered. The chip row is absent even though `groupMembers` is non-empty. This is because the chip row lives inside the `if speaker.isPlaying { }` conditional block in `cardContent`, which gates both `volumeTrack` and `GroupChipRow`. No empty space appears.
**Covers ADR contract assertion:** §7 SpeakerCard behavioural contract #3 (chip row only when `speaker.isPlaying`)
**Covers spec AC:** N/A direct AC, but aligns with spec §Error States ("chip row appears only on playing session cards") and ADR §8 CF-2

---

### TC-E53-I04

**ID:** TC-E53-I04
**Target:** `SpeakerCard` — host speaker NOT in chip row
**Setup:** Construct `SpeakerCard(speaker: host, isExpanded: false, roll: 0, pitch: 0, groupMembers: [memberA, memberB])` where `host` is distinct from `memberA` and `memberB`.
**Action:** Inspect all chip labels in the rendered chip row.
**Expected:** No chip has label `"+ \(host.name)"`. Only `"+ \(memberA.name)"` and `"+ \(memberB.name)"` are present. The host speaker (the card title) is not duplicated in the chip row.
**Covers ADR contract assertion:** §7 (SpeakerCard receives `groupMembers` already filtered to exclude the host — T-5306)
**Covers spec AC:** US-61 AC-2 ("The host speaker (the card's title) is never repeated in the chip row")

---

### TC-E53-I05

**ID:** TC-E53-I05
**Target:** `SpeakerCard` — 4 `groupMembers`: chip row shows 2 members + overflow chip
**Setup:** Construct `SpeakerCard` with `groupMembers: [mA, mB, mC, mD]`. `speaker.isPlaying = true`.
**Action:** Inspect the rendered `GroupChipRow` chips.
**Expected:** Exactly 3 chips are rendered: `"+ \(mA.name)"`, `"+ \(mB.name)"`, and the overflow chip (`"+2 more"` in English / `"+2 flere"` in Danish). No chip for `mC` or `mD` is shown directly.
**Covers ADR contract assertion:** §7 #4 (`groupMembers.count == 4` → 3 `ChipData` items: 2 `.member` + 1 `.overflow(2)`)
**Covers spec AC:** US-61 AC-4 (overflow rule)

---

### TC-E53-I06

**ID:** TC-E53-I06
**Target:** `SpeakerCard.accessibilityDescription` — with `groupMembers`
**Setup:** Construct `SpeakerCard` with `groupMembers: [memberA, memberB]`. `speaker.isPlaying = true`. `speaker.name = "Badeværelse"`.
**Action:** Read `accessibilityDescription` (via `@testable import Voxio` or by inspecting the `accessibilityLabel` of the rendered card element).
**Expected:** The string ends with `"Also playing: \(memberA.name), \(memberB.name)"` — the names are comma-separated, in the order they appear in `groupMembers`. The "Also playing:" prefix uses the localised string for the active language. The preceding parts of the description (speaker name, state, track, source badge, volume) are unchanged from the E-52 contract.
**Covers ADR contract assertion:** §7 #8 (`accessibilityDescription` ends with `"Also playing: MemberA, MemberB"`)
**Covers spec AC:** US-61 AC-8 (VoiceOver reads card including group members)

---

### TC-E53-I07

**ID:** TC-E53-I07
**Target:** `SpeakerCard.accessibilityDescription` — without `groupMembers`
**Setup:** Construct `SpeakerCard` with default `groupMembers: []`. `speaker.isPlaying = true`.
**Action:** Read `accessibilityDescription`.
**Expected:** The string does NOT contain "Also playing". The description is identical to the E-52 contract output. No trailing comma or empty fragment appears.
**Covers ADR contract assertion:** §7 #9 (`groupMembers: []` → same `accessibilityDescription` as E-52 — no "Also playing" suffix)
**Covers spec AC:** US-61 AC-8 (solo session VoiceOver label is clean)

---

### TC-E53-I08

**ID:** TC-E53-I08
**Target:** `SpeakerCard.accessibilityDescription` — Danish localisation of "Also playing"
**Setup:** Set language to Danish. Construct `SpeakerCard` with `groupMembers: [memberA]`.
**Action:** Read `accessibilityDescription`.
**Expected:** The appended portion reads `"Spiller også: \(memberA.name)"`. The English string "Also playing" does not appear.
**Covers ADR contract assertion:** §7 #8 (localised "Also playing" string from `UIStrings`/`GroupChipStrings`)
**Covers spec AC:** US-61 AC-8 (localisation)

---

### TC-E53-I09

**ID:** TC-E53-I09
**Target:** `SpeakerCard` — VoiceOver: chip row children not separately focusable
**Setup:** Enable VoiceOver. Render `SpeakerCard` with `groupMembers: [memberA, memberB]` in a host view. Navigate to the session card element with VoiceOver.
**Action:** Attempt to swipe VoiceOver focus into the chip row children.
**Expected:** The chip row chips are NOT separately announced as individual accessibility elements. VoiceOver does not stop on any chip. The card uses `accessibilityElement(children: .ignore)` (per design-spec §3.7), which suppresses the chip views' own accessibility elements. The chip names appear only as part of the card's combined `accessibilityLabel`.
**Covers ADR contract assertion:** §7 SpeakerCard behavioural contracts (VoiceOver: chip row labels in card's accessibility description, not as separate elements — design-spec §3.7)
**Covers spec AC:** US-61 AC-8; design-spec §3.7; T-5310 (VoiceOver verification)

---

### TC-E53-I10

**ID:** TC-E53-I10
**Target:** `SpeakerCard` — group composition change: chip row updates in place without full card re-render
**Setup:** Render `SpeakerCard` with `groupMembers: [memberA]` inside a host view that owns `@State var members: [Speaker]`.
**Action:** Mutate `members` to append `memberB`. Allow one SwiftUI update cycle.
**Expected:** The chip row updates to show 2 chips (`"+ \(memberA.name)"`, `"+ \(memberB.name)"`). The card's upper regions (speaker name, state label, now-playing panel, volume track) do NOT re-render visually — SwiftUI's diffing updates only the `GroupChipRow` subtree. If reflow jank is observed, verify that a `.transition(.opacity)` is applied to chip insertions per T-5307.
**Covers ADR contract assertion:** N/A direct ADR assertion; covers US-61 AC-7 and error state "Group composition changes while session card is visible"
**Covers spec AC:** US-61 AC-7 (chip row updates immediately without re-rendering the rest of the card); spec Error States

---

## 6. Acceptance Test Cases (SessionStripView filter + end-to-end)

These cases test the `SessionStripView` call-site filter that derives `groupMembers` for each card, and the end-to-end path from `SpeakerGroup.members` through to the rendered chip row. They require `SpeakerGroup` stubs and a rendered `SessionStripView` or `HomeView` in a host view.

---

### TC-E53-A01

**ID:** TC-E53-A01
**Target:** `SessionStripView` — solo session: filter produces `[]`, chip row absent
**Setup:** Create a `SpeakerGroup` with host `H` and `members: [H]` (H is the only member — solo session). `H.isPlaying = true`. Render `SessionStripView(groups: [group], ...)`.
**Action:** Inspect the `SpeakerCard` call in the `ForEach`. Read the `groupMembers` argument passed to `SpeakerCard`.
**Expected:** `group.members.filter { $0.id != group.hostSpeaker.id }` produces `[]` (empty — no members other than the host). `SpeakerCard` receives `groupMembers: []`. No chip row is rendered in the card. No empty space appears below the volume track.
**Covers ADR contract assertion:** §7 SessionStripView behavioural contract #11 (solo session: `SessionStripView` passes `groupMembers: []`)
**Covers spec AC:** US-61 AC-5 (solo host: chip row absent)

---

### TC-E53-A02

**ID:** TC-E53-A02
**Target:** `SessionStripView` — 2-speaker group: filter passes 1 non-host member
**Setup:** Create a `SpeakerGroup` with host `H` and `members: [H, memberA]`. Render `SessionStripView(groups: [group], ...)`.
**Action:** Inspect the `groupMembers` argument passed to `SpeakerCard`.
**Expected:** `groupMembers` = `[memberA]`. Host `H` is excluded by the filter. The chip row renders one chip: `"+ \(memberA.name)"`.
**Covers ADR contract assertion:** §7 SessionStripView behavioural contract — filter correctness; #1 (host never in chip row)
**Covers spec AC:** US-61 AC-1, AC-2

---

### TC-E53-A03

**ID:** TC-E53-A03
**Target:** `SessionStripView` — 4-speaker group: filter passes 3 non-host members → overflow triggers
**Setup:** Create a `SpeakerGroup` with host `H` and `members: [H, mA, mB, mC]` (3 non-host members = count at threshold). Render strip.
**Action:** Inspect `groupMembers` passed to `SpeakerCard` and the resulting `chipData`.
**Expected:** `groupMembers` = `[mA, mB, mC]` (3 elements). `chipData` = 3 × `.member` (no overflow — `count == 3` is within the no-overflow range). Chip row shows 3 chips.
**Covers ADR contract assertion:** §7 #3 (3 chips: no overflow)
**Covers spec AC:** US-61 AC-4 (overflow threshold is ">3 non-host members")

---

### TC-E53-A04

**ID:** TC-E53-A04
**Target:** `SessionStripView` — 5-speaker group: filter passes 4 non-host members → overflow triggers
**Setup:** Create a `SpeakerGroup` with host `H` and `members: [H, mA, mB, mC, mD]` (4 non-host members). Render strip.
**Action:** Inspect `groupMembers` and the rendered chips.
**Expected:** `groupMembers` = `[mA, mB, mC, mD]` (4 elements). `chipData` = 2 × `.member` + `.overflow(2)`. Rendered chips: `"+ \(mA.name)"`, `"+ \(mB.name)"`, `"+2 more"` (English). `mC` and `mD` are not shown directly.
**Covers ADR contract assertion:** §7 #4 (`groupMembers.count == 4` → overflow)
**Covers spec AC:** US-61 AC-4

---

### TC-E53-A05

**ID:** TC-E53-A05
**Target:** `SessionStripView` — member array order follows `SpeakerGroup.members` order (UQ-3)
**Setup:** Create a `SpeakerGroup` with host `H` and `members: [H, mZ, mA, mM]` (non-alphabetical). Render strip.
**Action:** Inspect the order of chips rendered in the chip row.
**Expected:** Chip 1 is `"+ \(mZ.name)"`, chip 2 is `"+ \(mA.name)"`, chip 3 is `"+ \(mM.name)"`. The order matches `SpeakerGroup.members` order (minus the host). No alphabetical or other sorting has been applied.
**Covers ADR contract assertion:** §7 SessionStripView behavioural contract #3 ("members array order is the `SpeakerGroup.members` order; do NOT sort")
**Covers spec AC:** US-61 AC-1 (implied order); spec Resolved Decisions UQ-3

---

### TC-E53-A06

**ID:** TC-E53-A06
**Target:** `SessionStripView` — multiple groups: each card's chip row is independent
**Setup:** Create two groups: group A (host `H_A`, members `[H_A, mA1, mA2]`) and group B (host `H_B`, members `[H_B, mB1]`). Both groups playing. Render `SessionStripView(groups: [groupA, groupB], ...)`.
**Action:** Inspect the `groupMembers` passed to each `SpeakerCard`.
**Expected:** Card for group A receives `groupMembers: [mA1, mA2]`. Card for group B receives `groupMembers: [mB1]`. No cross-contamination. Each card's chip row reflects its own group's non-host members only.
**Covers ADR contract assertion:** §7 (per-card chip isolation — each `SpeakerCard` in the `ForEach` gets its own filtered array)
**Covers spec AC:** US-61 AC-1

---

## 7. Error States and Boundary Values

---

### TC-E53-E01

**ID:** TC-E53-E01
**Target:** `GroupChipRow` — boundary: exactly 1 chip (`.overflow(1)` is not produced by E-53; but `.member` count of 1)
**Setup:** Construct `chips = [ChipData(id: UUID(), speakerName: "Pejsestuen", kind: .member)]`.
**Action:** Render `GroupChipRow(chips: chips)`. Confirm no crash and correct output.
**Expected:** One `Capsule` chip rendered with label `"+ Pejsestuen"`. `HStack` is present (non-empty input). No overflow chip. No crash.
**Covers ADR contract assertion:** §7 #2 (1-member: one chip rendered)
**Covers spec AC:** US-61 AC-1

---

### TC-E53-E02

**ID:** TC-E53-E02
**Target:** `SpeakerCard.chipData` — boundary: `groupMembers.count == 0`
**Setup:** `groupMembers = []`. Read `chipData`.
**Action:** See TC-E53-U02 — this entry cross-references the boundary at 0.
**Expected:** `chipData` = `[]`. Documented here as the explicit 0-member boundary case confirming the overflow guard is not entered.
**Covers ADR contract assertion:** §7 SpeakerCard contract #1
**Covers spec AC:** US-61 AC-5

---

### TC-E53-E03

**ID:** TC-E53-E03
**Target:** `SpeakerCard.chipData` — chip with very long `speakerName`
**Setup:** Construct `SpeakerCard` with `groupMembers: [Speaker(name: "Køkken, Stue, Soveværelse og Badeværelse")]` (excessively long name). `speaker.isPlaying = true`.
**Action:** Render the chip row inside a card-width container. Observe chip rendering.
**Expected:** The chip renders with `.lineLimit(1)` and `.truncationMode(.tail)` — the long name is truncated with ellipsis. The card layout is not broken. No runtime crash (e.g. no unconstrained layout or zero-size frame assertion).
**Covers ADR contract assertion:** §7 #6 (`.lineLimit(1)`, `.truncationMode(.tail)` — long names truncate)
**Covers spec AC:** US-61 AC-3 (chip row layout per design-spec §3.4)

---

### TC-E53-E04

**ID:** TC-E53-E04
**Target:** `GroupChipRow` — Dynamic Type AX1: chips remain compact and legible
**Setup:** Set Dynamic Type to AX1 (smallest extra-large size, still above default). Render `GroupChipRow` with 2 member chips.
**Action:** Observe chip height and text legibility.
**Expected:** Chips are rendered at a compact height consistent with `BeoType.caption` at AX1 scaling. Text is legible (not truncated at AX1 — only very long names would truncate at this size). The card layout is not disrupted.
**Covers ADR contract assertion:** §7 #6 (Dynamic Type — chips truncate, don't reflow)
**Covers spec AC:** T-5309 (Dynamic Type AX1 verification)

---

### TC-E53-E05

**ID:** TC-E53-E05
**Target:** `GroupChipRow` — Dynamic Type AX5: chips truncate, `HStack` does not wrap
**Setup:** Set Dynamic Type to AX5 (largest extra-large size). Render `GroupChipRow` with 3 member chips inside a card-width container.
**Action:** Observe chip rendering and `HStack` layout.
**Expected:** Chips remain on a single horizontal row — no vertical wrapping occurs. Individual chip text may be truncated with a trailing ellipsis. The `HStack` does not become a `VStack` or `LazyVGrid`. Card layout above and below the chip row is not disrupted.
**Covers ADR contract assertion:** §7 #6 ("The row does NOT reflow vertically at large Dynamic Type sizes")
**Covers spec AC:** T-5309 (Dynamic Type AX5 verification)

---

### TC-E53-E06

**ID:** TC-E53-E06
**Target:** `SpeakerCard` — `groupMembers` update while visible: chip row updates, card stable
**Setup:** Render `SpeakerCard` with `groupMembers: [mA, mB]` inside a `@State`-driven host view. Both chips visible.
**Action:** Remove `mB` from `groupMembers` (leaving `[mA]`). Allow one SwiftUI update cycle.
**Expected:** Chip row updates to show only one chip. The chip for `mB` is removed. The card regions above the chip row (speaker name, now-playing panel, volume track) remain visually stable — no full re-render or layout shift. If a `.transition(.opacity)` is configured on chip removal per T-5307, the removal is smooth.
**Covers ADR contract assertion:** N/A direct ADR assertion
**Covers spec AC:** US-61 AC-7 (group composition change: chip row updates immediately without re-rendering the rest)

---

### TC-E53-E07

**ID:** TC-E53-E07
**Target:** `SpeakerCard` — `isPlaying` transitions from `true` to `false` while `groupMembers` non-empty
**Setup:** Render `SpeakerCard` with `speaker.isPlaying = true` and `groupMembers: [mA]`. Chip row is visible.
**Action:** Mutate `speaker.isPlaying = false`. Allow one SwiftUI update cycle.
**Expected:** The chip row disappears (along with the `nowPlayingPanel` and `volumeTrack`) because it is inside the `if speaker.isPlaying { }` block. No orphaned chip row remains. No crash.
**Covers ADR contract assertion:** §7 SpeakerCard behavioural contract #3 (chip row absent when `speaker.isPlaying == false`)
**Covers spec AC:** ADR §8 CF-2 (chip row is inside `isPlaying` gate)

---

### TC-E53-E08

**ID:** TC-E53-E08
**Target:** Localisation strings — English `UIStrings` / `GroupChipStrings` property values
**Setup:** Access the string struct for E-53 (via `@testable import Voxio`). Language set to English.
**Action:** Read the property for "Also playing" and the "+N more" format.
**Expected:** The "Also playing" property value is exactly `"Also playing: %@"` (or equivalent format-string variant matching design-spec Appendix B `a11y.alsoPlaying`). The "+N more" format value produces `"+\(N) more"` when interpolated with an integer. No extra whitespace or punctuation is present.
**Covers ADR contract assertion:** ADR §8 CF-1 (strings implemented via `UIStrings`-style struct, not `NSLocalizedString` keys — test asserts on struct values)
**Covers spec AC:** US-61 AC-4, AC-8 (localisation correctness); design-spec Appendix B

---

### TC-E53-E09

**ID:** TC-E53-E09
**Target:** Localisation strings — Danish `UIStrings` / `GroupChipStrings` property values
**Setup:** Access the string struct. Language set to Danish.
**Action:** Read the Danish "Also playing" property and "+N flere" format.
**Expected:** The Danish "Also playing" property value produces `"Spiller også: \(name)"` when interpolated. The "+N" format produces `"+\(N) flere"`. No English strings bleed into the Danish path.
**Covers ADR contract assertion:** ADR §8 CF-1; §7 #5 and #7 (localisation via struct, not `.strings` file)
**Covers spec AC:** US-61 AC-4, AC-8 (Danish localisation)

---

## 8. Coverage Matrix (AC/ER → TC IDs)

| AC / Contract Assertion | TC IDs | Status |
|---|---|---|
| **ADR §7 #1** — `GroupChipRow(chips: [])` renders no view | TC-E53-U11, TC-E53-U02, TC-E53-I01 | Covered |
| **ADR §7 #2** — 1 `.member` chip: one `Capsule`, label `"+ SpeakerName"` | TC-E53-U12, TC-E53-E01 | Covered |
| **ADR §7 #3** — 3 `.member` chips: three `Capsule` views; background `.white.opacity(0.07)`, spacing `Spacing.s8`, padding `Spacing.s8`H/`Spacing.s4`V | TC-E53-U13, TC-E53-U17 | Covered |
| **ADR §7 #4** — `groupMembers.count == 4` → 2 `.member` + 1 `.overflow(2)` | TC-E53-U06, TC-E53-I05, TC-E53-A04 | Covered |
| **ADR §7 #5** — overflow chip label: `"+N more"` (EN) / `"+N flere"` (DA); `.overflow` chip tap-free | TC-E53-U14, TC-E53-U15, TC-E53-U16, TC-E53-U18, TC-E53-U19 | Covered |
| **ADR §7 #6** — overflow chip `accessibilityLabel` `"\(N) more speakers in this group"` (EN/DA) | TC-E53-U23, TC-E53-U24 | Covered |
| **ADR §7 #7** — member chip `accessibilityLabel` `"Also playing: \(speakerName)"` (EN) / `"Spiller også: \(speakerName)"` (DA) | TC-E53-U21, TC-E53-U22 | Covered |
| **ADR §7 #8** — `SpeakerCard` with `groupMembers: [mA, mB]` → `accessibilityDescription` ends with `"Also playing: mA, mB"` (EN) | TC-E53-I06, TC-E53-I08 | Covered |
| **ADR §7 #9** — `SpeakerCard` with `groupMembers: []` → same `accessibilityDescription` as E-52 | TC-E53-I07 | Covered |
| **ADR §7 #10** — chip row absent when `speaker.isPlaying == false` even with non-empty `groupMembers` | TC-E53-I03, TC-E53-E07 | Covered |
| **ADR §7 #11** — solo session (`members.count == 1`): `SessionStripView` passes `groupMembers: []` | TC-E53-A01 | Covered |
| **ADR §7 #12** — `ChipData` is `Identifiable` via `id: UUID` | TC-E53-U01 | Covered |
| **ADR §7 #13** — chip background is `.white.opacity(0.07)` in `Capsule()` | TC-E53-U12 | Covered |
| **ADR §7 #14** — no `Button` wrapper, no `.onTapGesture` on any chip in E-53 | TC-E53-U18, TC-E53-U19 | Covered |
| **US-61 AC-1** — chip row shows each non-host member as `"+ <name>"` | TC-E53-U12, TC-E53-U13, TC-E53-I02, TC-E53-A02 | Covered |
| **US-61 AC-2** — host speaker never in chip row | TC-E53-I04, TC-E53-A01 | Covered |
| **US-61 AC-3** — chip row layout per design-spec §3.4 (font, colour, background, padding) | TC-E53-U12, TC-E53-U17, TC-E53-E03 | Covered |
| **US-61 AC-4** — >3 non-host members: first 2 chips + `+N more`; overflow threshold | TC-E53-U05, TC-E53-U06, TC-E53-U07, TC-E53-U08, TC-E53-A03, TC-E53-A04 | Covered |
| **US-61 AC-5** — solo session (one member = host): chip row absent, no empty space | TC-E53-U11, TC-E53-I01, TC-E53-A01 | Covered |
| **US-61 AC-6** — tapping a chip is a no-op in F3 | TC-E53-U18, TC-E53-U19 | Covered |
| **US-61 AC-7** — chip row updates immediately on group composition change without re-rendering rest of card | TC-E53-I10, TC-E53-E06 | Covered |
| **US-61 AC-8** — VoiceOver: card label includes group members; chips not separately focusable | TC-E53-I06, TC-E53-I07, TC-E53-I08, TC-E53-I09, TC-E53-U21, TC-E53-U22, TC-E53-U23, TC-E53-U24 | Covered |
| **Overflow boundary: 0 members** | TC-E53-U02, TC-E53-E02 | Covered |
| **Overflow boundary: 1 member** | TC-E53-U03, TC-E53-E01 | Covered |
| **Overflow boundary: 2 members** | TC-E53-U04 | Covered |
| **Overflow boundary: 3 members (no overflow)** | TC-E53-U05, TC-E53-A03 | Covered |
| **Overflow boundary: 4 members (first overflow: 2 + `.overflow(2)`)** | TC-E53-U06, TC-E53-I05, TC-E53-A04 | Covered |
| **Overflow boundary: 5 members (2 + `.overflow(3)`)** | TC-E53-U07 | Covered |
| **Overflow boundary: 10 members (2 + `.overflow(8)`)** | TC-E53-U08, TC-E53-U16 | Covered |
| **Localisation: EN overflow label** | TC-E53-U14, TC-E53-U16, TC-E53-E08 | Covered |
| **Localisation: DA overflow label** | TC-E53-U15, TC-E53-U16, TC-E53-E09 | Covered |
| **Localisation: EN member `accessibilityLabel`** | TC-E53-U21, TC-E53-E08 | Covered |
| **Localisation: DA member `accessibilityLabel`** | TC-E53-U22, TC-E53-E09 | Covered |
| **Dynamic Type AX1** | TC-E53-E04 | Covered (manual) |
| **Dynamic Type AX5: truncation, no reflow** | TC-E53-U20, TC-E53-E05 | Covered (AX5 manual) |
| **VoiceOver: chips not separate accessibility elements** | TC-E53-I09 | Covered (manual) |
| **VoiceOver: card label includes "Also playing" suffix** | TC-E53-I06, TC-E53-I09 | Covered |
| **`ChipData.kind == .member` vs `.overflow` `Equatable`** | TC-E53-U09 | Covered |
| **Member order preserved (UQ-3)** | TC-E53-U10, TC-E53-A05 | Covered |
| **No outer padding on `GroupChipRow` itself** | TC-E53-U25 | Covered (code review) |
| **`isPlaying == false`: chip row absent** | TC-E53-I03, TC-E53-E07 | Covered |
| **Backwards-compatible: existing `SpeakerCard` call sites compile without `groupMembers:`** | TC-E53-I01 | Covered |

---

## 9. Spec Gaps Discovered

The following ambiguities or omissions were identified during test-plan authoring. None are implementation blockers for E-53; each is flagged for the Spec Author and Architect to resolve before QA sign-off.

**Gap 1 — Overflow chip `speakerName` field value is unspecified**

The ADR §7 public interface contract defines `ChipData.speakerName: String` as the display name used for the chip label and `accessibilityLabel`. For `.overflow(Int)` chips, the rendered label is derived from `kind`, not from `speakerName`. The ADR does not specify what value, if any, should be stored in `.speakerName` for overflow chips — it could be an empty string, a placeholder string, or a count string like `"+2 more"`. TC-E53-U06 notes this but does not assert on it. The Implementer should document the convention (e.g. `speakerName = ""` for overflow chips) to avoid confusion when F2 extends `ChipData`.

**Gap 2 — Overflow chip `accessibilityLabel` Danish exact string not enumerated**

ADR §7 #6 specifies `"\(N) more speakers in this group"` in English and "Danish equivalent" without giving the exact string. TC-E53-U24 asserts that the Danish string matches the `UIStrings`/`GroupChipStrings` struct value, but does not specify the string itself. Design-spec Appendix B does not include this key either — only `a11y.alsoPlaying` is listed. The Implementer must decide the Danish overflow accessibility string and record it in the `GroupChipStrings.swift` (or equivalent) struct. Recommended: `"\(N) flere højttalere i denne gruppe"`. This should be added to the spec Appendix B.

**Gap 3 — `GroupChipRow` row-level `accessibilityElement` treatment unspecified**

ADR §7 does not specify whether `GroupChipRow` itself carries an `accessibilityElement(children: .combine)`, `accessibilityElement(children: .contain)`, or no group modifier. The parent `SpeakerCard` uses `accessibilityElement(children: .ignore)` (design-spec §3.7), which collapses the entire card including all chips into one accessibility element. This means any modifier on `GroupChipRow` is moot — the chips are never individually exposed to VoiceOver. However, if `GroupChipRow` is ever used outside a `SpeakerCard` context (e.g. in a preview or future F2 surface), the per-chip `accessibilityLabel` values matter. The test plan asserts per-chip labels (TC-E53-U21–U24) to catch regressions in isolation testing. The spec should note that `GroupChipRow` is designed to be consumed inside `accessibilityElement(children: .ignore)` parents and that the per-chip labels are consumed indirectly via `SpeakerCard.accessibilityDescription`, not by VoiceOver directly.

**Gap 4 — `ChipData` memberwise initialiser and `onTap` default value enforcement**

ADR §5 Consequences states that F2/E-61 will add `var onTap: (() -> Void)? = nil` to `ChipData` with a default so that E-53 construction sites compile without change. E-53 must construct `ChipData` using labelled initialisation (not a hand-rolled init) so that when F2 adds `onTap`, the compiler fills it in from the default. If E-53's Implementer writes a custom `init` that omits `onTap`, F2's addition will break E-53's custom init. The spec should explicitly state: "E-53 must not define a custom `init` for `ChipData`; the synthesised memberwise initialiser (with F2's eventual `onTap = nil` default) is the only init." This should be added as a note in ADR §5 or the epics task T-5301.

**Gap 5 — F2 forward-compatibility note for `ChipKind` exhaustive `switch`**

ADR §8 CF-3 states that F2 adding `case loading` to `ChipKind` will break the exhaustive `switch` in `GroupChipRow.body` (by design — the compiler error is the signal). However, the test plan cannot cover this because `case loading` does not exist in E-53. No TCs are written for F2's `loading` variant. This is documented here for completeness: the E-53 `switch` must have exactly `case .member` and `case .overflow` — no `@unknown default`. Any implementation that adds `@unknown default` or `default:` to work around future extension would silently hide unhandled F2 cases and should be flagged in code review as a violation of the architecture intent.

---

## 10. Tests Deferred to Manual Device Verification

The following items cannot be fully automated at the unit or XCUITest level and are deferred to the manual verification tasks T-5309 and T-5310 defined in the epics document.

| Item | Reason for deferral | Epic task |
|---|---|---|
| Chip row visual alignment inside the card on physical device (chip colours, opacity rendering of `.white.opacity(0.07)` on hardware) | Requires visual inspection on device; simulator rendering may differ for opacity compositing | T-5309 |
| Dynamic Type AX1 — chip size and legibility | Requires system Dynamic Type setting; XCUITest cannot reliably assert rendered font metrics | T-5309 |
| Dynamic Type AX5 — truncation confirmed visually (no reflow) | Same as above; truncation boundary depends on runtime font metrics | T-5309 |
| 4-speaker group chip row: `+ Member1`, `+ Member2`, `+2 more` confirmed on device | End-to-end requires a live B&O group of 4 speakers on the LAN | T-5309 |
| VoiceOver: chip row not separately focusable; card label includes "Also playing" string | Requires VoiceOver enabled and manual VoiceOver navigation; XCUITest `accessibilityActivate` does not reliably traverse `accessibilityElement(children: .ignore)` hierarchies | T-5310 |
| VoiceOver: correct ordering of `accessibilityDescription` parts (name, state, track, volume, "Also playing") | Requires screen reader traversal on device to confirm announcement order | T-5310 |
| Group composition change during active VoiceOver session — chip row updates without focus disruption | Cannot be automated with XCUITest due to VoiceOver focus-state opacity | T-5310 |
| Chip row visual consistency when `speaker.isPlaying` transitions while card is on-screen (chip row appears/disappears) | Requires live speaker or state mutation observable on a running app | T-5309 |
