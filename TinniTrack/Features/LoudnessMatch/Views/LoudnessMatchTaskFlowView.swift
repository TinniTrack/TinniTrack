import SwiftUI

struct LoudnessMatchTaskFlowView: View {
    let scheduledTask: ScheduledTask
    let enrollment: StudyEnrollment
    let studyService: StudyServiceProtocol
    let onSubmitted: () -> Void

    @StateObject private var viewModel: LoudnessMatchTaskFlowViewModel

    init(
        scheduledTask: ScheduledTask,
        enrollment: StudyEnrollment,
        studyService: StudyServiceProtocol,
        onSubmitted: @escaping () -> Void
    ) {
        self.scheduledTask = scheduledTask
        self.enrollment = enrollment
        self.studyService = studyService
        self.onSubmitted = onSubmitted
        _viewModel = StateObject(wrappedValue: LoudnessMatchTaskFlowViewModel())
    }

    var body: some View {
        List {
            safetyGateSection
            protocolSection
            eventSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Loudness Match")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "Unable to Continue",
            isPresented: Binding(
                get: { viewModel.message != nil },
                set: { shouldShow in
                    if !shouldShow {
                        viewModel.clearMessage()
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                viewModel.clearMessage()
            }
        } message: {
            Text(messageText)
        }
    }

    private var safetyGateSection: some View {
        Section {
            Label("Calibrated playback remains locked for participants.", systemImage: "lock.shield")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                viewModel.refreshGuardrails()
            } label: {
                Label("Check Audio Guardrails", systemImage: "checkmark.shield")
            }
        } footer: {
            Text("This Phase 4 screen exercises the study protocol but does not enable calibrated tone playback until the required preflight can prove route, volume, and restart safety.")
        }
    }

    @ViewBuilder
    private var protocolSection: some View {
        switch viewModel.protocolState {
        case .collectingLaterality:
            Section("Tinnitus Location") {
                ForEach(TinnitusLaterality.allCases, id: \.self) { laterality in
                    Button(lateralityTitle(laterality)) {
                        viewModel.selectLaterality(laterality)
                    }
                }
            }

        case .awaitingThreshold:
            Section("Threshold") {
                TextField("Threshold dB HL", text: $viewModel.thresholdLevelText)
                    .keyboardType(.decimalPad)

                Button {
                    viewModel.recordThresholdFromInput()
                } label: {
                    Label("Use Threshold", systemImage: "checkmark.circle")
                }

                Button(role: .destructive) {
                    viewModel.markThresholdUnavailable()
                } label: {
                    Label("Continue Without Threshold", systemImage: "exclamationmark.triangle")
                }
            }

        case .readyForTrial:
            Section(viewModel.currentTrialLabel) {
                Button {
                    viewModel.playTone()
                } label: {
                    Label("Play Tone", systemImage: "play.fill")
                }
                .disabled(!viewModel.canPlayTone)

                Button(role: .destructive) {
                    viewModel.stopTone()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }

                HStack {
                    Button("Much Softer") {
                        viewModel.adjustLevel(.muchSofter)
                    }
                    Button("Softer") {
                        viewModel.adjustLevel(.softer)
                    }
                }

                HStack {
                    Button("Louder") {
                        viewModel.adjustLevel(.louder)
                    }
                    Button("Much Louder") {
                        viewModel.adjustLevel(.muchLouder)
                    }
                }

                Button {
                    viewModel.acceptCurrentLevel()
                } label: {
                    Label("Same Loudness", systemImage: "equal.circle")
                }
            }

        case .awaitingConfidence:
            Section("Confidence") {
                ForEach(TinnitusConfidenceRating.allCases, id: \.self) { confidence in
                    Button(confidenceTitle(confidence)) {
                        viewModel.recordConfidence(confidence)
                    }
                }
            }

        case .completed(let summary):
            Section("Summary") {
                LabeledContent("Trials", value: "\(summary.trials.count)")
                LabeledContent(
                    "Spread",
                    value: String(format: "%.1f dB", summary.withinSessionSpreadDB)
                )
                if summary.qualityFlags.isEmpty {
                    Text("No quality flags recorded.")
                        .foregroundStyle(.secondary)
                } else {
                    Text(summary.qualityFlags.map(\.rawValue).joined(separator: ", "))
                        .foregroundStyle(.secondary)
                }
            }

        case .aborted:
            Section("Stopped") {
                Text("This loudness-match session was stopped.")
                    .foregroundStyle(.secondary)
            }

        case .restartRequired:
            Section("Restart Required") {
                Text("Audio guardrails changed. Restart the task before any calibrated playback.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var eventSection: some View {
        Section("Protocol Log") {
            LabeledContent("Events", value: "\(viewModel.events.count)")
        }
    }

    private var messageText: String {
        switch viewModel.message {
        case .playbackDisabled:
            return "Calibrated playback is still disabled for this participant workflow."
        case .invalidThreshold:
            return "Enter a finite threshold value in dB HL."
        case .guardrailsUnavailable:
            return "Audio guardrails are missing, failed, or require restart."
        case .playbackFailed(let message):
            return message
        case nil:
            return ""
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
            return "Central"
        case .unclear:
            return "Unclear"
        }
    }

    private func confidenceTitle(_ confidence: TinnitusConfidenceRating) -> String {
        switch confidence {
        case .low:
            return "Low"
        case .medium:
            return "Medium"
        case .high:
            return "High"
        }
    }
}
