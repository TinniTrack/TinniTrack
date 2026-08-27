import SwiftUI

struct StudyTaskOrientationSheet: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var viewModel: StudyTaskDashboardViewModel

    @StateObject private var loudnessViewModel: LoudnessMatchTaskFlowViewModel
    @StateObject private var preflightSession: CalibratedAudioPreflightSession
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
        .onChange(of: preflightSession.requestedFallback) { _, fallback in
            guard fallback == .airPods else {
                return
            }
            navigationPath = [.taskIntro, .correctEar]
            preflightSession.consumeRequestedFallback()
        }
        .onChange(of: thresholdCoordinator.presentation) { _, presentation in
            if presentation != nil {
                preflightSession.transition(to: .activeTest)
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
                    isEnabled: preflightSession.canCommitCurrentPhase,
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
                    isEnabled: preflightSession.canCommitCurrentPhase,
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
                    isEnabled: preflightSession.canCommitCurrentPhase
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

        case .thresholdStatus:
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
                || poppedRoutes.contains(.thresholdStatus) {
                thresholdCoordinator.stop()
            }
            if loudnessViewModel.isPlaying {
                loudnessViewModel.stopTone()
            }
        }

        preflightSession.transition(to: preflightPhase(for: newPath.last))
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
            preflightSession.transition(to: .maximumVolume)
            presentedPreflightFailure = failure

        case .completed:
            dismiss()

        case .idle, .preparing, .presentingResearchKit:
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
        case .thresholdStatus:
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
        preflightSession.clearMessage()
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
        preflightSession.stop()
        if loudnessViewModel.isPlaying {
            loudnessViewModel.stopTone()
        }
    }
}

private enum StudyTaskOrientationRoute: Hashable {
    case taskIntro
    case correctEar
    case quietRoom
    case fit
    case maxVolume
    case thresholdStatus
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
