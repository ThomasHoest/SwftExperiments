# ADR-003 — Listener-Based Group Reconstruction (Discovery Service)

**Status:** Proposed
**Date:** 2026-05-12
**Deciders:** Engineering Lead
**Refs:** ADR-002-voxio-1.4-ios.md (D3 group/session model), ADR-E53-group-chip-row.md (chip row consumes `SpeakerGroup.members`), ADR-E54-bottom-bar-redesign.md (connector consumes `[SpeakerGroup]`), Mozart Open API spec v5.3.1.108 (`/api/v1/beolink/listeners`, `/api/v1/beolink/peers`, `BeolinkListener`, `BeolinkLeader` schemas), CLAUDE.md (Mozart REST base, mDNS service type, `/playback/sources/active`)

---

## 1. Decision

`SpeakerDiscoveryService.reconstructGroupsAsync()` is rewritten to build `SpeakerGroup` membership from **`GET /beolink/listeners`** on each Mozart speaker (leader → followers) and from **`activeSources.primaryJid`** in each ASE speaker's existing `/BeoZone/Zone/ActiveSources` response (follower → leader's JID). The existing `getPeers()` path remains in place for F2 / E-59 drag-target discovery only — it is no longer used to derive group membership. The current peers-based union-find merges all Beolink-discoverable Mozart speakers into a single "group" regardless of playback state, which is the bug causing wrong speakers to appear in E-53's chip row and E-54's connector line. The listeners-based reconstruction reflects actual real-time grouping state and unblocks F2 (drag-to-join, tap-to-remove) from operating on top of a misread of the current state.

---

## 2. Context

### Bug manifestation

On a network with multiple Mozart speakers, the session card's group chip row (E-53) and the bottom bar's pill connector line (E-54) show speakers as grouped even when no Beolink group exists at the Mozart level — confirmed during on-device testing of F1.

### Root cause

`SpeakerDiscoveryService.reconstructGroupsAsync()` (lines 162–194) calls `getPeers()` per Mozart speaker, then runs a union-find that merges any pair of speakers reporting each other as peers. The Mozart Open API spec describes `GET /beolink/peers` as:

> "Get information about the Beolink peers **discovered by** this device."

That is, every Beolink-capable device on the local mesh that this speaker can reach — the set of *possible* expansion targets, not the set of *current* group members. On a healthy LAN with multiple Mozart speakers, all peers see all peers, so the union-find collapses them into one giant group.

### Prior decisions affected

- **ADR-002 D3** defines `SpeakerGroup { members: [Speaker], hostSpeaker: Speaker }` as the canonical group model produced by `SpeakerDiscoveryService`. This ADR does not change the model — only how it's populated.
- **ADR-E53 §7** (`SpeakerCard.groupMembers: [Speaker] = []`) and the `GroupChipRow` consume `SpeakerGroup.members` filtered to exclude the host. Display logic is correct; the data feeding it is wrong.
- **ADR-E54 §7** introduces `sameGroup(_:_:)` on `SpeakerSelectorPill` to determine connector visibility, reading from the injected `[SpeakerGroup]`. Same situation — display logic correct, source data wrong.
- **F2 / E-59–E-61** (deferred) implements drag-to-join and tap-to-remove. F2 will *write* group state via `/beolink/expand` and `/beolink/leave`, then expect the next discovery cycle to reflect the change. If the read path is wrong, F2 cannot be tested or trusted to operate.

### Authoritative Mozart endpoints

From the Mozart Open API spec v5.3.1.108:

| Endpoint | Returns | Semantics |
|---|---|---|
| `GET /beolink/peers` | `[BeolinkPeer]` (jid + friendlyName + ipAddress) | All Beolink devices visible on the mesh. **Discovery-time data.** |
| `GET /beolink/listeners` | `[BeolinkListener]` (jid + audioTransport) | Devices currently listening to *this* device's active experience. **Live grouping data.** |
| `GET /beolink/self` | `BeolinkSelf` (jid + friendlyName) | Own identity. |
| `GET /playback/sources/active` | response includes `playbackContentMetadata.remoteLeader: BeolinkLeader` (jid + friendlyName) | If present on a follower, points to the leader's JID. **Follower-side cross-check.** |

