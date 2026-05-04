# Design Specification: Voxio 1.2 Group UI
**Version:** 1.0  
**Status:** Draft  
**Date:** 2026-05-01  
**Platform:** iOS 26 (iPhone, portrait, dark-mode only)  
**Design Language:** Liquid Glass  
**References:** design-spec-bo-voice-control v1.1, VoxioSpecification-1.1.md, research-findings-voxio-1.2.md (Topic C), design-spec-widget-voxio-1.2.md, BeoColor.swift, DesignTokens.swift, SpeakerCard.swift

---

## Design Philosophy

The multiroom group is the primary unit of Voxio 1.2. A group of one speaker behaves and looks identical to the existing v1.1 speaker card — no regression, no visual noise for the common single-speaker case. A group of two or more speakers expands that same card surface to show all members playing together, with a clear session indicator and per-member leave controls.

The group card is still a single Liquid Glass surface. It grows vertically to accommodate its members; it does not fragment into separate cards or introduce a new visual layer. The session identity is expressed through a compact status row at the top of the card, a shared track panel, and a subtle member list — never through colour-coded borders or heavy chrome. Bang & Olufsen restraint applies: one card, one session, everything needed at a glance and nothing more.

---

## Design Principles (Group-Specific)

1. **Group of 1 is the baseline.** The single-speaker card is unchanged. No new visual element appears unless there is a second member.
2. **The card grows, not the list.** When speakers join a group, the existing card expands vertically. There is no transition to a new view or a new card type.
3. **The session is always clear.** The user can tell at a glance that two speakers are playing together, who the host is, and which member they would be removing by tapping Leave.
4. **Leave is one tap, not one gesture.** Per-member leave buttons are always visible in the expanded card. There is no swipe-to-reveal. Touch targets are ≥ 44 × 44 pt.
5. **Join is confirmed, leave is immediate.** Joining another speaker's session is a state change with networking cost and is disruptive if accidental — it requires a 3-second countdown (matching E-25 precedent). Leaving is safe and easily reversible — both tap-leave and voice-leave fire immediately with no countdown, and a toast confirmation is shown.

---

## Visual Language

All group UI uses the same surface, colour, and motion system as v1.1. No new surface materials. No new glasstypes.

| Element | Specification |
|---|---|
| Group card surface | `systemMaterial` Liquid Glass, `RoundedRectangle(cornerRadius: Radius.card)` — identical to the existing `SpeakerCard` |
| Session badge | Compact Liquid Glass pill, `ultraThinMaterial` + `black.opacity(0.45)` surface, same treatment as `DarkGlassButton` but non-interactive |
| Leave button | `DarkGlassButton(role: .cancel)` — standard dark glass capsule, red label and icon |
| Member row | Inset panel within the card, `white.opacity(0.07)` background (matches `nowPlayingPanel` treatment from `SpeakerCard`) |
| Join loading indicator | Inline spinner replacing the leave button area; `BeoColor.labelSecondary` tint |
| Card divider | `BeoColor.separator` at 0.15 opacity, 0.5 pt hairline (matches widget spec) |

---

## Layering Model

Group UI elements follow the same four-layer model as v1.1:

```
Layer 4 — Dynamic overlay    Confirmation countdown surface, join toast, leave toast
Layer 3 — Glass controls     Group card, member leave buttons, session badge
Layer 2 — Glass refraction   Liquid Glass card surface refracting the orb background
Layer 1 — AppBackground.png  Fixed dark navy / blue-teal orb image, full-bleed
```

The session badge floats on Layer 3 within the card — it is painted on the card surface itself, not above it.

---

## Section 1 — Group Card: Group of 1

**Decision: the group-of-1 card is identical to the existing `SpeakerCard` in every respect.**

No new elements are added. No session badge. No member list. No leave button. The word "Group" does not appear anywhere in the UI for a group of one.

**Rationale:** The vast majority of users will have one speaker active at any given moment. Introducing group chrome in the one-speaker state would create visual noise and erode the meaning of those elements when they do appear in multi-speaker groups. The simplest honest UI for a group of one is the speaker's own card, unchanged.

**Implementation note for engineers:** The `Group` model wraps a `SpeakerCard` when `members.count == 1`. The view layer renders `SpeakerCard(speaker: group.hostSpeaker)` directly — no `GroupCard` wrapper, no conditional chrome.

---

## Section 2 — Group Card: Group of 2+

### 2.1 Anatomy

The multi-member group card is a vertically extended version of the existing `SpeakerCard`. The card's internal structure is:

```
┌─────────────────────────────────────────────────────────────────┐
│  [link.circle.fill]  Playing Together · 2 speakers              │  ← Session header row
│  ─────────────────────────────────────────────────────────────  │
│  Jazz Radio                                              [~~~]   │  ← Shared now-playing panel
│  Spotify                                                         │
│  ──────────────────────────────────────────────────────[vol 42]  │
│  ─────────────────────────────────────────────────────────────  │
│  [hifispeaker.fill] Beosound Stage        HOST            ·      │  ← Member row 1 (host)
│  ─────────────────────────────────────────────────────────────  │
│  [hifispeaker.fill] Beosound Balance                  [Leave]    │  ← Member row 2 (listener)
│  ─────────────────────────────────────────────────────────────  │
│  [hifispeaker.fill] Beosound Emerge                   [Leave]    │  ← Member row 3 (listener)
└─────────────────────────────────────────────────────────────────┘
```

