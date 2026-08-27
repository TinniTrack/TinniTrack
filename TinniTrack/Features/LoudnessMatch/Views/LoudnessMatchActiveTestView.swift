import SwiftUI

struct LoudnessMatchActiveTestView: View {
    @ObservedObject var viewModel: LoudnessMatchTaskFlowViewModel

    var body: some View {
        activeStateView
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("loudness_active_test_step")
    }

    @ViewBuilder
    private var activeStateView: some View {
        switch viewModel.protocolState {
        case .collectingLaterality:
            StudyTestTitleBlock(
                title: "Tinnitus Location Needed",
                bodyText: "Go back and choose where you hear your tinnitus before starting the loudness match."
            )

        case .awaitingThreshold:
            StudyTestTitleBlock(
                title: "Loading Hearing-Test Threshold",
                bodyText: "Study No. 1 uses the imported Apple hearing-test threshold for dB SL."
            )

        case .readyForTrial:
            readyForTrialView

        case .awaitingConfidence(let trial):
            confidenceView(for: trial)

        case .completed(let summary):
            completedView(trialCount: summary.trials.count)

        case .aborted:
            StudyTestTitleBlock(
                title: "Test Stopped",
                bodyText: "This loudness-match session was stopped."
            )

        case .restartRequired:
            StudyTestTitleBlock(
                title: "Restart Required",
                bodyText: "Audio route or volume changed during the test. Restart the task before calibrated playback continues."
            )
        }
    }

    private var readyForTrialView: some View {
        VStack(alignment: .leading, spacing: 16) {
            trialProgress(currentStep: currentTrialIndex)

            StudyTestTitleBlock(
                title: "Match the Loudness",
                bodyText: "Adjust the tone until it sounds as loud as your tinnitus, then accept the match."
            )

            adjustmentControls
        }
    }

    private func confidenceView(
        for trial: PendingTinnitusLoudnessMatchTrial
    ) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            trialProgress(currentStep: trial.trialIndex)

            StudyTestTitleBlock(
                title: "How Confident Are You in That Match?",
                bodyText: "Trial \(trial.trialIndex) match saved."
            )

            VStack(spacing: 12) {
                ForEach(TinnitusConfidenceRating.allCases, id: \.self) { confidence in
                    StudyTestControlButton(
                        title: confidenceTitle(confidence),
                        accessibilityIdentifier: "loudness_confidence_\(confidence.rawValue)_button"
                    ) {
                        viewModel.recordConfidence(confidence)
                    }
                }
            }
            .frame(maxWidth: 440)
            .frame(maxWidth: .infinity)
        }
    }

    private func completedView(trialCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            trialProgress(currentStep: 3)

            StudyTestTitleBlock(
                title: "Test Complete",
                bodyText: "Your loudness-match result is ready to submit."
            )

            summaryRow("Trials", "\(trialCount)")
        }
    }

    private func trialProgress(currentStep: Int) -> some View {
        StudyTestProgress(
            currentStep: currentStep,
            totalSteps: 3,
            title: "Loudness match",
            accessibilityLabel: "Loudness-match trial progress"
        )
    }

    private var adjustmentControls: some View {
        VStack(spacing: 8) {
            adjustmentButton(
                title: "Much Louder",
                detail: "Large adjustment",
                systemImage: "chevron.up.2",
                adjustment: .muchLouder,
                accessibilityLabel: "Much louder",
                accessibilityHint: "Raises the tone level by a larger step.",
                accessibilityIdentifier: "loudness_much_louder_button"
            )

            adjustmentButton(
                title: "Louder",
                detail: "Small adjustment",
                systemImage: "chevron.up",
                adjustment: .louder,
                accessibilityLabel: "Louder",
                accessibilityHint: "Raises the tone level by a small step.",
                accessibilityIdentifier: "loudness_louder_button"
            )

            StudyTestToneButton(
                isPlaying: viewModel.isPlaying,
                isEnabled: viewModel.isPlaying || viewModel.canPlayTone,
                accessibilityIdentifier: "loudness_play_button",
                action: toggleTonePlayback
            )
            .frame(maxWidth: .infinity)

            adjustmentButton(
                title: "Softer",
                detail: "Small adjustment",
                systemImage: "chevron.down",
                adjustment: .softer,
                accessibilityLabel: "Softer",
                accessibilityHint: "Lowers the tone level by a small step.",
                accessibilityIdentifier: "loudness_softer_button"
            )

            adjustmentButton(
                title: "Much Softer",
                detail: "Large adjustment",
                systemImage: "chevron.down.2",
                adjustment: .muchSofter,
                accessibilityLabel: "Much softer",
                accessibilityHint: "Lowers the tone level by a larger step.",
                accessibilityIdentifier: "loudness_much_softer_button"
            )
        }
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity)
    }

    private func adjustmentButton(
        title: String,
        detail: String,
        systemImage: String,
        adjustment: TinnitusLoudnessAdjustment,
        accessibilityLabel: String,
        accessibilityHint: String,
        accessibilityIdentifier: String
    ) -> some View {
        StudyTestControlButton(
            title: title,
            detail: detail,
            systemImage: systemImage,
            isEnabled: canAdjustLevel,
            accessibilityLabel: accessibilityLabel,
            accessibilityHint: accessibilityHint,
            accessibilityIdentifier: accessibilityIdentifier
        ) {
            viewModel.adjustLevel(adjustment)
        }
    }

    private func summaryRow(_ title: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .foregroundStyle(StudyTestColors.secondaryText)

            Spacer(minLength: 12)

            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(StudyTestColors.text)
                .monospacedDigit()
        }
        .font(.title3)
        .padding(16)
        .background(StudyTestColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(StudyTestColors.separator.opacity(0.30), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
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

    private func toggleTonePlayback() {
        if viewModel.isPlaying {
            viewModel.stopTone()
        } else {
            viewModel.playTone()
        }
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