The `/beolink/listeners` response carries only `jid` — we resolve JID → local `Speaker` via the existing `Speaker.identifier.jid`. Friendly name comes from the local `Speaker`, not the listener payload.

### Authoritative ASE/BNR endpoint

BNR/ASE does not currently override `SpeakerClient.getPeers()` (so it returns the protocol default `[]`), with the result that all ASE speakers are rendered as solo today. The grouping data exists in the existing `/BeoZone/Zone/ActiveSources` response — already fetched on every state poll — but is not consumed for group reconstruction. Specifically, `BNRActiveSourcesResponse.ActiveSources.primaryJid` (BNRClient.swift:318) carries the JID of the device that **owns** the primary experience:

- If `primaryJid` is missing or equals this speaker's own JID → leader or solo.
- If `primaryJid` is a different JID → this speaker is following that JID's device.

The C# reference `BuildExpandExperienceRequest(listenerJid)` and the existing `BNRClient.expandExperience(listenerJid:)` confirm the leader-owns-primaryExperience model. The `borrowed: Bool` flag on each `BNRSourceObject` (BNRClient.swift:337) corroborates follower state — already used to filter the favorites list in `getSources()` (BNRClient.swift:240).

### iOS 26 platform constraints

`URLSession` + `JSONDecoder` are the only platform dependencies of this change. No new frameworks, no new background tasks, no entitlements changes.

### Currently observable state

| Symptom | Status |
|---|---|
| Mozart-only LAN: all speakers shown as one group regardless of playback | Reproduced |
| ASE-only LAN: all speakers solo regardless of join state | Reproduced (default `getPeers()` returns `[]`) |
| Mixed LAN: Mozart pool merges; ASE pool stays solo | By inspection |
| F2 / E-59 drop targets if we used `discovery.groups` | Would inherit the wrong grouping |

---

## 3. Options Considered

### Option A — Listeners + activeSources.primaryJid (chosen)

Two-step reconstruction:
1. **Leader-side scan** (Mozart): per Mozart speaker, fetch `/beolink/listeners`. Non-empty result ⇒ this speaker is a leader; group = `[self] + resolve(listeners.map(\.jid))`. Resolution = lookup in `allSpeakers` by `speaker.identifier.jid`.
2. **Follower-side scan** (ASE + Mozart cross-check): per speaker not yet assigned to a group, fetch the leader JID:
   - ASE: from `/BeoZone/Zone/ActiveSources` → `activeSources.primaryJid` (filter: ignore if equals own JID).
   - Mozart: from `/playback/sources/active` → `playbackContentMetadata.remoteLeader.jid`.
   If the leader JID resolves to a known speaker, fold this speaker into the leader's group (creating a 2-speaker group if the leader scan didn't see it — handles the brief window where one side updates first).
3. **Leftover** speakers → solo groups of 1.

Advantages: leader-side is authoritative when available, follower-side handles the race where one side updates first, both platforms get correct grouping with the same algorithm.

Disadvantages: two REST calls per speaker in the worst case. Same network cost order as today (today is one `getPeers()` per Mozart speaker + zero for ASE; new is one `getListeners()` per Mozart + one cross-check fetch for unassigned speakers). Acceptable.

### Option B — Metadata-only (`playbackContentMetadata.remoteLeader.jid`)

Skip listeners entirely. For each speaker, look at its own active source. If `remoteLeader.jid` is present, fold into that leader's group.

Advantages: one REST call per speaker (no separate `/beolink/listeners`).

Disadvantages: `playbackContentMetadata` is metadata about the *currently playing track*. A leader that isn't currently playing may not have its listeners reflected in any follower's metadata. The listeners endpoint is the spec-canonical "who joined me" query and is correct regardless of playback state. Rejected.

### Option C — Keep peers-based + filter by playback state