**Zone breakdown (top to bottom):**

| Zone | Content | Background | Padding |
|---|---|---|---|
| Session header | Session badge + member count | Transparent (card surface shows through) | `Spacing.s16` horizontal, `Spacing.s12` vertical |
| Divider | `BeoColor.separator` hairline | — | — |
| Now-playing panel | Shared track name, source, playback bars | `white.opacity(0.07)` inset panel | `Spacing.s16` horizontal, `Spacing.s14` vertical |
| Volume track | Gold fill bar + level number | Transparent | `Spacing.s24` horizontal, `Spacing.s12` bottom |
| Divider | `BeoColor.separator` hairline | — | — |
| Member rows | Per-member name + role badge / leave button | Alternating: transparent / `white.opacity(0.04)` | `Spacing.s20` horizontal, `Spacing.s12` vertical |

The card's overall horizontal inset from screen edges is 20 pt (matching the v1.1 `SpeakerCard`).

---

### 2.2 Session Header Row

The session header occupies the top of the card where the speaker name lives in a group-of-1 card. When a group has 2+ members the speaker name is replaced by the session indicator.

**Content:**

| Element | Spec |
|---|---|
| Icon | `link.circle.fill`, SF Symbols 6, 16 pt, `BeoColor.accent` (`#C8A97E`) |
| Label | "Playing Together · {N} speakers" — localised; "Spiller Sammen · {N} højttalere" (Danish) |
| Font | `BeoType.body` (SF Pro Text Regular 15 pt), `BeoColor.labelPrimary` |
| Icon–label gap | `Spacing.s8` (8 pt) |
| Trailing | None — the badge is left-aligned within the header zone |

The "Playing Together" label is the primary signal that these speakers form a session. The member count (`· 2 speakers`) is a secondary label in `BeoColor.labelSecondary` appended inline.

**Accessibility:** The session header row is a non-interactive `Text` element. VoiceOver reads it as: "[N] speakers playing together" — not the literal badge text, which is redundant with the member list below.

---

### 2.3 Now-Playing Panel (Shared)

The now-playing panel is unchanged from v1.1 `SpeakerCard.nowPlayingPanel`. It shows the shared track and playback bars from the host speaker.

**When members have divergent state (edge case):** In a healthy Beolink session all members play the same source in sync. The app treats the host speaker's playback state as canonical. If the app detects a state mismatch (e.g. a member is paused while the host is playing — possible during a network hiccup), the divergent member row shows a `pause.fill` icon at 11 pt in `BeoColor.labelSecondary` inline with the member name. No separate now-playing panel per member. This is an edge case, not the normal state.

---

### 2.4 Member Rows

Each member is shown in a dedicated row below the now-playing panel. Rows are separated by 0.5 pt hairlines (`BeoColor.separator` at 0.15 opacity).

**Host row:**

| Element | Spec |
|---|---|
| Leading icon | `hifispeaker.fill`, 14 pt, `BeoColor.labelSecondary` |
| Speaker name | `BeoType.body` (SF Pro Text Regular 15 pt), `BeoColor.labelPrimary` |
| Role badge | "HOST" — `BeoType.caption` (SF Pro Text Medium 12 pt), `BeoColor.accent` (`#C8A97E`), trailing-aligned |
| Leave button | **Not shown for the host.** The host cannot leave its own session; it can only disband the session entirely (a separate action, not in v1.2 scope). |

**Listener row:**

| Element | Spec |
|---|---|
| Leading icon | `hifispeaker.fill`, 14 pt, `BeoColor.labelSecondary` |
| Speaker name | `BeoType.body` (SF Pro Text Regular 15 pt), `BeoColor.labelPrimary` |
| Leave button | `DarkGlassButton` with `role: .cancel` — `xmark.circle.fill` icon (14 pt, system red), label "Leave", system red. Trailing-aligned within the row. |

**Leave button sizing:**

The leave button minimum tap target is 44 × 44 pt. Visually it renders as a compact pill (`DarkGlassButtonTokens`: 10 pt vertical padding, 16 pt horizontal padding), but the outer `Button` wrapper uses `.frame(minWidth: 44, minHeight: 44)` to extend the hit area without visual change.

**Member row height:** Minimum 52 pt (accommodates the leave button at its natural size with safe-area compliant spacing). If a speaker name truncates to two lines, the row height grows to accommodate Dynamic Type.

---

### 2.5 Expand / Collapse for Large Groups

**Policy for v1.2:** Groups with up to 4 members show all member rows without collapse. Groups with 5 or more members collapse to show 3 rows plus a "Show {N} more…" button at the bottom of the member list.

**Collapsed state (5+ members):**

```
│  [hifispeaker.fill] Beosound Stage      HOST           ·    │
│  [hifispeaker.fill] Beosound Balance               [Leave]  │
│  [hifispeaker.fill] Beosound Emerge                [Leave]  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Show 2 more speakers…                               │  │
│  └──────────────────────────────────────────────────────┘  │
```

