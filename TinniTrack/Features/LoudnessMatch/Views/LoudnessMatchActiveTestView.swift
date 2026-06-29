import SwiftUI

struct LoudnessMatchActiveTestView: View {
    @ObservedObject var viewModel: LoudnessMatchTaskFlowViewModel
    let scheduledTask: ScheduledTask
    let enrollment: StudyEnrollment
    let studyService: StudyServiceProtocol
    var completedBodyText = "Submit this loudness-match result to finish the scheduled task."
    let onSubmitted: () async -> Void

    var body: some View {
        LoudnessMatchModalContentLayout {
            activeStateView
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(maxHeight: .infinity, alignment: .top)
                .accessibilityIdentifier("loudness_active_test_step")
        } footer: {
            EmptyView()
        }
    }

    @ViewBuilder
    private var activeStateView: some View {
        switch viewModel.protocolState {
        case .collectingLaterality:
            LoudnessMatchModalTitleBlock(
                title: "Tinnitus Location Needed",
                bodyText: "Go back and choose where you hear your tinnitus before starting the loudness match."
            )

        case .awaitingThreshold:
            LoudnessMatchModalTitleBlock(
                title: "Loading hearing-test threshold",
                bodyText: "Study No. 1 uses the imported Apple hearing-test threshold for dB SL."
            )

        case .readyForTrial:
            readyForTrialView

        case .awaitingConfidence(let trial):
            VStack(alignment: .leading, spacing: 22) {
                LoudnessMatchModalTitleBlock(
                    title: "How confident are you in that match?",
                    bodyText: "Trial \(trial.trialIndex) match saved."
                )

                VStack(spacing: 12) {
                    ForEach(TinnitusConfidenceRating.allCases, id: \.self) { confidence in
                        modalChoiceButton(confidenceTitle(confidence)) {
                            viewModel.recordConfidence(confidence)
                        }
                    }
                }
            }

        case .completed(let summary):
            VStack(alignment: .leading, spacing: 22) {
                LoudnessMatchModalTitleBlock(
                    title: "Test Complete",
                    bodyText: completedBodyText
                )

                VStack(alignment: .leading, spacing: 12) {
                    summaryRow("Trials", "\(summary.trials.count)")
                }

                LoudnessMatchModalPrimaryButton(
                    title: viewModel.isSubmitting ? "Submitting" : "Submit",
                    isEnabled: viewModel.canSubmit,
                    isLoading: viewModel.isSubmitting
                ) {
                    Task {
                        await viewModel.submitCompletedRun(
                            scheduledTask: scheduledTask,
                            enrollment: enrollment,
                            studyService: studyService
                        )
                        if viewModel.hasSubmitted {
                            await onSubmitted()
                        }
                    }
                }
            }

        case .aborted:
            LoudnessMatchModalTitleBlock(
                title: "Test Stopped",
                bodyText: "This loudness-match session was stopped."
            )

        case .restartRequired:
            LoudnessMatchModalTitleBlock(
                title: "Restart Required",
                bodyText: "Audio route or volume changed during the test. Restart the task before calibrated playback continues."
            )
        }
    }

