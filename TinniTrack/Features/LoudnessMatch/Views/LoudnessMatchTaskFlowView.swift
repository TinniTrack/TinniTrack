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
            LabeledContent("Audio Guardrails", value: guardrailStatusText)
            Button {
                viewModel.refreshGuardrails()
            } label: {
                Label("Check Audio Guardrails", systemImage: "checkmark.shield")
            }

            TextField("Quiet-room samples dBA", text: $viewModel.environmentSamplesText)
                .keyboardType(.numbersAndPunctuation)

            Toggle("Fit / seal confirmed", isOn: $viewModel.fitSealConfirmed)
            Toggle("Safety acknowledged", isOn: $viewModel.safetyAcknowledged)

            if viewModel.preflightReady {
                Label("Ready for guarded playback", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label("Playback and submission are locked until preflight passes.", systemImage: "lock.shield")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Preflight")
        } footer: {
            Text("Use comma, space, or line separated dBA samples. The current Study A implementation records this as quiet-room context and requires five samples below 45 dBA.")
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
            .disabled(!viewModel.preflightReady)

        case .awaitingThreshold:
            Section {
                TextField("Researcher threshold dB HL", text: $viewModel.thresholdLevelText)
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
            } header: {
                Text("1000 Hz Threshold")
            } footer: {
                Text("Manual threshold entry is persisted as a scaffold source, not as measured ResearchKit audiometry.")
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
                .disabled(!viewModel.preflightReady)
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

                Button {
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
                } label: {
                    Label(viewModel.isSubmitting ? "Submitting" : "Submit", systemImage: "square.and.arrow.up")
                }
                .disabled(!viewModel.canSubmit)
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
        case .invalidEnvironmentSamples:
            return "Enter at least five finite quiet-room dBA samples below 45 dBA."
        case .missingPreflight(let message):
            return message
        case .incompletePayload(let message):
            return message
        case .guardrailsUnavailable:
            return "Audio guardrails are missing, failed, or require restart."
        case .playbackFailed(let message):
            return message
        case .submissionFailed(let message):
            return message
        case nil:
            return ""
        }
    }

    private var guardrailStatusText: String {
        switch viewModel.currentGuardrailValidation.state {
        case .notEvaluated:
            return "Not checked"
        case .passed:
            return "Passed"
        case .failed:
            return "Failed"
        case .restartRequired:
            return "Restart required"
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
