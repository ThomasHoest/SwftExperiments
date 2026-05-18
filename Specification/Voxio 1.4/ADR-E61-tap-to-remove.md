# ADR-E61 — Tap-to-Remove (E-61): handleRemoveTap, ChipData.onTap, VoiceOver Alternate-Add

**Status:** Accepted
**Date:** 2026-05-12
**Deciders:** Engineering Lead
**Refs:** ADR-E53 §5 CF-4, ADR-E60 CF-1 + §5 Consequences, spec-multiroom-grouping.md v1.0 (TR-6, TR-9, US-83), design-spec-multiroom-grouping.md v1.1 (§5, §8, Appendix B), epics-and-tasks-multiroom-grouping.md v1.0 (E-61 T-6101–T-6107), CLAUDE.md

---

## 1. Decision

`SessionViewModel.handleRemoveTap(_:)` implements an optimistic remove: `discovery.removeMember(speaker)` runs synchronously on the main actor before the detached leave Task launches. On `leave()` success, `HapticEngine.shared.commandRecognised()` fires and a VoiceOver announcement is posted. On failure, `discovery.mergeIntoSpeakerGroup(source:target:)` re-inserts the chip and the error is surfaced via the existing injected `onError: (String) -> Void` callback — not `ToastCenter.shared`, which does not exist (CF-1). `ChipData` gains `var onTap: (@MainActor () -> Void)? = nil` defaulting to `nil` so all E-53/E-60 construction sites compile unchanged; `ChipData` is annotated `@unchecked Sendable` (documented: constructed and consumed exclusively on `@MainActor`). `SpeakerDiscoveryService.removeMember` receives a single `mergeCooldownUntil` stamp to prevent a lagging `refreshGroups()` from reversing the optimistic removal during Mozart's `/beolink/leave` propagation lag. The existing in-place `group.members.remove(at:)` mutation is preserved — `SpeakerGroup` is `@Observable`, so SwiftUI tracks inner property mutations without an array-slot replacement. `SessionViewModel` gains `var presentAddSpeakerSheet: Bool = false` for the VoiceOver alternate-add path (T-6106).

---

## 2. Context

**ADR-E53 CF-4.** Adding `onTap: (@MainActor () -> Void)?` breaks `ChipData`'s implicit `Sendable`. Annotate with `@unchecked Sendable`; document that `ChipData` is exclusively `@MainActor`-constructed and consumed. All E-53/E-60 construction sites use the memberwise initialiser — `onTap` defaults to `nil`, requiring no call-site change.

**ADR-E60 CF-1.** `ToastCenter.shared` does not exist. Error delivery is `onError: (String) -> Void` injected at `SessionViewModel.init`, already wired in `SessionStripView.resolvedSessionVM(for:)` by E-60. No change to `resolvedSessionVM` is required.

**`removeMember` propagation hazard.** The prompt flags that in-place `group.members.remove(at:)` does not fire `@Published` on `SpeakerDiscoveryService.groups`. This was a concern before `SpeakerGroup` became `@Observable`. `SpeakerGroup` is `@Observable @MainActor final class` (confirmed `iOS/Voxio/Core/Models/Group.swift` line 9); writes to `group.members` trigger SwiftUI observation for every view reading `group.members`, including the chip row's `ForEach`. Array-slot replacement is not required and would add unnecessary churn.

**Cooldown symmetry.** Mozart's `/beolink/leave` propagation to `/beolink/listeners` has the same 1–5 s lag as `/beolink/expand`. A `refreshGroups()` firing inside that window re-inserts the removed speaker and reverses the optimistic removal. Decision: stamp `mergeCooldownUntil = Date().addingTimeInterval(Self.mergeCooldownSeconds)` inside `removeMember` on every successful find-and-remove (before the `return`). The mDNS path (`removeSpeaker(ip:)`) does not call `removeMember`, so this stamp does not affect mDNS flows.

**Host-removal rollback corner case.** If the removed speaker was the group host and `mergeIntoSpeakerGroup` cannot find the original host in discovery, the method's fallback creates a new group — but since the host id is absent, the speaker re-insertion is a no-op. The toast fires as the only signal. Document inline per T-6104.