The "Show {N} more…" row uses a `DarkGlassButton` (default role) with a `chevron.down` trailing icon. Tapping it expands the card inline (no navigation), revealing remaining member rows with a smooth height animation. The button then changes to "Show less" with a `chevron.up` icon.

**Collapse trigger:** Group size ≥ 5 members. In practice, B&O home networks rarely exceed 4–5 speakers — this threshold was chosen to keep the card to a manageable height in the common case.

**Rationale for 4-member full-display threshold:** The research findings note that home Beolink sessions typically have 2–3 speakers. Collapsing at 5 handles outlier networks without adding collapse chrome to typical use.

---

### 2.6 Card Height Calculation

The card height is dynamic, not fixed. It grows from the existing `SpeakerCard` height.

| Component | Approximate Height |
|---|---|
| Session header zone | 52 pt |
| Hairline divider | 0.5 pt |
| Now-playing panel | 64 pt (matches v1.1) |
| Volume track | 36 pt |
| Hairline divider | 0.5 pt |
| Per member row | 52 pt each |
| Bottom inset | 12 pt |

A 2-member group card (1 host + 1 listener): approx. 52 + 64 + 36 + 104 + 12 = **268 pt**  
A 3-member group card (1 host + 2 listeners): approx. **320 pt**  
A 4-member group card: approx. **372 pt**

These heights are estimates; Dynamic Type may grow row heights. The card must not overflow the viewport — if it does, the card itself becomes vertically scrollable (internal scroll, not the screen scroll).

---

### 2.7 Transition Animation

When a speaker joins or leaves a group the card animates between states. All animations use `BeoAnimation.spring` (`response: 0.45, dampingFraction: 0.75`) unless Reduce Motion is enabled, in which case they are replaced with `easeInOut(duration: 0.2)` cross-fades.

**Speaker joins the group (card gains a member row):**

1. The session header's member count updates with a cross-fade: "2 speakers" → "3 speakers".
2. The new member row slides in from the bottom of the member list with a combined `slide` + `opacity` transition (`AnyTransition.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .move(edge: .trailing).combined(with: .opacity))`).
3. The card grows to its new height using `withAnimation(BeoAnimation.spring)` — no explicit height clamp; SwiftUI's `VStack` height expansion drives the growth.

**Speaker leaves the group (card loses a member row):**

1. The leaving member row slides out to the trailing edge and fades simultaneously.
2. The card shrinks to its new height.
3. The session header count updates: "3 speakers" → "2 speakers".
4. If the group falls to 1 member: the entire group card cross-fades to a single `SpeakerCard` for the remaining speaker. Duration: `easeInOut(duration: 0.3)`.

**Note on the group-of-2 → group-of-1 transition:** This is the most visually significant transition. The group card (with session header and member rows) must dissolve and be replaced by a plain speaker card. Use `matchedGeometryEffect` anchored on the card's bounding rect to keep the card in its list position during the transition. The card does not slide to a new position; it morphs in place.

**Haptic feedback for join/leave completions:** A `.success` notification haptic fires on the main thread when the API confirms a join or leave. A `.error` notification haptic fires if the API returns an error.

---

## Section 3 — Join Confirmation Flow

### 3.1 Trigger

Voice command: **"[Speaker A] join [Speaker B]"** or equivalent natural-language paraphrase.

**Parsed VoiceCommand:** `joinGroup(joiner: SpeakerReference, host: SpeakerReference)` — a new intent added in v1.2. (Note: the existing `VoiceCommand` enum is extended; see §6 for token list.)

---

### 3.2 Confirmation Countdown Surface

The join confirmation reuses the v1.1 E-25 countdown surface exactly. No new surface is introduced.

**Read-back text (spoken aloud by TTS and shown in the countdown surface):**

| Scenario | English read-back | Danish read-back |
|---|---|---|
| Speaker A joining Speaker B | "Adding [A] to [B]'s session" | "Tilføjer [A] til [B]'s session" |
| Speaker A joining the active group (when only one group exists) | "Adding [A] to the group" | "Tilføjer [A] til gruppen" |

The read-back string is the first line in the countdown surface (SF Pro Display Regular 22 pt, `BeoColor.labelPrimary`). The small "About to:" label in `BeoColor.labelSecondary` precedes it, as per the v1.1 confirmation sheet pattern.

**Countdown timing:** 3 seconds. Identical to all other v1.1 confirmable actions. The countdown begins after TTS read-back completes.

**Cancel:** Same grammar as v1.1 — "cancel", "no", "nej", "annuller". Tapping the `DarkGlassButton(role: .cancel)` "Cancel" button also cancels.

**Haptics:** `.medium` impact on countdown start; `.success` notification on auto-execute (join fires); `.error` notification on cancel.

---

### 3.3 Loading State (Join in Progress)

After the countdown auto-executes (or is not cancelled), the join API call is in flight. During this period:

**Card state — the group card that A is joining:**

