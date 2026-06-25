import SwiftUI

struct LoudnessMatchTaskModalFlowView: View {
    let scheduledTask: ScheduledTask
    let enrollment: StudyEnrollment
    let studyService: StudyServiceProtocol
    let onSubmitted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: LoudnessMatchTaskFlowViewModel
    @State private var step: LoudnessMatchModalStep = .intro
    @State private var isCloseConfirmationPresented = false
    @State private var isNoiseSuggestionsPresented = false

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
        ZStack(alignment: .top) {
            LoudnessMatchModalColors.background
                .ignoresSafeArea()

            if step == .activeTest {
                LoudnessMatchActiveTestView(
                    viewModel: viewModel,
                    scheduledTask: scheduledTask,
                    enrollment: enrollment,
                    studyService: studyService
                ) { @MainActor in
                    onSubmitted()
                    dismiss()
                }
            } else {
                LoudnessMatchModalContentLayout {
                    LoudnessMatchPreparationStepView(
                        step: step,
                        viewModel: viewModel,
                        showNoiseSuggestions: { isNoiseSuggestionsPresented = true }
                    )
                } footer: {
                    LoudnessMatchModalPrimaryButton(
                        title: primaryButtonTitle,
                        isEnabled: isPrimaryButtonEnabled,
                        isInteractionEnabled: isPrimaryButtonInteractionEnabled
                    ) {
                        advance()
                    }
                }
            }

            topControls

            if shouldShowAirPodsInterruptionOverlay {
                airPodsInterruptionPopup
                    .transition(.opacity)
                    .zIndex(2)
            } else if shouldShowQuietRoomInterruptionPopup {
                quietRoomInterruptionPopup
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        .foregroundStyle(LoudnessMatchModalColors.text)
        .interactiveDismissDisabled(true)
        .onAppear {
            handleStepEntered(step)
        }
        .onChange(of: step) { newStep in
            handleStepEntered(newStep)
        }
        .onChange(of: viewModel.isAirPodsRouteInterrupted) { isInterrupted in
            if !isInterrupted {
                resumeCurrentStepAfterAirPodsReconnect()
            }
        }
        .onDisappear {
            cleanupForDismiss(abortActiveTest: false)
        }
        .fullScreenCover(isPresented: $isNoiseSuggestionsPresented) {
            LoudnessMatchNoiseSuggestionsView {
                isNoiseSuggestionsPresented = false
            }
        }
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
        .alert("Stop this test?", isPresented: $isCloseConfirmationPresented) {
            Button("Keep Testing", role: .cancel) {}
            Button("Stop Test", role: .destructive) {
                cleanupForDismiss(abortActiveTest: true)
                dismiss()
            }
        } message: {
            Text("Your current loudness-match progress will be discarded.")
        }
    }

    private var topControls: some View {
        HStack {
            if step != .intro {
                LoudnessMatchModalIconButton(
                    systemName: "chevron.left",
                    accessibilityLabel: "Back",
                    accessibilityIdentifier: "loudness_modal_back_button",
                    action: goBack
                )
            }

            Spacer()

            LoudnessMatchModalIconButton(
                systemName: "xmark",
                accessibilityLabel: "Close",
                accessibilityIdentifier: "loudness_modal_close_button",
                action: requestClose
            )
        }
        .padding(.horizontal, 26)
        .padding(.top, 18)
    }

    private var shouldShowAirPodsInterruptionOverlay: Bool {
        viewModel.isAirPodsRouteInterrupted && step != .intro && step != .correctEar
    }

    private var shouldShowQuietRoomInterruptionPopup: Bool {
        viewModel.isEnvironmentQuietnessInterrupted
            && step != .intro
            && step != .correctEar
            && step != .quietRoom
    }

    private var airPodsInterruptionPopup: some View {
        interruptionPopup(
            systemName: "airpodspro",
            title: airPodsInterruptionTitle,
            bodyText: airPodsInterruptionBodyText,
            accessibilityIdentifier: "loudness_airpods_interruption_popup"
        )
    }

    private var airPodsInterruptionTitle: String {
        viewModel.isAirPodsPlaybackRouteBlockedByAnotherApp
            ? "Calibrated Audio Blocked"
            : "Reconnect Your AirPods"
    }

    private var airPodsInterruptionBodyText: String {
        if viewModel.isAirPodsPlaybackRouteBlockedByAnotherApp {
            return "Another app is using your AirPods for call audio. Close Phone, Zoom, or other apps that may be using the headphones. The task will resume once AirPods return to calibrated playback."
        }

        return "Please put both AirPods in your ears and reconnect to continue the task. The task will automatically resume once your AirPods are connected and in both ears."
    }

    private var quietRoomInterruptionPopup: some View {
        interruptionPopup(
            systemName: "ear.badge.waveform",
            title: "Find a Quiet Place",
            bodyText: "The room is too loud for this task. The task will automatically resume once the room is quiet enough.",
            accessibilityIdentifier: "loudness_quiet_room_interruption_popup",
            quietRoomLevelRatio: quietRoomInterruptionLevelRatio
        )
    }

    private func interruptionPopup(
        systemName: String,
        title: String,
        bodyText: String,
        accessibilityIdentifier: String,
        quietRoomLevelRatio: Double? = nil
    ) -> some View {
        ZStack {
            Color.black.opacity(0.32)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                if let quietRoomLevelRatio {
                    LoudnessMatchNoiseGateMeter(
                        status: .tooLoud,
                        levelRatio: quietRoomLevelRatio,
                        isCompact: true
                    )
                    .padding(.horizontal, 6)
                    .accessibilityHidden(true)
                } else {
                    Image(systemName: systemName)
                        .font(.system(size: 58, weight: .regular))
                        .foregroundStyle(LoudnessMatchModalColors.primary)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }

                Text(title)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(LoudnessMatchModalColors.text)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)

                Text(bodyText)
                    .font(.callout)
                    .foregroundStyle(LoudnessMatchModalColors.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(5)
                    .minimumScaleFactor(0.82)

                LoudnessMatchModalPrimaryButton(
                    title: "Exit Task",
                    isEnabled: true
                ) {
                    exitTask()
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LoudnessMatchModalColors.background)
                    .shadow(color: .black.opacity(0.18), radius: 22, x: 0, y: 12)
            )
            .padding(.horizontal, 30)
        }
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var quietRoomInterruptionLevelRatio: Double {
        guard let latestSampleDBA = viewModel.environmentGateUpdate?.latestSampleDBA else {
            return 1.2
        }

        return latestSampleDBA / TinnitusEnvironmentSPLGateConfiguration.studyNo1.thresholdDBA
    }

    private var primaryButtonTitle: String {
        switch step {
        case .intro:
            return "Get Started"
        case .quietRoom, .correctEar, .fit:
            return "Next"
        case .maxVolume:
            return "Start Test"
        case .activeTest:
            return ""
        }
    }

    private var isPrimaryButtonEnabled: Bool {
        switch step {
        case .intro, .fit:
            return true
        case .correctEar:
            return viewModel.headphoneRouteAssessment.passesAirPodsPro2PlaybackHeuristic
        case .quietRoom:
            return viewModel.environmentGateResult?.passed == true
        case .maxVolume:
            return viewModel.currentGuardrailValidation.state == .passed
        case .activeTest:
            return false
        }
    }

    private var isPrimaryButtonInteractionEnabled: Bool {
        switch step {
        case .correctEar:
            return true
        default:
            return isPrimaryButtonEnabled
        }
    }

    private var hasStartedTest: Bool {
        step == .activeTest || viewModel.events.count > 1
    }

    private func advance() {
        switch step {
        case .intro:
            step = .correctEar
        case .correctEar:
            guard viewModel.validateAirPodsForCorrectEarStep() else {
                return
            }
            viewModel.stopHeadphoneRouteMonitoring()
            viewModel.startAirPodsContinuityMonitoring()
            viewModel.prepareEnvironmentGateForQuietRoomStep()
            step = .quietRoom
        case .quietRoom:
            guard viewModel.environmentGateResult?.passed == true else {
                return
            }
            viewModel.cancelEnvironmentGate()
            step = .fit
        case .fit:
            viewModel.completeFitConfirmation()
            step = .maxVolume
        case .maxVolume:
            guard viewModel.acknowledgeSafetyAndStartTest() else {
                return
            }
            viewModel.stopVolumeGateMonitoring()
            step = .activeTest
        case .activeTest:
            break
        }
    }

    private func goBack() {
        if viewModel.isPlaying {
            viewModel.stopTone()
        }

        switch step {
        case .intro:
            break
        case .quietRoom:
            viewModel.cancelEnvironmentGate()
            viewModel.stopAirPodsContinuityMonitoring()
            step = .correctEar
        case .correctEar:
            viewModel.stopHeadphoneRouteMonitoring()
            step = .intro
        case .fit:
            step = .quietRoom
        case .maxVolume:
            viewModel.stopVolumeGateMonitoring()
            step = .fit
        case .activeTest:
            step = .maxVolume
        }
    }

    private func requestClose() {
        if hasStartedTest {
            isCloseConfirmationPresented = true
        } else {
            cleanupForDismiss(abortActiveTest: false)
            dismiss()
        }
    }

    private func exitTask() {
        cleanupForDismiss(abortActiveTest: hasStartedTest)
        dismiss()
    }

    private func handleStepEntered(_ newStep: LoudnessMatchModalStep) {
        switch newStep {
        case .correctEar:
            viewModel.stopAirPodsContinuityMonitoring()
            viewModel.stopVolumeGateMonitoring()
            viewModel.cancelEnvironmentGate()
            viewModel.startHeadphoneRouteMonitoring()
        case .quietRoom:
            viewModel.stopHeadphoneRouteMonitoring()
            if viewModel.environmentGateResult?.passed != true {
                viewModel.startContinuousEnvironmentGate()
            }
        case .maxVolume:
            viewModel.stopHeadphoneRouteMonitoring()
            viewModel.startVolumeGateMonitoring()
        default:
            break
        }
    }

    private func resumeCurrentStepAfterAirPodsReconnect() {
        switch step {
        case .quietRoom:
            if viewModel.environmentGateResult?.passed != true {
                viewModel.startContinuousEnvironmentGate()
            }
        case .maxVolume:
            viewModel.startVolumeGateMonitoring()
        default:
            break
        }
    }

    private func cleanupForDismiss(abortActiveTest: Bool) {
        viewModel.stopHeadphoneRouteMonitoring()
        viewModel.stopAirPodsContinuityMonitoring()
        viewModel.cancelEnvironmentGate()
        viewModel.stopVolumeGateMonitoring()

        if abortActiveTest {
            viewModel.abort()
        } else if viewModel.isPlaying {
            viewModel.stopTone()
        }
    }

    private var messageText: String {
        switch viewModel.message {
        case .playbackDisabled:
            return "Calibrated playback is still disabled for this participant workflow."
        case .environmentGateFailed:
            return "The quiet-room gate did not collect enough consecutive samples below the Study No. 1 threshold."
        case .airPodsNotInEar:
            return "Please place your AirPods in your ear."
        case .unsupportedHeadphones:
            return "We detected headphones that are not AirPods Pro 2. AirPods Pro 2 are the only headphones we can use for this study."
        case .calibratedPlaybackRouteUnavailable:
            return "AirPods Pro 2 are connected, but another app is using them for call audio. Close Phone, Zoom, or other apps that may be using the headphones, then try again."
        case .missingAudiogramThreshold(let message):
            return message
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
}

#Preview {
    LoudnessMatchTaskModalFlowView(
        scheduledTask: ScheduledTask(
            id: UUID(),
            enrollmentID: UUID(),
            taskKey: "lm_1khz_v2",
            taskVersion: 2,
            scheduledFor: Date(),
            windowStart: Date(),
            windowEnd: Date().addingTimeInterval(3_600),
            status: .scheduled,
            dayIndex: 0,
            slotIndex: 0,
            completedAt: nil
        ),
        enrollment: StudyEnrollment(
            id: UUID(),
            userID: UUID(),
            studyID: UUID(),
            status: .enrolled,
            enrolledAt: Date(),
            createdAt: Date()
        ),
        studyService: SupabaseStudyService(),
        onSubmitted: {}
    )
}