---

## 3. Options Considered

**`removeMember` array-slot replace (parallel to `mergeIntoSpeakerGroup`) — rejected.** Not required given `@Observable` tracking. The only real propagation risk (eventual-consistency lag) is handled by the `mergeCooldownUntil` stamp.

**`ToastCenter.shared` error delivery — rejected.** Type does not exist; see ADR-E60 CF-1.

**`onTap: (() -> Void)?` without `@MainActor` qualifier — rejected.** `handleRemoveTap` is `@MainActor`-isolated; the closure must match to avoid actor-hopping warnings under strict concurrency checking.

---

## 4. Rationale

Optimistic remove matches the leave-latency profile (short, rollback is visually simple). `onError` reuses the E-60 pipeline without new shared state. The `mergeCooldownUntil` stamp inside `removeMember` is the smallest correct fix for eventual-consistency symmetry. `@unchecked Sendable` is the established resolution for a struct containing a main-actor-bound closure used exclusively on `@MainActor`.

---

## 5. Public Interface Contract

```swift
// MARK: - ChipData additions (GroupChipRow.swift)
// Add stored property with default:
var onTap: (@MainActor () -> Void)? = nil
// Add below struct declaration:
extension ChipData: @unchecked Sendable {}
// Rationale: ChipData is constructed and consumed exclusively on @MainActor.
// onTap closures call SessionViewModel methods, which are @MainActor-isolated.

// MARK: - GroupChipRow.chipView — .member branch (GroupChipRow.swift)
// When chip.onTap != nil, wrap chip label in Button(action: chip.onTap!) { <chip label> }
// with .contentShape(Capsule()) so the full capsule area is tappable.
// Add to settled (.member) chips:
//   .accessibilityRole(.button)
//   .accessibilityLabel(String(format: strings.chipMemberLabel, chip.speakerName))
//   .accessibilityHint(strings.chipMemberHint)
// Loading chips retain the status-only label from E-60; no role change.

// MARK: - SessionViewModel (SessionViewModel.swift)
// New stored property:
var presentAddSpeakerSheet: Bool = false

// Replace handleRemoveTap stub:
@MainActor
func handleRemoveTap(_ speaker: Speaker) {
    let originalGroup = discovery.groups.first { $0.members.contains { $0.id == speaker.id } }
    guard let host = originalGroup?.hostSpeaker else { return }
    discovery.removeMember(speaker)       // optimistic; stamps mergeCooldownUntil
    Task { [weak self] in
        do {
            try await speaker.client.leave()
            await MainActor.run {
                HapticEngine.shared.commandRecognised()
                let s = GroupingStrings.forLanguage(LanguageService.shared.activeLanguage)
                UIAccessibility.post(notification: .announcement,
                                     argument: String(format: s.a11yRemoved, speaker.name))
            }
        } catch {
            await MainActor.run {
                guard let self else { return }
                self.discovery.mergeIntoSpeakerGroup(source: speaker, target: host)
                // If host disappeared: mergeIntoSpeakerGroup is a no-op; toast is the only signal.
                HapticEngine.shared.errorOccurred()
                let s = GroupingStrings.forLanguage(LanguageService.shared.activeLanguage)
                self.onError(String(format: s.removeFailed, speaker.name))
            }
        }
    }
}
// Contracts: Task is NOT cancelled on view teardown (parallel to TR-4 step 5).
// onError routes via the existing SessionStripView-injected callback. No ToastCenter.

// MARK: - SpeakerDiscoveryService.removeMember addition (SpeakerDiscoveryService.swift)
// Inside the found-and-removed path, before the existing `return`:
mergeCooldownUntil = Date().addingTimeInterval(Self.mergeCooldownSeconds)

// MARK: - GroupingStrings additions (GroupingStrings.swift)
var removeFailed: String       // "Couldn't remove %@" / "Kunne ikke fjerne %@"
var a11yRemoved: String        // "%@ removed from group" / "%@ fjernet fra gruppe"
var chipMemberLabel: String    // "%@, in group. Tap to remove." / "%@, i gruppe. Tryk for at fjerne."
var chipMemberHint: String     // "Removes this speaker from the group." / "Fjerner denne højttaler fra gruppen."
var a11yAddAction: String      // "Add speaker" / "Tilføj højttaler"
```

