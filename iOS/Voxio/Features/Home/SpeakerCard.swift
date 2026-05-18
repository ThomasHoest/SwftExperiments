import SwiftUI

// MARK: - SpeakerCard
//
// E-56 changes applied in this file:
//   T-5601 — cardContent now switches on speaker.playbackState (four-case enum).
//   T-5602 — transportRow computed view; DarkGlassIconButton(size: 52).
//   T-5603 — onPlayTapped() / onPauseTapped() implementations.
//   T-5604 — PlaybackBars receives playbackState: speaker.playbackState.
//   T-5605 — optional SpeakerGroup param; resolvedGroup computed property.
//   T-5606 — @Binding var errorMessage: String?; showErrorToast helper; stopped-state Play pill.
//   T-5607 — .accessibilityElement(children: .contain); summary moved to headerSection.
//   T-5609 — #Preview blocks for all four playback states.
//
// E-57 changes applied in this file:
//   T-5702 — @State dragVolume/lastLimitHaptic; InteractiveVolumeBar replaces volumeTrack call.
//   T-5703 — handleLimitHaptic(_:) — limit haptic + AccessibilityNotification, gated by lastLimitHaptic.
//   T-5705 — broadcastVolume(_:) async — fan-out via resolvedGroup.setVolumeOnAllMembers; partial-failure toast.
//
// E-58 changes applied in this file:
//   T-5801 — @State favorites: [Favorite]; .task async load via speaker.getFavorites().
//   T-5802 — favoritesRow @ViewBuilder; trailingFadeGradient; mounted in both cardContent branches.
//   T-5803 — onFavoriteTapped(fav:); UIStrings.couldNotStartFavorite error toast.
//   T-5804 — .accessibilityElement(children: .contain) on ScrollView; per-pill labels from DarkGlassButton.
//   T-5806 — #Preview blocks for favorites row (5 favorites playing, 0 favorites playing, 3 favorites stopped).
//
// CF-1 decision: @Binding var errorMessage: String? (SwiftUI symmetry, as ADR recommends).
// Every call site must supply errorMessage:. #Preview blocks use .constant(nil).

struct SpeakerCard: View {
    var speaker: Speaker
    var isExpanded: Bool
    var roll: Double
    var pitch: Double
    /// Non-host members of the speaker's group. Default empty keeps all pre-E-53 call sites valid.
    /// Populated by SessionStripView with group.members filtered to exclude the host.
    var groupMembers: [Speaker] = []   // E-53 T-5304

    /// Optional group for transport + volume dispatch (E-56 T-5605).
    /// When nil, solo card wraps speaker via SpeakerGroup.single(speaker) internally.
    /// F2 will pass real multi-member groups; all existing call sites pass nil (default).
    var group: SpeakerGroup? = nil     // E-56 T-5605

    /// E-59 T-5905: session view model supplying drop state.
    /// Nil on pre-E-59 call sites (HomeView idle card, previews) — no drop destination attached.
    /// CF-7: must be the same SpeakerGroup instance as `group` when both are non-nil.
    var sessionVM: SessionViewModel? = nil   // E-59 T-5905

    /// Routes transport errors to the HomeView toast surface (E-56 T-5606).
    @Binding var errorMessage: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorContrast

    // MARK: - Volume drag state (E-57 T-5702)

    /// Non-nil while the user is dragging the volume bar; overrides speaker.volume for display.
    /// Reset to nil on drag end after broadcastVolume fires.
    @State private var dragVolume: Int? = nil

    /// Tracks which limit (0 or 100) last fired a limitReached haptic within this drag,
    /// preventing repeated firing while held at a boundary.
    @State private var lastLimitHaptic: Int? = nil

    // MARK: - Favorites state (E-58 T-5801)

    /// Favorites loaded from speaker.getFavorites() on card appear.
    /// Empty array while loading, after failure, or when the speaker has no presets.
    @State private var favorites: [Favorite] = []

    // MARK: - Group-aware dispatch (T-5605)

    /// Resolves to the supplied group or a single-speaker group wrapping the card's speaker.
    /// Transport calls always go through resolvedGroup.hostSpeaker.
    private var resolvedGroup: SpeakerGroup { group ?? SpeakerGroup.single(speaker) }