Continue using `getPeers()` but only merge speakers whose `playbackState == .playing` AND who share `nowPlaying.primaryLine` AND whose volumes match... this devolves into heuristics that get fragile on radio streams (track changes between speakers in a group), buffering states, and cross-platform mixes. Rejected on first-principles: peers ≠ group.

### Option D — WebSocket-driven incremental updates

If a Mozart WebSocket event announces group changes (e.g. `WebSocketEventBeolinkExperiencesResult` or similar), we could maintain groups incrementally without polling. Pros: real-time. Cons: requires investigation of which WS events are actually emitted by current firmware — separately from the REST fix; not blocking; can be added on top of Option A as a follow-up enhancement. **Out of scope for this ADR.**

---

## 4. Rationale

Option A wins because:
- `GET /beolink/listeners` is the spec-canonical authority for current Mozart grouping.
- The follower-side cross-check (`activeSources.primaryJid` for ASE; `playbackContentMetadata.remoteLeader.jid` for Mozart) makes the algorithm tolerant of the brief race where one side updates ahead of the other.
- A single algorithm covers both platforms uniformly — no platform-specific control flow in `SpeakerDiscoveryService`.
- Existing `getPeers()` stays, ready for F2 / E-59 to use as the "where can I expand to?" target list (peers minus current group members ≈ valid drop targets).
- ASE moves from always-solo to correct grouping without changing any platform-specific UX.

---

## 5. Consequences

### Display layers — no contract changes

- **E-53 group chip row**: `SpeakerCard.groupMembers` still receives `group.members.filter { $0.id != group.hostSpeaker.id }` from `SessionStripView`. Same input shape, correct data.
- **E-54 connector line**: `SpeakerSelectorPill.sameGroup(_:_:)` still queries `groups: [SpeakerGroup]`. Same input shape, correct data.
- **F2 / E-59 drag target list**: continues to use `getPeers()` — semantically correct for "where can I expand to?". The drop-target validity computation (E-59 T-5903) intersects peers with non-self speakers and excludes current group members.
- **F2 / E-60 join loading**: writes via `beolinkExpand(jid:)` (Mozart) or `expandExperience(listenerJid:)` (ASE). After write, schedule a `reconstructGroupsAsync()` call after a short debounce (≥ 300 ms — covers the listener-side state propagation window).
- **F2 / E-61 tap-to-remove**: writes via `beolinkLeave()` (Mozart) or `leave()` (ASE). Same post-write reconstruct schedule.

### Network cost

| Scenario | Today | After |
|---|---|---|
| N Mozart speakers | N × `getPeers()` | N × `getListeners()` + ≤ N × `getActiveSource()` for cross-check |
| M ASE speakers | 0 (no override) | ≤ M × already-cached `/BeoZone/Zone/ActiveSources` reads |
| Reconstruct frequency | After `didSettle` and on add/remove | Unchanged |

Worst-case: doubles the network calls during reconstruct. Each call is < 200 bytes, completes in < 100 ms on a healthy LAN. Acceptable.

### Polling vs. push

This ADR keeps the reconstruct trigger model unchanged — runs on `didSettle` and on speaker add/remove. F2 must trigger a fresh reconstruct after every expand/leave write to surface the change in UI within ~500 ms. WS-driven incremental updates are a follow-up.

### F2 architecture impact

F2 / E-59 ADR (when written) must specify:
- Drop-target eligibility uses `getPeers()` (peers visible to the dragged-from speaker), filtered against `discovery.groups` to exclude current group members.
- Successful `beolinkExpand` triggers a `discovery.refreshGroups()` after a 300 ms debounce.
- Drag-from a speaker that's currently a follower: needs to leave its current group first OR the expand call handles the migration (verify against Mozart spec; out of scope here).

### ASE behavior change

ASE speakers transition from always-solo (current) to correctly grouped (new). This is a UX *improvement* but technically a behavior change — flagged here for QA testing scope.

### Mixed-platform groups

