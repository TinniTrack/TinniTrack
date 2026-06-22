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

            Toggle("Researcher verified AirPods Pro 2", isOn: $viewModel.researchProtocolAirPodsPro2Verified)

            Button {
                Task {
                    await viewModel.runEnvironmentGate()
                }
            } label: {
                Label(
                    viewModel.isRunningEnvironmentGate ? "Checking Room" : "Run Quiet-Room Check",
                    systemImage: "waveform.badge.magnifyingglass"
                )
            }
            .disabled(viewModel.isRunningEnvironmentGate)

            LabeledContent("Quiet-Room Gate", value: environmentGateStatusText)

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
            Text("AirPods Pro 2 verification is a research-protocol confirmation because public iOS route APIs do not expose Apple's private AirPods hearing-test verification or firmware details.")
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
                Button {
                    viewModel.playThresholdTone()
                } label: {
                    Label("Play Threshold Tone", systemImage: "play.fill")
                }
                .disabled(!viewModel.canPlayThresholdTone)

                Button(role: .destructive) {
                    viewModel.stopTone()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }

                HStack {
                    Button("Heard") {
                        viewModel.recordThresholdResponse(.heard)
                    }
                    Button("Not Heard") {
                        viewModel.recordThresholdResponse(.notHeard)
                    }
                }
                .disabled(!viewModel.canRecordThresholdResponse)

                LabeledContent("Responses", value: "\(viewModel.thresholdStaircase.presentations.count)")
            } header: {
                Text("1000 Hz Threshold")
            } footer: {
                Text("The threshold staircase records every presented 1000 Hz level and heard/not-heard response before loudness matching starts.")
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
        case .environmentGateFailed:
            return "The quiet-room gate did not collect enough consecutive samples below the Study A threshold."
        case .missingPreflight(let message):
            return message
        case .incompletePayload(let message):
            return message
        case .guardrailsUnavailable:
            return "Audio guardrails are missing, failed, or require restart."
        case .environmentGateUnavailable(let message):
            return message
        case .playbackFailed(let message):
            return message
        case .submissionFailed(let message):
            return message
        case nil:
            return ""
        }
    }

    private var environmentGateStatusText: String {
        guard let result = viewModel.environmentGateResult else {
            return "Not checked"
        }
        return result.passed ? "Passed" : "Failed"
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
