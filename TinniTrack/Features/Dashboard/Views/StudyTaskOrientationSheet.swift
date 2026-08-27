import SwiftUI

struct StudyTaskOrientationSheet: View {
    @Binding var step: StudyTaskOrientationStep
    @ObservedObject var viewModel: StudyTaskDashboardViewModel
    let enrollment: StudyEnrollment
    let studyService: StudyServiceProtocol

    let openHealthApp: () -> Void
    let close: () -> Void

    @StateObject private var loudnessViewModel = LoudnessMatchTaskFlowViewModel()
    @State private var isCloseConfirmationPresented = false
    @State private var isNoiseSuggestionsPresented = false
    @State private var orientationThresholdErrorMessage: String?
    @State private var prepareOnboardingThresholdTask: Task<Void, Never>?
    @AccessibilityFocusState private var isInterruptionPopupFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            LoudnessMatchModalColors.background
                .ignoresSafeArea()

            if step == .activeTest, let onboardingTask = viewModel.onboardingThresholdTask {
                ResearchKitTaskPresenterView(
                    request: .studyNo1OrientationThreshold(identifier: "study-no-1-orientation-threshold")
                ) { summary in
                    Task { @MainActor in
                        await handleOrientationThresholdCompletion(summary, onboardingTask: onboardingTask)
                    }
                }
                .accessibilityHidden(isInterruptionOverlayPresented)
            } else {
                LoudnessMatchModalContentLayout {
                    currentStepContent
                } footer: {
                    LoudnessMatchModalPrimaryButton(
                        title: primaryButtonTitle,
                        isEnabled: isPrimaryButtonEnabled,
                        isInteractionEnabled: isPrimaryButtonInteractionEnabled,
                        isLoading: isPrimaryButtonLoading
                    ) {
                        advance()
                    }
                }
                .accessibilityHidden(isInterruptionOverlayPresented)
            }

            topControls
                .accessibilityHidden(isInterruptionOverlayPresented)

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
        .onChange(of: step) { _, newStep in
            handleStepEntered(newStep)
        }
        .onChange(of: loudnessViewModel.isAirPodsRouteInterrupted) { _, isInterrupted in
            if !isInterrupted {
                resumeCurrentStepAfterAirPodsReconnect()
            }
        }
        .onChange(of: loudnessViewModel.headphoneRouteAssessment) { _, assessment in
            returnToAirPodsConfirmationIfNeeded(for: assessment)
        }
        .onChange(of: isInterruptionOverlayPresented) { _, isPresented in
            isInterruptionPopupFocused = isPresented
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
                get: {
                    loudnessViewModel.message != nil
                        || viewModel.taskLoadErrorMessage != nil
                        || orientationThresholdErrorMessage != nil
                },
                set: { shouldShow in
                    if !shouldShow {
                        loudnessViewModel.clearMessage()
                        viewModel.dismissTaskError()
                        orientationThresholdErrorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                loudnessViewModel.clearMessage()
                viewModel.dismissTaskError()
                orientationThresholdErrorMessage = nil
            }
        } message: {
            Text(messageText)
        }
        .alert("Stop orientation?", isPresented: $isCloseConfirmationPresented) {
            Button("Keep Going", role: .cancel) {}
            Button("Stop Orientation", role: .destructive) {
                cleanupForDismiss(abortActiveTest: hasStartedTest)
                close()
            }
        } message: {
            Text("Your current Study No. 1 onboarding progress will be discarded.")
        }
    }

