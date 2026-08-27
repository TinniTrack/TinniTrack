import SwiftUI

struct StudyTaskOrientationSheet: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var viewModel: StudyTaskDashboardViewModel

    @StateObject private var loudnessViewModel: LoudnessMatchTaskFlowViewModel
    @StateObject private var thresholdCoordinator: StudyOrientationThresholdCoordinator
    @State private var navigationPath: [StudyTaskOrientationRoute] = []
    @State private var isCloseConfirmationPresented = false
    @State private var isNoiseSuggestionsPresented = false
    @State private var presentedPreflightFailure: StudyOrientationThresholdCoordinator.RetryableFailure?

    init(
        viewModel: StudyTaskDashboardViewModel,
        enrollment: StudyEnrollment,
        studyService: StudyServiceProtocol,
        loudnessViewModel: LoudnessMatchTaskFlowViewModel? = nil
    ) {
        let resolvedLoudnessViewModel = loudnessViewModel ?? LoudnessMatchTaskFlowViewModel()
        self.viewModel = viewModel
        _loudnessViewModel = StateObject(wrappedValue: resolvedLoudnessViewModel)
        _thresholdCoordinator = StateObject(
            wrappedValue: StudyOrientationThresholdCoordinator(
                enrollment: enrollment,
                studyService: studyService,
                submissionBuilder: resolvedLoudnessViewModel,
                completeOnboarding: { [weak viewModel] in
                    guard let viewModel else {
                        return .cancelled
                    }
                    return await viewModel.completeStudyOnboarding()
                }
            )
        )
    }

    var body: some View {
        ZStack {
            LoudnessMatchModalColors.background
                .ignoresSafeArea()

            orientationNavigation
                .accessibilityHidden(isInterruptionOverlayPresented)

            if let interruptionConfiguration {
                CalibratedAudioInterruptionOverlay(
                    systemName: interruptionConfiguration.systemName,
                    title: interruptionConfiguration.title,
                    bodyText: interruptionConfiguration.bodyText,
                    accessibilityIdentifier: interruptionConfiguration.accessibilityIdentifier,
                    quietRoomLevelRatio: interruptionConfiguration.quietRoomLevelRatio,
                    actionTitle: "Exit Orientation",
                    action: exitOrientation
                )
                .transition(.opacity)
                .zIndex(2)
            }
        }
        .foregroundStyle(LoudnessMatchModalColors.text)
        .interactiveDismissDisabled(true)
        .onChange(of: navigationPath) { oldPath, newPath in
            handleNavigationPathChange(from: oldPath, to: newPath)
        }
        .onChange(of: loudnessViewModel.isAirPodsRouteInterrupted) { _, isInterrupted in
            if !isInterrupted {
                resumeCurrentRouteAfterAirPodsReconnect()
            }
        }
        .onChange(of: loudnessViewModel.headphoneRouteAssessment) { _, assessment in
            returnToAirPodsConfirmationIfNeeded(for: assessment)
        }
        .onChange(of: thresholdCoordinator.presentation) { _, presentation in
            if presentation != nil {
                loudnessViewModel.stopVolumeGateMonitoring()
            }
        }
        .onChange(of: thresholdCoordinator.state) { _, state in
            handleThresholdStateChange(state)
        }
        .onDisappear {
            guard thresholdCoordinator.presentation == nil,
                  !isNoiseSuggestionsPresented
            else {
                return
            }
            cleanupForDismiss()
        }
        .fullScreenCover(item: researchKitPresentation) { presentation in
            ResearchKitTaskPresenterView(request: presentation.request) { summary in
                Task { @MainActor in
                    thresholdCoordinator.accept(summary, for: presentation)
                }
            }
            .interactiveDismissDisabled(true)
        }
        .fullScreenCover(isPresented: $isNoiseSuggestionsPresented) {
            LoudnessMatchNoiseSuggestionsView {
                isNoiseSuggestionsPresented = false
            }
        }
        .alert(
            "Unable to Continue",
            isPresented: generalErrorPresentation
        ) {
            Button("OK", role: .cancel, action: clearGeneralErrors)
        } message: {
            Text(generalErrorMessage)
        }
        .alert(
            "Unable to Complete Hearing Check",
            isPresented: preflightFailurePresentation
        ) {
            Button("Not Now", role: .cancel) {
                presentedPreflightFailure = nil
            }
            Button("Try Again") {
                presentedPreflightFailure = nil
                thresholdCoordinator.begin()
            }
        } message: {
            Text(presentedPreflightFailure?.message ?? "Please review the setup and try again.")
        }
        .alert("Exit Orientation?", isPresented: $isCloseConfirmationPresented) {
            Button("Keep Going", role: .cancel) {}
            Button("Exit Orientation", role: .destructive) {
                exitOrientation()
            }
        } message: {
            Text("Your current Study No. 1 onboarding progress will be discarded.")
        }
    }

    private var orientationNavigation: some View {
        NavigationStack(path: $navigationPath) {
            StudyOrientationPage(
                primaryAction: StudyOrientationPageAction(
                    title: "Continue",
                    isEnabled: viewModel.isAudiogramPrerequisiteMet,
                    action: advanceFromHearingTest
                ),
                requestClose: requestClose
            ) {
                StudyOrientationHearingTestView(viewModel: viewModel)
            }
            .navigationDestination(for: StudyTaskOrientationRoute.self) { route in
                orientationPage(for: route)
            }
        }
        .tint(LoudnessMatchModalColors.primary)
    }

    @ViewBuilder
    private func orientationPage(for route: StudyTaskOrientationRoute) -> some View {
        switch route {
        case .taskIntro:
            StudyOrientationPage(
                primaryAction: action(title: "Get Started", route: route),
                requestClose: requestClose
            ) {
                LoudnessMatchPreparationStepView(
                    step: .intro,
                    viewModel: loudnessViewModel,
                    showNoiseSuggestions: showNoiseSuggestions
                )
                .accessibilityIdentifier("study_onboarding_loudness_intro_step")
            }

        case .correctEar:
            StudyOrientationPage(
                primaryAction: action(
                    title: "Next",
                    isEnabled: loudnessViewModel.isCurrentAirPodsPro2PlaybackRouteConfirmed,
                    route: route
                ),
                requestClose: requestClose
            ) {
                preparationContent(for: .correctEar)
            }

        case .quietRoom:
            StudyOrientationPage(
                primaryAction: action(
                    title: "Next",
                    isEnabled: loudnessViewModel.environmentGateResult?.passed == true,
                    route: route
                ),
                requestClose: requestClose
            ) {
                preparationContent(for: .quietRoom)
            }

        case .fit:
            StudyOrientationPage(
                primaryAction: action(title: "Next", route: route),
                requestClose: requestClose
            ) {
                preparationContent(for: .fit)
            }

        case .maxVolume:
            StudyOrientationPage(
                primaryAction: action(
                    title: thresholdCoordinator.isPreparing ? "Starting" : "Start Test",
                    isEnabled: loudnessViewModel.currentGuardrailValidation.state == .passed
                        && !thresholdCoordinator.isPreparing,
                    isLoading: thresholdCoordinator.isPreparing,
                    route: route
                ),
                requestClose: requestClose
            ) {
                LoudnessMatchPreparationStepView(
                    step: .maxVolume,
                    viewModel: loudnessViewModel,
                    maxVolumeActionTitle: "Start Test",
                    showNoiseSuggestions: showNoiseSuggestions
                )
            }

        case .thresholdStatus:
            StudyOrientationPage(
                primaryAction: nil,
                requestClose: requestClose
            ) {
                StudyOrientationThresholdStatusView(
                    state: thresholdCoordinator.state,
                    retryFinalization: thresholdCoordinator.retryFinalization
                )
            }
            .navigationBarBackButtonHidden(true)
        }
    }

    private func preparationContent(for step: LoudnessMatchModalStep) -> some View {
        LoudnessMatchPreparationStepView(
            step: step,
            viewModel: loudnessViewModel,
            showNoiseSuggestions: showNoiseSuggestions
        )
    }

    private func action(
        title: String,
        isEnabled: Bool = true,
        isLoading: Bool = false,
        route: StudyTaskOrientationRoute
    ) -> StudyOrientationPageAction {
        StudyOrientationPageAction(
            title: title,
            isEnabled: isEnabled,
            isLoading: isLoading,
            action: { advance(from: route) }
        )
    }

    private func advanceFromHearingTest() {
        guard viewModel.isAudiogramPrerequisiteMet else {
            return
        }
        navigationPath.append(.taskIntro)
    }

    private func advance(from route: StudyTaskOrientationRoute) {
        guard route == navigationPath.last else {
            return
        }

        switch route {
        case .taskIntro:
            navigationPath.append(.correctEar)

        case .correctEar:
            guard loudnessViewModel.validateAirPodsForCorrectEarStep() else {
                return
            }
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
            thresholdCoordinator.begin()

        case .thresholdStatus:
            break
        }
    }

    private func handleNavigationPathChange(
        from oldPath: [StudyTaskOrientationRoute],
        to newPath: [StudyTaskOrientationRoute]
    ) {
        let oldRoute = oldPath.last
        let newRoute = newPath.last
        guard oldRoute != newRoute else {
            return
        }

        if newPath.count < oldPath.count {
            cleanupForNavigationPop(oldPath.dropFirst(newPath.count).reversed())
        }

        handleRouteEntered(newRoute)
    }

    private func cleanupForNavigationPop<Routes: Sequence>(_ poppedRoutes: Routes)
    where Routes.Element == StudyTaskOrientationRoute {
        if loudnessViewModel.isPlaying {
            loudnessViewModel.stopTone()
        }

        for route in poppedRoutes {
            switch route {
            case .correctEar:
                loudnessViewModel.stopHeadphoneRouteMonitoring()
            case .quietRoom:
                loudnessViewModel.cancelEnvironmentGate()
                loudnessViewModel.stopAirPodsContinuityMonitoring()
            case .maxVolume:
                thresholdCoordinator.stop()
                loudnessViewModel.stopVolumeGateMonitoring()
            case .taskIntro, .fit, .thresholdStatus:
                break
            }
        }
    }

    private func handleRouteEntered(_ route: StudyTaskOrientationRoute?) {
        switch route {
        case .correctEar:
            loudnessViewModel.stopAirPodsContinuityMonitoring()
            loudnessViewModel.stopVolumeGateMonitoring()
            loudnessViewModel.cancelEnvironmentGate()
            loudnessViewModel.startHeadphoneRouteMonitoring()

        case .quietRoom:
            loudnessViewModel.stopHeadphoneRouteMonitoring()
            loudnessViewModel.startAirPodsContinuityMonitoring()
            if loudnessViewModel.environmentGateResult?.passed != true {
                loudnessViewModel.startContinuousEnvironmentGate()
            }

        case .maxVolume:
            loudnessViewModel.stopHeadphoneRouteMonitoring()
            loudnessViewModel.startVolumeGateMonitoring()

        case nil, .taskIntro, .fit, .thresholdStatus:
            break
        }
    }

    private func handleThresholdStateChange(
        _ state: StudyOrientationThresholdCoordinator.State
    ) {
        switch state {
        case .submitting, .finalizing, .finalizationFailure:
            if case .finalizationFailure = state {
                viewModel.dismissTaskError()
            }
            if navigationPath.last != .thresholdStatus {
                navigationPath.append(.thresholdStatus)
            }

        case .preflightFailure(let failure):
            if navigationPath.last == .thresholdStatus {
                navigationPath.removeLast()
            }
            loudnessViewModel.startVolumeGateMonitoring()
            presentedPreflightFailure = failure

        case .completed:
            dismiss()

        case .idle, .preparing, .presentingResearchKit:
            break
        }
    }

    private func resumeCurrentRouteAfterAirPodsReconnect() {
        switch navigationPath.last {
        case .quietRoom:
            if loudnessViewModel.environmentGateResult?.passed != true {
                loudnessViewModel.startContinuousEnvironmentGate()
            }
        case .maxVolume:
            loudnessViewModel.startVolumeGateMonitoring()
        case nil, .taskIntro, .correctEar, .fit, .thresholdStatus:
            break
        }
    }

    private func returnToAirPodsConfirmationIfNeeded(
        for assessment: HeadphoneRouteAssessment
    ) {
        guard let currentRoute = navigationPath.last,
              currentRoute != .taskIntro,
              currentRoute != .correctEar,
              currentRoute != .thresholdStatus,
              assessment.isCompatibleBluetoothPlaybackRoute,
              !loudnessViewModel.isCurrentAirPodsPro2PlaybackRouteConfirmed
        else {
            return
        }

        navigationPath = [.taskIntro, .correctEar]
    }

    private var interruptionConfiguration: InterruptionConfiguration? {
        if shouldShowAirPodsInterruption {
            return InterruptionConfiguration(
                systemName: "airpodspro",
                title: airPodsInterruptionTitle,
                bodyText: airPodsInterruptionBodyText,
                accessibilityIdentifier: "study_onboarding_airpods_interruption_popup"
            )
        }

        if shouldShowQuietRoomInterruption {
            return InterruptionConfiguration(
                systemName: "ear.badge.waveform",
                title: "Find a Quiet Place",
                bodyText: "The room is too loud for this task. Onboarding will resume once the room is quiet enough.",
                accessibilityIdentifier: "study_onboarding_quiet_room_interruption_popup",
                quietRoomLevelRatio: quietRoomInterruptionLevelRatio
            )
        }

        return nil
    }

    private var shouldShowAirPodsInterruption: Bool {
        guard let route = navigationPath.last else {
            return false
        }
        return loudnessViewModel.isAirPodsRouteInterrupted
            && route != .taskIntro
            && route != .correctEar
            && route != .thresholdStatus
    }

    private var shouldShowQuietRoomInterruption: Bool {
        guard let route = navigationPath.last else {
            return false
        }
        return loudnessViewModel.isEnvironmentQuietnessInterrupted
            && route != .taskIntro
            && route != .correctEar
            && route != .quietRoom
            && route != .thresholdStatus
    }

    private var isInterruptionOverlayPresented: Bool {
        interruptionConfiguration != nil
    }

    private var isCurrentA2DPRouteUnconfirmed: Bool {
        loudnessViewModel.headphoneRouteAssessment.isCompatibleBluetoothPlaybackRoute
            && !loudnessViewModel.isCurrentAirPodsPro2PlaybackRouteConfirmed
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

    private var quietRoomInterruptionLevelRatio: Double {
        guard let latestSampleDBA = loudnessViewModel.environmentGateUpdate?.latestSampleDBA else {
            return 1.2
        }
        return latestSampleDBA / TinnitusEnvironmentSPLGateConfiguration.studyNo1.thresholdDBA
    }

    private var researchKitPresentation: Binding<StudyOrientationThresholdCoordinator.Presentation?> {
        Binding(
            get: { thresholdCoordinator.presentation },
            set: { presentation in
                guard presentation == nil,
                      let currentPresentation = thresholdCoordinator.presentation
                else {
                    return
                }
                thresholdCoordinator.presentationDismissed(currentPresentation)
            }
        )
    }

    private var generalErrorPresentation: Binding<Bool> {
        Binding(
            get: {
                loudnessViewModel.message != nil
                    || (viewModel.taskLoadErrorMessage != nil
                        && !isShowingThresholdStatus)
            },
            set: { shouldShow in
                if !shouldShow {
                    clearGeneralErrors()
                }
            }
        )
    }

    private var preflightFailurePresentation: Binding<Bool> {
        Binding(
            get: { presentedPreflightFailure != nil },
            set: { shouldShow in
                if !shouldShow {
                    presentedPreflightFailure = nil
                }
            }
        )
    }

    private var generalErrorMessage: String {
        if let dashboardMessage = viewModel.taskLoadErrorMessage {
            return dashboardMessage
        }
        return Self.message(for: loudnessViewModel.message)
    }

    private var isShowingThresholdStatus: Bool {
        switch thresholdCoordinator.state {
        case .submitting, .finalizing, .finalizationFailure:
            return true
        case .idle,
             .preparing,
             .presentingResearchKit,
             .preflightFailure,
             .completed:
            return false
        }
    }

    private func clearGeneralErrors() {
        loudnessViewModel.clearMessage()
        viewModel.dismissTaskError()
    }

    private func requestClose() {
        isCloseConfirmationPresented = true
    }

    private func exitOrientation() {
        cleanupForDismiss()
        dismiss()
    }

    private func showNoiseSuggestions() {
        isNoiseSuggestionsPresented = true
    }

    private func cleanupForDismiss() {
        thresholdCoordinator.stop()
        loudnessViewModel.stopHeadphoneRouteMonitoring()
        loudnessViewModel.stopAirPodsContinuityMonitoring()
        loudnessViewModel.cancelEnvironmentGate()
        loudnessViewModel.stopVolumeGateMonitoring()
        if loudnessViewModel.isPlaying {
            loudnessViewModel.stopTone()
        }
    }

    private static func message(
        for message: LoudnessMatchTaskFlowViewModel.FlowMessage?
    ) -> String {
        switch message {
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
        case .missingAudiogramThreshold(let message),
             .missingPreflight(let message),
             .incompletePayload(let message),
             .environmentGateUnavailable(let message),
             .playbackFailed(let message),
             .submissionFailed(let message):
            return message
        case .guardrailsUnavailable:
            return "Audio guardrails are missing, failed, or require restart."
        case nil:
            return ""
        }
    }
}

private struct StudyOrientationPageAction {
    let title: String
    var isEnabled = true
    var isLoading = false
    let action: () -> Void
}

private struct StudyOrientationPage<Content: View>: View {
    let primaryAction: StudyOrientationPageAction?
    let requestClose: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: max(0, proxy.size.height - 48), alignment: .top)
                    .padding(.horizontal, 34)
                    .padding(.vertical, 24)
            }
        }
        .background(LoudnessMatchModalColors.background)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let primaryAction {
                LoudnessMatchModalPrimaryButton(
                    title: primaryAction.title,
                    isEnabled: primaryAction.isEnabled,
                    isLoading: primaryAction.isLoading,
                    action: primaryAction.action
                )
                .accessibilityIdentifier("study_onboarding_primary_button")
                .padding(.horizontal, 34)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
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
}

private struct InterruptionConfiguration {
    let systemName: String
    let title: String
    let bodyText: String
    let accessibilityIdentifier: String
    var quietRoomLevelRatio: Double?
}
