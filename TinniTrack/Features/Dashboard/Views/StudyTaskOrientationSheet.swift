import SwiftUI

struct StudyTaskOrientationSheet: View {
    @Binding var step: StudyTaskOrientationStep
    @ObservedObject var viewModel: StudyTaskDashboardViewModel
    let enrollment: StudyEnrollment
    let studyService: StudyServiceProtocol

    let openHealthApp: () -> Void
    let close: () -> Void

    @StateObject private var loudnessViewModel = LoudnessMatchTaskFlowViewModel()
    @State private var navigationPath: [StudyTaskOrientationStep]
    @State private var isCloseConfirmationPresented = false
    @State private var isNoiseSuggestionsPresented = false
    @State private var orientationThresholdErrorMessage: String?

    init(
        step: Binding<StudyTaskOrientationStep>,
        viewModel: StudyTaskDashboardViewModel,
        enrollment: StudyEnrollment,
        studyService: StudyServiceProtocol,
        openHealthApp: @escaping () -> Void,
        close: @escaping () -> Void
    ) {
        _step = step
        self.viewModel = viewModel
        self.enrollment = enrollment
        self.studyService = studyService
        self.openHealthApp = openHealthApp
        self.close = close
        _navigationPath = State(initialValue: Self.initialNavigationPath(for: step.wrappedValue))
    }

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
            } else {
                orientationNavigation
            }

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
        .onChange(of: navigationPath) { oldPath, newPath in
            handleNavigationPathChange(from: oldPath, to: newPath)
        }
        .onChange(of: step) { _, newStep in
            handleStepEntered(newStep)
        }
        .onChange(of: loudnessViewModel.isAirPodsRouteInterrupted) { _, isInterrupted in
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
        .alert("Exit Orientation?", isPresented: $isCloseConfirmationPresented) {
            Button("Keep Going", role: .cancel) {}
            Button("Exit Orientation", role: .destructive) {
                cleanupForDismiss(abortActiveTest: hasStartedTest)
                close()
            }
        } message: {
            Text("Your current Study No. 1 onboarding progress will be discarded.")
        }
    }

    private var orientationNavigation: some View {
        NavigationStack(path: $navigationPath) {
            orientationPage(for: .welcome)
                .navigationDestination(for: StudyTaskOrientationStep.self) { destination in
                    orientationPage(for: destination)
                }
        }
        .tint(LoudnessMatchModalColors.primary)
    }

    private func orientationPage(for pageStep: StudyTaskOrientationStep) -> some View {
        GeometryReader { proxy in
            ScrollView {
                currentStepContent(for: pageStep)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: max(0, proxy.size.height - 48), alignment: .top)
                    .padding(.horizontal, 34)
                    .padding(.vertical, 24)
            }
        }
        .background(LoudnessMatchModalColors.background)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            orientationPrimaryAction(for: pageStep)
        }
        .navigationTitle("Orientation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: requestClose) {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("Close")
                .accessibilityIdentifier("study_onboarding_close_button")
            }
        }
    }

    private func orientationPrimaryAction(for pageStep: StudyTaskOrientationStep) -> some View {
        LoudnessMatchModalPrimaryButton(
            title: primaryButtonTitle(for: pageStep),
            isEnabled: isPrimaryButtonEnabled(for: pageStep),
            isInteractionEnabled: isPrimaryButtonInteractionEnabled(for: pageStep),
            isLoading: isPrimaryButtonLoading(for: pageStep)
        ) {
            advance(from: pageStep)
        }
        .accessibilityIdentifier("study_onboarding_primary_button")
        .padding(.horizontal, 34)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func currentStepContent(for pageStep: StudyTaskOrientationStep) -> some View {
        switch pageStep {
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
            Image(systemName: "waveform.path")
                .font(.system(size: 92, weight: .medium))
                .foregroundStyle(LoudnessMatchModalColors.primary)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

            LoudnessMatchModalTitleBlock(
                title: "Welcome to Study No. 1",
                bodyText: "We will set up your hearing-test baseline, then run the same tinnitus loudness-match flow used for every Study No. 1 task."
            )
        }
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

    private func primaryButtonTitle(for pageStep: StudyTaskOrientationStep) -> String {
        switch pageStep {
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

    private func isPrimaryButtonEnabled(for pageStep: StudyTaskOrientationStep) -> Bool {
        switch pageStep {
        case .welcome, .taskIntro, .fit:
            return true
        case .hearingTest:
            return viewModel.isAudiogramPrerequisiteMet
        case .correctEar:
            return loudnessViewModel.headphoneRouteAssessment.passesAirPodsPro2PlaybackHeuristic
        case .quietRoom:
            return loudnessViewModel.environmentGateResult?.passed == true
        case .maxVolume:
            return loudnessViewModel.currentGuardrailValidation.state == .passed
                && !viewModel.isPreparingOnboardingThresholdTask
        case .activeTest:
            return false
        }
    }

    private func isPrimaryButtonInteractionEnabled(for pageStep: StudyTaskOrientationStep) -> Bool {
        switch pageStep {
        case .correctEar:
            return true
        default:
            return isPrimaryButtonEnabled(for: pageStep)
        }
    }

    private func isPrimaryButtonLoading(for pageStep: StudyTaskOrientationStep) -> Bool {
        pageStep == .maxVolume && viewModel.isPreparingOnboardingThresholdTask
    }

    private var currentNavigationStep: StudyTaskOrientationStep {
        navigationPath.last ?? .welcome
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
        loudnessViewModel.isAirPodsPlaybackRouteBlockedByAnotherApp
            ? "Calibrated Audio Blocked"
            : "Reconnect Your AirPods"
    }

    private var airPodsInterruptionBodyText: String {
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

                LoudnessMatchModalPrimaryButton(title: "Exit Orientation", isEnabled: true) {
                    requestClose()
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
        guard let latestSampleDBA = loudnessViewModel.environmentGateUpdate?.latestSampleDBA else {
            return 1.2
        }

        return latestSampleDBA / TinnitusEnvironmentSPLGateConfiguration.studyNo1.thresholdDBA
    }

    private func advance(from pageStep: StudyTaskOrientationStep) {
        guard pageStep == currentNavigationStep else {
            return
        }

        switch pageStep {
        case .welcome:
            navigationPath.append(.hearingTest)
        case .hearingTest:
            guard viewModel.isAudiogramPrerequisiteMet else {
                return
            }
            navigationPath.append(.taskIntro)
        case .taskIntro:
            navigationPath.append(.correctEar)
        case .correctEar:
            guard loudnessViewModel.validateAirPodsForCorrectEarStep() else {
                return
            }
            loudnessViewModel.stopHeadphoneRouteMonitoring()
            loudnessViewModel.startAirPodsContinuityMonitoring()
            loudnessViewModel.prepareEnvironmentGateForQuietRoomStep()
            navigationPath.append(.quietRoom)
        case .quietRoom:
            guard loudnessViewModel.environmentGateResult?.passed == true else {
                return
            }
            navigationPath.append(.fit)
        case .fit:
            loudnessViewModel.completeFitConfirmation()
            navigationPath.append(.maxVolume)
        case .maxVolume:
            guard loudnessViewModel.acknowledgeSafetyAndStartTest() else {
                return
            }
            Task {
                if await viewModel.prepareStudyOnboardingThresholdTask() != nil {
                    guard currentNavigationStep == .maxVolume else {
                        return
                    }
                    loudnessViewModel.stopVolumeGateMonitoring()
                    step = .activeTest
                } else if !viewModel.requiresStudyOnboardingCompletion {
                    close()
                }
            }
        case .activeTest:
            break
        }
    }

    private func handleNavigationPathChange(
        from oldPath: [StudyTaskOrientationStep],
        to newPath: [StudyTaskOrientationStep]
    ) {
        let oldStep = oldPath.last ?? .welcome
        let newStep = newPath.last ?? .welcome
        guard oldStep != newStep else {
            return
        }

        if newPath.count < oldPath.count {
            cleanupForNavigationPop(
                oldPath.dropFirst(newPath.count).reversed()
            )
        }

        step = newStep
    }

    private func cleanupForNavigationPop<Steps: Sequence>(_ poppedSteps: Steps)
    where Steps.Element == StudyTaskOrientationStep {
        if loudnessViewModel.isPlaying {
            loudnessViewModel.stopTone()
        }

        for poppedStep in poppedSteps {
            switch poppedStep {
            case .correctEar:
                loudnessViewModel.stopHeadphoneRouteMonitoring()
            case .quietRoom:
                loudnessViewModel.cancelEnvironmentGate()
                loudnessViewModel.stopAirPodsContinuityMonitoring()
            case .maxVolume:
                loudnessViewModel.stopVolumeGateMonitoring()
            case .welcome, .hearingTest, .taskIntro, .fit, .activeTest:
                break
            }
        }
    }

    private func requestClose() {
        isCloseConfirmationPresented = true
    }

    private func handleStepEntered(_ newStep: StudyTaskOrientationStep) {
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

    private func cleanupForDismiss(abortActiveTest: Bool) {
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

    private static func initialNavigationPath(
        for initialStep: StudyTaskOrientationStep
    ) -> [StudyTaskOrientationStep] {
        switch initialStep {
        case .welcome:
            return []
        case .hearingTest:
            return [.hearingTest]
        case .taskIntro:
            return [.hearingTest, .taskIntro]
        case .correctEar:
            return [.hearingTest, .taskIntro, .correctEar]
        case .quietRoom:
            return [.hearingTest, .taskIntro, .correctEar, .quietRoom]
        case .fit:
            return [.hearingTest, .taskIntro, .correctEar, .quietRoom, .fit]
        case .maxVolume, .activeTest:
            return [.hearingTest, .taskIntro, .correctEar, .quietRoom, .fit, .maxVolume]
        }
    }

    private static let hearingTestDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }()
}
