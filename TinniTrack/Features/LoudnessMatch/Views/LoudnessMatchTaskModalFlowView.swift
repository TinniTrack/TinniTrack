import SwiftUI

struct LoudnessMatchTaskModalFlowView: View {
    @Environment(\.dismiss) private var dismiss

    let scheduledTask: ScheduledTask
    let enrollment: StudyEnrollment
    let studyService: StudyServiceProtocol
    let onSubmitted: () -> Void

    @StateObject private var viewModel: LoudnessMatchTaskFlowViewModel
    @StateObject private var preflightSession: CalibratedAudioPreflightSession
    @State private var navigationPath: [LoudnessMatchPreparationRoute] = []
    @State private var selectedLaterality: TinnitusLaterality?
    @State private var isActiveTestPresented = false
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
        ZStack(alignment: .top) {
            LoudnessMatchModalColors.background
                .ignoresSafeArea()

            if isActiveTestPresented {
                activeTestContent
                    .accessibilityHidden(isInterruptionOverlayPresented)

                activeTestCloseControl
                    .accessibilityHidden(isInterruptionOverlayPresented)
            } else {
                preparationNavigation
                    .accessibilityHidden(isInterruptionOverlayPresented)
            }

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
        .foregroundStyle(LoudnessMatchModalColors.text)
        .interactiveDismissDisabled(true)
        .onChange(of: navigationPath) { oldPath, newPath in
            handleNavigationPathChange(from: oldPath, to: newPath)
        }
        .onChange(of: preflightSession.requestedFallback) { _, fallback in
            handleRequestedFallback(fallback)
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

    private var preparationNavigation: some View {
        NavigationStack(path: $navigationPath) {
            preparationPage(for: .intro)
                .navigationDestination(for: LoudnessMatchPreparationRoute.self) { route in
                    preparationPage(for: route.step)
                }
        }
        .tint(LoudnessMatchModalColors.primary)
    }

    private var activeTestContent: some View {
        LoudnessMatchActiveTestView(
            viewModel: viewModel,
            scheduledTask: scheduledTask,
            enrollment: enrollment,
            studyService: studyService
        ) { @MainActor in
            onSubmitted()
            dismiss()
        }
    }

    private var activeTestCloseControl: some View {
        HStack {
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

    private func preparationPage(for step: LoudnessMatchModalStep) -> some View {
        LoudnessMatchModalContentLayout {
            LoudnessMatchPreparationStepView(
                step: step,
                viewModel: viewModel,
                selectedLaterality: selectedLaterality,
                showNoiseSuggestions: showNoiseSuggestions,
                selectLaterality: selectLaterality
            )
        } footer: {
            LoudnessMatchModalPrimaryButton(
                title: primaryButtonTitle(for: step),
                isEnabled: isPrimaryButtonEnabled(for: step)
            ) {
                advance(from: step)
            }
        }
        .background(LoudnessMatchModalColors.background)
        .navigationTitle("Loudness Match")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: requestClose) {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("Close")
                .accessibilityIdentifier("loudness_modal_close_button")
            }
        }
    }

    private func primaryButtonTitle(for step: LoudnessMatchModalStep) -> String {
        switch step {
        case .intro:
            return "Get Started"
        case .correctEar, .quietRoom, .fit:
            return "Next"
        case .maxVolume:
            return "Continue"
        case .tinnitusLocation:
            return "Start Test"
        case .activeTest:
            return ""
        }
    }

    private func isPrimaryButtonEnabled(for step: LoudnessMatchModalStep) -> Bool {
        switch step {
        case .intro:
            return true
        case .correctEar, .quietRoom, .fit, .maxVolume:
            return preflightSession.canCommitCurrentPhase
        case .tinnitusLocation:
            return selectedLaterality != nil
                && !viewModel.isResolvingAudiogramThreshold
                && startLoudnessMatchTask == nil
                && viewModel.preflightReady
        case .activeTest:
            return false
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

        case .activeTest:
            break
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

            preflightSession.transition(to: phase(for: .activeTest))
            isActiveTestPresented = true
            clearStartTaskIfCurrent(generation)
        }
    }

    private func handleNavigationPathChange(
        from oldPath: [LoudnessMatchPreparationRoute],
        to newPath: [LoudnessMatchPreparationRoute]
    ) {
        let oldRoute = oldPath.last
        let newRoute = newPath.last
        guard oldRoute != newRoute else {
            return
        }

        if oldRoute == .tinnitusLocation, newRoute != .tinnitusLocation {
            cancelStartLoudnessMatch()
        }

        if newPath.count < oldPath.count, viewModel.isPlaying {
            viewModel.stopTone()
        }

        let newStep = newRoute?.step ?? .intro
        preflightSession.transition(to: phase(for: newStep))
    }

    private func handleRequestedFallback(
        _ fallback: CalibratedAudioPreflightSession.Phase?
    ) {
        guard fallback == .airPods else {
            return
        }

        cancelStartLoudnessMatch()
        navigationPath = [.correctEar]
        preflightSession.consumeRequestedFallback()
    }

    private func phase(
        for step: LoudnessMatchModalStep
    ) -> CalibratedAudioPreflightSession.Phase? {
        switch step {
        case .intro:
            return nil
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

    private var currentPreparationStep: LoudnessMatchModalStep {
        navigationPath.last?.step ?? .intro
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
                title: "Find a Quiet Place",
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
        isActiveTestPresented || viewModel.events.count > 1
    }

    private func selectLaterality(_ laterality: TinnitusLaterality) {
        selectedLaterality = laterality
    }

    private func showNoiseSuggestions() {
        isNoiseSuggestionsPresented = true
    }

    private func requestClose() {
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

private enum LoudnessMatchPreparationRoute: Hashable {
    case correctEar
    case quietRoom
    case fit
    case maxVolume
    case tinnitusLocation

    var step: LoudnessMatchModalStep {
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
