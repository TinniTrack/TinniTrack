import SwiftUI

struct LoudnessMatchNoiseGateView: View {
    let update: TinnitusEnvironmentSPLGateUpdate?
    let showSuggestions: () -> Void

    private var status: TinnitusEnvironmentSPLGateStatus {
        update?.status ?? .measuring
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 42) {
            VStack(spacing: 34) {
                NoiseGateMeter(status: status, progress: progress)

                HStack(spacing: 10) {
                    statusIcon
                    Text(statusText)
                        .font(.title2)
                        .fontWeight(.bold)
                        .textCase(.uppercase)
                        .foregroundStyle(statusColor)
                        .accessibilityIdentifier("loudness_noise_status_label")
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            }
            .padding(.top, 122)

            VStack(alignment: .leading, spacing: 14) {
                LoudnessMatchModalTitleBlock(
                    title: "Find a quiet place where you can focus and take the test.",
                    bodyText: "Too much background noise can cause inaccurate results in your test."
                )

                Button(action: showSuggestions) {
                    Label("Show Suggestions To Reduce Noise", systemImage: "info.circle.fill")
                        .font(.title3)
                        .foregroundStyle(LoudnessMatchModalColors.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                .buttonStyle(.plain)
                .padding(.top, 14)
            }
        }
        .accessibilityIdentifier("loudness_noise_gate_step")
    }

    private var statusIcon: Image {
        switch status {
        case .measuring:
            return Image(systemName: "ellipsis")
        case .tooLoud:
            return Image(systemName: "exclamationmark.circle.fill")
        case .passed:
            return Image(systemName: "checkmark.circle.fill")
        }
    }

    private var statusText: String {
        switch status {
        case .measuring:
            return "In Progress..."
        case .tooLoud:
            return "Too much noise"
        case .passed:
            return "Noise Ok"
        }
    }

    private var statusColor: Color {
        switch status {
        case .measuring:
            return LoudnessMatchModalColors.secondaryText
        case .tooLoud:
            return LoudnessMatchModalColors.warning
        case .passed:
            return LoudnessMatchModalColors.success
        }
    }

    private var progress: Double {
        guard let update else {
            return 0
        }

        return min(
            1,
            Double(update.contiguousPassingSamples) / Double(TinnitusEnvironmentSPLGateConfiguration.studyA.requiredContiguousSamples)
        )
    }
}

private struct NoiseGateMeter: View {
    let status: TinnitusEnvironmentSPLGateStatus
    let progress: Double

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<16, id: \.self) { index in
                Capsule()
                    .fill(color(for: index))
                    .frame(width: 7, height: height(for: index))
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.18), value: status)
        .animation(.easeInOut(duration: 0.18), value: progress)
    }

    private func height(for index: Int) -> CGFloat {
        switch status {
        case .tooLoud:
            return index > 10 ? 72 : 32
        case .measuring, .passed:
            return 7
        }
    }

    private func color(for index: Int) -> Color {
        switch status {
        case .measuring:
            return Color.white.opacity(0.36)
        case .tooLoud:
            return LoudnessMatchModalColors.warning
        case .passed:
            let filledCount = max(1, Int((progress * 16).rounded(.up)))
            return index < filledCount ? LoudnessMatchModalColors.success : Color.white.opacity(0.20)
        }
    }
}

struct LoudnessMatchNoiseSuggestionsView: View {
    let dismiss: () -> Void

    var body: some View {
        ZStack {
            LoudnessMatchModalColors.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    LoudnessMatchModalIconButton(
                        systemName: "checkmark",
                        accessibilityLabel: "Done",
                        accessibilityIdentifier: "loudness_noise_suggestions_done_button",
                        action: dismiss
                    )
                    .background(LoudnessMatchModalColors.primary, in: Circle())
                }
                .padding(.horizontal, 34)
                .padding(.top, 22)

                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        LoudnessMatchModalTitleBlock(
                            title: "Suggestions to Reduce Background Noise",
                            bodyText: "Background noise can make it too hard to hear the tones in the test."
                        )

                        suggestionRow(systemName: "sofa.fill", text: "Try moving to a room or location that's typically more quiet.")
                        suggestionRow(systemName: "fan.slash.fill", text: "Close windows and turn off fans or air conditioning.")
                        suggestionRow(systemName: "moon.stars.fill", text: "Try again later when your space might be more quiet or calm.")
                    }
                    .padding(.horizontal, 34)
                    .padding(.top, 82)
                    .padding(.bottom, 34)
                }
            }
        }
    }

    private func suggestionRow(systemName: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 22) {
            Image(systemName: systemName)
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(LoudnessMatchModalColors.primary)
                .frame(width: 48)

            Text(text)
                .font(.title3)
                .foregroundStyle(.white)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
