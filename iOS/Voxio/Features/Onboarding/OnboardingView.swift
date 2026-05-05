import SwiftUI
import AVFoundation
import Speech

// E-38 T-3801 — First-boot onboarding screen.
// Presented as .fullScreenCover on first launch (isReshow == false) or
// as .sheet from Settings (isReshow == true, US-66).
//
// Permission requests (T-3803) have moved here from VoiceToText.start().
// T-2209 — .preferredColorScheme(.dark) is mandatory on every .fullScreenCover content root.

struct OnboardingView: View {
    /// Called when the user taps the primary CTA.
    /// On first launch: triggers permission requests, then dismisses.
    /// On re-show (isReshow == true): dismisses immediately; no permission requests.
    var onDismiss: () -> Void

    /// true  → presented as .sheet from Settings; no permission requests; does not write hasCompletedOnboarding.
    /// false → presented as .fullScreenCover; runs the full dismiss flow.
    var isReshow: Bool = false

    @ObservedObject private var langService = LanguageService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Entrance animation state
    @State private var hasEntered = false

    private var lang: Language { langService.activeLanguage }

    // MARK: — Localised strings

    private var headline: String {
        lang == .danish ? "Velkommen til Voxio" : "Welcome to Voxio"
    }
    private var subheadline: String {
        lang == .danish ? "Sig bare højttalerens navn." : "Just say the speaker's name."
    }
    private var bodyText: String {
        lang == .danish
            ? "Voxio lytter gennem mikrofonen og styrer Bang & Olufsen-højttalere på dit netværk."
            : "Voxio listens through your microphone and controls Bang & Olufsen speakers on your network."
    }
    private var examplesLeadIn: String {
        lang == .danish ? "Prøv at sige:" : "Try saying:"
    }
    private var examplePhrases: [String] {
        lang == .danish
            ? ["\u{201C}Beolab, afspil\u{201D}", "\u{201C}Beolab, skru op\u{201D}", "\u{201C}Beolab, stop\u{201D}"]
            : ["\u{201C}Beolab, play\u{201D}",   "\u{201C}Beolab, volume up\u{201D}", "\u{201C}Beolab, stop\u{201D}"]
    }
    private var ctaLabel: String {
        if isReshow { return lang == .danish ? "Luk" : "Close" }
        return lang == .danish ? "Kom i gang" : "Get started"
    }
    private var examplesAccessibilityLabel: String {
        let joined = examplePhrases.joined(separator: ". ")
        return (lang == .danish ? "Eksempler: " : "Examples: ") + joined
    }
    private var ctaAccessibilityHint: String {
        isReshow ? "" : (lang == .danish
            ? "Lukker introduktionen og åbner hovedskærmen."
            : "Closes onboarding and opens the main screen.")
    }

    // MARK: — Body

    var body: some View {
        ZStack {
            // T-1.3 — full-screen BeoColor.bg fill
            BeoColor.bg.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer(minLength: Spacing.s24)

                    orbGraphic

                    Spacer(minLength: Spacing.s8)

                    headlineSection

                    Spacer(minLength: Spacing.s16)

                    bodySection

                    Spacer(minLength: Spacing.s20)

                    examplesSection

                    Spacer(minLength: Spacing.s20)
                }
                .padding(.horizontal, Spacing.s16)
            }