    @ViewBuilder
    private var currentStepContent: some View {
        switch step {
        case .welcome:
            welcomeStep
        case .hearingTest:
            hearingTestStep
        case .taskIntro:
            LoudnessMatchPreparationStepView(
                step: .intro,
                viewModel: loudnessViewModel,
                showNoiseSuggestions: { isNoiseSuggestionsPresented = true }
            )
            .accessibilityIdentifier("study_onboarding_loudness_intro_step")
        case .correctEar:
            LoudnessMatchPreparationStepView(
                step: .correctEar,
                viewModel: loudnessViewModel,
                showNoiseSuggestions: { isNoiseSuggestionsPresented = true }
            )
        case .quietRoom:
            LoudnessMatchPreparationStepView(
                step: .quietRoom,
                viewModel: loudnessViewModel,
                showNoiseSuggestions: { isNoiseSuggestionsPresented = true }
            )
        case .fit:
            LoudnessMatchPreparationStepView(
                step: .fit,
                viewModel: loudnessViewModel,
                showNoiseSuggestions: { isNoiseSuggestionsPresented = true }
            )
        case .maxVolume:
            LoudnessMatchPreparationStepView(
                step: .maxVolume,
                viewModel: loudnessViewModel,
                maxVolumeActionTitle: "Start Test",
                showNoiseSuggestions: { isNoiseSuggestionsPresented = true }
            )
        case .activeTest:
            EmptyView()
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 28) {
            Spacer(minLength: 0)

            Image(systemName: "waveform.path")
                .font(.system(size: 92, weight: .medium))
                .foregroundStyle(LoudnessMatchModalColors.primary)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

            LoudnessMatchModalTitleBlock(
                title: "Welcome to Study No. 1",
                bodyText: "We will set up your hearing-test baseline, then run the same tinnitus loudness-match flow used for every Study No. 1 task."
            )

            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .accessibilityIdentifier("study_onboarding_welcome_step")
    }

    private var hearingTestStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            Image(systemName: "airpodspro")
                .font(.system(size: 86, weight: .regular))
                .foregroundStyle(LoudnessMatchModalColors.graphic)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

            LoudnessMatchModalTitleBlock(
                title: "Take an Apple Hearing Test",
                bodyText: "Use AirPods Pro 2 with your paired iPhone. In Settings, open your AirPods and tap Take a Hearing Test. When you return, connect Apple Health so TinniTrack can import the result."
            )

            importStateContent

            Link(
                "Need help taking an Apple Hearing Test?",
                destination: URL(string: "https://support.apple.com/en-us/120991")!
            )
            .font(.callout)
            .fontWeight(.semibold)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .task {
            await viewModel.checkOrientationImportStatus()
        }
        .accessibilityIdentifier("study_onboarding_hearing_test_step")
    }

    @ViewBuilder
    private var importStateContent: some View {
        switch viewModel.orientationImportState {
        case .waitingForPermission:
            inlineStatus(
                systemName: "heart.text.square",
                title: "Apple Health access needed",
                message: "Allow audiogram read access to import your Apple hearing test."
            )

            secondaryActionButton(
                title: viewModel.isSyncing ? "Connecting" : "Connect Apple Health",
                isLoading: viewModel.isSyncing
            ) {
                Task { await viewModel.connectAppleHealthForOrientation() }
            }

        case .requestingOrChecking:
            HStack(spacing: 12) {
                ProgressView()
                Text("Checking hearing-test import...")
                    .font(.callout)
                    .foregroundStyle(LoudnessMatchModalColors.secondaryText)
            }

        case .success(let hearingTestDate):
            inlineStatus(
                systemName: "checkmark.circle.fill",
                title: "Hearing test imported",
                message: successMessageForHearingTestDate(hearingTestDate),
                tint: LoudnessMatchModalColors.success
            )

        case .authorizedNoHearingTest:
            inlineStatus(
                systemName: "exclamationmark.circle",
                title: "No hearing test found yet",
                message: "Apple Health is connected, but no audiogram is available yet. Complete the Apple Hearing Test and check again."
            )

            secondaryActionButton(
                title: viewModel.isSyncing ? "Checking" : "Check Again",
                isLoading: viewModel.isSyncing
            ) {
                Task { await viewModel.connectAppleHealthForOrientation() }
            }

        case .permissionDenied:
            inlineStatus(
                systemName: "lock.circle",
                title: "Permission required",
                message: "Approve hearing-test access in Apple Health, then return here and check again."
            )

            HStack(spacing: 12) {
                secondaryActionButton(title: "Open Health", isLoading: false, action: openHealthApp)
                secondaryActionButton(
                    title: viewModel.isSyncing ? "Checking" : "Check Again",
                    isLoading: viewModel.isSyncing
                ) {
                    Task { await viewModel.checkOrientationImportStatus() }
                }
            }

        case .error(let message):
            inlineStatus(
                systemName: "exclamationmark.triangle",
                title: "Import unavailable",
                message: message
            )

            secondaryActionButton(
                title: viewModel.isSyncing ? "Retrying" : "Try Again",
                isLoading: viewModel.isSyncing
            ) {
                Task { await viewModel.connectAppleHealthForOrientation() }
            }
        }
    }

    private func inlineStatus(
        systemName: String,
        title: String,
        message: String,
        tint: Color = LoudnessMatchModalColors.secondaryText
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemName)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(LoudnessMatchModalColors.text)

