import SwiftUI

struct StudyTaskOrientationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @ObservedObject var viewModel: StudyTaskDashboardViewModel

    @StateObject private var loudnessViewModel: LoudnessMatchTaskFlowViewModel
    @StateObject private var preflightSession: CalibratedAudioPreflightSession
    @StateObject private var thresholdCoordinator: StudyOrientationThresholdCoordinator
    @StateObject private var thresholdTestSession: StudyOrientationThresholdTestSession
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
        _preflightSession = StateObject(
            wrappedValue: CalibratedAudioPreflightSession(controller: resolvedLoudnessViewModel)
        )
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
        _thresholdTestSession = StateObject(
            wrappedValue: StudyOrientationThresholdTestSession(
                playTone: { stimulus, duration in
                    try await resolvedLoudnessViewModel.playOrientationThresholdTone(
                        stimulus,
                        duration: duration
                    )
                },
                stopTone: {
                    resolvedLoudnessViewModel.stopOrientationThresholdTone()
                },
                outputVolume: {
                    resolvedLoudnessViewModel.orientationThresholdOutputVolume
                }
            )
        )
    }

    var body: some View {
        closeConfirmationContent
    }

    private var closeConfirmationContent: some View {
        preflightFailureAlertContent
            .alert("Exit Orientation?", isPresented: $isCloseConfirmationPresented) {
                Button("Keep Going", role: .cancel) {
                    resumeThresholdTestIfReady()
                }
                Button("Exit Orientation", role: .destructive) {
                    exitOrientation()
                }
            } message: {
                Text("Your current Study No. 1 onboarding progress will be discarded.")
            }
    }

    private var preflightFailureAlertContent: some View {
        generalAlertContent
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
    }

    private var generalAlertContent: some View {
        modalContent
            .alert(
                "Unable to Continue",
                isPresented: generalErrorPresentation
            ) {
                Button("OK", role: .cancel, action: clearGeneralErrors)
            } message: {
                Text(generalErrorMessage)
            }
    }

    private var modalContent: some View {
        lifecycleContent
            .fullScreenCover(isPresented: $isNoiseSuggestionsPresented) {
                LoudnessMatchNoiseSuggestionsView {
                    isNoiseSuggestionsPresented = false
                }
            }
    }

    private var lifecycleContent: some View {
        orientationContent
            .foregroundStyle(StudyTestColors.text)
            .interactiveDismissDisabled(true)
            .onChange(of: navigationPath) { oldPath, newPath in
                handleNavigationPathChange(from: oldPath, to: newPath)
            }
            .onChange(of: preflightSession.requestedFallback) { _, fallback in
                handleRequestedFallback(fallback)
            }
            .onChange(of: thresholdCoordinator.state) { _, state in
                handleThresholdStateChange(state)
            }
            .onChange(of: isInterruptionOverlayPresented) { _, isPresented in
                updateThresholdPlaybackForPresentationChange(isPaused: isPresented)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    loudnessViewModel.resumeEnvironmentGateAfterAppActivity()
                } else {
                    loudnessViewModel.suspendEnvironmentGateForAppInactivity()
                }
                updateThresholdPlaybackForPresentationChange(isPaused: phase != .active)
            }
            .onChange(of: isCloseConfirmationPresented) { _, isPresented in
                updateThresholdPlaybackForPresentationChange(isPaused: isPresented)
            }
            .onDisappear(perform: handleSheetDisappear)
    }

    private var orientationContent: some View {
        ZStack {
            StudyTestColors.background
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
    }

    private var orientationNavigation: some View {
        NavigationStack(path: $navigationPath) {
            StudyTestPage(
                navigationTitle: "Orientation",
                closeAction: orientationCloseAction,
                primaryAction: StudyTestPageAction(
                    title: "Continue",
                    isEnabled: viewModel.isAudiogramPrerequisiteMet,
                    accessibilityIdentifier: "study_onboarding_primary_button",
                    action: advanceFromHearingTest
                )
            ) {
                StudyOrientationHearingTestView(viewModel: viewModel)
            }
            .navigationDestination(for: StudyTaskOrientationRoute.self) { route in
                orientationPage(for: route)
            }
        }
        .tint(StudyTestColors.accent)
    }

    @ViewBuilder
    private func orientationPage(for route: StudyTaskOrientationRoute) -> some View {
        switch route {
        case .taskIntro:
            StudyTestPage(
                navigationTitle: "Orientation",
                closeAction: orientationCloseAction,
                primaryAction: action(title: "Get Started", route: route)
            ) {
                LoudnessMatchPreparationStepView(
                    step: .intro,
                    viewModel: loudnessViewModel,
                    showNoiseSuggestions: showNoiseSuggestions
                )
                .accessibilityIdentifier("study_onboarding_loudness_intro_step")
            }

        case .correctEar:
            StudyTestPage(
                navigationTitle: "Orientation",
                closeAction: orientationCloseAction,
                primaryAction: action(
                    title: "Next",
                    isEnabled: preflightSession.canCommitCurrentPhase,
                    route: route
                )
            ) {
                preparationContent(for: .correctEar)
            }

        case .quietRoom:
            StudyTestPage(
                navigationTitle: "Orientation",
                closeAction: orientationCloseAction,
                primaryAction: action(
                    title: "Next",
                    isEnabled: preflightSession.canCommitCurrentPhase,
                    route: route
                )
            ) {
                preparationContent(for: .quietRoom)
            }

        case .fit:
            StudyTestPage(
                navigationTitle: "Orientation",
                closeAction: orientationCloseAction,
                primaryAction: action(title: "Next", route: route)
            ) {
                preparationContent(for: .fit)
            }

        case .maxVolume:
            StudyTestPage(
                navigationTitle: "Orientation",
                closeAction: orientationCloseAction,
                primaryAction: action(
                    title: thresholdCoordinator.isPreparing ? "Starting" : "Start Test",
                    isEnabled: preflightSession.canCommitCurrentPhase
                        && !thresholdCoordinator.isPreparing,
                    isLoading: thresholdCoordinator.isPreparing,
                    route: route
                )
            ) {
                LoudnessMatchPreparationStepView(
                    step: .maxVolume,
                    viewModel: loudnessViewModel,
                    maxVolumeActionTitle: "Start Test",
                    showNoiseSuggestions: showNoiseSuggestions
                )
            }

        case .thresholdTest:
            StudyOrientationThresholdTestView(
                session: thresholdTestSession,
                requestClose: requestClose,
                complete: thresholdCoordinator.submit
            )

        case .thresholdStatus:
            StudyTestPage(
                navigationTitle: "Orientation",
                closeAction: orientationCloseAction
            ) {
                StudyOrientationThresholdStatusView(
                    state: thresholdCoordinator.state,
                    retrySubmission: thresholdCoordinator.retrySubmission,
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
    ) -> StudyTestPageAction {
        StudyTestPageAction(
            title: title,
            isEnabled: isEnabled,
            isLoading: isLoading,
            accessibilityIdentifier: "study_onboarding_primary_button",
            action: { advance(from: route) }
        )
    }

    private var orientationCloseAction: StudyTestCloseAction {
        StudyTestCloseAction(
            accessibilityIdentifier: "study_onboarding_close_button",
            action: requestClose
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
            guard preflightSession.commitCurrentPhase() else { return }
            navigationPath.append(.quietRoom)

        case .quietRoom:
            guard preflightSession.commitCurrentPhase() else { return }
            navigationPath.append(.fit)

        case .fit:
            guard preflightSession.commitCurrentPhase() else { return }
            navigationPath.append(.maxVolume)

        case .maxVolume:
            guard preflightSession.commitCurrentPhase() else { return }
            thresholdCoordinator.begin()

        case .thresholdTest, .thresholdStatus:
            break
        }
    }

    private func handleNavigationPathChange(
        from oldPath: [StudyTaskOrientationRoute],
        to newPath: [StudyTaskOrientationRoute]
    ) {
        guard oldPath.last != newPath.last else {
            return
        }

        if newPath.count < oldPath.count {
            let poppedRoutes = oldPath.dropFirst(newPath.count)
            if poppedRoutes.contains(.maxVolume)
                || poppedRoutes.contains(.thresholdTest)
                || poppedRoutes.contains(.thresholdStatus) {
                thresholdCoordinator.stop()
                thresholdTestSession.stop()
            }
            if loudnessViewModel.isPlaying {
                loudnessViewModel.stopTone()
            }
        }

        preflightSession.transition(to: preflightPhase(for: newPath.last))
    }

    private func handleRequestedFallback(
        _ fallback: CalibratedAudioPreflightSession.Phase?
    ) {
        guard fallback == .airPods else {
            return
        }
        navigationPath = [.taskIntro, .correctEar]
        preflightSession.consumeRequestedFallback()
    }

    private func handleThresholdStateChange(
        _ state: StudyOrientationThresholdCoordinator.State
    ) {
        switch state {
        case .readyForTest:
            preflightSession.transition(to: .activeTest)
            if navigationPath.last != .thresholdTest {
                navigationPath.append(.thresholdTest)
            }

        case .submitting, .submissionFailure, .finalizing, .finalizationFailure:
            if case .finalizationFailure = state {
                viewModel.dismissTaskError()
            }
            thresholdTestSession.pause()
            if navigationPath.last != .thresholdStatus {
                navigationPath.append(.thresholdStatus)
            }

        case .preflightFailure(let failure):
            thresholdTestSession.stop()
            navigationPath.removeAll { route in
                route == .thresholdTest || route == .thresholdStatus
            }
            preflightSession.transition(to: .maximumVolume)
            presentedPreflightFailure = failure

        case .completed:
            dismiss()

        case .idle, .preparing:
            break
        }
    }

    private func preflightPhase(
        for route: StudyTaskOrientationRoute?
    ) -> CalibratedAudioPreflightSession.Phase? {
        switch route {
        case .correctEar:
            return .airPods
        case .quietRoom:
            return .quietRoom
        case .fit:
            return .fit
        case .maxVolume:
            return .maximumVolume
        case .thresholdTest, .thresholdStatus:
            return .activeTest
        case nil, .taskIntro:
            return nil
        }
    }

    private var interruptionConfiguration: InterruptionConfiguration? {
        guard navigationPath.last != .thresholdStatus else {
            return nil
        }

        switch preflightSession.interruption {
        case .airPods(let routeUnconfirmed, let blockedByAnotherApp):
            return InterruptionConfiguration(
                systemName: "airpodspro",
                title: airPodsInterruptionTitle(
                    routeUnconfirmed: routeUnconfirmed,
                    blockedByAnotherApp: blockedByAnotherApp
                ),
                bodyText: airPodsInterruptionBodyText(
                    routeUnconfirmed: routeUnconfirmed,
                    blockedByAnotherApp: blockedByAnotherApp
                ),
                accessibilityIdentifier: "study_onboarding_airpods_interruption_popup"
            )

        case .quietRoom(let levelRatio):
            return InterruptionConfiguration(
                systemName: "ear.badge.waveform",
                title: "Find a Quiet Place",
                bodyText: "The room is too loud for this task. Onboarding will resume once the room is quiet enough.",
                accessibilityIdentifier: "study_onboarding_quiet_room_interruption_popup",
                quietRoomLevelRatio: levelRatio
            )

        case nil:
            return nil
        }
    }

    private var isInterruptionOverlayPresented: Bool {
        interruptionConfiguration != nil
    }

    private func airPodsInterruptionTitle(
        routeUnconfirmed: Bool,
        blockedByAnotherApp: Bool
    ) -> String {
        if routeUnconfirmed {
            return "AirPods Output Changed"
        }
        return blockedByAnotherApp
            ? "Calibrated Audio Blocked"
            : "Reconnect Your AirPods"
    }

    private func airPodsInterruptionBodyText(
        routeUnconfirmed: Bool,
        blockedByAnotherApp: Bool
    ) -> String {
        if routeUnconfirmed {
            return "The audio output changed after confirmation. Confirm the current AirPods again before continuing."
        }
        if blockedByAnotherApp {
            return "Another app is using your AirPods for call audio. Close Phone, Zoom, or other apps that may be using the headphones. Onboarding will resume once AirPods return to calibrated playback."
        }
        return "Please put both AirPods in your ears and reconnect to continue onboarding."
    }

    private var generalErrorPresentation: Binding<Bool> {
        Binding(
            get: {
                preflightSession.participantMessage != nil
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
        return preflightSession.participantMessage ?? ""
    }

    private var isShowingThresholdStatus: Bool {
        switch thresholdCoordinator.state {
        case .submitting, .submissionFailure, .finalizing, .finalizationFailure:
            return true
        case .idle,
             .preparing,
             .readyForTest,
             .preflightFailure,
             .completed:
            return false
        }
    }

    private func clearGeneralErrors() {
        preflightSession.clearMessage()
        viewModel.dismissTaskError()
    }

    private func handleSheetDisappear() {
        guard !isNoiseSuggestionsPresented else {
            return
        }
        cleanupForDismiss()
    }

    private func requestClose() {
        if navigationPath.last == .thresholdTest {
            thresholdTestSession.pause()
        }
        isCloseConfirmationPresented = true
    }

    private func updateThresholdPlaybackForPresentationChange(isPaused: Bool) {
        guard navigationPath.last == .thresholdTest else {
            return
        }
        if isPaused {
            thresholdTestSession.pause()
        } else {
            resumeThresholdTestIfReady()
        }
    }

    private func resumeThresholdTestIfReady() {
        guard navigationPath.last == .thresholdTest,
              scenePhase == .active,
              !isCloseConfirmationPresented,
              !isInterruptionOverlayPresented
        else {
            return
        }
        thresholdTestSession.resume()
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
        thresholdTestSession.stop()
        preflightSession.stop()
        loudnessViewModel.stopOrientationThresholdTone()
    }
}

private enum StudyTaskOrientationRoute: Hashable {
    case taskIntro
    case correctEar
    case quietRoom
    case fit
    case maxVolume
    case thresholdTest
    case thresholdStatus
}

private struct InterruptionConfiguration {
    let systemName: String
    let title: String
    let bodyText: String
    let accessibilityIdentifier: String
    var quietRoomLevelRatio: Double?
}
