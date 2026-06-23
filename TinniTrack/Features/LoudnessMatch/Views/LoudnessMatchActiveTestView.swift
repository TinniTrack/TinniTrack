import SwiftUI

struct LoudnessMatchActiveTestView: View {
    @ObservedObject var viewModel: LoudnessMatchTaskFlowViewModel
    let scheduledTask: ScheduledTask
    let enrollment: StudyEnrollment
    let studyService: StudyServiceProtocol
    let onSubmitted: () -> Void

    var body: some View {
        LoudnessMatchModalContentLayout {
            VStack(alignment: .leading, spacing: 28) {
                activeStateView
            }
            .accessibilityIdentifier("loudness_active_test_step")
        } footer: {
            EmptyView()
        }
    }

    @ViewBuilder
    private var activeStateView: some View {
        switch viewModel.protocolState {
        case .collectingLaterality:
            VStack(alignment: .leading, spacing: 26) {
                LoudnessMatchModalTitleBlock(
                    title: "Where do you hear your tinnitus?",
                    bodyText: "Choose the option that best matches where the sound is most noticeable right now."
                )

                VStack(spacing: 12) {
                    ForEach(TinnitusLaterality.allCases, id: \.self) { laterality in
                        modalChoiceButton(lateralityTitle(laterality)) {
                            viewModel.selectLaterality(laterality)
                        }
                    }
                }
            }

        case .awaitingThreshold:
            VStack(alignment: .leading, spacing: 28) {
                LoudnessMatchModalTitleBlock(
                    title: "Find the softest tone you can hear.",
                    bodyText: "Tap Play Tone, then tell us whether you heard the sound. The level will adjust automatically."
                )

                levelReadout(
                    title: "Current level",
                    value: String(format: "%.0f dB HL", viewModel.thresholdStaircase.currentLevelDBHL)
                )

                HStack(spacing: 12) {
                    modalActionButton(
                        viewModel.isPlaying ? "Playing" : "Play Tone",
                        systemName: "play.fill",
                        isPrimary: true,
                        isEnabled: viewModel.canPlayThresholdTone && !viewModel.isPlaying
                    ) {
                        viewModel.playThresholdTone()
                    }

                    modalActionButton(
                        "Stop",
                        systemName: "stop.fill",
                        isPrimary: false,
                        isEnabled: viewModel.isPlaying
                    ) {
                        viewModel.stopTone()
                    }
                }

                HStack(spacing: 12) {
                    modalActionButton("Heard", systemName: "ear.fill", isPrimary: false, isEnabled: viewModel.canRecordThresholdResponse) {
                        viewModel.recordThresholdResponse(.heard)
                    }
                    modalActionButton("Not Heard", systemName: "ear.badge.xmark", isPrimary: false, isEnabled: viewModel.canRecordThresholdResponse) {
                        viewModel.recordThresholdResponse(.notHeard)
                    }
                }

                Text("Responses: \(viewModel.thresholdStaircase.presentations.count)")
                    .font(.callout)
                    .foregroundStyle(LoudnessMatchModalColors.secondaryText)
            }

        case .readyForTrial:
            VStack(alignment: .leading, spacing: 28) {
                LoudnessMatchModalTitleBlock(
                    title: viewModel.currentTrialLabel,
                    bodyText: "Adjust the tone until it sounds as loud as your tinnitus, then accept the match."
                )

                if let level = viewModel.currentCandidateLevelDBHL {
                    levelReadout(title: "Tone level", value: String(format: "%.0f dB HL", level))
                }

                HStack(spacing: 12) {
                    modalActionButton(
                        viewModel.isPlaying ? "Playing" : "Play Tone",
                        systemName: "play.fill",
                        isPrimary: true,
                        isEnabled: viewModel.canPlayTone && !viewModel.isPlaying
                    ) {
                        viewModel.playTone()
                    }

                    modalActionButton("Stop", systemName: "stop.fill", isPrimary: false, isEnabled: viewModel.isPlaying) {
                        viewModel.stopTone()
                    }
                }

                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        modalActionButton("Much Softer", systemName: "minus.circle", isPrimary: false) {
                            viewModel.adjustLevel(.muchSofter)
                        }
                        modalActionButton("Softer", systemName: "minus", isPrimary: false) {
                            viewModel.adjustLevel(.softer)
                        }
                    }

                    HStack(spacing: 12) {
                        modalActionButton("Louder", systemName: "plus", isPrimary: false) {
                            viewModel.adjustLevel(.louder)
                        }
                        modalActionButton("Much Louder", systemName: "plus.circle", isPrimary: false) {
                            viewModel.adjustLevel(.muchLouder)
                        }
                    }
                }

                LoudnessMatchModalPrimaryButton(title: "Same Loudness", isEnabled: viewModel.preflightReady) {
                    viewModel.acceptCurrentLevel()
                }
            }

        case .awaitingConfidence(let trial):
            VStack(alignment: .leading, spacing: 28) {
                LoudnessMatchModalTitleBlock(
                    title: "How confident are you in that match?",
                    bodyText: "Trial \(trial.trialIndex) is set to \(String(format: "%.0f dB HL", trial.acceptedLevelDBHL))."
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
            VStack(alignment: .leading, spacing: 26) {
                LoudnessMatchModalTitleBlock(
                    title: "Test Complete",
                    bodyText: "Submit this loudness-match result to finish the scheduled task."
                )

                VStack(alignment: .leading, spacing: 12) {
                    summaryRow("Trials", "\(summary.trials.count)")
                    summaryRow("Matched level", String(format: "%.0f dB HL", summary.medianMatchedDBHL))
                    summaryRow("Spread", String(format: "%.1f dB", summary.withinSessionSpreadDB))
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
                            onSubmitted()
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

    private func levelReadout(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.callout)
                .foregroundStyle(LoudnessMatchModalColors.secondaryText)
            Text(value)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
        }
        .padding(.vertical, 6)
    }

    private func summaryRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(LoudnessMatchModalColors.secondaryText)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
        }
        .font(.title3)
    }

    private func modalChoiceButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(LoudnessMatchModalColors.controlBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(LoudnessMatchModalColors.controlStroke, lineWidth: 1)
        }
    }

    private func modalActionButton(
        _ title: String,
        systemName: String,
        isPrimary: Bool,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemName)
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.74)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .foregroundStyle(isEnabled ? .white : LoudnessMatchModalColors.disabledText)
        .background(isPrimary && isEnabled ? LoudnessMatchModalColors.primary : LoudnessMatchModalColors.controlBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(LoudnessMatchModalColors.controlStroke, lineWidth: 1)
        }
    }

    private func lateralityTitle(_ laterality: TinnitusLaterality) -> String {
        switch laterality {
        case .left:
            return "Left"
        case .right:
            return "Right"
        case .bilateral:
            return "Both"
        case .central:
            return "Center"
        case .unclear:
            return "Not Sure"
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
