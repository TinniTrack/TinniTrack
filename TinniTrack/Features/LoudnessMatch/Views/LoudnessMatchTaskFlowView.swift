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
            guardrailDiagnostics

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

    private var guardrailDiagnostics: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(guardrailDiagnosticSummary)
                .font(.footnote)
                .foregroundStyle(viewModel.currentGuardrailValidation.state == .passed ? .green : .secondary)

            DisclosureGroup {
                VStack(alignment: .leading, spacing: 8) {
                    guardrailDiagnosticRow("State", guardrailStatusText)
                    guardrailDiagnosticRow("Reason", guardrailReasonText)
                    guardrailDiagnosticRow("Output volume", guardrailOutputVolumeText)
                    guardrailDiagnosticRow("Volume policy", guardrailVolumePolicyText)
                    guardrailDiagnosticRow("Checked", guardrailCheckedTimeText)

                    Divider()

                    Text("Route outputs")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    let outputs = viewModel.currentGuardrailValidation.metadata.routeDetails?.outputs ?? []
                    if outputs.isEmpty {
                        Text("No current route outputs were reported by AVAudioSession.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(outputs.enumerated()), id: \.offset) { index, output in
                            guardrailRouteOutputView(output, index: index)
                        }
                    }
                }
                .padding(.top, 4)
            } label: {
                Label("Guardrail diagnostics", systemImage: "stethoscope")
                    .font(.footnote)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func guardrailDiagnosticRow(_ title: String, _ value: String) -> some View {
        LabeledContent {
            Text(value)
                .multilineTextAlignment(.trailing)
        } label: {
            Text(title)
        }
        .font(.caption)
    }

    private func guardrailRouteOutputView(
        _ output: CalibratedAudioRouteOutput,
        index: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Output \(index + 1): \(output.portName)")
                .font(.caption)
            Text("Type: \(guardrailPortKindText(output.portType))")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let identifier = output.verifiedCalibratedHeadphoneIdentifier {
                Text("Verified profile: \(identifier)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Verified profile: none")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let source = output.verificationSource {
                Text("Verification source: \(source.rawValue)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let uid = output.portUID, !uid.isEmpty {
                Text("UID: \(uid)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
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

    private var guardrailDiagnosticSummary: String {
        switch viewModel.currentGuardrailValidation.state {
        case .notEvaluated:
            return "Tap Check Audio Guardrails to read the current audio route and system volume."
        case .passed:
            return "Passed: current route, AirPods Pro 2 verification, and max-volume policy all match."
        case .failed, .restartRequired:
            return guardrailReasonText
        }
    }

    private var guardrailReasonText: String {
        guard let error = viewModel.currentGuardrailValidation.error else {
            switch viewModel.currentGuardrailValidation.state {
            case .notEvaluated:
                return "No guardrail check has run yet."
            case .passed:
                return "No failure."
            case .failed:
                return "The guardrail policy failed without a specific error."
            case .restartRequired:
                return "The guardrail state changed and the task must restart before playback."
            }
        }

        switch error {
        case .unsupportedRoute(let route, _):
            let count = route.outputs.count
            if count == 0 {
                return "No audio output route is available. Connect AirPods Pro 2 and try again."
            }
            if count > 1 {
                return "Expected exactly one Bluetooth A2DP output, but AVAudioSession reported \(count) outputs."
            }
            let output = route.outputs[0]
            return "Expected Bluetooth A2DP AirPods output, but current route is \(guardrailPortKindText(output.portType))."
        case .unverifiedHeadphoneProfile:
            return "Current route is not verified as AirPods Pro 2. Confirm the researcher verification toggle and Bluetooth A2DP route."
        case .invalidVolume(let volume, let policy):
            return "System output volume must be \(formatRaw(policy.requiredVolume)) +/- \(formatRaw(policy.tolerance)); current raw volume is \(formatRaw(volume))."
        case .routeChanged:
            return "Audio route changed after guardrails passed. Restart this loudness-match task before playback."
        case .volumeChanged(_, let currentVolume):
            return "System output volume changed after guardrails passed. Current raw volume is \(formatOptionalRaw(currentVolume)). Restart before playback."
        case .unavailableAudioSessionData(let reason):
            return reason
        case .missingCalibrationProfile(let identifier):
            return "Missing calibration profile for \(identifier)."
        }
    }

    private var guardrailOutputVolumeText: String {
        formatOptionalRaw(viewModel.currentGuardrailValidation.metadata.rawOutputVolume)
    }

    private var guardrailVolumePolicyText: String {
        viewModel.currentGuardrailValidation.metadata.volumePolicyDescription
    }

    private var guardrailCheckedTimeText: String {
        let timestamp = viewModel.currentGuardrailValidation.metadata.timestamp
        guard timestamp != Date.distantPast else {
            return "Never"
        }

        return timestamp.formatted(date: .omitted, time: .standard)
    }

    private func guardrailPortKindText(_ kind: CalibratedAudioRoutePortKind) -> String {
        switch kind {
        case .builtInSpeaker:
            return "Built-in speaker"
        case .builtInReceiver:
            return "Built-in receiver"
        case .wiredHeadphones:
            return "Wired headphones"
        case .bluetoothA2DP:
            return "Bluetooth A2DP"
        case .bluetoothHFP:
            return "Bluetooth hands-free"
        case .bluetoothLE:
            return "Bluetooth LE"
        case .airPlay:
            return "AirPlay"
        case .carAudio:
            return "Car audio"
        case .hdmi:
            return "HDMI"
        case .usbAudio:
            return "USB audio"
        case .unknown(let rawValue):
            return "Unknown (\(rawValue))"
        }
    }

    private func formatOptionalRaw(_ value: Double?) -> String {
        guard let value else {
            return "Unavailable"
        }
        return formatRaw(value)
    }

    private func formatRaw(_ value: Double) -> String {
        String(format: "%.4f", value)
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