Mozart and ASE speakers cannot natively group with each other (different Beolink protocol versions). The algorithm correctly handles this because Mozart's `getListeners()` only returns Mozart peers, and ASE's `primaryJid` only references ASE peers. No special-casing in `SpeakerDiscoveryService` required.

---

## 6. File-Level Plan

### Modified files

| Path | Change |
|---|---|
| `iOS/Voxio/Core/Models/BeolinkPeer.swift` | Unchanged in shape (`{ jid: String, friendlyName: String? }`). Friendly name already Optional — decodes correctly against the minimal `BeolinkListener` payload (no `friendlyName` field) by leaving the property `nil`. |
| `iOS/Voxio/Core/Protocols/SpeakerClient.swift` | Add `func getListeners() async throws -> [BeolinkPeer]` with protocol-extension default `[]`. Add `func getLeaderJid() async throws -> String?` with default `nil`. Keep existing `func getPeers() async throws -> [BeolinkPeer]`. |
| `iOS/Voxio/Core/Networking/MozartClient.swift` | Add `func getBeolinkListeners() async throws -> [BeolinkPeer]` calling `GET /beolink/peers`'s sibling endpoint `GET /beolink/listeners`. Decoding into `[BeolinkPeer]` — Optional `friendlyName` means the spec's `BeolinkListener` shape decodes cleanly. |
| `iOS/Voxio/Core/Networking/MozartClient+SpeakerClient.swift` | Override `getListeners()` to call `getBeolinkListeners()`. Override `getLeaderJid()` to extract `playbackContentMetadata.remoteLeader.jid` from the active-source response, returning `nil` if absent. |
| `iOS/Voxio/Core/Networking/BNRClient.swift` | Add a public `getLeaderJidFromActiveSources() async throws -> String?` helper that reads the already-defined `activeSources.primaryJid` from `/BeoZone/Zone/ActiveSources` (already fetched in `fetchActiveSources()` — can reuse or duplicate the call). Returns `nil` if missing or equals this device's own JID. |
| `iOS/Voxio/Core/Networking/BNRClient.swift` (extension) | Override `SpeakerClient.getLeaderJid()` to call the helper. `getListeners()` stays as the protocol default `[]` — ASE doesn't expose a listeners endpoint we can use, so ASE grouping is purely follower-driven via `getLeaderJid()`. |
| `iOS/Voxio/Core/Discovery/SpeakerDiscoveryService.swift` | Rewrite `reconstructGroupsAsync()` per Option A. Remove the union-find over `getPeers()`. Add `func refreshGroups() async` (public, callable from F2 post-write reconstruct triggers). Add per-speaker debug logs: `[SDS] <speakerName>: leader of N | follower of <jid> | solo`. |

### New files

None — all changes are additive within existing files.

### No changes to

- `iOS/Voxio/Core/Models/SpeakerGroup.swift` (`Group.swift`) — group model unchanged.
- `iOS/Voxio/Core/Models/Speaker.swift` — speaker model unchanged.
- `iOS/Voxio/Features/Home/SpeakerCard.swift` — chip row consumer unchanged.
- `iOS/Voxio/Features/Home/SpeakerSelectorPill.swift` — connector consumer unchanged.
- `iOS/Voxio/Features/Home/SessionStripView.swift` — group source unchanged.
- Any backend or spec file.

---

## 7. Public Interface Contract