            // CTA pinned to bottom safe area
            VStack {
                Spacer()
                ctaSection
                    .padding(.horizontal, Spacing.s16)
                    .padding(.bottom, Spacing.s24)
            }
        }
        // T-2209 — mandatory on every .fullScreenCover content root
        .preferredColorScheme(.dark)
        .onAppear { @MainActor in
            if reduceMotion {
                hasEntered = true
            } else {
                withAnimation(BeoAnimation.spring.delay(0.05)) {
                    hasEntered = true
                }
            }
        }
        .opacity(hasEntered ? 1 : 0)
        .offset(y: (hasEntered || reduceMotion) ? 0 : 12)
        .animation(reduceMotion ? BeoAnimation.toast : BeoAnimation.spring, value: hasEntered)
    }

    // MARK: — Subviews

    /// Design spec §1.4 — static radial-gradient Circle as the orb fallback.
    /// The home-screen orb depends on live Speaker state; onboarding has no speaker yet.
    private var orbGraphic: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        BeoColor.accent.opacity(0.8),
                        BeoColor.accent.opacity(0.2)
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: 48
                )
            )
            .overlay(
                Circle()
                    .strokeBorder(BeoColor.cardBorder, lineWidth: 0.5)
            )
            .frame(width: 96, height: 96)
            .accessibilityHidden(true)   // decorative per spec §1.4 / §4.2
    }

    private var headlineSection: some View {
        VStack(spacing: Spacing.s12) {
            Text(headline)
                .font(BeoType.speakerName)
                .foregroundStyle(BeoColor.text)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Text(subheadline)
                .font(BeoType.nowPlaying)
                .foregroundStyle(BeoColor.text)
                .multilineTextAlignment(.center)
        }
    }

    private var bodySection: some View {
        Text(bodyText)
            .font(BeoType.body)
            .foregroundStyle(BeoColor.muted)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 320)
    }

    private var examplesSection: some View {
        VStack(spacing: Spacing.s12) {
            Text(examplesLeadIn)
                .font(BeoType.caption)
                .foregroundStyle(BeoColor.muted)
                .multilineTextAlignment(.center)

            // Example card — spec §1.8
            VStack(spacing: 0) {
                ForEach(Array(examplePhrases.enumerated()), id: \.offset) { index, phrase in
                    VStack(spacing: 0) {
                        if index > 0 {
                            Divider()
                                .background(BeoColor.separator)
                        }
                        HStack {
                            Text(phrase)
                                .font(BeoType.confirmation)
                                .foregroundStyle(BeoColor.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, Spacing.s16)
                                .padding(.vertical, Spacing.s12)
                        }
                        .frame(minHeight: 48)
                    }
                }
            }
            .background(BeoColor.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card)
                    .strokeBorder(BeoColor.cardBorder, lineWidth: 0.5)
            )
            // Spec §1.8 / §4.2 — combine for VoiceOver
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(examplesAccessibilityLabel)
        }
    }

    private var ctaSection: some View {
        // Spec §1.9 — gold fill (accent) with dark label; Radius.pill; 44 pt tall min; 220 pt wide min
        Button(action: handleCTA) {
            Text(ctaLabel)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(BeoColor.text)
                .padding(.vertical, 14)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
        }
        .background(
            Capsule()
                .fill(BeoColor.accent)
        )
        .clipShape(Capsule())
        .frame(minWidth: 220)
        .buttonStyle(OnboardingCTAButtonStyle(reduceMotion: reduceMotion))
        .accessibilityLabel(ctaLabel)
        .accessibilityHint(ctaAccessibilityHint)
    }

    // MARK: — CTA action

    private func handleCTA() {
        if isReshow {
            // Re-show path: just dismiss, no permission requests, no flag write
            onDismiss()
        } else {
            // First-launch path: T-3803 — request permissions sequentially, then dismiss.
            // Permission requests moved here from VoiceToText.start() per ADR E-38.
            Task { @MainActor in
                // Speech recognition first per ADR §Conflicts Flagged point 1
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    SFSpeechRecognizer.requestAuthorization { _ in
                        continuation.resume()
                    }
                }
                // Microphone second
                _ = await AVAudioApplication.requestRecordPermission()
                // Safe to set flag and dismiss
                onDismiss()
            }
        }
    }
}

// MARK: — CTA ButtonStyle (spec §1.9 / §1.11 Reduce Motion)

private struct OnboardingCTAButtonStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(reduceMotion
                ? (configuration.isPressed ? 0.7 : 1.0)    // Reduce Motion: opacity dip
                : 1.0
            )
            .scaleEffect(reduceMotion
                ? 1.0
                : (configuration.isPressed ? DarkGlassButtonTokens.pressedScale : 1.0)
            )
            .animation(
                .spring(
                    response: DarkGlassButtonTokens.pressSpringResponse,
                    dampingFraction: DarkGlassButtonTokens.pressSpringDamping
                ),
                value: configuration.isPressed
            )
    }
}

// MARK: — Previews

#Preview("OnboardingView — first launch") {
    OnboardingView(onDismiss: {})
}

#Preview("OnboardingView — re-show (sheet)") {
    OnboardingView(onDismiss: {}, isReshow: true)
}