                Text(message)
                    .font(.callout)
                    .foregroundStyle(LoudnessMatchModalColors.secondaryText)
                    .lineLimit(4)
                    .minimumScaleFactor(0.82)
            }
        }
        .padding(16)
        .background(LoudnessMatchModalColors.controlBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(LoudnessMatchModalColors.controlStroke, lineWidth: 1)
        }
    }

    private func secondaryActionButton(
        title: String,
        isLoading: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                }

                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 48)
            .foregroundStyle(isLoading ? LoudnessMatchModalColors.disabledText : LoudnessMatchModalColors.text)
            .background(LoudnessMatchModalColors.controlBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(LoudnessMatchModalColors.controlStroke, lineWidth: 1)
            }
        }
        .buttonStyle(AppRoundedButtonStyle(cornerRadius: 8))
        .disabled(isLoading)
    }

    private var topControls: some View {
        HStack {
            if step != .welcome, step != .activeTest {
                LoudnessMatchModalIconButton(
                    systemName: "chevron.left",
                    accessibilityLabel: "Back",
                    accessibilityIdentifier: "study_onboarding_back_button",
                    action: goBack
                )
            }

            Spacer()

            LoudnessMatchModalIconButton(
                systemName: "xmark",
                accessibilityLabel: "Close",
                accessibilityIdentifier: "study_onboarding_close_button",
                action: requestClose
            )
        }
        .padding(.horizontal, 26)
        .padding(.top, 18)
    }

    private var primaryButtonTitle: String {
        switch step {
        case .welcome:
            return "Continue"
        case .hearingTest:
            return "Continue"
        case .taskIntro:
            return "Get Started"
        case .correctEar, .quietRoom, .fit:
            return "Next"
        case .maxVolume:
            return viewModel.isPreparingOnboardingThresholdTask ? "Starting" : "Start Test"
        case .activeTest:
            return ""
        }
    }

    private var isPrimaryButtonEnabled: Bool {
        switch step {
        case .welcome, .taskIntro, .fit:
            return true
        case .hearingTest:
            return viewModel.isAudiogramPrerequisiteMet
        case .correctEar:
            return loudnessViewModel.isCurrentAirPodsPro2PlaybackRouteConfirmed
        case .quietRoom:
            return loudnessViewModel.environmentGateResult?.passed == true
        case .maxVolume:
            return loudnessViewModel.currentGuardrailValidation.state == .passed
                && !viewModel.isPreparingOnboardingThresholdTask
        case .activeTest:
            return false
        }
    }

    private var isPrimaryButtonInteractionEnabled: Bool {
        isPrimaryButtonEnabled
    }

    private var isPrimaryButtonLoading: Bool {
        step == .maxVolume && viewModel.isPreparingOnboardingThresholdTask
    }

    private var hasStartedTest: Bool {
        step == .activeTest || loudnessViewModel.events.count > 1
    }

    private var shouldShowAirPodsInterruptionOverlay: Bool {
        loudnessViewModel.isAirPodsRouteInterrupted
            && step != .welcome
            && step != .hearingTest
            && step != .taskIntro
            && step != .correctEar
    }

    private var shouldShowQuietRoomInterruptionPopup: Bool {
        loudnessViewModel.isEnvironmentQuietnessInterrupted
            && step != .welcome
            && step != .hearingTest
            && step != .taskIntro
            && step != .correctEar
            && step != .quietRoom
    }

    private var airPodsInterruptionPopup: some View {
        interruptionPopup(
            systemName: "airpodspro",
            title: airPodsInterruptionTitle,
            bodyText: airPodsInterruptionBodyText,
            accessibilityIdentifier: "study_onboarding_airpods_interruption_popup"
        )
    }

    private var airPodsInterruptionTitle: String {
        if isCurrentA2DPRouteUnconfirmed {
            return "AirPods Output Changed"
        }

        return loudnessViewModel.isAirPodsPlaybackRouteBlockedByAnotherApp
            ? "Calibrated Audio Blocked"
            : "Reconnect Your AirPods"
    }

    private var airPodsInterruptionBodyText: String {
        if isCurrentA2DPRouteUnconfirmed {
            return "The audio output changed after confirmation. Exit and restart orientation to confirm the current AirPods before continuing."
        }

        if loudnessViewModel.isAirPodsPlaybackRouteBlockedByAnotherApp {
            return "Another app is using your AirPods for call audio. Close Phone, Zoom, or other apps that may be using the headphones. Onboarding will resume once AirPods return to calibrated playback."
        }

        return "Please put both AirPods in your ears and reconnect to continue onboarding."
    }

    private var quietRoomInterruptionPopup: some View {
        interruptionPopup(
            systemName: "ear.badge.waveform",
            title: "Find a Quiet Place",
            bodyText: "The room is too loud for this task. Onboarding will resume once the room is quiet enough.",
            accessibilityIdentifier: "study_onboarding_quiet_room_interruption_popup",
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

            ScrollView {
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
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($isInterruptionPopupFocused)

                    Text(bodyText)
                        .font(.callout)
                        .foregroundStyle(LoudnessMatchModalColors.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    LoudnessMatchModalPrimaryButton(title: "Exit Orientation", isEnabled: true) {
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
                .padding(.vertical, 32)
            }
            .scrollIndicators(.hidden)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var quietRoomInterruptionLevelRatio: Double {
        guard let latestSampleDBA = loudnessViewModel.environmentGateUpdate?.latestSampleDBA else {
            return 1.2
        }

        return latestSampleDBA / TinnitusEnvironmentSPLGateConfiguration.studyNo1.thresholdDBA
    }

    private func advance() {
        switch step {
        case .welcome:
            step = .hearingTest
        case .hearingTest:
            guard viewModel.isAudiogramPrerequisiteMet else {
                return
            }
            step = .taskIntro
        case .taskIntro:
            step = .correctEar
        case .correctEar:
            guard loudnessViewModel.validateAirPodsForCorrectEarStep() else {
                return
            }
            loudnessViewModel.stopHeadphoneRouteMonitoring()
            loudnessViewModel.startAirPodsContinuityMonitoring()
            loudnessViewModel.prepareEnvironmentGateForQuietRoomStep()
            step = .quietRoom
        case .quietRoom:
            guard loudnessViewModel.environmentGateResult?.passed == true else {
                return
            }
            step = .fit
        case .fit:
            loudnessViewModel.completeFitConfirmation()
            step = .maxVolume
        case .maxVolume:
            guard loudnessViewModel.acknowledgeSafetyAndStartTest() else {
                return
            }
            prepareOnboardingThresholdTask?.cancel()
            prepareOnboardingThresholdTask = Task { @MainActor in
                let onboardingTask = await viewModel.prepareStudyOnboardingThresholdTask()
                guard !Task.isCancelled, step == .maxVolume else {
                    return
                }

                if !viewModel.requiresStudyOnboardingCompletion {
                    close()
                    return
                }

                guard onboardingTask != nil,
                      loudnessViewModel.preflightReady,
                      loudnessViewModel.isCurrentAirPodsPro2PlaybackRouteConfirmed,
                      !loudnessViewModel.isAirPodsRouteInterrupted
                else {
                    return
                }

                loudnessViewModel.stopVolumeGateMonitoring()
                step = .activeTest
            }
        case .activeTest:
            break
        }
    }

    private func goBack() {
        guard step != .activeTest else {
            return
        }

        if loudnessViewModel.isPlaying {
            loudnessViewModel.stopTone()
        }

        switch step {
        case .welcome:
            break
        case .hearingTest:
            step = .welcome
        case .taskIntro:
            step = .hearingTest
        case .correctEar:
            loudnessViewModel.stopHeadphoneRouteMonitoring()
            step = .taskIntro
        case .quietRoom:
            loudnessViewModel.cancelEnvironmentGate()
            loudnessViewModel.stopAirPodsContinuityMonitoring()
            step = .correctEar
        case .fit:
            step = .quietRoom
        case .maxVolume:
            loudnessViewModel.stopVolumeGateMonitoring()
            step = .fit
        case .activeTest:
            break
        }
    }

    private func requestClose() {
        if hasStartedTest {
            isCloseConfirmationPresented = true
        } else {
            cleanupForDismiss(abortActiveTest: false)
            close()
        }
    }

    private func exitTask() {
        cleanupForDismiss(abortActiveTest: hasStartedTest)
        close()
    }

    private func handleStepEntered(_ newStep: StudyTaskOrientationStep) {
        if newStep != .maxVolume {
            prepareOnboardingThresholdTask?.cancel()
            prepareOnboardingThresholdTask = nil
        }

        switch newStep {
        case .correctEar:
            loudnessViewModel.stopAirPodsContinuityMonitoring()
            loudnessViewModel.stopVolumeGateMonitoring()
            loudnessViewModel.cancelEnvironmentGate()
            loudnessViewModel.startHeadphoneRouteMonitoring()
        case .quietRoom:
            loudnessViewModel.stopHeadphoneRouteMonitoring()
            if loudnessViewModel.environmentGateResult?.passed != true {
                loudnessViewModel.startContinuousEnvironmentGate()
            }
        case .maxVolume:
            loudnessViewModel.stopHeadphoneRouteMonitoring()
            loudnessViewModel.startVolumeGateMonitoring()
        default:
            break
        }
    }

    private func resumeCurrentStepAfterAirPodsReconnect() {
        switch step {
        case .quietRoom:
            if loudnessViewModel.environmentGateResult?.passed != true {
                loudnessViewModel.startContinuousEnvironmentGate()
            }
        case .maxVolume:
            loudnessViewModel.startVolumeGateMonitoring()
        default:
            break
        }
    }

    private var isCurrentA2DPRouteUnconfirmed: Bool {
        loudnessViewModel.headphoneRouteAssessment.isCompatibleBluetoothPlaybackRoute
            && !loudnessViewModel.isCurrentAirPodsPro2PlaybackRouteConfirmed
    }

    private func returnToAirPodsConfirmationIfNeeded(for assessment: HeadphoneRouteAssessment) {
        guard step != .welcome,
              step != .hearingTest,
              step != .taskIntro,
              step != .correctEar,
              step != .activeTest,
              assessment.isCompatibleBluetoothPlaybackRoute,
              !loudnessViewModel.isCurrentAirPodsPro2PlaybackRouteConfirmed
        else {
            return
        }

        step = .correctEar
    }

    private func cleanupForDismiss(abortActiveTest: Bool) {
        prepareOnboardingThresholdTask?.cancel()
        prepareOnboardingThresholdTask = nil
        loudnessViewModel.stopHeadphoneRouteMonitoring()
        loudnessViewModel.stopAirPodsContinuityMonitoring()
        loudnessViewModel.cancelEnvironmentGate()
        loudnessViewModel.stopVolumeGateMonitoring()

        if abortActiveTest {
            loudnessViewModel.abort()
        } else if loudnessViewModel.isPlaying {
            loudnessViewModel.stopTone()
        }
    }

    private var isInterruptionOverlayPresented: Bool {
        shouldShowAirPodsInterruptionOverlay || shouldShowQuietRoomInterruptionPopup
    }

    private var messageText: String {
        if let orientationThresholdErrorMessage {
            return orientationThresholdErrorMessage
        }

        if let dashboardMessage = viewModel.taskLoadErrorMessage {
            return dashboardMessage
        }

        switch loudnessViewModel.message {
        case .playbackDisabled:
            return "Calibrated playback is still disabled for this participant workflow."
        case .environmentGateFailed:
            return "The quiet-room gate did not collect enough consecutive samples below the Study No. 1 threshold."
        case .airPodsNotInEar:
            return "Please place your AirPods in your ear."
        case .unsupportedHeadphones:
            return "We detected headphones that are not AirPods Pro 2. AirPods Pro 2 are the only headphones we can use for this study."
        case .airPodsPro2ConfirmationRequired:
            return "Confirm that the connected headphones are AirPods Pro 2 before continuing."
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

    private func handleOrientationThresholdCompletion(
        _ summary: ResearchKitTaskResultSummary,
        onboardingTask: ScheduledTask
    ) async {
        guard summary.finishState == .completed else {
            orientationThresholdErrorMessage = "The orientation threshold task was not completed."
            step = .maxVolume
            return
        }

        guard let thresholdResult = summary.studyNo1OrientationThreshold,
              thresholdResult.isComplete
        else {
            orientationThresholdErrorMessage = "The orientation threshold task did not return both 1 kHz ear thresholds."
            step = .maxVolume
            return
        }

        let submitted = await loudnessViewModel.submitOrientationThreshold(
            result: thresholdResult,
            scheduledTask: onboardingTask,
            enrollment: enrollment,
            studyService: studyService
        )
        guard submitted else {
            step = .maxVolume
            return
        }

        await viewModel.completeStudyOnboarding()
        if !viewModel.requiresStudyOnboardingCompletion {
            close()
        }
    }

    private func successMessageForHearingTestDate(_ date: Date?) -> String {
        guard let date else {
            return "Success. We imported your hearing test."
        }
        return "Success. We imported your hearing test from \(Self.hearingTestDateFormatter.string(from: date))."
    }

    private static let hearingTestDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }()
}