```swift
// MARK: - SpeakerClient additions
// File: iOS/Voxio/Core/Protocols/SpeakerClient.swift

protocol SpeakerClient {
    // ... existing methods unchanged ...

    /// Returns Beolink-capable devices visible on the local mesh. Used by F2 / E-59
    /// to populate drop-target eligibility. Mozart-only today; ASE returns []. NOT
    /// used for current-group membership — see getListeners() for that.
    func getPeers() async throws -> [BeolinkPeer]    // existing

    /// Returns devices currently listening to this device's active experience.
    /// Non-empty ⇒ this device is a leader; the returned JIDs are its followers.
    /// Empty ⇒ this device is solo or itself a follower (use getLeaderJid()).
    /// Mozart: calls GET /beolink/listeners. ASE: returns [] (use getLeaderJid()).
    func getListeners() async throws -> [BeolinkPeer]

    /// Returns the JID of the device this speaker is currently following, or nil if
    /// this device is solo or a leader. Mozart: reads playbackContentMetadata.
    /// remoteLeader.jid from /playback/sources/active. ASE: reads activeSources.
    /// primaryJid from /BeoZone/Zone/ActiveSources, returning nil when equal to
    /// own JID.
    func getLeaderJid() async throws -> String?
}

extension SpeakerClient {
    func getListeners() async throws -> [BeolinkPeer] { [] }
    func getLeaderJid() async throws -> String? { nil }
}
```

```swift
// MARK: - MozartClient additions
// File: iOS/Voxio/Core/Networking/MozartClient.swift

extension MozartClient {
    /// GET /beolink/listeners — current followers of this speaker.
    func getBeolinkListeners() async throws -> [BeolinkPeer] {
        try await get("/beolink/listeners")
    }
}

// File: iOS/Voxio/Core/Networking/MozartClient+SpeakerClient.swift

extension MozartClient: SpeakerClient {
    func getListeners() async throws -> [BeolinkPeer] {
        try await getBeolinkListeners()
    }

    func getLeaderJid() async throws -> String? {
        // Decode playbackContentMetadata.remoteLeader.jid from /playback/sources/active.
        // Returns nil if not following anyone or if metadata is absent.
        // Implementation reuses the existing /playback/sources/active fetch path with
        // a metadata decoder that tolerates absent remoteLeader.
    }
}
```

```swift
// MARK: - BNRClient additions
// File: iOS/Voxio/Core/Networking/BNRClient.swift

extension BNRClient {
    /// Returns activeSources.primaryJid from /BeoZone/Zone/ActiveSources, or nil if
    /// missing or equal to this device's own JID. Used to detect ASE follower state.
    func getLeaderJidFromActiveSources() async throws -> String? {
        let raw = try await send("/BeoZone/Zone/ActiveSources", method: "GET")
        let response = try decoder.decode(BNRActiveSourcesResponse.self, from: raw)
        guard let jid = response.activeSources?.primaryJid else { return nil }
        let ownJid = try? await getJid()
        return jid == ownJid ? nil : jid
    }
}

extension BNRClient: SpeakerClient {
    func getLeaderJid() async throws -> String? {
        try await getLeaderJidFromActiveSources()
    }
    // getListeners() stays as protocol default [] — ASE has no listener-side endpoint.
}
```

```swift
// MARK: - SpeakerDiscoveryService rewrite
// File: iOS/Voxio/Core/Discovery/SpeakerDiscoveryService.swift

extension SpeakerDiscoveryService {
    /// Forces a fresh group reconstruction. Call after F2 expand/leave writes complete.
    func refreshGroups() async {
        await reconstructGroupsAsync()
    }
}

// reconstructGroupsAsync() rewrite (replaces lines 162–194):
//
// 1. Reset accumulator: `var groupBuilder: [String /* leaderJid */: [Speaker]] = [:]`,
//    `var assigned: Set<UUID /* speaker.id */> = []`.
//
// 2. Leader-side scan (Mozart):
//    for each speaker in allSpeakers where platform == .mozart:
//        let listeners = (try? await speaker.client.getListeners()) ?? []
//        guard !listeners.isEmpty, let selfJid = speaker.identifier.jid else { continue }
//        var members: [Speaker] = [speaker]
//        for listener in listeners {
//            if let s = allSpeakers.first(where: { $0.identifier.jid == listener.jid }) {
//                members.append(s)
//            }
//        }
//        groupBuilder[selfJid] = members
//        for m in members { assigned.insert(m.id) }
//
// 3. Follower-side scan (ASE + Mozart cross-check):
//    for each speaker in allSpeakers where !assigned.contains(speaker.id):
//        guard let leaderJid = (try? await speaker.client.getLeaderJid()) else { continue }
//        guard let leader = allSpeakers.first(where: { $0.identifier.jid == leaderJid }) else { continue }
//        if var existing = groupBuilder[leaderJid] {
//            // Leader already accounted for; just add this follower.
//            if !existing.contains(where: { $0.id == speaker.id }) { existing.append(speaker) }
//            groupBuilder[leaderJid] = existing
//        } else {
//            // Leader didn't report listeners (timing race or empty list); create 2-speaker group.
//            groupBuilder[leaderJid] = [leader, speaker]
//            assigned.insert(leader.id)
//        }
//        assigned.insert(speaker.id)
//
// 4. Solo groups: every speaker not yet assigned becomes a group-of-1.
//    for speaker in allSpeakers where !assigned.contains(speaker.id):
//        groupBuilder["solo-\(speaker.id)"] = [speaker]
//
// 5. Build SpeakerGroup array: each accumulator entry becomes a SpeakerGroup whose
//    hostSpeaker is the leader (the speaker whose JID matched the key) or the first
//    member for solo groups.
//
// 6. Set `self.groups = ...`. Log per-speaker role lines: `[SDS] <name>: leader (N followers) | follower of <leaderJid> | solo`.
```