    // MARK: - UIStrings

    private var ui: UIStrings { UIStrings.forLanguage(LanguageService.shared.activeLanguage) }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            cardContent
            if !reduceMotion { specularHighlight }
        }
        .glassEffect(in: RoundedRectangle(cornerRadius: Radius.card))
        // Always-on hairline border so the card edge is visible on the dark background
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card)
                .stroke(Color.white.opacity(colorContrast == .increased ? 0.0 : 0.12), lineWidth: 0.5)
        )
        // T-2206 — Increase Contrast reactive border; BeoColor.muted (labelSecondary alias)
        .overlay(
            colorContrast == .increased
                ? RoundedRectangle(cornerRadius: Radius.card).stroke(BeoColor.muted, lineWidth: 1)
                : nil
        )
        // E-59 T-5905 — Drop destination (CF-2: applied BEFORE .scaleEffect so hit area
        // matches visible geometry after the scale transform).
        // sessionVM == nil → no .dropDestination, no gold-border (pre-E-59 call sites).
        //
        // Behavioural contracts:
        //   1. sessionVM == nil → no .dropDestination, no gold-border overlay.
        //   2. Self-drop (source.id == hostSpeaker.id) returns false; no side effects.
        //   3. Unresolvable identifier (resolveSpeaker returns nil) returns false.
        //   4. dropZoneActive transitions to false within one spring cycle after ghost leaves.
        //
        // .contentShape declares the ENTIRE rounded rectangle as the hit region. Without
        // it SwiftUI hit-tests only against rendered subview shapes (metadata pill, favorite
        // buttons, transport row) — meaning the background area between those subviews was
        // not catching drops. The shape mirrors the card's visual outline.
        .contentShape(RoundedRectangle(cornerRadius: Radius.card))
        .dropDestination(for: SpeakerIdentifier.self) { items, location in
            // Every rejection path logs so we can see WHY a drop fizzled on device.
            guard let vm = sessionVM else {
                Log.info("[Drop] rejected: sessionVM is nil (card not in session strip context)")
                return false
            }
            Log.info("[Drop] received \(items.count) item(s) at \(location.debugDescription) on card hosted by \(vm.group.hostSpeaker.name)")
            guard let droppedId = items.first else {
                Log.info("[Drop] rejected: items.first is nil")
                return false
            }
            Log.info("[Drop] dropped identifier: jid=\(droppedId.jid ?? "nil") host=\(droppedId.host) id=\(droppedId.id)")
            guard let source = vm.resolveSpeaker(droppedId) else {
                Log.info("[Drop] rejected: resolveSpeaker returned nil for id=\(droppedId.id)")
                return false
            }
            guard source.id != vm.group.hostSpeaker.id else {
                Log.info("[Drop] rejected: self-drop — source.id (\(source.name)) == target.id (\(vm.group.hostSpeaker.name))")
                return false
            }
            Log.info("[Drop] ACCEPTED: \(source.name) → \(vm.group.hostSpeaker.name) — dispatching handleJoinDrop")
            vm.handleJoinDrop(source: source, target: vm.group.hostSpeaker)
            return true
        } isTargeted: { isOver in
            guard let vm = sessionVM else { return }
            Log.info("[Drop] isTargeted=\(isOver) for card hosted by \(vm.group.hostSpeaker.name)")
            // Use a fast easeOut instead of BeoAnimation.spring (0.45 s response)
            // so the gold border lights up the moment the ghost enters the card,
            // not after a perceptible delay.
            withAnimation(.easeOut(duration: 0.12)) { vm.dropZoneActive = isOver }
            if isOver { HapticEngine.shared.dragEnteredDropZone() }
        }
        // Scope the cardExpand spring to the scaleEffect transform only — wrapping it in a
        // .transaction would still animate sibling state changes (favorites loading, metadata
        // arriving) in the same render. Using .animation(value:) without a spring (which rings)
        // keeps the expand subtle and prevents layout-shift bouncing that propagated through to
        // the voice feedback area below the card at first boot.
        .scaleEffect(reduceMotion ? 1.0 : (isExpanded ? 1.02 : 1.0))
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .easeOut(duration: 0.2), value: isExpanded)
        // E-59 T-5906 — Drop-zone visual cue applied LAST (CF-2: above hairline borders + scale).
        // Tinted fill + 3 pt stroke for clear visibility when a drag ghost is over the card.
        // Animation: the withAnimation(BeoAnimation.spring) inside isTargeted drives the fade.
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card)
                .fill(BeoColor.accent.opacity(
                    (sessionVM?.dropZoneActive == true) ? 0.10 : 0
                ))
                .allowsHitTesting(false)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card)
                .strokeBorder(BeoColor.accent,
                              lineWidth: (sessionVM?.dropZoneActive == true) ? 3 : 0)
        )
        // T-5607: loosened from .ignore to .contain so transport button is VoiceOver-reachable.
        // Card-level summary moved to headerSection's accessibilityLabel.
        .accessibilityElement(children: .contain)
        // E-61 T-6106: VoiceOver alternate path for join (cross-references US-80 alternate).
        // Drag-and-drop is not VoiceOver-accessible; this custom action presents a
        // confirmationDialog listing every eligible draggable speaker so VoiceOver users
        // can join speakers without a drag gesture. Eligibility uses the same predicate as
        // SpeakerSelectorPill.isDraggable (TR-2): not a playing host, not already grouped.
        .accessibilityAction(named: Text(GroupingStrings.forLanguage(LanguageService.shared.activeLanguage).a11yAddAction)) {
            sessionVM?.presentAddSpeakerSheet = true
        }
        // E-61 T-6106: confirmationDialog driven by sessionVM.presentAddSpeakerSheet.
        // Lists every eligible speaker (same eligibility as SpeakerSelectorPill.isDraggable).
        // Selecting a speaker fires handleJoinDrop — identical to the drag-drop path.
        .confirmationDialog(
            Text(GroupingStrings.forLanguage(LanguageService.shared.activeLanguage).a11yAddAction),
            isPresented: Binding(
                get: { sessionVM?.presentAddSpeakerSheet ?? false },
                set: { sessionVM?.presentAddSpeakerSheet = $0 }
            ),
            titleVisibility: .visible
        ) {
            let discovery = sessionVM?.discovery
            let vm = sessionVM
            let allGroups = discovery?.groups ?? []
            // Eligible speakers: same predicate as SpeakerSelectorPill.isDraggable (TR-2):
            //   (a) Not the playing host of any group
            //   (b) Not already in a multi-member group
            //   (c) Not currently in a joinsInFlight set
            let eligibleSpeakers = allGroups.flatMap(\.members).filter { candidate in
                let isPlayingHost = allGroups.contains {
                    $0.hostSpeaker.id == candidate.id && $0.playbackState == .playing
                }
                let isInMultiGroup = allGroups.contains {
                    $0.members.count > 1 && $0.members.contains { $0.id == candidate.id }
                }
                let isInFlight = vm?.joinsInFlight.contains(candidate.identifier.id) ?? false
                return !isPlayingHost && !isInMultiGroup && !isInFlight
            }
            ForEach(eligibleSpeakers) { candidate in
                Button(candidate.name) {
                    if let vm, let host = vm.group.hostSpeaker as Speaker? {
                        vm.handleJoinDrop(source: candidate, target: host)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        // E-58 T-5801: load favorites once on appear; silent failure (logged at info, no toast).
        .task {
            do {
                favorites = try await speaker.getFavorites()
            } catch {
                Log.info("[\(speaker.name)] getFavorites failed: \(error)")
                favorites = []
            }
        }
    }

    // MARK: - Chip data (E-53 / E-60 T-6002)

    /// Converts groupMembers to [ChipData], applying the overflow rule, then appends
    /// loading chips for any in-flight joins not already resolved to settled members.
    ///
    /// Overflow rule:
    /// - members.count > 3 → 2 member chips + 1 overflow chip (count - 2 remaining).
    /// - members.count <= 3 → one chip per member.
    /// - members.isEmpty → only loading chips (if any in-flight).
    ///
    /// Loading chips (E-60 T-6002):
    /// - Appended AFTER the overflow chip — never count toward overflow threshold.
    /// - Omitted if the speaker is already in groupMembers (settled member wins; avoids
    ///   duplicate when model and task state briefly overlap).
    /// - CF-3: resolveSpeaker uses a synthetic SpeakerIdentifier(host: inFlightId, jid: nil).
    ///   Mozart speakers whose joinsInFlight key is a JID may miss the JID-first lookup
    ///   and fall back to displaying the raw JID string. Cosmetic degradation; verify T-6005.
    private var chipData: [ChipData] {
        // E-61 T-6102: capture sessionVM once so the onTap closures can reference it
        // without capturing `self` (which would extend the view's lifetime unnecessarily).
        let vm = sessionVM

        // Phase 1 — settled member chips with overflow rule.
        var chips: [ChipData]
        if groupMembers.isEmpty {
            chips = []
        } else if groupMembers.count > 3 {
            let memberChips = groupMembers.prefix(2).map { member -> ChipData in
                let m = member
                return ChipData(speakerName: m.name, kind: .member,
                                onTap: { vm?.handleRemoveTap(m) })
            }
            // Overflow chip carries no name — label derived from .overflow(N), not speakerName.
            // Overflow chips are display-only (no individual tap-to-remove).
            let overflowChip = ChipData(speakerName: "", kind: .overflow(groupMembers.count - 2))
            chips = memberChips + [overflowChip]
        } else {
            chips = groupMembers.map { member -> ChipData in
                let m = member
                return ChipData(speakerName: m.name, kind: .member,
                                onTap: { vm?.handleRemoveTap(m) })
            }
        }

        // Phase 2 — loading chips for in-flight joins not yet settled (E-60 T-6002).
        if let vm = sessionVM {
            let settledIds = Set(groupMembers.map { $0.identifier.id })
            for inFlightId in vm.joinsInFlight where !settledIds.contains(inFlightId) {
                // Synthetic identifier — host fallback path (CF-3 cosmetic limitation).
                let resolved = vm.resolveSpeaker(
                    SpeakerIdentifier(host: inFlightId, jid: nil, platform: .mozart)
                )
                let displayName = resolved?.name ?? inFlightId
                chips.append(ChipData(speakerName: displayName, kind: .loading(name: displayName)))
            }
        }

        return chips
    }

    // MARK: - Accessibility summary (T-5607: moved from card level to header level)

    private var accessibilityDescription: String {
        let p = speaker.nowPlaying
        var parts = [speaker.name, speaker.stateDisplay]
        if p.isPlaying {
            if let primary = p.primaryLine, !primary.isEmpty { parts.append(primary) }
            if let secondary = p.secondaryLine, !secondary.isEmpty { parts.append(secondary) }
            if let badge = p.sourceBadge, !badge.isEmpty { parts.append(badge) }
        }
        if let vol = speaker.volume { parts.append("Volume \(vol)") }
        // E-53 T-5305: append group members to accessibility description
        if !groupMembers.isEmpty {
            let strings = GroupChipStrings.forLanguage(LanguageService.shared.activeLanguage)
            let names = groupMembers.map(\.name).joined(separator: ", ")
            parts.append("\(strings.alsoPlaying): \(names)")
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Card content (T-5601: switched on playbackState)

    @ViewBuilder
    private var cardContent: some View {
        switch speaker.playbackState {
        case .playing, .paused, .buffering:
            // Playing branch: header + now-playing panel + volume bar + transport row + group chips
            VStack(alignment: .leading, spacing: 0) {
                headerSection
                nowPlayingPanel
                // T-5702: InteractiveVolumeBar replaces the static volumeTrack.
                // dragVolume overrides speaker.volume while the user drags (WS events don't jump the bar).
                InteractiveVolumeBar(
                    value: Binding<Int>(
                        get: { dragVolume ?? speaker.volume ?? 0 },
                        set: { newValue in
                            dragVolume = newValue
                            handleLimitHaptic(newValue)
                        }
                    ),
                    onEditingChanged: { editing in
                        if !editing {
                            let final = dragVolume ?? speaker.volume ?? 0
                            Task { await broadcastVolume(final) }
                            dragVolume = nil
                            lastLimitHaptic = nil
                        }
                    }
                )
                .padding(.horizontal, Spacing.s24)
                .padding(.vertical, Spacing.s12)
                // transportRow moved inline into nowPlayingPanel — see inlineTransportButton.
                // E-58 T-5802: favorites row — absent when favorites is empty
                favoritesRow
                // E-53 T-5304: group chip row — shown when host has non-host members or in-flight joins.
                // E-60 T-6002: chipData now includes loading chips from sessionVM.joinsInFlight;
                // guard changed from !groupMembers.isEmpty to !chipData.isEmpty so the row
                // appears immediately on drop even before any settled member exists.
                if !chipData.isEmpty {
                    GroupChipRow(chips: chipData)
                        .padding(.horizontal, Spacing.s24)
                        .padding(.bottom, Spacing.s16)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .stopped:
            // Stopped branch: header + full-width Play pill + favorites row.
            // E-58 T-5802: favoritesRow is mounted below stoppedPlayPill.
            VStack(alignment: .leading, spacing: 0) {
                headerSection
                stoppedPlayPill
                // E-58 T-5802: favorites row — absent when favorites is empty
                favoritesRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Header section (T-5607: carries card-level summary accessibilityLabel)

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(speaker.name)
                    .font(BeoType.speakerName)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Text(speaker.stateDisplay)
                    .font(BeoType.body)
                    .foregroundStyle(.secondary)
            }
            .layoutPriority(1)

            Spacer()

            if let badge = speaker.nowPlaying.sourceBadge, !badge.isEmpty {
                Text(badge)
                    .font(BeoType.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.white.opacity(0.07), in: Capsule())
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        // Use the cardContent branch as the discriminator, not speaker.isPlaying:
        // .buffering toggles isPlaying off briefly during normal streaming, which would
        // bounce the header padding (and everything below it) by 12 pt on each buffer event.
        // The nowPlayingPanel renders in all of .playing/.paused/.buffering, so the same
        // 16 pt bottom padding applies to all three; only the .stopped branch (which shows
        // a Play pill instead of nowPlayingPanel) needs the looser 28 pt for visual balance.
        .padding(.bottom, speaker.playbackState == .stopped ? 28 : 16)
        // T-5607: card-level summary now lives here so VoiceOver reads it first,
        // then moves on to the individually-reachable transport button.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Now playing panel

    private var nowPlayingPanel: some View {
        let p = speaker.nowPlaying
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if let primary = p.primaryLine, !primary.isEmpty {
                    Text(primary)
                        .font(BeoType.nowPlaying)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                if let secondary = p.secondaryLine, !secondary.isEmpty {
                    Text(secondary)
                        .font(BeoType.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Inline play/pause button replaces the previous PlaybackBars
            // motif. Saves ~50 pt of vertical real estate vs the standalone
            // transportRow that used to live below the volume bar. Size 36 pt
            // fits the metadata pill without expanding its height noticeably.
            inlineTransportButton
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var inlineTransportButton: some View {
        switch speaker.playbackState {
        case .playing, .buffering:
            DarkGlassIconButton(
                systemImage: "pause.fill",
                role: .default,
                accessibilityLabel: ui.pause,
                size: 36,
                action: onPauseTapped
            )
        case .paused:
            DarkGlassIconButton(
                systemImage: "play.fill",
                role: .confirm,
                accessibilityLabel: ui.play,
                size: 36,
                action: onPlayTapped
            )
        case .stopped:
            EmptyView()   // nowPlayingPanel does not render in .stopped
        }
    }

    // MARK: - Limit haptic (E-57 T-5703)
    // Fires once per boundary crossing within a drag; resets when value returns to mid-range.

    private func handleLimitHaptic(_ value: Int) {
        if value == 0 && lastLimitHaptic != 0 {
            HapticEngine.shared.limitReached()
            AccessibilityNotification.Announcement("Volume at minimum").post()
            lastLimitHaptic = 0
        } else if value == 100 && lastLimitHaptic != 100 {
            HapticEngine.shared.limitReached()
            AccessibilityNotification.Announcement("Volume at maximum").post()
            lastLimitHaptic = 100
        } else if value > 0 && value < 100 {
            lastLimitHaptic = nil
        }
    }

    // MARK: - Group volume broadcast (E-57 T-5705)
    // Dispatched on drag end; partial failures surface via showErrorToast.

    private func broadcastVolume(_ level: Int) async {
        let results = await resolvedGroup.setVolumeOnAllMembers(level)
        let failed = results.filter {
            if case .failure = $0.result { return true } else { return false }
        }
        guard !failed.isEmpty else { return }
        for item in failed {
            if case .failure(let error) = item.result {
                Log.error("[\(item.speaker.name)] setVolume(\(level)) failed: \(error)")
            }
        }
        let suffix = failed.count == 1 ? "speaker" : "speakers"
        showErrorToast("Volume failed on \(failed.count) \(suffix)")
        HapticEngine.shared.errorOccurred()
    }

    // MARK: - Transport row (T-5602)
    // Centred single button: pause.fill when playing/buffering, play.fill (gold) when paused.
    // Layout per design-spec §1.2: h-pad s24, v-pad s16 top, s20 bottom.

    @ViewBuilder
    private var transportRow: some View {
        HStack {
            Spacer()
            switch speaker.playbackState {
            case .playing, .buffering:
                DarkGlassIconButton(
                    systemImage: "pause.fill",
                    role: .default,
                    accessibilityLabel: ui.pause,
                    size: 52,
                    action: onPauseTapped
                )
            case .paused:
                DarkGlassIconButton(
                    systemImage: "play.fill",
                    role: .confirm,
                    accessibilityLabel: ui.play,
                    size: 52,
                    action: onPlayTapped
                )
            case .stopped:
                EmptyView()
            }
            Spacer()
        }
        .padding(.horizontal, Spacing.s24)
        .padding(.top, Spacing.s8)
        .padding(.bottom, Spacing.s8)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Stopped-state Play pill (T-5606)
    // Full-width DarkGlassButton with play.fill icon and .confirm (gold) role.

    private var stoppedPlayPill: some View {
        DarkGlassButton(
            label: ui.play,
            systemImage: "play.fill",
            role: .confirm,
            action: onPlayTapped
        )
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.s24)
        .padding(.top, Spacing.s20)
        .padding(.bottom, Spacing.s20)
    }

    // MARK: - Favorites row (E-58 T-5802, T-5803, T-5804)
    // Horizontally-scrolling pill row. Absent (zero height) when favorites is empty.
    // CF-1: All pills use .default role — NEVER .confirm. No active-favorite highlight (UQ-1).
    // CF-2: Uses fav.presetIndex — NOT ForEach enumeration offset.

    @ViewBuilder
    private var favoritesRow: some View {
        if favorites.isEmpty == false {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.s8) {
                    ForEach(favorites) { fav in
                        DarkGlassButton(label: fav.displayName, role: .default) {
                            onFavoriteTapped(fav: fav)
                        }
                        .fixedSize()
                    }
                }
                .padding(.horizontal, Spacing.s24)
            }
            .mask(trailingFadeGradient)
            .padding(.top, Spacing.s8)
            .padding(.bottom, Spacing.s20)
            // T-5804: contain so VoiceOver navigates each pill individually.
            .accessibilityElement(children: .contain)
        }
        // Empty → EmptyView() — zero height, no placeholder (spec US-72).
    }

    /// Trailing fade gradient that signals scrollability (design-spec §4.2).
    private var trailingFadeGradient: some View {
        LinearGradient(
            stops: [
                .init(color: .white, location: 0),
                .init(color: .white, location: 0.85),
                .init(color: .clear,  location: 1.0)
            ],
            startPoint: .leading,
            endPoint:   .trailing
        )
    }

    /// Tap handler for a favorites pill.
    /// CF-2: uses fav.presetIndex (stored on the Favorite model), NOT ForEach enumeration offset.
    private func onFavoriteTapped(fav: Favorite) {
        HapticEngine.shared.commandRecognised()
        Task {
            do {
                try await speaker.playFavorite(presetIndex: fav.presetIndex)
            } catch {
                Log.error("[\(speaker.name)] playFavorite(\(fav.presetIndex)) failed: \(error)")
                showErrorToast(ui.couldNotStartFavorite)
                HapticEngine.shared.errorOccurred()
            }
        }
    }

    // MARK: - Specular highlight

    private var specularHighlight: some View {
        LinearGradient(
            colors: [.white.opacity(0.16), .clear],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 48)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .offset(x: roll * 28)
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }

    // MARK: - Transport tap handlers (T-5603 + T-5605)

    private func onPlayTapped() {
        HapticEngine.shared.commandRecognised()
        Task { @MainActor in
            do {
                try await resolvedGroup.hostSpeaker.play()
            } catch {
                showErrorToast(errorText(for: error))
                HapticEngine.shared.errorOccurred()
            }
        }
    }

    private func onPauseTapped() {
        HapticEngine.shared.commandRecognised()
        Task { @MainActor in
            do {
                try await resolvedGroup.hostSpeaker.pause()
            } catch {
                showErrorToast(errorText(for: error))
                HapticEngine.shared.errorOccurred()
            }
        }
    }

    // MARK: - Error toast helper (T-5606)
    // Sets the @Binding errorMessage so HomeView's onChange creates the Toast.
    // E-57 and E-58 reuse this helper unchanged.

    private func showErrorToast(_ message: String) {
        errorMessage = message
    }

    private func errorText(for error: Error) -> String {
        if let speakerError = error as? SpeakerError {
            switch speakerError {
            case .timeout:
                return "Speaker timed out"
            case .unreachable:
                return "Speaker unreachable"
            default:
                return "Could not reach \(speaker.name)"
            }
        }
        return "Could not reach \(speaker.name)"
    }
}

// MARK: - Previews (T-5609)
// All four playback states. errorMessage uses .constant(nil) per CF-1 decision (@Binding choice).
// Preview stubs are lightweight — only the minimum protocol surface is implemented.

#if DEBUG

// MARK: Preview stubs (main-target only, not exported to test target)

private final class PreviewSpeakerClient: SpeakerClient {
    /// Favorites returned by getSources() — configurable per-preview (T-5806).
    var stubFavorites: [Favorite] = []

    func play() async throws {}
    func pause() async throws {}
    func stop() async throws {}
    func setVolume(_ level: Int) async throws {}
    func mute(_ muted: Bool) async throws {}
    func getVolume() async throws -> Int { 50 }
    func getPlaybackState() async throws -> SpeakerPlaybackState { .stopped }
    func getSources() async throws -> [Favorite] { stubFavorites }
    func activateSource(_ id: String) async throws {}
    func getBattery() async throws -> Battery? { nil }
    func getName() async throws -> String { "Preview" }
    func getJid() async throws -> String? { nil }
    func getPeers() async throws -> [BeolinkPeer] { [] }
    func join(peer: SpeakerIdentifier) async throws {}
    func leave() async throws {}
}

private final class PreviewSpeakerEventSource: SpeakerEventSource {
    func events() -> AsyncStream<SpeakerEvent> {
        AsyncStream { $0.finish() }
    }
}

@MainActor
private func makePreviewSpeaker(
    playbackValue: PlaybackValue,
    volumeLevel: Int? = 55,
    favorites: [Favorite] = []
) -> Speaker {
    let client = PreviewSpeakerClient()
    client.stubFavorites = favorites
    let spk = Speaker(
        host: "192.168.1.10",
        client: client,
        eventSource: PreviewSpeakerEventSource(),
        platform: .mozart
    )
    spk.name = "Beosound Balance"
    spk.state = playbackValue
    spk.volume = volumeLevel
    if playbackValue != .unknown && playbackValue != .stopped {
        // Provide metadata for non-stopped states via JSON decode round-trip (avoids memberwise init)
        let json = """
        {"title":"Space Oddity","artist":"David Bowie","album":"Space Oddity"}
        """.data(using: .utf8)!
        spk.metadata = try? JSONDecoder().decode(PlaybackMetadata.self, from: json)
    }
    return spk
}

/// Five sample favorites used in E-58 preview blocks (T-5806).
private let previewFavorites5: [Favorite] = [
    Favorite(id: "fav-1", displayName: "Radio 24syv",   presetIndex: 1),
    Favorite(id: "fav-2", displayName: "Jazz FM",        presetIndex: 2),
    Favorite(id: "fav-3", displayName: "Morning Playlist", presetIndex: 3),
    Favorite(id: "fav-4", displayName: "Chill Vibes",   presetIndex: 4),
    Favorite(id: "fav-5", displayName: "Evening News",  presetIndex: 5),
]

/// Three sample favorites used in E-58 stopped-state preview (T-5806).
private let previewFavorites3: [Favorite] = [
    Favorite(id: "fav-1", displayName: "Radio 24syv",   presetIndex: 1),
    Favorite(id: "fav-2", displayName: "Jazz FM",        presetIndex: 2),
    Favorite(id: "fav-3", displayName: "Morning Playlist", presetIndex: 3),
]

#Preview("SpeakerCard — Playing") {
    @Previewable @State var errorMessage: String? = nil
    ZStack {
        Color(hex: "#0A0E1A").ignoresSafeArea()
        SpeakerCard(
            speaker: makePreviewSpeaker(playbackValue: .playing),
            isExpanded: false,
            roll: 0,
            pitch: 0,
            errorMessage: $errorMessage
        )
        .padding(20)
    }
    .preferredColorScheme(.dark)
}

#Preview("SpeakerCard — Paused") {
    @Previewable @State var errorMessage: String? = nil
    ZStack {
        Color(hex: "#0A0E1A").ignoresSafeArea()
        SpeakerCard(
            speaker: makePreviewSpeaker(playbackValue: .paused, volumeLevel: 40),
            isExpanded: false,
            roll: 0,
            pitch: 0,
            errorMessage: $errorMessage
        )
        .padding(20)
    }
    .preferredColorScheme(.dark)
}

#Preview("SpeakerCard — Buffering") {
    @Previewable @State var errorMessage: String? = nil
    ZStack {
        Color(hex: "#0A0E1A").ignoresSafeArea()
        SpeakerCard(
            speaker: makePreviewSpeaker(playbackValue: .buffering, volumeLevel: 60),
            isExpanded: false,
            roll: 0,
            pitch: 0,
            errorMessage: $errorMessage
        )
        .padding(20)
    }
    .preferredColorScheme(.dark)
}

#Preview("SpeakerCard — Stopped") {
    @Previewable @State var errorMessage: String? = nil
    ZStack {
        Color(hex: "#0A0E1A").ignoresSafeArea()
        SpeakerCard(
            speaker: makePreviewSpeaker(playbackValue: .unknown, volumeLevel: nil),
            isExpanded: false,
            roll: 0,
            pitch: 0,
            errorMessage: $errorMessage
        )
        .padding(20)
    }
    .preferredColorScheme(.dark)
}

// MARK: - E-58 Favorites row previews (T-5806)

#Preview("SpeakerCard — Playing + 5 Favorites") {
    @Previewable @State var errorMessage: String? = nil
    ZStack {
        Color(hex: "#0A0E1A").ignoresSafeArea()
        SpeakerCard(
            speaker: makePreviewSpeaker(playbackValue: .playing, favorites: previewFavorites5),
            isExpanded: false,
            roll: 0,
            pitch: 0,
            errorMessage: $errorMessage
        )
        .padding(20)
    }
    .preferredColorScheme(.dark)
}

#Preview("SpeakerCard — Stopped + 3 Favorites") {
    @Previewable @State var errorMessage: String? = nil
    ZStack {
        Color(hex: "#0A0E1A").ignoresSafeArea()
        SpeakerCard(
            speaker: makePreviewSpeaker(playbackValue: .unknown, volumeLevel: nil, favorites: previewFavorites3),
            isExpanded: false,
            roll: 0,
            pitch: 0,
            errorMessage: $errorMessage
        )
        .padding(20)
    }
    .preferredColorScheme(.dark)
}

#Preview("SpeakerCard — Playing + 0 Favorites") {
    @Previewable @State var errorMessage: String? = nil
    ZStack {
        Color(hex: "#0A0E1A").ignoresSafeArea()
        SpeakerCard(
            speaker: makePreviewSpeaker(playbackValue: .playing, favorites: []),
            isExpanded: false,
            roll: 0,
            pitch: 0,
            errorMessage: $errorMessage
        )
        .padding(20)
    }
    .preferredColorScheme(.dark)
}

#endif
