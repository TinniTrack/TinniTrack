import SwiftUI

struct LoudnessMatchTaskModalFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    let scheduledTask: ScheduledTask
    let enrollment: StudyEnrollment
    let studyService: StudyServiceProtocol
    let onSubmitted: () -> Void

    @StateObject private var viewModel: LoudnessMatchTaskFlowViewModel
    @StateObject private var preflightSession: CalibratedAudioPreflightSession
    @State private var navigationPath: [LoudnessMatchTaskRoute] = []
    @State private var selectedLaterality: TinnitusLaterality?
    @State private var isCloseConfirmationPresented = false
    @State private var isNoiseSuggestionsPresented = false
    @State private var startLoudnessMatchTask: Task<Void, Never>?
    @State private var startLoudnessMatchGeneration: UUID?

    init(
        scheduledTask: ScheduledTask,
        enrollment: StudyEnrollment,
        studyService: StudyServiceProtocol,
        viewModel: LoudnessMatchTaskFlowViewModel? = nil,
        onSubmitted: @escaping () -> Void
    ) {
        let resolvedViewModel = viewModel ?? LoudnessMatchTaskFlowViewModel()
        self.scheduledTask = scheduledTask
        self.enrollment = enrollment
        self.studyService = studyService
        self.onSubmitted = onSubmitted
        _viewModel = StateObject(wrappedValue: resolvedViewModel)
        _preflightSession = StateObject(
            wrappedValue: CalibratedAudioPreflightSession(controller: resolvedViewModel)
        )
    }

    var body: some View {
        ZStack {
            StudyTestColors.background
                .ignoresSafeArea()

            taskNavigation
                .accessibilityHidden(isInterruptionOverlayPresented)

            if let interruptionConfiguration {
                CalibratedAudioInterruptionOverlay(
                    systemName: interruptionConfiguration.systemName,
                    title: interruptionConfiguration.title,
                    bodyText: interruptionConfiguration.bodyText,
                    accessibilityIdentifier: interruptionConfiguration.accessibilityIdentifier,
                    quietRoomLevelRatio: interruptionConfiguration.quietRoomLevelRatio,
                    actionTitle: "Exit Task",
                    action: exitTask
                )
                .transition(.opacity)
                .zIndex(2)
            }
        }
        .foregroundStyle(StudyTestColors.text)
        .interactiveDismissDisabled(true)
        .onChange(of: navigationPath) { oldPath, newPath in
            handleNavigationPathChange(from: oldPath, to: newPath)
        }
        .onChange(of: preflightSession.requestedFallback) { _, fallback in
            handleRequestedFallback(fallback)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                viewModel.resumeEnvironmentGateAfterAppActivity()
            } else {
                viewModel.suspendEnvironmentGateForAppInactivity()
                if viewModel.isPlaying {
                    viewModel.stopTone()
                }
            }
        }
        .onDisappear {
            guard !isNoiseSuggestionsPresented else {
                return
            }
            cleanupForDismiss(abortActiveTest: false)
        }
        .fullScreenCover(isPresented: $isNoiseSuggestionsPresented) {
            LoudnessMatchNoiseSuggestionsView {
                isNoiseSuggestionsPresented = false
            }
        }
        .alert(
            "Unable to Continue",
            isPresented: participantMessagePresentation
        ) {
            Button("OK", role: .cancel, action: preflightSession.clearMessage)
        } message: {
            Text(preflightSession.participantMessage ?? "")
        }
        .alert(closeConfirmationTitle, isPresented: $isCloseConfirmationPresented) {
            Button(hasStartedTest ? "Keep Testing" : "Keep Going", role: .cancel) {}
            Button(hasStartedTest ? "Stop Test" : "Exit Task", role: .destructive) {
                cleanupForDismiss(abortActiveTest: hasStartedTest)
                dismiss()
            }
        } message: {
            Text("Your current loudness-match progress will be discarded.")
        }
    }

    private var taskNavigation: some View {
        NavigationStack(path: $navigationPath) {
            preparationPage(for: .intro)
                .navigationDestination(for: LoudnessMatchTaskRoute.self) { route in
                    switch route {
                    case .activeTest:
                        activeTestPage
                    case .correctEar, .quietRoom, .fit, .maxVolume, .tinnitusLocation:
                        if let step = route.preparationStep {
                            preparationPage(for: step)
                        }
                    }
                }
        }
        .tint(StudyTestColors.accent)
    }

    private func preparationPage(for step: LoudnessMatchModalStep) -> some View {
        StudyTestPage(
            navigationTitle: "Loudness Match",
            closeAction: closeAction,
            primaryAction: StudyTestPageAction(
                title: primaryButtonTitle(for: step),
                isEnabled: isPrimaryButtonEnabled(for: step),
                isLoading: step == .tinnitusLocation && startLoudnessMatchTask != nil,
                accessibilityIdentifier: "loudness_modal_primary_button",
                action: { advance(from: step) }
            )
        ) {
            LoudnessMatchPreparationStepView(
                step: step,
                viewModel: viewModel,
                selectedLaterality: selectedLaterality,
                showNoiseSuggestions: showNoiseSuggestions,
                selectLaterality: selectLaterality
            )
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var activeTestPage: some View {
        StudyTestPage(
            navigationTitle: "Loudness Match",
            closeAction: closeAction,
            primaryAction: activeTestPrimaryAction
        ) {
            LoudnessMatchActiveTestView(viewModel: viewModel)
        }
        .navigationBarBackButtonHidden(true)
    }

    private var activeTestPrimaryAction: StudyTestPageAction? {
        switch viewModel.protocolState {
        case .readyForTrial:
            return StudyTestPageAction(
                title: "Same Loudness",
                isEnabled: viewModel.preflightReady,
                accessibilityLabel: "Same loudness",
                accessibilityHint: "Accepts the current tone level and continues to confidence rating.",
                accessibilityIdentifier: "loudness_modal_primary_button",
                action: viewModel.acceptCurrentLevel
            )

        case .completed:
            return StudyTestPageAction(
                title: viewModel.isSubmitting ? "Submitting" : "Submit",
                isEnabled: viewModel.canSubmit,
                isLoading: viewModel.isSubmitting,
                accessibilityIdentifier: "loudness_modal_primary_button",
                action: submitCompletedRun
            )

        case .collectingLaterality,
             .awaitingThreshold,
             .awaitingConfidence,
             .aborted,
             .restartRequired:
            return nil
        }
    }

    private var closeAction: StudyTestCloseAction {
        StudyTestCloseAction(
            accessibilityIdentifier: "loudness_modal_close_button",
            action: requestClose
        )
    }

    private func primaryButtonTitle(for step: LoudnessMatchModalStep) -> String {
        switch step {
        case .intro:
            return "Get Started"
        case .correctEar:
            return viewModel.isCurrentAirPodsPro2PlaybackRouteConfirmed
                ? "Continue"
                : "Confirm AirPods Pro 2"
        case .quietRoom, .fit:
            return "Next"
        case .maxVolume:
            return "Continue"
        case .tinnitusLocation:
            return startLoudnessMatchTask == nil ? "Start Test" : "Starting"
        }
    }

    private func isPrimaryButtonEnabled(for step: LoudnessMatchModalStep) -> Bool {
        switch step {
        case .intro:
            return true
        case .correctEar:
            return viewModel.headphoneRouteAssessment
                .isAirPodsProPlaybackRouteCandidate
        case .quietRoom, .fit, .maxVolume:
            return preflightSession.canCommitCurrentPhase
        case .tinnitusLocation:
            return selectedLaterality != nil
                && !viewModel.isResolvingAudiogramThreshold
                && startLoudnessMatchTask == nil
                && viewModel.preflightReady
        }
    }

    private func advance(from step: LoudnessMatchModalStep) {
        guard step == currentPreparationStep else {
            return
        }

        switch step {
        case .intro:
            navigationPath.append(.correctEar)

        case .correctEar:
            if !viewModel.isCurrentAirPodsPro2PlaybackRouteConfirmed {
                viewModel.setAirPodsPro2ConfirmedForCurrentRoute(true)
            }
            guard preflightSession.commitCurrentPhase() else {
                return
            }
            navigationPath.append(.quietRoom)

        case .quietRoom:
            guard preflightSession.commitCurrentPhase() else {
                return
            }
            navigationPath.append(.fit)

        case .fit:
            guard preflightSession.commitCurrentPhase() else {
                return
            }
            navigationPath.append(.maxVolume)

        case .maxVolume:
            guard preflightSession.commitCurrentPhase() else {
                return
            }
            selectedLaterality = viewModel.selectedLaterality ?? selectedLaterality
            navigationPath.append(.tinnitusLocation)

        case .tinnitusLocation:
            guard preflightSession.commitCurrentPhase(),
                  let selectedLaterality
            else {
                return
            }
            startLoudnessMatch(for: selectedLaterality)
        }
    }

    private func startLoudnessMatch(for laterality: TinnitusLaterality) {
        guard startLoudnessMatchTask == nil else {
            return
        }

        let generation = UUID()
        startLoudnessMatchGeneration = generation
        startLoudnessMatchTask = Task { @MainActor in
            let didStart = await viewModel.startLoudnessMatch(laterality: laterality)
            guard !Task.isCancelled,
                  startLoudnessMatchGeneration == generation,
                  currentPreparationStep == .tinnitusLocation,
                  viewModel.preflightReady,
                  viewModel.isCurrentAirPodsPro2PlaybackRouteConfirmed,
                  !viewModel.isAirPodsRouteInterrupted,
                  didStart
            else {
                clearStartTaskIfCurrent(generation)
                return
            }

            preflightSession.transition(to: .activeTest)
            clearStartTaskIfCurrent(generation)
            navigationPath.append(.activeTest)
        }
    }

    private func submitCompletedRun() {
        Task { @MainActor in
            await viewModel.submitCompletedRun(
                scheduledTask: scheduledTask,
                enrollment: enrollment,
                studyService: studyService
            )
            if viewModel.hasSubmitted {
                onSubmitted()
                dismiss()
            }
        }
    }

    private func handleNavigationPathChange(
        from oldPath: [LoudnessMatchTaskRoute],
        to newPath: [LoudnessMatchTaskRoute]
    ) {
        let oldRoute = oldPath.last
        let newRoute = newPath.last
        guard oldRoute != newRoute else {
            return
        }

        if oldRoute == .tinnitusLocation,
           newRoute != .tinnitusLocation,
           newRoute != .activeTest {
            cancelStartLoudnessMatch()
        }

        if oldRoute == .activeTest, newRoute != .activeTest {
            viewModel.abort()
        } else if newPath.count < oldPath.count, viewModel.isPlaying {
            viewModel.stopTone()
        }

        preflightSession.transition(to: phase(for: newRoute))
    }

    private func handleRequestedFallback(
        _ fallback: CalibratedAudioPreflightSession.Phase?
    ) {
        guard fallback == .airPods else {
            return
        }

        cancelStartLoudnessMatch()
        if navigationPath.last == .activeTest {
            viewModel.abort()
        }
        navigationPath = [.correctEar]
        preflightSession.consumeRequestedFallback()
    }

    private func phase(
        for route: LoudnessMatchTaskRoute?
    ) -> CalibratedAudioPreflightSession.Phase? {
        guard let route else {
            return nil
        }

        switch route {
        case .correctEar:
            return .airPods
        case .quietRoom:
            return .quietRoom
        case .fit:
            return .fit
        case .maxVolume:
            return .maximumVolume
        case .tinnitusLocation:
            return .postPreflight
        case .activeTest:
            return .activeTest
        }
    }

    private var currentPreparationStep: LoudnessMatchModalStep? {
        guard let route = navigationPath.last else {
            return .intro
        }
        return route.preparationStep
    }

    private var participantMessagePresentation: Binding<Bool> {
        Binding(
            get: { preflightSession.participantMessage != nil },
            set: { isPresented in
                if !isPresented {
                    preflightSession.clearMessage()
                }
            }
        )
    }

    private var interruptionConfiguration: LoudnessMatchInterruptionConfiguration? {
        switch preflightSession.interruption {
        case .airPods(let routeUnconfirmed, let blockedByAnotherApp):
            if routeUnconfirmed {
                return LoudnessMatchInterruptionConfiguration(
                    systemName: "airpodspro",
                    title: "AirPods Output Changed",
                    bodyText: "The audio output changed after confirmation. Exit and restart this task to confirm the current AirPods before continuing.",
                    accessibilityIdentifier: "loudness_airpods_interruption_popup"
                )
            }

            return LoudnessMatchInterruptionConfiguration(
                systemName: "airpodspro",
                title: blockedByAnotherApp ? "Calibrated Audio Blocked" : "Reconnect Your AirPods",
                bodyText: blockedByAnotherApp
                    ? "Another app is using your AirPods for call audio. Close Phone, Zoom, or other apps that may be using the headphones. The task will resume once AirPods return to calibrated playback."
                    : "Please put both AirPods in your ears and reconnect to continue the task. The task will automatically resume once your AirPods are connected and in both ears.",
                accessibilityIdentifier: "loudness_airpods_interruption_popup"
            )

        case .quietRoom(let levelRatio):
            return LoudnessMatchInterruptionConfiguration(
                systemName: "ear.badge.waveform",
                title: "Find a quiet place",
                bodyText: "The room is too loud for this task. The task will automatically resume once the room is quiet enough.",
                accessibilityIdentifier: "loudness_quiet_room_interruption_popup",
                quietRoomLevelRatio: levelRatio
            )

        case nil:
            return nil
        }
    }

    private var isInterruptionOverlayPresented: Bool {
        interruptionConfiguration != nil
    }

    private var hasStartedTest: Bool {
        navigationPath.last == .activeTest || viewModel.events.count > 1
    }

    private func selectLaterality(_ laterality: TinnitusLaterality) {
        selectedLaterality = laterality
    }

    private func showNoiseSuggestions() {
        isNoiseSuggestionsPresented = true
    }

    private func requestClose() {
        if navigationPath.last == .activeTest, viewModel.isPlaying {
            viewModel.stopTone()
        }
        isCloseConfirmationPresented = true
    }

    private var closeConfirmationTitle: String {
        hasStartedTest ? "Stop this test?" : "Exit this task?"
    }

    private func exitTask() {
        cleanupForDismiss(abortActiveTest: hasStartedTest)
        dismiss()
    }

    private func cancelStartLoudnessMatch() {
        startLoudnessMatchGeneration = nil
        startLoudnessMatchTask?.cancel()
        startLoudnessMatchTask = nil
    }

    private func clearStartTaskIfCurrent(_ generation: UUID) {
        guard startLoudnessMatchGeneration == generation else {
            return
        }
        startLoudnessMatchGeneration = nil
        startLoudnessMatchTask = nil
    }

    private func cleanupForDismiss(abortActiveTest: Bool) {
        cancelStartLoudnessMatch()

        if abortActiveTest {
            viewModel.abort()
        } else if viewModel.isPlaying {
            viewModel.stopTone()
        }

        preflightSession.stop()
    }
}

private enum LoudnessMatchTaskRoute: Hashable {
    case correctEar
    case quietRoom
    case fit
    case maxVolume
    case tinnitusLocation
    case activeTest

    var preparationStep: LoudnessMatchModalStep? {
        switch self {
        case .correctEar:
            return .correctEar
        case .quietRoom:
            return .quietRoom
        case .fit:
            return .fit
        case .maxVolume:
            return .maxVolume
        case .tinnitusLocation:
            return .tinnitusLocation
        case .activeTest:
            return nil
        }
    }
}

private struct LoudnessMatchInterruptionConfiguration {
    let systemName: String
    let title: String
    let bodyText: String
    let accessibilityIdentifier: String
    var quietRoomLevelRatio: Double? = nil
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