The existing group card (or the host's speaker card if it is a group of 1) enters a loading state:
- The session header shows "Adding [A]…" with an inline `ProgressView` (circular, 12 pt, `BeoColor.labelSecondary`) replacing the member count badge.
- The card is not interactive during loading (leave buttons are disabled, `opacity(0.4)`).

**Card state — Speaker A (the joiner) before joining:**

If A was previously a standalone group-of-1 card in the list, it shows a loading indicator:
- The speaker name remains.
- The status subtitle changes to "Joining [B]…" in `BeoColor.labelSecondary`.
- A `ProgressView` circular spinner (14 pt, `BeoColor.labelSecondary`) appears trailing the subtitle.

**Loading duration:** The app shows loading state until the API response is received or a timeout occurs (5 seconds, matching `MozartClient`'s existing request timeout). On timeout or error, a top-toast error appears (matching the v1.1 error toast pattern).

---

### 3.4 Loading State: Error

If the join API call fails:
- Loading indicators are removed.
- Both cards return to their pre-join state.
- A top-toast slides in: `exclamationmark.bubble` icon + "Couldn't add [A] to [B]'s session. Check the network." in SF Pro Text 15 pt.
- Auto-dismisses after 4 seconds.

---

## Section 4 — Leave Confirmation Flow

### 4.1 Leave is Immediate — No Confirmation Countdown

**Decision: leave does not require a countdown.**

**Rationale:**
1. Leave is non-destructive — the speaker continues playing independently after leaving (it does not stop). The user can re-join immediately.
2. Leave is initiated by tapping a clearly labelled "Leave" button on the specific member's row — it is not a voice command that fires a global action on an ambiguous target. The intent is unambiguous.
3. Requiring a 3-second countdown on a tap-to-leave action adds friction without safety value. The leave action is reversible by a voice command.

**Voice-initiated leave is immediate — no countdown is shown.** The leave API call fires as soon as the voice command is parsed and the read-back completes. The card updates within 3 seconds to reflect the new group state. This matches the functional spec decision: leave is a recoverable action (the speaker can rejoin) and does not require a safety window.

**Voice read-back for voice-command leave:**

| English | Danish |
|---|---|
| "[A] leaving the group" | "[A] forlader gruppen" |

**Note:** Issue 3 (1-second voice-leave countdown requiring `ConfirmationCoordinator` API change) is resolved: voice-leave is immediate. `ConfirmationCoordinator` requires no changes for v1.2.

---

### 4.2 Tap-to-Leave Flow

1. User taps the "Leave" button in a member row.
2. The leave button immediately shows a loading state: the `xmark.circle.fill` icon is replaced by an inline `ProgressView` (12 pt, `BeoColor.labelSecondary`). The button is disabled.
3. The app calls `POST /beolink/leave` (Mozart) or `DELETE /BeoZone/Zone/ActiveSources/primaryExperience` (BNR) on the leaving speaker.
4. On success:
   - The leaving member row slides out (trailing edge + opacity, `BeoAnimation.spring`).
   - The card shrinks.
   - If the group falls to 1 member: the card morphs to a standard speaker card (§2.7).
   - A `.success` haptic fires.
   - A transient toast: "[Speaker name] left the group." Auto-dismisses after 2 seconds.
5. On failure:
   - The leave button returns to its normal state.
   - Error toast: "Couldn't remove [A] from the group. Check the network."

---

### 4.3 Post-Leave Card Behaviour

| Scenario | Result |
|---|---|
| Group of 3 → speaker leaves | Group card shrinks to show 2 members; session header updates to "2 speakers" |
| Group of 2 → listener leaves | Remaining speaker's group card morphs to a standard speaker card (group-of-1 rules apply — no session chrome) |
| Group of 2 → host leaves | **Not a supported action in v1.2.** The host cannot leave its own session without disbanding the group. The leave button is hidden on the host row. This is a known limitation — see §7 Issue 1. |

---

## Section 5 — Empty and Loading States

### 5.1 App Startup: Peers Being Fetched

On launch, the app discovers speakers via mDNS and calls `GET /beolink/peers` (or `GET /BeoZone/Zone/Sources` for BNR) on each. There is a window — typically 1–3 seconds — during which the speaker is known but group membership is not yet determined.

**During this window, the app shows standard speaker cards for each discovered speaker.** No group chrome is shown until peer data returns. This is the safest default: showing a group card prematurely and then restructuring the list causes jarring layout changes. Showing plain speaker cards and then assembling them into group cards is a smoother transition.

**Startup sequence:**

1. `mDNS` resolves a speaker → `SpeakerCard` appears with the standard loading shimmer (skeleton state, matching v1.1 `Speaker.isInitializing` behaviour).
2. Speaker REST init completes (`getPlaybackState`, `getVolume`, etc.) → card displays live state.
3. Peers API call completes:
   - If no peers: card stays as a group-of-1 (unchanged).
   - If peers found: the relevant cards are replaced by a single `GroupCard` with the assembled members. This replacement is animated: the individual cards fade out while the group card fades in. Duration: `easeInOut(duration: 0.4)`.

**State label during peer fetch:** No special label. The speaker card shows normally while peer data loads. The transition to a group card is the user's signal that a session was found.

---

### 5.2 Skeleton / Shimmer State

No new skeleton state is required for groups specifically. The existing speaker card loading state (used while `Speaker.isInitializing`) is sufficient for the startup window described in §5.1.

---

### 5.3 Speaker Mid-Join (Awaiting API Response)

Described in §3.3. The joining speaker shows an inline `ProgressView` and a "Joining [B]…" subtitle. The target group card shows "Adding [A]…" in the session header.

---

### 5.4 Speaker Mid-Leave (Awaiting API Response)

Described in §4.2. The leave button shows an inline `ProgressView` and is disabled.

---

### 5.5 Empty Group List

If no speakers are discovered at all (network issue, no B&O speakers on LAN), the existing v1.1 empty/offline state applies. No group-specific empty state is needed.

---

## Section 6 — Design Tokens

### 6.1 New BeoColor Tokens

| Token | Value | Usage |
|---|---|---|
| `BeoColor.sessionAccent` | `BeoColor.accent` alias — `#C8A97E` | Session header icon (`link.circle.fill`), HOST role badge. **Not a new hex value** — an alias of the existing `BeoColor.accent` with a semantic name for the group context. Avoids coupling group-specific usage directly to the generic `accent` token. |

**Token conflict check:** `BeoColor.sessionAccent` is an alias, not a new colour. It resolves to `Color("Accent")` from `Assets.xcassets`. No conflict with existing tokens.

**Decision needed from engineering/design:** Should `sessionAccent` be a named alias in `BeoColor.swift` or should the group view components reference `BeoColor.accent` directly? Recommendation: named alias for semantic clarity. This is a trivial additive change.

---

### 6.2 New Spacing Tokens

No new `Spacing` enum cases are required. All group UI spacing uses existing tokens:

| Usage | Token | Value |
|---|---|---|
| Session header horizontal padding | `Spacing.s16` | 16 pt |
| Session header vertical padding | `Spacing.s12` | 12 pt |
| Member row horizontal padding | `Spacing.s20` | 20 pt |
| Member row vertical padding | `Spacing.s12` | 12 pt |
| Session icon to label gap | `Spacing.s8` | 8 pt |
| Member icon to speaker name gap | `Spacing.s8` | 8 pt |
| Member name to leave button gap | flexible spacer | auto |

---

### 6.3 New Radius Tokens

No new `Radius` tokens. The group card uses `Radius.card` (20 pt). The "Show more" button uses `Radius.pill` (100 pt). Member rows are not individually rounded — they are inset zones within the card.

---

### 6.4 New BeoType Tokens

| Token | Font | Weight | Size | Usage |
|---|---|---|---|---|
| `BeoType.memberName` | SF Pro Text | Regular | 15 pt | Member row speaker name. **Identical to `BeoType.body`** — this is an alias with a semantic name, not a new typeface specification. |
| `BeoType.roleLabel` | SF Pro Text | Medium | 12 pt | "HOST" role badge. **Identical to `BeoType.caption`** — again an alias. |

**Recommendation:** Do not add these as separate entries in `DesignTokens.swift`. Use `BeoType.body` and `BeoType.caption` directly. The semantic distinction is documented here for design clarity, not as an engineering token.

---

### 6.5 New Animation Tokens

| Token | Value | Usage |
|---|---|---|
| `BeoAnimation.memberJoin` | `.spring(response: 0.45, dampingFraction: 0.75)` combined with `AnyTransition.move(edge: .bottom).combined(with: .opacity)` | Member row insertion |
| `BeoAnimation.memberLeave` | `.spring(response: 0.45, dampingFraction: 0.75)` combined with `AnyTransition.move(edge: .trailing).combined(with: .opacity)` | Member row removal |
| `BeoAnimation.groupCardMorph` | `easeInOut(duration: 0.3)` | Group-of-2 → group-of-1 card transition |
| `BeoAnimation.groupAssemble` | `easeInOut(duration: 0.4)` | Startup: individual cards fade out, group card fades in |

**Engineering note:** `memberJoin` and `memberLeave` share the same spring parameters as `BeoAnimation.spring`. They are not separate `Animation` objects — they are named `AnyTransition` values. These can be defined as static properties on `AnyTransition` via an extension rather than in `BeoAnimation`. Flag for engineering to determine best home.

---

### 6.6 New VoiceCommand Cases

The following new `VoiceCommand` enum cases are required for v1.2. They are listed here for completeness; implementation is the concern of the functional spec.

| Case | Parameters | English paraphrase examples |
|---|---|---|
| `.joinGroup(joiner:, host:)` | `joiner: SpeakerReference`, `host: SpeakerReference` | "Speaker A join Speaker B", "Add Beosound to the living room" |
| `.leaveGroup(speaker:)` | `speaker: SpeakerReference` | "Speaker A leave the group", "Disconnect Beosound Stage from the session" |

These cases require new NLP training data for the Tier 2 `NLModel` and new Tier 1 Foundation Models prompt entries. They do not affect the existing 13-intent set; they extend it.

---

### 6.7 Token Summary Table

| Token | Type | New or Existing | Notes |
|---|---|---|---|
| `BeoColor.sessionAccent` | `Color` | New alias | Maps to `BeoColor.accent` (`#C8A97E`) |
| `BeoAnimation.memberJoin` | `AnyTransition` | New | `move(.bottom) + opacity` |
| `BeoAnimation.memberLeave` | `AnyTransition` | New | `move(.trailing) + opacity` |
| `BeoAnimation.groupCardMorph` | `Animation` | New | `easeInOut(0.3)` |
| `BeoAnimation.groupAssemble` | `Animation` | New | `easeInOut(0.4)` |
| All `Spacing.*` | `CGFloat` | Existing | No new values needed |
| All `Radius.*` | `CGFloat` | Existing | No new values needed |
| `BeoType.body` | `Font` | Existing | Reused for member names |
| `BeoType.caption` | `Font` | Existing | Reused for role badge |

**No conflicts with existing tokens have been identified.**

---

## Section 7 — UX/UI Issues and Open Questions

### Issue 1 — Host Cannot Leave Its Own Session (P1, Product Decision)

**Description:** In the Mozart API, the host speaker cannot call `POST /beolink/leave` to leave its own session — it is the session source. The only action available to the host is `POST /beolink/allstandby` (all devices standby) or stopping playback entirely. There is no "disband group" API call.

**Impact:** The host member row has no Leave button. This is accurate to the API, but a user may expect to be able to dissolve the group from the host's row.

**Current design decision:** No leave button on the host row. The HOST badge makes it clear this speaker is the session anchor. Listeners can leave independently.

**Flag:** Product must decide whether to expose "Stop All" (all standby) or "Disband Group" (all leave, host continues playing solo) as a group-level action in v1.2 or defer to v1.3. If added, this would appear as a button in the session header row, not in the host member row.

**Resolution needed from:** Product. Design cannot proceed on this path without a product decision.

---

### Issue 2 — BNR Session Identity Is Not Reliable (P1, Engineering Decision)

**Description:** The research findings (Topic C) confirm that BNR speakers have no peers endpoint. Group membership must be inferred from the `multiroom` field in `/BeoZone/Zone/Sources`. If a BNR speaker is a listener in a Mozart session, the app cannot definitively know the identity of the other participants.

**Impact on UI:** The app may be unable to show the full member list for groups containing BNR speakers. The group card may show "Playing Together · {N} speakers" in the session header but only display the speakers it can identify.

**Proposed degraded-mode UI:**

If the app cannot identify all session members (BNR speaker as listener, peers unknown):
- Show the known speakers as member rows.
- Add an "additional speaker in session" placeholder row: `hifispeaker.fill` icon (muted), label "Other speaker" in `BeoColor.labelSecondary`, no leave button.

**Flag for engineering:** Confirm whether the Mozart `/beolink/peers` endpoint on the host speaker returns the JIDs of BNR listeners. If yes, the app can call the Mozart peer to get BNR device identity and the degraded mode is unnecessary.

**Resolution needed from:** Engineering research.

---

### Issue 3 — Voice-Leave Countdown Duration (RESOLVED)

**Resolution:** Voice-leave is immediate — no countdown. The leave API call fires as soon as the voice command is parsed and the read-back completes. This decision is recorded in the functional spec (VoxioSpecification-1.2.md §Technical Context: "Leave is immediate — no countdown required") and is now applied consistently in this design spec (§4.1). `ConfirmationCoordinator` requires no changes for v1.2. This issue is closed.

---

### Issue 4 — Cross-Platform Join (Mozart Speaker Joining BNR Host) (P2, Product Decision)

**Description:** The research findings confirm that when a Mozart speaker (A) attempts to join a BNR speaker (B) that is the current host, the only available path is for A to call `beolinkJoin()` — which joins "the active" Beolink session on the LAN. This is unreliable if multiple sessions exist.

**Impact on UX:** The voice command "Speaker A join Speaker B" may fail silently or join the wrong session if B is a BNR speaker and another session is active.

**Proposed UI for this case:**
- The join proceeds as normal from the UI perspective.
- If the API call succeeds but A ends up in a different session (detectable by checking A's post-join peer list), show an error toast: "Couldn't join [B]'s session. Try stopping other sessions first."
- If the API call fails, show the standard join error toast.

**Flag for product:** Should the voice command "Speaker A join Speaker B" be disabled (with an error response) when B is a BNR speaker and another session is active? Or should the app attempt the join and surface an error on failure?

**Recommendation:** Attempt and surface error on failure. Do not pre-emptively block the command — most home networks have at most one active session, so the ambiguous case is rare.

**Resolution needed from:** Product sign-off.

---

### Issue 5 — Card Height on Small Devices (P2, Design)

**Description:** A 4-member group card is approximately 372 pt tall. On an iPhone SE (screen height 667 pt, usable height after safe areas ~560 pt), a 4-member group card plus the orb animation at the bottom would leave very little room for other cards in the list.

**Impact:** The list may require the user to scroll even when the home screen previously fit all speakers without scrolling.

**Mitigation options:**
1. Limit group card max height to 300 pt and scroll internally (scrollable member list within the card). This trades external scroll for internal scroll.
2. Collapse to 3 member rows at 3+ members (rather than the 4-member threshold described in §2.5). This reduces the threshold.
3. Accept that a 4-speaker group on an SE-class device requires scrolling. Most modern iPhones have ≥ 812 pt usable height where this is not a problem.

**Recommendation:** Option 3 for v1.2. Document the SE edge case as a known limitation. The SE is the minimum supported device size, and multi-speaker groups are a power-user feature. Re-evaluate in v1.3 if user feedback confirms SE users are common.

**Resolution needed from:** Design and Product sign-off on the known limitation.

---

### Issue 6 — VoiceOver Focus Order in the Group Card (P2, Accessibility)

**Description:** A group card contains multiple interactive elements (multiple leave buttons) and multiple speaker names. The VoiceOver focus order must be unambiguous.

**Specified VoiceOver reading order:**

1. Session header: "[N] speakers playing together" (non-interactive)
2. Now-playing panel: "[Track name], playing on [Source]" (non-interactive)
3. Volume: "Volume [N]" (non-interactive)
4. Host member: "[Speaker name], host" (non-interactive)
5. Listener 1: "[Speaker name]" then "Leave [Speaker name], button" (interactive)
6. Listener 2: "[Speaker name]" then "Leave [Speaker name], button" (interactive)
… and so on.

The group card is **not** wrapped in `.accessibilityElement(children: .ignore)` — it must expose its interactive children (leave buttons) to VoiceOver. The overall card is not a single VoiceOver element; it is a container of individually focusable elements.

**Accessibility labels for leave buttons:**

| Element | accessibilityLabel |
|---|---|
| Leave button for listener | "Leave group, [Speaker name]" |
| HOST badge | "Host" (read as part of the speaker name row: "[Speaker name], host") |
| Session header | "[N] speakers playing together" |
| "Show more speakers" button | "Show [N] more speakers" |
| "Show less" button | "Show fewer speakers" |

---

### Issue 7 — Reduce Motion: Card Assembly and Morph (P2, Accessibility)

When Reduce Motion is enabled:
- Member row join/leave: replace `move + opacity` transitions with `opacity` only (cross-fade at 0.2 s).
- Group card morph (group-of-2 → group-of-1): cross-fade at 0.2 s instead of the `easeInOut(0.3)` morph.
- Group card assembly at startup: cross-fade at 0.2 s instead of `easeInOut(0.4)`.
- No change to card content rendering or touch targets.

---

### Issue 8 — "Leave" Button Label Length and Localisation (P2, Design)

**Description:** In Danish, "Leave" translates to "Forlad" (imperative) — 7 characters vs 5. This is fine. However, the HOST badge translates to "VÆRT" — 4 characters — and the session header "Spiller Sammen · {N} højttalere" is significantly longer than the English equivalent, which may cause the session header to wrap to two lines on narrow devices (iPhone SE at 375 pt).

**Mitigation:** Set `lineLimit(1)` and `truncationMode(.tail)` on the session header label. If truncation occurs, the full text is available via VoiceOver's `accessibilityLabel`. The icon (`link.circle.fill`) remains visible even when the label truncates — the session status is not lost.

**Alternative for very narrow devices:** Show "· {N}" (just the count) when the full label does not fit. This requires a `ViewThatFits` or geometry-based conditional. Flag for engineering if SE testing shows truncation.

---

### Issue 9 — Session Header Wording When Group Has No Active Playback (P3, Design)

**Description:** A group can exist (peers are linked) without any speaker actively playing. For example, all speakers are idle but remain linked from a previous session.

**Current spec (§2.2) assumes active playback.** "Playing Together" is inaccurate when nothing is playing.

**Proposed state-aware wording:**

| Group playback state | Session header label |
|---|---|
| Playing | "Playing Together · {N} speakers" |
| Paused | "Paused · {N} speakers" |
| Stopped / Idle | "Linked · {N} speakers" |

The icon remains `link.circle.fill` in `BeoColor.accent` when playing; `BeoColor.labelSecondary` when not playing.

**Decision needed from:** Product (confirm the "Linked" concept is meaningful to users — it implies a session exists but nothing is playing, which may be confusing vs. just showing individual speaker cards).

---

### Issue 10 — What Happens to a Group Card When the Group Host Goes Offline (P2, Engineering Decision)

**Description:** If the host speaker drops off the network during an active group session, the group card loses its source of truth for playback state.

**Proposed behaviour:**
- The host member row adds an offline indicator: `wifi.slash` icon (14 pt, `BeoColor.labelSecondary`) replacing the `hifispeaker.fill` icon.
- The now-playing panel is replaced with the standard offline/error state (matching v1.1 speaker card behaviour: subtitle reads "Offline" in `BeoColor.labelSecondary`).
- Leave buttons on listener rows remain active — listeners should still be able to leave an orphaned session.
- After the speaker reconnects (mDNS re-discovery), the card returns to normal state.

**Resolution needed from:** Engineering (confirm that leave API calls succeed on listener speakers even when the host is unreachable).

---

## Section 8 — Screens Summary

| State | Trigger | Primary Element | Session Chrome Visible |
|---|---|---|---|
| Group of 1 — any state | Single speaker in group | Standard `SpeakerCard` | No |
| Group of 2+ — playing | Multiple speakers in session | `GroupCard` with session header, member rows, leave buttons | Yes |
| Group of 2+ — paused | Host paused | `GroupCard`, now-playing panel shows last track | Yes |
| Group of 2+ — idle | No playback | `GroupCard`, "Linked · N speakers" header | Yes |
| Join countdown | Voice join command parsed | E-25 countdown surface with join read-back | Background unchanged |
| Join in progress | Countdown auto-executed | Group card shows loading state in header + A shows joining state | Partial (loading chrome) |
| Join error | API failure | Standard error toast (non-blocking, top) | Unchanged |
| Leave in progress | Leave button tapped | Leave button shows spinner; row disabled | Unchanged |
| Leave complete | API success | Member row slides out, card shrinks | Yes (updated count) |
| Leave error | API failure | Standard error toast | Unchanged |
| Startup assembly | Peer fetch completes | Individual cards fade out, group card fades in | Instant |

---

## Section 9 — Iconography

All icons use SF Symbols 6 (iOS 26 baseline). No custom iconography in v1.2.

| Element | SF Symbol | Rendering Mode | Tint |
|---|---|---|---|
| Session indicator | `link.circle.fill` | `.hierarchical` | `BeoColor.accent` when playing, `BeoColor.labelSecondary` otherwise |
| Member speaker icon | `hifispeaker.fill` | `.hierarchical` | `BeoColor.labelSecondary` |
| Leave button icon | `xmark.circle.fill` | `.monochrome` | `Color.red` (system adaptive) |
| Offline member | `wifi.slash` | `.hierarchical` | `BeoColor.labelSecondary` |
| Show more/less chevron | `chevron.down` / `chevron.up` | `.monochrome` | `BeoColor.labelPrimary` |
| Divergent-state indicator | `pause.fill` | `.monochrome` | `BeoColor.labelSecondary` |

---

## Section 10 — Accessibility Summary

| Requirement | Specification |
|---|---|
| Minimum tap target | 44 × 44 pt for all leave buttons (visual 36+ pt; `.frame(minWidth: 44, minHeight: 44)` on wrapper) |
| VoiceOver focus order | Session header → now-playing → volume → host row → listener rows with leave buttons (§7 Issue 6) |
| VoiceOver labels | Full label table in §7 Issue 6 |
| Dynamic Type | All text uses `BeoType` tokens scaled by Dynamic Type. Card height adapts. Member row minimum height 52 pt; grows with content. |
| Reduce Motion | All spring/slide animations replaced by cross-fade (0.2 s). Card assembly uses cross-fade (0.2 s). |
| Increase Contrast | Group card inherits the 1 pt `BeoColor.muted` border from the existing `SpeakerCard` Increase Contrast path. Member row dividers increase to 1 pt at `BeoColor.muted` opacity 0.5. |
| Colour as sole differentiator | Never. The HOST badge uses text ("HOST") not just gold colour. The session indicator uses an icon + text, not just a tinted border. Leave buttons use icon + label, not colour alone. |

---

## Section 11 — Out of Scope (v1.2 Group UI)

- **Disband group / all standby.** The host cannot leave or disband the session in v1.2. This is a known limitation (§7 Issue 1). Deferred to v1.3.
- **Volume per member.** The group card shows only the host speaker's volume. Individual member volume control is not surfaced. All members in a Beolink session share the volume command — per-member volume is a v1.3+ consideration.
- **Reordering members.** The member list is ordered: host first, then listeners in discovery order. No drag-to-reorder.
- **Naming / renaming a group.** Groups are ad-hoc; they do not have persistent names. "Playing Together" is the fixed session label.
- **Group-level play/pause/stop.** All commands in v1.2 target individual speakers. The group card does not have a play/pause button. Voice commands to the host speaker propagate to the session naturally via Beolink.
- **Live Activity for groups.** Deferred to v1.3 (consistent with the widget spec deferral).
- **iPad and landscape.** Portrait iPhone only.

---

## Appendix A — SF Symbol Reference (Group-Specific Additions)

| Symbol | Usage | Confirmed SF Symbols 6 |
|---|---|---|
| `link.circle.fill` | Session indicator in group card header | Yes |
| `wifi.slash` | Offline member in member row | Yes (existing in v1.1 iconography) |
| `xmark.circle.fill` | Leave button icon | Yes (note: distinct from `xmark` used in cancel buttons — the `.circle.fill` variant reads clearly at 14 pt in a dense row) |

---

## Appendix B — Design Tokens Reference (v1.2 Group UI Additions)

```swift
// BeoColor addition — semantic alias for session-related accent usage
extension BeoColor {
    static let sessionAccent = BeoColor.accent  // T-2800: maps to Color("Accent") = #C8A97E
}

// Animation additions — group card transitions
extension BeoAnimation {
    static var memberJoin: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal:   .move(edge: .trailing).combined(with: .opacity)
        )
    }
    // Note: memberJoin / memberLeave are AnyTransition, not Animation.
    // Apply with: withAnimation(BeoAnimation.spring) { ... }

    static let groupCardMorph:  Animation = .easeInOut(duration: 0.3)
    static let groupAssemble:   Animation = .easeInOut(duration: 0.4)
}
```

No new `Spacing`, `Radius`, or `BeoType` enum cases are required. All group UI spacing, sizing, and typography is served by existing tokens.

No new colour asset values are required in `Assets.xcassets`. `BeoColor.sessionAccent` is a Swift alias to the existing `Accent` asset.

---

*End of design specification v1.0*