---

## 6. File-Level Plan

| File | Change | Tasks |
|---|---|---|
| `iOS/Voxio/Features/Home/SessionViewModel.swift` | Replace `handleRemoveTap` stub (full implementation above). Add `var presentAddSpeakerSheet: Bool = false`. | T-6101, T-6106 |
| `iOS/Voxio/Features/Home/Components/GroupChipRow.swift` | Add `onTap` to `ChipData` with `nil` default; `@unchecked Sendable` extension. In `.member` chip branch: `Button` wrapper when `onTap != nil`; `.contentShape(Capsule())`; `.accessibilityRole(.button)`; `.accessibilityLabel`; `.accessibilityHint`. | T-6102, T-6105 |
| `iOS/Voxio/Features/Home/SpeakerCard.swift` | In `chipData`, capture `let vm = sessionVM` at top; pass `onTap: { vm?.handleRemoveTap(member) }` per `.member` chip. On card body, add `.accessibilityAction(named: strings.a11yAddAction) { sessionVM?.presentAddSpeakerSheet = true }` and a `.confirmationDialog` listing eligible speakers, driven by `Binding` over `sessionVM?.presentAddSpeakerSheet`. T-6103 (chip-row collapse) is already handled by the `if !chipData.isEmpty` guard from E-60 — verify only, no code change. | T-6102, T-6103, T-6106 |
| `iOS/Voxio/Core/Discovery/SpeakerDiscoveryService.swift` | Stamp `mergeCooldownUntil` before `return` in `removeMember` on successful find. One line. | T-6101 |
| `iOS/Voxio/Core/Strings/GroupingStrings.swift` | Add five string properties (above) to struct and both static lets. NOT `.strings` files — ADR-E53 CF-1 applies. | T-6105, T-6106 |

`SessionStripView.resolvedSessionVM(for:)` — no change. `onError` injection is already in place from E-60.

---

## 7. Conflicts Flagged

**CF-1: `ToastCenter.shared.show(.error(…))` in T-6101 pseudocode is wrong.** No such type exists in the codebase. The correct pattern is `self.onError(String(format: strings.removeFailed, speaker.name))`. Implementer must not copy the T-6101 pseudocode verbatim.

**CF-2: Localisation uses `GroupingStrings.swift` struct pattern, not `.strings` files.** Design spec Appendix B key names (`a11y.chip.member`, `grouping.a11yAddAction`) describe intent. Implement as Swift struct properties per ADR-E53 CF-1.

**CF-3: `removeMember` in-place mutation is safe — no rewrite required.** The prompt identifies a propagation hazard; it is resolved by `SpeakerGroup`'s `@Observable` conformance. Verified against `iOS/Voxio/Core/Models/Group.swift`. The cooldown stamp (not an array-slot replace) is the only addition needed.

---

## 8. Out of Scope

Voice command `"remove X from group"` — unchanged, not part of E-61. Confirmation dialog on remove — UQ-1 resolved: none. Drag from chip row to reorder — design-spec §9 exclusion. Touch-path telemetry events — out of scope for v1.4 per master spec.

---

## 9. Platform Constraint Checks

| API | Min | Status |
|---|---|---|
| `.accessibilityAction(named:_:)` | iOS 14+ | Safe |
| `.confirmationDialog(_:isPresented:titleVisibility:actions:)` | iOS 15+ | Safe |
| `@Observable` inner-property tracking | iOS 17+ | Safe (v1.4 target: iOS 26) |
| `UIAccessibility.post(notification: .announcement, argument:)` | iOS 7+ | Safe |
| `Button(action:label:)` + `.contentShape(Capsule())` | iOS 13+ | Safe |

No new entitlements, frameworks, or Info.plist keys required.

---

**Verdict: PROCEED**