```swift
// MARK: - getLeaderJid implementation note for Mozart
//
// /playback/sources/active returns a wrapper object. The relevant nested field is:
//   { ... "playbackContentMetadata": { ... "remoteLeader": { "jid": "...", "friendlyName": "..." } } }
//
// The remoteLeader key may be absent entirely when not following. The decoder
// chain must tolerate:
//   - playbackContentMetadata absent → return nil
//   - playbackContentMetadata present, remoteLeader absent → return nil
//   - remoteLeader present → return remoteLeader.jid
//
// Implementation: define a private Codable shape inside MozartClient+SpeakerClient
// that decodes just the path we need; ignore all other fields.
```

Key behavioural contracts:

1. `getListeners()` on Mozart returns the listeners list verbatim; an empty list explicitly means "this device is solo or itself a follower."
2. `getLeaderJid()` returns `nil` when this device is solo or a leader. Returns the leader's JID string when this device is currently following someone.
3. `getLeaderJid()` on ASE returns `nil` when `activeSources.primaryJid` equals this device's own JID (this device is its own primary).
4. `getLeaderJid()` on Mozart returns `nil` when `playbackContentMetadata.remoteLeader` is absent.
5. `reconstructGroupsAsync()` is idempotent — calling it twice in succession produces the same `groups` array (modulo speaker pointer identity which is stable).
6. A successful F2 write (`beolinkExpand` or `beolinkLeave`) must trigger `discovery.refreshGroups()` after a ≥ 300 ms debounce. F2's ADR will record the exact delay.
7. The order of `groups` in `discovery.groups` reflects the leader's order in `allSpeakers` (which is discovery order), not insertion order to `groupBuilder`.
8. **Unresolved-leader edge case**: if a follower's `getLeaderJid()` returns a JID that is **not** in `allSpeakers` (leader was not discovered by mDNS — different VLAN, or speaker offline between discovery and reconstruct), the follower is assigned as a solo group-of-1. The `guard let leader = allSpeakers.first(where: ...)` branch in §6 silently drops these followers into the leftover bucket, where Step 4 produces the solo group. This is correct safe behavior — render as solo rather than crash on an unknown JID.

---

## 8. Conflicts Flagged

### CF-1: F2 / E-59 drop-target eligibility — uses `getPeers()`, not `groups`

F2 / E-59's drag-to-join needs to know "what speakers can I expand to from speaker X?" That answer is `getPeers()` on speaker X, filtered to exclude speakers already in X's current group. This ADR keeps `getPeers()` available and unchanged. F2 / E-59's ADR (when written) must explicitly cite `getPeers()` for drop targets — not `discovery.groups`, which is the *current* membership, not the *eligible* membership.

### CF-2: ASE-only environments lose the visual all-solo behavior