    private var readyForTrialView: some View {
        VStack(spacing: 0) {
            trialProgressHeader
                .padding(.bottom, 24)

            VStack(spacing: 12) {
                Text("Match the loudness")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(LoudnessMatchModalColors.text)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)

                Text("Adjust the tone until it sounds as loud as your tinnitus, then accept the match.")
                    .font(.system(size: 19, weight: .regular))
                    .lineSpacing(4)
                    .foregroundStyle(LoudnessMatchModalColors.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .padding(.bottom, 24)

            adjustmentStack

            Spacer(minLength: 18)

            LoudnessMatchModalPrimaryButton(title: "Same Loudness", isEnabled: viewModel.preflightReady) {
                viewModel.acceptCurrentLevel()
            }
            .padding(.bottom, 32)
            .accessibilityLabel("Same loudness")
            .accessibilityHint("Accepts the current tone level and continues to the next step.")
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var trialProgressHeader: some View {
        VStack(spacing: 12) {
            Text(viewModel.currentTrialLabel)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(LoudnessMatchModalColors.text)

            HStack(spacing: 0) {
                ForEach(1...3, id: \.self) { index in
                    LoudnessMatchTrialProgressCircle(
                        index: index,
                        currentIndex: currentTrialIndex
                    )

                    if index < 3 {
                        Rectangle()
                            .fill(index <= currentTrialIndex ? LoudnessMatchModalColors.primary : LoudnessMatchModalColors.controlStroke)
                            .frame(width: 56, height: 2)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Trial \(currentTrialIndex) of 3")
        }
        .frame(maxWidth: .infinity)
    }

    private var adjustmentStack: some View {
        VStack(spacing: 10) {
            LoudnessMatchAdjustmentButton(configuration: .muchLouder, isEnabled: canAdjustLevel) {
                viewModel.adjustLevel(.muchLouder)
            }

            LoudnessMatchAdjustmentButton(configuration: .louder, isEnabled: canAdjustLevel) {
                viewModel.adjustLevel(.louder)
            }

            LoudnessMatchPlayButton(
                isPlaying: viewModel.isPlaying,
                isEnabled: viewModel.isPlaying || viewModel.canPlayTone
            ) {
                if viewModel.isPlaying {
                    viewModel.stopTone()
                } else {
                    viewModel.playTone()
                }
            }
            .padding(.vertical, 2)

            LoudnessMatchAdjustmentButton(configuration: .softer, isEnabled: canAdjustLevel) {
                viewModel.adjustLevel(.softer)
            }

            LoudnessMatchAdjustmentButton(configuration: .muchSofter, isEnabled: canAdjustLevel) {
                viewModel.adjustLevel(.muchSofter)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var canAdjustLevel: Bool {
        viewModel.preflightReady && viewModel.currentCandidateLevelDBHL != nil
    }

    private var currentTrialIndex: Int {
        switch viewModel.protocolState {
        case .readyForTrial(let index, _):
            return min(max(index, 1), 3)
        case .awaitingConfidence(let trial):
            return min(max(trial.trialIndex, 1), 3)
        default:
            return 1
        }
    }

    private func summaryRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(LoudnessMatchModalColors.secondaryText)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(LoudnessMatchModalColors.text)
        }
        .font(.title3)
    }

    private func modalChoiceButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
                .foregroundStyle(LoudnessMatchModalColors.text)
                .background(LoudnessMatchModalColors.controlBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(LoudnessMatchModalColors.controlStroke, lineWidth: 1)
                }
        }
        .buttonStyle(AppRoundedButtonStyle(cornerRadius: 8))
    }

    private func confidenceTitle(_ confidence: TinnitusConfidenceRating) -> String {
        switch confidence {
        case .low:
            return "Low Confidence"
        case .medium:
            return "Medium Confidence"
        case .high:
            return "High Confidence"
        }
    }
}

private struct LoudnessMatchTrialProgressCircle: View {
    let index: Int
    let currentIndex: Int

    private var isCurrent: Bool {
        index == currentIndex
    }

    private var isComplete: Bool {
        index < currentIndex
    }

    var body: some View {
        Text("\(index)")
            .font(.headline)
            .fontWeight(.bold)
            .foregroundStyle(isCurrent ? LoudnessMatchModalColors.primaryText : textColor)
            .frame(width: 48, height: 48)
            .background(isCurrent ? LoudnessMatchModalColors.primary : Color(uiColor: .systemBackground), in: Circle())
            .overlay {
                Circle()
                    .stroke(borderColor, lineWidth: isCurrent ? 0 : 1.4)
            }
    }

    private var textColor: Color {
        isComplete ? LoudnessMatchModalColors.primary : LoudnessMatchModalColors.text
    }

    private var borderColor: Color {
        isComplete ? LoudnessMatchModalColors.primary.opacity(0.65) : LoudnessMatchModalColors.controlStroke
    }
}

private struct LoudnessMatchAdjustmentButton: View {
    let configuration: Configuration
    let isEnabled: Bool
    let action: () -> Void

    private let maxButtonWidth: CGFloat = 340
    private let iconColumnWidth: CGFloat = 82

    var body: some View {
        Button(action: action) {
            GeometryReader { proxy in
                let containerWidth = min(maxButtonWidth, proxy.size.width)
                let buttonWidth = min(configuration.width, containerWidth)
                let iconWidth = min(iconColumnWidth, buttonWidth * 0.28)

                ZStack {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(configuration.backgroundColor)
                        .frame(width: buttonWidth, height: configuration.height)
                        .overlay {
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .stroke(configuration.borderColor, lineWidth: 1.2)
                                .frame(width: buttonWidth, height: configuration.height)
                        }

                    Text(configuration.title)
                        .font(.system(size: configuration.fontSize, weight: .bold))
                        .foregroundStyle(configuration.foregroundColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .frame(width: buttonWidth, height: configuration.height)
                        .multilineTextAlignment(.center)

                    HStack(spacing: 0) {
                        adjustmentIcon
                            .frame(width: iconWidth, height: configuration.height)

                        Rectangle()
                            .fill(configuration.borderColor)
                            .frame(width: 1, height: configuration.height - 22)

                        Spacer()
                    }
                    .frame(width: containerWidth, height: configuration.height)
                }
                .frame(width: containerWidth, height: configuration.height)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: maxButtonWidth)
            .frame(height: configuration.height)
            .opacity(isEnabled ? 1 : 0.46)
            .contentShape(Rectangle())
        }
        .buttonStyle(AppRoundedButtonStyle(cornerRadius: 15))
        .disabled(!isEnabled)
        .accessibilityLabel(configuration.accessibilityLabel)
        .accessibilityHint(configuration.accessibilityHint)
        .accessibilityIdentifier(configuration.accessibilityIdentifier)
    }

    @ViewBuilder
    private var adjustmentIcon: some View {
        VStack(spacing: configuration.iconSpacing) {
            ForEach(0..<configuration.chevronCount, id: \.self) { _ in
                Image(systemName: configuration.chevronSystemName)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(configuration.foregroundColor)
            }
        }
        .accessibilityHidden(true)
    }

    struct Configuration {
        let title: String
        let width: CGFloat
        let height: CGFloat
        let fontSize: CGFloat
        let foregroundColor: Color
        let backgroundColor: Color
        let borderColor: Color
        let chevronSystemName: String
        let chevronCount: Int
        let iconSpacing: CGFloat
        let accessibilityLabel: String
        let accessibilityHint: String
        let accessibilityIdentifier: String

        static let muchLouder = Configuration(
            title: "Much Louder",
            width: 340,
            height: 58,
            fontSize: 21,
            foregroundColor: LoudnessMatchActiveTestColors.strongRed,
            backgroundColor: LoudnessMatchActiveTestColors.strongRedFill,
            borderColor: LoudnessMatchActiveTestColors.strongRedStroke,
            chevronSystemName: "chevron.up",
            chevronCount: 2,
            iconSpacing: -9,
            accessibilityLabel: "Much louder",
            accessibilityHint: "Raises the tone level by a larger step.",
            accessibilityIdentifier: "loudness_much_louder_button"
        )

        static let louder = Configuration(
            title: "Louder",
            width: 306,
            height: 52,
            fontSize: 20,
            foregroundColor: LoudnessMatchActiveTestColors.softRed,
            backgroundColor: LoudnessMatchActiveTestColors.softRedFill,
            borderColor: LoudnessMatchActiveTestColors.softRedStroke,
            chevronSystemName: "chevron.up",
            chevronCount: 1,
            iconSpacing: 0,
            accessibilityLabel: "Louder",
            accessibilityHint: "Raises the tone level by a small step.",
            accessibilityIdentifier: "loudness_louder_button"
        )

        static let softer = Configuration(
            title: "Softer",
            width: 306,
            height: 52,
            fontSize: 20,
            foregroundColor: LoudnessMatchActiveTestColors.softGreen,
            backgroundColor: LoudnessMatchActiveTestColors.softGreenFill,
            borderColor: LoudnessMatchActiveTestColors.softGreenStroke,
            chevronSystemName: "chevron.down",
            chevronCount: 1,
            iconSpacing: 0,
            accessibilityLabel: "Softer",
            accessibilityHint: "Lowers the tone level by a small step.",
            accessibilityIdentifier: "loudness_softer_button"
        )

        static let muchSofter = Configuration(
            title: "Much Softer",
            width: 340,
            height: 58,
            fontSize: 21,
            foregroundColor: LoudnessMatchActiveTestColors.strongGreen,
            backgroundColor: LoudnessMatchActiveTestColors.strongGreenFill,
            borderColor: LoudnessMatchActiveTestColors.strongGreenStroke,
            chevronSystemName: "chevron.down",
            chevronCount: 2,
            iconSpacing: -9,
            accessibilityLabel: "Much softer",
            accessibilityHint: "Lowers the tone level by a larger step.",
            accessibilityIdentifier: "loudness_much_softer_button"
        )
    }
}

private struct LoudnessMatchPlayButton: View {
    let isPlaying: Bool
    let isEnabled: Bool
    let action: () -> Void

    private let buttonDiameter: CGFloat = 92

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(playFill)
                .frame(width: buttonDiameter, height: buttonDiameter)
                .overlay {
                    Circle()
                        .stroke(LoudnessMatchModalColors.primary.opacity(isEnabled ? 0.58 : 0.22), lineWidth: 2)
                }
                .shadow(color: LoudnessMatchModalColors.primary.opacity(isPlaying ? 0.10 : 0.04), radius: 16, x: 0, y: 8)
                .overlay {
                    Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                        .font(.system(size: isPlaying ? 32 : 38, weight: .bold))
                        .foregroundStyle(isEnabled ? LoudnessMatchModalColors.primary : LoudnessMatchModalColors.disabledText)
                        .offset(x: isPlaying ? 0 : 3)
                        .accessibilityHidden(true)
                }
            .frame(width: buttonDiameter, height: buttonDiameter)
            .contentShape(Circle())
        }
        .buttonStyle(AppCircleButtonStyle())
        .disabled(!isEnabled)
        .accessibilityLabel(isPlaying ? "Stop tone playback" : "Play tone")
        .accessibilityHint(isPlaying ? "Stops tone playback." : "Starts tone playback.")
        .accessibilityIdentifier("loudness_play_button")
    }

    private var playFill: Color {
        isPlaying
            ? LoudnessMatchModalColors.primary.opacity(0.09)
            : Color(uiColor: .systemBackground)
    }
}

private enum LoudnessMatchActiveTestColors {
    static let strongRed = Color(red: 0.78, green: 0.04, blue: 0.05)
    static let softRed = Color(red: 0.74, green: 0.05, blue: 0.06)
    static let strongRedFill = Color(red: 1.0, green: 0.94, blue: 0.94)
    static let softRedFill = Color(red: 1.0, green: 0.96, blue: 0.96)
    static let strongRedStroke = Color(red: 1.0, green: 0.54, blue: 0.56)
    static let softRedStroke = Color(red: 1.0, green: 0.70, blue: 0.71)

    static let strongGreen = Color(red: 0.01, green: 0.42, blue: 0.09)
    static let softGreen = Color(red: 0.03, green: 0.43, blue: 0.11)
    static let strongGreenFill = Color(red: 0.94, green: 0.98, blue: 0.93)
    static let softGreenFill = Color(red: 0.96, green: 0.99, blue: 0.95)
    static let strongGreenStroke = Color(red: 0.57, green: 0.78, blue: 0.55)
    static let softGreenStroke = Color(red: 0.68, green: 0.84, blue: 0.66)
}