ASE speakers will now correctly show grouping when they're following another ASE leader. Pre-existing ASE deployments where users have grouped speakers via the BeoApp will see those groups in Voxio's chip row and connector line for the first time. This is a UX improvement but is a behavior change worth flagging in QA scope and in release notes.

### CF-3: Mixed Mozart + ASE LANs

A Mozart speaker and an ASE speaker cannot natively form a Beolink group with each other (different protocols). The algorithm correctly produces separate groups for each platform's leaders. No special-casing is required, but the implementer must verify this by inspection.

### CF-4: WebSocket events not used here

Mozart may emit Beolink-related WS events (verification TBD). This ADR's reconstruct is polling-triggered (on `didSettle` and add/remove, plus F2 post-write triggers). Real-time updates via WS are a future enhancement and explicitly out of scope. The polling delay between an external app's group change and Voxio reflecting it is bounded by the user's next interaction or the next mDNS settle cycle — acceptable for v1.4.

### CF-5: Cross-check fetch cost for Mozart

The follower-side cross-check on Mozart re-fetches `/playback/sources/active`. The active-source data is already pulled at speaker init and on WS event — we have it in memory. Optimisation: read from `speaker.activeSource` if cached and only fall back to a fresh fetch if cache is stale (> some threshold). **Out of scope for this ADR's initial implementation** — the simple per-reconstruct fetch is fast enough at typical home-LAN scales (1–8 speakers).

### CF-6: F1 / E-57 group volume broadcast unaffected

E-57's `SpeakerGroup.setVolumeOnAllMembers(_:)` operates on `group.members` regardless of how the group was constructed. Correct group data ⇒ correct broadcast targets. No code change needed in F1.

### CF-7: F1 / E-56 transport dispatch unaffected

E-56's `resolvedGroup.hostSpeaker.play()` / `.pause()` similarly operates on whatever `SpeakerGroup` is wired in. Correct group ⇒ correct transport target.

---

## 9. Platform Constraint Checks

| API | Introduced | Status |
|---|---|---|
| `URLSession` HTTP GET to `http://<speaker-ip>/api/v1/beolink/listeners` | Existing pattern | Safe |
| JSON decoding `[BeolinkPeer]` with Optional `friendlyName` | Existing pattern | Safe (`Optional` decodes as `nil` when key absent) |
| `withTaskGroup` for parallel per-speaker fetches | iOS 15+ | Safe (already used in `Speaker.initialize()` and `SpeakerGroup.setVolumeOnAllMembers`) |
| Re-using `MdnsDiscovery.foundHosts` semantics | Existing | Unchanged |

No new entitlements, frameworks, or platform features.

---

## 10. Task Gate

Not an epic-style task list — this is a single corrective change. Implementation breakdown:

| Step | Description |
|---|---|
| Step 1 | Add `getListeners()` and `getLeaderJid()` to `SpeakerClient` protocol with extension defaults. |
| Step 2 | Add `MozartClient.getBeolinkListeners()`. |
| Step 3 | Override `getListeners()` and `getLeaderJid()` in `MozartClient+SpeakerClient`. Implement `getLeaderJid()` with a private decoder shape for `playbackContentMetadata.remoteLeader.jid`. |
| Step 4 | Add `BNRClient.getLeaderJidFromActiveSources()` and override `getLeaderJid()` in BNR's `SpeakerClient` extension. |
| Step 5 | Rewrite `SpeakerDiscoveryService.reconstructGroupsAsync()` per §7. |
| Step 6 | Add `SpeakerDiscoveryService.refreshGroups()` public method. |
| Step 7 | Per-speaker log line on reconstruct: `[SDS] <name>: leader (N) | follower of <jid> | solo`. |
| Step 8 | Build verify. |
| Step 9 | Manual verification on a real LAN: form/break Beolink groups via the BeoApp and confirm chip row + connector update within one reconstruct cycle (≤ a few seconds). |

---

**Verdict: PROCEED** (pending architect review of this ADR).
