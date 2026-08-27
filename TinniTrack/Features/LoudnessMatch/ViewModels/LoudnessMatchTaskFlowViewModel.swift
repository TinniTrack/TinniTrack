import Combine
import Foundation
import OSLog

@MainActor
final class LoudnessMatchTaskFlowViewModel: ObservableObject {
    enum FlowMessage: Equatable {
        case playbackDisabled
        case environmentGateFailed
        case missingPreflight(String)
        case incompletePayload(String)
        case guardrailsUnavailable
        case environmentGateUnavailable(String)
        case airPodsNotInEar
        case unsupportedHeadphones
        case airPodsPro2ConfirmationRequired
        case calibratedPlaybackRouteUnavailable
        case missingAudiogramThreshold(String)
        case playbackFailed(String)
        case submissionFailed(String)
    }

    @Published private(set) var protocolState: TinnitusProtocolState
    @Published private(set) var selectedLaterality: TinnitusLaterality?
    @Published private(set) var researchProtocolAirPodsPro2Confirmation: ResearchProtocolHeadphoneRouteConfirmation?
    @Published var fitSealConfirmed = false
    @Published var safetyAcknowledged = false
    @Published private(set) var environmentGateResult: TinnitusEnvironmentSPLGateResult?
    @Published private(set) var environmentGateUpdate: TinnitusEnvironmentSPLGateUpdate?
    @Published private(set) var hasPassedEnvironmentGate = false
    @Published private(set) var isRunningEnvironmentGate = false
    @Published private(set) var headphoneRouteAssessment: HeadphoneRouteAssessment = .notEvaluated
    @Published private(set) var isHeadphoneRouteMonitoring = false
    @Published private(set) var isAirPodsContinuityMonitoring = false
    @Published private(set) var isAirPodsRouteInterrupted = false
    @Published private(set) var isVolumeGateMonitoring = false
    @Published private(set) var isResolvingAudiogramThreshold = false
    @Published private(set) var currentGuardrailValidation: CalibratedAudioGuardrailValidation
    @Published private(set) var message: FlowMessage?
    @Published private(set) var isPlaying = false
    @Published private(set) var isPreparingPlayback = false
    @Published private(set) var isSubmitting = false
    @Published private(set) var hasSubmitted = false
    @Published private(set) var completedSummary: TinnitusLoudnessMatchSummary?

    private var engine: TinnitusProtocolEngine
    private let player: CalibratedTonePlaying?
    private let guardrailMonitor: CalibratedAudioSessionGuardrailMonitor?
    private let researchProtocolHeadphoneResolver: ResearchProtocolCalibratedHeadphoneResolver?
    private let guardrailProvider: () -> CalibratedAudioGuardrailValidation
    private let headphoneRouteProvider: AudioSessionRouteVolumeProviding?
    private let headphoneRouteAssessor: HeadphoneRouteAssessor
    private let environmentMeter: EnvironmentSPLMeasuring
    private let environmentGateMonitor: EnvironmentSPLGateMonitoring
    private let environmentWorkflowManager: EnvironmentSPLWorkflowManaging?
    private let audiogramRepository: AudiogramRepositoryProtocol
    private let audiogramThresholdResolver: AudiogramThresholdResolver
    private let allowsCalibratedPlayback: Bool
    private let runtimeContextProvider: StudyNo1RuntimeContextProviding
    private let submissionExporter: StudyNo1LoudnessMatchSubmissionExporter
    private let orientationThresholdExporter: StudyNo1OrientationThresholdSubmissionExporter
    private let dateProvider: () -> Date
    private let routeDiagnosticsLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "TinniTrack",
        category: "LoudnessAirPodsGate"
    )
    private var environmentGateTask: Task<Void, Never>?
    private var environmentMonitorSession: (any EnvironmentSPLMonitorSession)?
    private var environmentGateStateMachine = TinnitusEnvironmentSPLGateStateMachine()
    private var headphoneRouteObservation: AudioSessionObservation?
    private var airPodsContinuityObservation: AudioSessionObservation?
    private var shouldResumeEnvironmentGateAfterPlayback = false
    private var playbackStopTask: Task<Void, Never>?
    private var pendingEnvironmentMonitorStopTasks: [Task<Void, Never>] = []
    private var audioWorkflowEndTask: Task<Void, Never>?
    private var isEnvironmentSuspendedForAppInactivity = false
    private var shouldResumeEnvironmentGateAfterAppActivity = false
    private var appInactivityMonitorStopTask: Task<Void, Never>?
    private var appActivityResumeTask: Task<Void, Never>?
    private var playbackPreparationGeneration: UInt64 = 0
    private let environmentDiagnosticsLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "TinniTrack",
        category: "EnvironmentGatePolicy"
    )

    init(
        engine: TinnitusProtocolEngine? = nil,
        player: CalibratedTonePlaying? = nil,
        guardrailProvider: (() -> CalibratedAudioGuardrailValidation)? = nil,
        headphoneRouteProvider: AudioSessionRouteVolumeProviding? = nil,
        headphoneRouteAssessor: HeadphoneRouteAssessor? = nil,
        environmentMeter: EnvironmentSPLMeasuring? = nil,
        environmentGateMonitor: EnvironmentSPLGateMonitoring? = nil,
        audiogramRepository: AudiogramRepositoryProtocol? = nil,
        audiogramThresholdResolver: AudiogramThresholdResolver? = nil,
        allowsCalibratedPlayback: Bool = true,
        runtimeContextProvider: StudyNo1RuntimeContextProviding? = nil,
        submissionExporter: StudyNo1LoudnessMatchSubmissionExporter? = nil,
        orientationThresholdExporter: StudyNo1OrientationThresholdSubmissionExporter? = nil,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        let resolvedEngine = engine ?? TinnitusProtocolEngine()
        let monitor: CalibratedAudioSessionGuardrailMonitor?
        let researchProtocolResolver: ResearchProtocolCalibratedHeadphoneResolver?
        let resolvedPlayer: CalibratedTonePlaying?
        let resolvedGuardrailProvider: () -> CalibratedAudioGuardrailValidation
        let resolvedHeadphoneRouteProvider: AudioSessionRouteVolumeProviding?

        if let guardrailProvider {
            monitor = nil
            researchProtocolResolver = nil
            resolvedGuardrailProvider = guardrailProvider
            resolvedPlayer = player
            resolvedHeadphoneRouteProvider = headphoneRouteProvider
        } else {
            let routeProvider = headphoneRouteProvider ?? AVAudioSessionRouteVolumeProvider()
            let resolver = ResearchProtocolCalibratedHeadphoneResolver()
            let guardrailMonitor = CalibratedAudioSessionGuardrailMonitor(
                provider: routeProvider,
                profileResolver: resolver
            )
            monitor = guardrailMonitor
            researchProtocolResolver = resolver
            resolvedGuardrailProvider = {
                guardrailMonitor.validateCurrentGuardrails()
            }
            resolvedPlayer = player ?? CalibratedToneAudioPlayer()
            resolvedHeadphoneRouteProvider = routeProvider
        }

        self.engine = resolvedEngine
        self.player = resolvedPlayer
        self.guardrailMonitor = monitor
        self.researchProtocolHeadphoneResolver = researchProtocolResolver
        self.guardrailProvider = resolvedGuardrailProvider
        self.headphoneRouteProvider = resolvedHeadphoneRouteProvider
        self.headphoneRouteAssessor = headphoneRouteAssessor
            ?? HeadphoneRouteAssessor()
        let resolvedEnvironmentMeter = environmentMeter ?? AVAudioEnvironmentSPLMeter()
        self.environmentMeter = resolvedEnvironmentMeter
        self.environmentGateMonitor = environmentGateMonitor
            ?? (resolvedEnvironmentMeter as? EnvironmentSPLGateMonitoring)
            ?? OneShotEnvironmentSPLGateMonitor(meter: resolvedEnvironmentMeter)
        environmentWorkflowManager = resolvedEnvironmentMeter as? EnvironmentSPLWorkflowManaging
        self.audiogramRepository = audiogramRepository ?? SupabaseAudiogramRepository()
        self.audiogramThresholdResolver = audiogramThresholdResolver
            ?? AudiogramThresholdResolver()
        self.allowsCalibratedPlayback = allowsCalibratedPlayback
        self.runtimeContextProvider = runtimeContextProvider ?? SystemStudyNo1RuntimeContextProvider()
        self.submissionExporter = submissionExporter ?? StudyNo1LoudnessMatchSubmissionExporter()
        self.orientationThresholdExporter = orientationThresholdExporter ?? StudyNo1OrientationThresholdSubmissionExporter()
        self.dateProvider = dateProvider
        researchProtocolAirPodsPro2Confirmation = nil
        protocolState = resolvedEngine.state
        currentGuardrailValidation = self.guardrailProvider()
        syncHeadphoneRouteAssessmentFromPassedGuardrails()
    }

    var events: [TinnitusProtocolEvent] {
        engine.events
    }

    var canPlayTone: Bool {
        allowsCalibratedPlayback
            && currentGuardrailValidation.state == .passed
            && preflightReady
            && !isAirPodsRouteInterrupted
            && !isPreparingPlayback
            && playbackStopTask == nil
            && environmentGateUpdate?.hasCurrentQuietDecision == true
            && currentCandidateLevelDBHL != nil
    }

    var preflightReady: Bool {
        currentGuardrailValidation.state == .passed
            && isCurrentAirPodsPro2PlaybackRouteConfirmed
            && !isAirPodsRouteInterrupted
            && environmentGateUpdate?.hasCurrentQuietDecision == true
            && fitSealConfirmed
            && safetyAcknowledged
    }

    private var preflightReadyIgnoringEnvironmentLifecycle: Bool {
        currentGuardrailValidation.state == .passed
            && isCurrentAirPodsPro2PlaybackRouteConfirmed
            && !isAirPodsRouteInterrupted
            && environmentGateResult?.passed == true
            && !isEnvironmentQuietnessInterrupted
            && fitSealConfirmed
            && safetyAcknowledged
    }

    var canSubmit: Bool {
        completedSummary != nil
            && preflightReady
            && !isSubmitting
            && !hasSubmitted
    }

    var isEnvironmentQuietnessInterrupted: Bool {
        environmentGateUpdate?.status.isGenuineLoudnessInterruption == true
    }

    var isAirPodsPlaybackRouteBlockedByAnotherApp: Bool {
        headphoneRouteAssessment.isBluetoothHeadsetProfile
            && (headphoneRouteAssessment.looksLikeAirPodsProRoute
                || confirmedRouteNameMatchesCurrentRoute)
    }

    var isCurrentAirPodsPro2PlaybackRouteConfirmed: Bool {
        confirmationMatchesCurrentRoute(researchProtocolAirPodsPro2Confirmation)
    }

    var currentCandidateLevelDBHL: Double? {
        engine.currentCandidateLevelDBHL
    }

    var isComplete: Bool {
        completedSummary != nil
    }

    var currentTrialLabel: String {
        if case .readyForTrial(let index, _) = protocolState {
            return "Trial \(index) of 3"
        }
        if case .awaitingConfidence(let trial) = protocolState {
            return "Trial \(trial.trialIndex) of 3"
        }
        return "Trial"
    }

    func refreshGuardrails() {
        currentGuardrailValidation = guardrailProvider()
        syncHeadphoneRouteAssessmentFromPassedGuardrails()
        if currentGuardrailValidation.state != .passed, hasRequestedStimulus {
            engine.applyGuardrailValidation(currentGuardrailValidation)
            syncFromEngine()
        }
    }

    func refreshHeadphoneRouteAssessment() {
        guard let headphoneRouteProvider else {
            return
        }

        headphoneRouteProvider.refreshRouteAndVolume()
        let assessment = headphoneRouteAssessor.assess(
            outputs: headphoneRouteProvider.currentRouteOutputs(),
            outputVolume: headphoneRouteProvider.currentOutputVolume()
        )
        setHeadphoneRouteAssessment(assessment, source: "correctEarRefresh")
        invalidateAmbiguousConfirmationIfNeeded(for: assessment)
        refreshGuardrails()
    }

    func startHeadphoneRouteMonitoring() {
        guard let headphoneRouteProvider else {
            refreshHeadphoneRouteAssessment()
            return
        }

        stopHeadphoneRouteMonitoring()
        isHeadphoneRouteMonitoring = true
        refreshHeadphoneRouteAssessment()

        headphoneRouteObservation = headphoneRouteProvider.observeRouteChanges { [weak self] in
            Task { @MainActor in
                self?.refreshHeadphoneRouteAssessment()
            }
        }
    }

    func stopHeadphoneRouteMonitoring() {
        headphoneRouteObservation?.invalidate()
        headphoneRouteObservation = nil
        isHeadphoneRouteMonitoring = false
    }

    func startAirPodsContinuityMonitoring() {
        guard let headphoneRouteProvider else {
            evaluateAirPodsContinuity()
            return
        }

        stopAirPodsContinuityMonitoring(clearInterruption: false)
        isAirPodsContinuityMonitoring = true
        evaluateAirPodsContinuity()

        airPodsContinuityObservation = headphoneRouteProvider.observeRouteChanges { [weak self] in
            Task { @MainActor in
                guard let self else {
                    return
                }
                self.evaluateAirPodsContinuity(refreshRouteAndVolume: !self.isRunningEnvironmentGate)
            }
        }
    }

    func stopAirPodsContinuityMonitoring(clearInterruption: Bool = true) {
        airPodsContinuityObservation?.invalidate()
        airPodsContinuityObservation = nil
        isAirPodsContinuityMonitoring = false
        if clearInterruption {
            isAirPodsRouteInterrupted = false
        }
    }

    func evaluateAirPodsContinuity(refreshRouteAndVolume: Bool = true) {
        guard let headphoneRouteProvider else {
            return
        }

        if refreshRouteAndVolume {
            headphoneRouteProvider.refreshRouteAndVolume()
        }
        let assessment = headphoneRouteAssessor.assess(
            outputs: headphoneRouteProvider.currentRouteOutputs(),
            outputVolume: headphoneRouteProvider.currentOutputVolume()
        )
        setHeadphoneRouteAssessment(assessment, source: "continuityRefresh")
        invalidateAmbiguousConfirmationIfNeeded(for: assessment)

        if confirmationMatchesCurrentRoute(researchProtocolAirPodsPro2Confirmation, assessment: assessment) {
            isAirPodsRouteInterrupted = false
            if refreshRouteAndVolume {
                refreshGuardrails()
            }
            return
        }

        isAirPodsRouteInterrupted = true
        stopVolumeGateMonitoring()
        if isPlaying {
            stopTone()
        }
        if refreshRouteAndVolume {
            // Keep diagnostics current while the interruption overlay pauses the flow.
            // Applying this transient failure to the engine would incorrectly turn a
            // recoverable disconnect into a protocol restart.
            currentGuardrailValidation = guardrailProvider()
        }
    }

    @discardableResult
    func validateAirPodsForCorrectEarStep() -> Bool {
        refreshHeadphoneRouteAssessment()
        guard headphoneRouteAssessment.isCompatibleBluetoothPlaybackRoute else {
            message = airPodsGateMessage(for: headphoneRouteAssessment)
            return false
        }

        guard headphoneRouteAssessment.isAirPodsProPlaybackRouteCandidate else {
            message = .unsupportedHeadphones
            return false
        }

        guard isCurrentAirPodsPro2PlaybackRouteConfirmed else {
            message = .airPodsPro2ConfirmationRequired
            return false
        }

        message = nil
        return true
    }

    func setAirPodsPro2ConfirmedForCurrentRoute(_ isConfirmed: Bool) {
        guard isConfirmed else {
            researchProtocolHeadphoneResolver?.confirmation = nil
            researchProtocolAirPodsPro2Confirmation = nil
            refreshGuardrails()
            return
        }

        refreshHeadphoneRouteAssessment()
        guard headphoneRouteAssessment.isAirPodsProPlaybackRouteCandidate else {
            message = headphoneRouteAssessment.isCompatibleBluetoothPlaybackRoute
                ? .unsupportedHeadphones
                : airPodsGateMessage(for: headphoneRouteAssessment)
            return
        }

        guard let portName = headphoneRouteAssessment.portName else {
            message = airPodsGateMessage(for: headphoneRouteAssessment)
            return
        }

        let confirmation = ResearchProtocolHeadphoneRouteConfirmation(
            headphoneIdentifier: CalibratedHeadphoneIdentifier.airPodsPro2,
            portUID: headphoneRouteAssessment.routeUID,
            portName: portName,
            confirmedAt: dateProvider()
        )

        researchProtocolHeadphoneResolver?.confirmation = confirmation
        researchProtocolAirPodsPro2Confirmation = confirmation
        isAirPodsRouteInterrupted = false
        message = nil
        refreshGuardrails()
    }

    private func airPodsGateMessage(for assessment: HeadphoneRouteAssessment) -> FlowMessage {
        if assessment.isBluetoothHeadsetProfile,
           assessment.looksLikeAirPodsProRoute
            || researchProtocolAirPodsPro2Confirmation?.portName == assessment.portName {
            return .calibratedPlaybackRouteUnavailable
        }

        switch assessment.primaryIssue {
        case .noOutput, .builtInOutput, .bluetoothHeadsetProfile, .bluetoothLowEnergyRoute, .unknownRoute, nil:
            return .airPodsNotInEar
        case .multipleOutputs, .unsupportedWiredOrExternalRoute, .outputVolumeUnavailable:
            return .unsupportedHeadphones
        }
    }

    private func confirmationMatchesCurrentRoute(
        _ confirmation: ResearchProtocolHeadphoneRouteConfirmation?,
        assessment: HeadphoneRouteAssessment? = nil
    ) -> Bool {
        let assessment = assessment ?? headphoneRouteAssessment
        guard let confirmation,
              confirmation.headphoneIdentifier == CalibratedHeadphoneIdentifier.airPodsPro2,
              assessment.isAirPodsProPlaybackRouteCandidate,
              let portName = assessment.portName
        else {
            return false
        }

        if let confirmedPortUID = confirmation.portUID {
            return assessment.routeUID == confirmedPortUID
        }

        return assessment.routeUID == nil && confirmation.portName == portName
    }

    private var confirmedRouteNameMatchesCurrentRoute: Bool {
        guard let confirmedPortName = researchProtocolAirPodsPro2Confirmation?.portName else {
            return false
        }
        return headphoneRouteAssessment.portName == confirmedPortName
    }

    private func invalidateAmbiguousConfirmationIfNeeded(for assessment: HeadphoneRouteAssessment) {
        guard let confirmation = researchProtocolAirPodsPro2Confirmation,
              confirmation.portUID == nil,
              !confirmationMatchesCurrentRoute(confirmation, assessment: assessment)
        else {
            return
        }

        researchProtocolHeadphoneResolver?.confirmation = nil
        researchProtocolAirPodsPro2Confirmation = nil
    }

    private func syncHeadphoneRouteAssessmentFromPassedGuardrails() {
        guard currentGuardrailValidation.state == .passed,
              let output = currentGuardrailValidation.metadata.routeDetails?.outputs.first
        else {
            return
        }

        if researchProtocolAirPodsPro2Confirmation == nil,
           output.verifiedCalibratedHeadphoneIdentifier == CalibratedHeadphoneIdentifier.airPodsPro2,
           output.verificationSource == .researchProtocol {
            researchProtocolAirPodsPro2Confirmation = ResearchProtocolHeadphoneRouteConfirmation(
                headphoneIdentifier: CalibratedHeadphoneIdentifier.airPodsPro2,
                portUID: output.portUID,
                portName: output.portName,
                confirmedAt: currentGuardrailValidation.metadata.timestamp
            )
        }

        setHeadphoneRouteAssessment(HeadphoneRouteAssessment(
            level: HeadphoneRouteAssessor.looksLikeAirPodsPro(output.portName)
                ? .likelyAirPodsProRoute
                : .compatibleBluetoothPlaybackRoute,
            outputCount: currentGuardrailValidation.metadata.routeDetails?.outputs.count ?? 1,
            portName: output.portName,
            portType: output.portType,
            portTypeRawValue: nil,
            routeUID: output.portUID,
            channelNames: output.channelNames,
            outputVolume: currentGuardrailValidation.metadata.rawOutputVolume,
            issues: []
        ), source: "passedGuardrailSync")
    }

    private func setHeadphoneRouteAssessment(_ assessment: HeadphoneRouteAssessment, source: String) {
        headphoneRouteAssessment = assessment
        logHeadphoneRouteAssessment(assessment, source: source)
    }

    private func logHeadphoneRouteAssessment(_ assessment: HeadphoneRouteAssessment, source: String) {
        let confirmationMatchesRoute = confirmationMatchesCurrentRoute(
            researchProtocolAirPodsPro2Confirmation,
            assessment: assessment
        )
        routeDiagnosticsLogger.info(
            """
            route_assessment source=\(source, privacy: .public) compatiblePlayback=\(assessment.isCompatibleBluetoothPlaybackRoute, privacy: .public) airPodsNameSignal=\(assessment.looksLikeAirPodsProRoute, privacy: .public) confirmedCurrentRoute=\(confirmationMatchesRoute, privacy: .public) level=\(assessment.level.rawValue, privacy: .public) issue=\(assessment.primaryIssue?.rawValue ?? "none", privacy: .public) outputs=\(assessment.outputCount, privacy: .public) portType=\(assessment.portTypeRawValue ?? "none", privacy: .public) uidHash=\(assessment.routeUIDFingerprint ?? "none", privacy: .public) portName=\(assessment.portName ?? "none", privacy: .private) channels=\(assessment.channelNames.joined(separator: "|"), privacy: .private) volume=\(assessment.outputVolume ?? -1, privacy: .public)
            """
        )
    }

    func selectLaterality(_ laterality: TinnitusLaterality) async {
        guard !isResolvingAudiogramThreshold else {
            return
        }

        isResolvingAudiogramThreshold = true
        defer { isResolvingAudiogramThreshold = false }

        do {
            let audiogram = try await audiogramRepository.fetchLatestAudiogram()
            guard !Task.isCancelled else {
                return
            }
            let threshold = try audiogramThresholdResolver.resolveThresholdDBHL(
                for: TinnitusProtocolEngine.loudnessMatchPlaybackChannel,
                in: audiogram
            )
            guard !Task.isCancelled else {
                return
            }
            selectedLaterality = laterality
            engine.selectLaterality(
                laterality,
                healthKitAudiogramThresholdDBHL: threshold
            )
            message = nil
            syncFromEngine()
        } catch is CancellationError {
            return
        } catch let error as AudiogramThresholdResolutionError {
            guard !Task.isCancelled else {
                return
            }
            message = .missingAudiogramThreshold(error.localizedDescription)
        } catch {
            guard !Task.isCancelled else {
                return
            }
            message = .missingAudiogramThreshold(error.localizedDescription)
        }
    }

    func startLoudnessMatch(laterality: TinnitusLaterality) async -> Bool {
        if selectedLaterality == laterality, isReadyForLoudnessTrial {
            message = nil
            return true
        }

        guard case .collectingLaterality = protocolState else {
            message = .missingPreflight("Restart this loudness-match task to change tinnitus location after the test has started.")
            return false
        }

        await selectLaterality(laterality)
        return !Task.isCancelled && isReadyForLoudnessTrial
    }

    func runEnvironmentGate() async {
        guard !isRunningEnvironmentGate else {
            return
        }

        environmentGateStateMachine = TinnitusEnvironmentSPLGateStateMachine()
        let started = environmentGateStateMachine.beginMonitoring(reason: .initial)
        applyEnvironmentGateUpdate(started.update)
        isRunningEnvironmentGate = true
        defer { isRunningEnvironmentGate = false }

        do {
            let result = try await environmentMeter.runGate(configuration: .studyNo1)
            _ = environmentGateStateMachine.handle(.ready, generation: started.generation)
            for measurement in result.measurements {
                _ = environmentGateStateMachine.handle(
                    .measurement(measurement),
                    generation: started.generation
                )
            }
            applyEnvironmentGateUpdate(environmentGateStateMachine.currentUpdate)
            message = result.passed ? nil : .environmentGateFailed
        } catch {
            if let update = environmentGateStateMachine.handle(
                .unavailable(.unavailable),
                generation: started.generation
            ) {
                applyEnvironmentGateUpdate(update)
            }
            message = .environmentGateUnavailable(error.localizedDescription)
        }
    }

    func startContinuousEnvironmentGate() {
        let reason: TinnitusEnvironmentSPLReacquisitionReason = hasPassedEnvironmentGate
            ? .manualRestart
            : .initial
        startContinuousEnvironmentGate(reason: reason)
    }

    private func startContinuousEnvironmentGate(
        reason: TinnitusEnvironmentSPLReacquisitionReason
    ) {
        guard !isRunningEnvironmentGate else {
            return
        }

        let started = environmentGateStateMachine.beginMonitoring(reason: reason)
        applyEnvironmentGateUpdate(started.update)
        isRunningEnvironmentGate = true
        message = nil

        let monitorSession = environmentGateMonitor.makeMonitor(
            configuration: .studyNo1,
            reason: reason
        )
        environmentMonitorSession = monitorSession
        let taskGeneration = started.generation
        environmentGateTask = Task { [weak self] in
            do {
                for try await event in monitorSession.events {
                    guard let self else {
                        return
                    }
                    guard let update = self.environmentGateStateMachine.handle(
                        event,
                        generation: taskGeneration
                    ) else {
                        continue
                    }
                    self.applyEnvironmentGateUpdate(update)
                }

                guard let self else {
                    return
                }
                self.finishContinuousEnvironmentGateTask(generation: taskGeneration)
            } catch {
                guard let self else {
                    return
                }
                self.finishContinuousEnvironmentGateTask(
                    generation: taskGeneration,
                    error: error
                )
            }
        }
    }

    func prepareEnvironmentGateForQuietRoomStep() {
        cancelEnvironmentMonitorConsumer()
        let update = environmentGateStateMachine.reset()
        applyEnvironmentGateUpdate(update)
        message = nil
    }

    private func applyEnvironmentGateUpdate(_ update: TinnitusEnvironmentSPLGateUpdate) {
        let previousStatus = environmentGateUpdate?.status
        environmentGateUpdate = update
        environmentGateResult = update.result
        hasPassedEnvironmentGate = update.result?.passed == true

        if previousStatus != update.status {
            environmentDiagnosticsLogger.info(
                "Gate transition from=\(String(describing: previousStatus), privacy: .public) to=\(String(describing: update.status), privacy: .public) generation=\(update.generation, privacy: .public)"
            )
        }
        if update.status.isGenuineLoudnessInterruption {
            environmentDiagnosticsLogger.info("Genuine sustained-loudness interruption entered; popup eligible")
            if isPlaying { stopTone() }
        } else if previousStatus?.isGenuineLoudnessInterruption == true,
                  update.status == .quiet {
            environmentDiagnosticsLogger.info("Quiet-screen interruption recovered after hysteresis debounce")
        }
    }

    func cancelEnvironmentGate() {
        if hasPassedEnvironmentGate {
            applyEnvironmentGateUpdate(
                environmentGateStateMachine.suspend(reason: .audioSessionHandoff)
            )
        } else {
            applyEnvironmentGateUpdate(environmentGateStateMachine.reset())
        }
        cancelEnvironmentMonitorConsumer()
    }

    func suspendEnvironmentGateForAppInactivity() {
        guard !isEnvironmentSuspendedForAppInactivity,
              audioWorkflowEndTask == nil
        else {
            return
        }

        isEnvironmentSuspendedForAppInactivity = true
        appActivityResumeTask?.cancel()
        appActivityResumeTask = nil
        playbackPreparationGeneration &+= 1
        isPreparingPlayback = false
        shouldResumeEnvironmentGateAfterAppActivity = isRunningEnvironmentGate
            || shouldResumeEnvironmentGateAfterPlayback

        if environmentGateUpdate?.status != .idle {
            applyEnvironmentGateUpdate(
                environmentGateStateMachine.suspend(reason: .appInactive)
            )
        }
        appInactivityMonitorStopTask = cancelEnvironmentMonitorConsumer()
    }

    func resumeEnvironmentGateAfterAppActivity() {
        guard isEnvironmentSuspendedForAppInactivity,
              audioWorkflowEndTask == nil
        else {
            return
        }

        isEnvironmentSuspendedForAppInactivity = false
        let monitorStopTask = appInactivityMonitorStopTask
        appInactivityMonitorStopTask = nil
        let playbackStopTask = playbackStopTask
        appActivityResumeTask?.cancel()
        appActivityResumeTask = Task { @MainActor [weak self] in
            await monitorStopTask?.value
            await playbackStopTask?.value
            guard let self,
                  !Task.isCancelled,
                  !self.isEnvironmentSuspendedForAppInactivity,
                  self.audioWorkflowEndTask == nil,
                  self.shouldResumeEnvironmentGateAfterAppActivity
            else {
                return
            }

            self.shouldResumeEnvironmentGateAfterAppActivity = false
            if self.isRunningEnvironmentGate {
                self.appActivityResumeTask = nil
                return
            }
            if self.shouldResumeEnvironmentGateAfterPlayback {
                self.resumeEnvironmentGateAfterPlaybackIfNeeded(reason: .manualRestart)
            } else {
                self.startContinuousEnvironmentGate(
                    reason: self.hasPassedEnvironmentGate ? .manualRestart : .initial
                )
            }
            self.appActivityResumeTask = nil
        }
    }

    private func finishContinuousEnvironmentGateTask(
        generation: TinnitusEnvironmentSPLGateStateMachine.Generation,
        error: Error? = nil
    ) {
        guard environmentGateStateMachine.generation == generation else {
            return
        }

        environmentGateTask = nil
        environmentMonitorSession = nil
        isRunningEnvironmentGate = false
        if let update = environmentGateStateMachine.handle(
            .unavailable(.unavailable),
            generation: generation
        ) {
            applyEnvironmentGateUpdate(update)
        }
        if let error {
            message = .environmentGateUnavailable(error.localizedDescription)
        } else {
            message = .environmentGateUnavailable(
                "Quiet-room monitoring ended unexpectedly. Return to the quiet-room step and try again."
            )
        }
    }

    @discardableResult
    private func cancelEnvironmentMonitorConsumer() -> Task<Void, Never>? {
        let monitorSession = environmentMonitorSession
        environmentMonitorSession = nil
        environmentGateTask?.cancel()
        environmentGateTask = nil
        isRunningEnvironmentGate = false
        if let monitorSession {
            let stopTask = Task { @MainActor in
                await monitorSession.stop()
            }
            pendingEnvironmentMonitorStopTasks.append(stopTask)
            return stopTask
        }
        return nil
    }

    func completeFitConfirmation() {
        fitSealConfirmed = true
    }

    func startVolumeGateMonitoring() {
        isVolumeGateMonitoring = true
        refreshGuardrails()
        guard let guardrailMonitor else {
            return
        }

        guardrailMonitor.startMonitoring { [weak self] validation in
            Task { @MainActor in
                guard let self else {
                    return
                }
                self.currentGuardrailValidation = validation
            }
        }
    }

    func stopVolumeGateMonitoring() {
        guardrailMonitor?.stopMonitoring()
        isVolumeGateMonitoring = false
    }

    @discardableResult
    func acknowledgeSafetyAndStartTest() -> Bool {
        safetyAcknowledged = true
        refreshGuardrails()

        guard preflightReady else {
            message = .missingPreflight("Complete quiet-room, fit, route, AirPods Pro 2 verification, and max-volume checks before starting the test.")
            return false
        }

        message = nil
        return true
    }

    func adjustLevel(_ adjustment: TinnitusLoudnessAdjustment) {
        engine.adjustLevel(adjustment)
        syncFromEngine()

        guard isPlaying else {
            return
        }

        startOrRefreshTonePlayback(isRefreshingActivePlayback: true)
    }

    func playTone() {
        guard !isPlaying, !isPreparingPlayback, playbackStopTask == nil else {
            return
        }

        guard preflightReady else {
            startOrRefreshTonePlayback(isRefreshingActivePlayback: false)
            return
        }

        if isRunningEnvironmentGate {
            isPreparingPlayback = true
            playbackPreparationGeneration &+= 1
            let preparationGeneration = playbackPreparationGeneration
            Task { @MainActor in
                let shouldResume = await suspendPassedEnvironmentGateForPlayback()
                guard preparationGeneration == playbackPreparationGeneration,
                      !Task.isCancelled
                else {
                    return
                }
                shouldResumeEnvironmentGateAfterPlayback = shouldResume
                isPreparingPlayback = false
                startOrRefreshTonePlayback(
                    isRefreshingActivePlayback: false,
                    environmentWasReadyBeforeHandoff: true
                )
            }
            return
        }

        startOrRefreshTonePlayback(isRefreshingActivePlayback: false)
    }

    func playOrientationThresholdTone(
        _ stimulus: StudyNo1OrientationThresholdStimulus,
        duration: TimeInterval
    ) async throws {
        if let playbackStopTask {
            await playbackStopTask.value
            try Task.checkCancellation()
        }
        try await waitForEnvironmentReacquisitionIfNeeded()
        guard !isPlaying, !isPreparingPlayback, playbackStopTask == nil else {
            throw OrientationThresholdPlaybackError.playbackAlreadyActive
        }
        guard preflightReady else {
            throw OrientationThresholdPlaybackError.preflightUnavailable
        }

        if isRunningEnvironmentGate {
            isPreparingPlayback = true
            let shouldResume = await suspendPassedEnvironmentGateForPlayback()
            shouldResumeEnvironmentGateAfterPlayback = shouldResume
            isPreparingPlayback = false
            if Task.isCancelled {
                resumeEnvironmentGateAfterPlaybackIfNeeded()
                throw CancellationError()
            }
        }

        guard allowsCalibratedPlayback else {
            resumeEnvironmentGateAfterPlaybackIfNeeded()
            throw OrientationThresholdPlaybackError.playbackDisabled
        }

        currentGuardrailValidation = guardrailProvider()
        guard preflightReadyIgnoringEnvironmentLifecycle,
              currentGuardrailValidation.state == .passed
        else {
            resumeEnvironmentGateAfterPlaybackIfNeeded()
            throw OrientationThresholdPlaybackError.preflightUnavailable
        }

        let request = CalibratedTonePlaybackRequest(
            frequencyHz: stimulus.frequencyHz,
            levelDBHL: stimulus.levelDBHL,
            channel: stimulus.channel,
            duration: duration,
            guardrailValidation: currentGuardrailValidation
        )

        do {
            _ = try player?.play(request)
            isPlaying = true
            startPlaybackGuardrailMonitoring()
            message = nil
        } catch {
            guardrailMonitor?.stopMonitoring()
            isPlaying = false
            resumeEnvironmentGateAfterPlaybackIfNeeded()
            throw error
        }
    }

    func stopOrientationThresholdTone() {
        guard playbackStopTask == nil else {
            return
        }
        guard isPlaying || isPreparingPlayback else {
            return
        }

        playbackPreparationGeneration &+= 1
        isPreparingPlayback = false
        guardrailMonitor?.stopMonitoring()
        _ = player?.stop()
        if hasPassedEnvironmentGate {
            applyEnvironmentGateUpdate(
                environmentGateStateMachine.suspend(
                    reason: isEnvironmentSuspendedForAppInactivity
                        ? .appInactive
                        : .responseTap
                )
            )
        }
        let stopTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.player?.waitForSilenceAfterStop()
            guard !Task.isCancelled else { return }
            self.isPlaying = false
            self.playbackStopTask = nil
            self.resumeEnvironmentGateAfterPlaybackIfNeeded(reason: .postResponse)
        }
        playbackStopTask = stopTask
    }

    var orientationThresholdOutputVolume: Double? {
        currentGuardrailValidation.metadata.rawOutputVolume
    }

    private func suspendPassedEnvironmentGateForPlayback() async -> Bool {
        guard isRunningEnvironmentGate,
              environmentGateResult?.passed == true,
              let task = environmentGateTask,
              let monitorSession = environmentMonitorSession
        else {
            return false
        }

        applyEnvironmentGateUpdate(
            environmentGateStateMachine.suspend(reason: .tonePlayback)
        )
        environmentGateTask = nil
        environmentMonitorSession = nil
        task.cancel()
        await monitorSession.stop()
        await task.value

        isRunningEnvironmentGate = false
        return true
    }

    private func startOrRefreshTonePlayback(
        isRefreshingActivePlayback: Bool,
        environmentWasReadyBeforeHandoff: Bool = false
    ) {
        guard allowsCalibratedPlayback else {
            message = .playbackDisabled
            resumeEnvironmentGateAfterPlaybackIfNeeded()
            return
        }

        guard preflightReady
                || (environmentWasReadyBeforeHandoff && preflightReadyIgnoringEnvironmentLifecycle)
        else {
            if isRefreshingActivePlayback {
                stopTone()
            }
            message = .missingPreflight("Complete audio guardrails, quiet-room samples, fit/seal confirmation, and safety acknowledgement before playback.")
            resumeEnvironmentGateAfterPlaybackIfNeeded()
            return
        }

        currentGuardrailValidation = guardrailProvider()
        guard currentGuardrailValidation.state == .passed else {
            if isRefreshingActivePlayback {
                stopTone()
            }
            let attempt = engine.playCurrentTone(guardrailValidation: currentGuardrailValidation)
            message = attempt.refusalReason == nil ? .guardrailsUnavailable : .guardrailsUnavailable
            syncFromEngine()
            resumeEnvironmentGateAfterPlaybackIfNeeded()
            return
        }

        let attempt = engine.playCurrentTone(guardrailValidation: currentGuardrailValidation)
        guard let request = attempt.request, attempt.refusalReason == nil else {
            if isRefreshingActivePlayback {
                stopTone()
            }
            message = .guardrailsUnavailable
            syncFromEngine()
            resumeEnvironmentGateAfterPlaybackIfNeeded()
            return
        }

        do {
            _ = try player?.play(request)
            isPlaying = true
            startPlaybackGuardrailMonitoring()
            message = nil
            syncFromEngine()
        } catch {
            guardrailMonitor?.stopMonitoring()
            isPlaying = false
            message = .playbackFailed(error.localizedDescription)
            syncFromEngine()
            resumeEnvironmentGateAfterPlaybackIfNeeded()
        }
    }

    func stopTone() {
        guardrailMonitor?.stopMonitoring()
        let metadata = player?.stop()
        isPlaying = false
        engine.recordStop(playbackMetadata: metadata)
        syncFromEngine()
        if hasPassedEnvironmentGate {
            applyEnvironmentGateUpdate(
                environmentGateStateMachine.suspend(
                    reason: isEnvironmentSuspendedForAppInactivity
                        ? .appInactive
                        : .responseTap
                )
            )
        }
        playbackStopTask?.cancel()
        let stopTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.player?.waitForSilenceAfterStop()
            guard !Task.isCancelled else { return }
            self.playbackStopTask = nil
            self.resumeEnvironmentGateAfterPlaybackIfNeeded(reason: .postResponse)
        }
        playbackStopTask = stopTask
    }

    private func resumeEnvironmentGateAfterPlaybackIfNeeded(
        reason: TinnitusEnvironmentSPLReacquisitionReason = .postPlayback
    ) {
        guard shouldResumeEnvironmentGateAfterPlayback,
              !isEnvironmentSuspendedForAppInactivity,
              !isRunningEnvironmentGate,
              environmentGateTask == nil
        else {
            return
        }

        shouldResumeEnvironmentGateAfterPlayback = false
        startContinuousEnvironmentGate(reason: reason)
    }

    private func waitForEnvironmentReacquisitionIfNeeded() async throws {
        guard hasPassedEnvironmentGate,
              environmentGateUpdate?.status != .quiet
        else {
            return
        }

        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            try Task.checkCancellation()
            if environmentGateUpdate?.status == .quiet {
                return
            }
            if environmentGateUpdate?.status.isGenuineLoudnessInterruption == true {
                throw OrientationThresholdPlaybackError.preflightUnavailable
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw OrientationThresholdPlaybackError.preflightUnavailable
    }

    func acceptCurrentLevel() {
        if isPlaying {
            stopTone()
        }
        engine.acceptCurrentLevel()
        syncFromEngine()
    }

    func recordConfidence(_ confidence: TinnitusConfidenceRating) {
        engine.recordConfidence(confidence)
        syncFromEngine()
    }

    func abort() {
        playbackPreparationGeneration &+= 1
        playbackStopTask?.cancel()
        playbackStopTask = nil
        cancelEnvironmentGate()
        stopAirPodsContinuityMonitoring()
        stopVolumeGateMonitoring()
        endAudioSessionWorkflow()
        if isPlaying {
            guardrailMonitor?.stopMonitoring()
            _ = player?.stop()
            isPlaying = false
        }
        engine.abort(.participantStopped)
        syncFromEngine()
    }

    func endAudioSessionWorkflow() {
        guard audioWorkflowEndTask == nil else {
            return
        }
        appActivityResumeTask?.cancel()
        appActivityResumeTask = nil
        shouldResumeEnvironmentGateAfterAppActivity = false
        let monitorSession = environmentMonitorSession
        environmentMonitorSession = nil
        environmentGateTask?.cancel()
        environmentGateTask = nil
        isRunningEnvironmentGate = false
        let player = self.player
        let workflowManager = environmentWorkflowManager
        let pendingStops = pendingEnvironmentMonitorStopTasks
        pendingEnvironmentMonitorStopTasks = []
        let endTask = Task { @MainActor in
            if let monitorSession {
                await monitorSession.stop()
            }
            for stopTask in pendingStops {
                await stopTask.value
            }
            _ = await player?.stopAndWaitForSilence()
            workflowManager?.endAudioWorkflow()
        }
        audioWorkflowEndTask = endTask
    }

    func makeStudyNo1Payload(
        scheduledTask: ScheduledTask,
        enrollment: StudyEnrollment,
        submittedAt: Date? = nil
    ) throws -> StudyNo1LoudnessMatchRunPayload {
        guard let summary = completedSummary else {
            throw StudyNo1PayloadValidationError.incompleteStudyNo1(reason: "Study No. 1 is not complete.")
        }
        guard let environment = environmentGateResult?.studyNo1Context else {
            throw StudyNo1PayloadValidationError.missingRequiredFields(["environment.samplesDBA"])
        }
        guard fitSealConfirmed else {
            throw StudyNo1PayloadValidationError.missingRequiredFields(["fitSeal.status"])
        }
        guard safetyAcknowledged else {
            throw StudyNo1PayloadValidationError.missingRequiredFields(["safety.acknowledgedAt"])
        }

        currentGuardrailValidation = guardrailProvider()
        let preflight = StudyNo1PreflightContext(
            identifiers: StudyNo1IdentifierContext(
                participantId: enrollment.userID.uuidString,
                studySessionId: enrollment.id.uuidString,
                enrollmentId: enrollment.id.uuidString,
                scheduledTaskId: scheduledTask.id.uuidString
            ),
            startedAt: events.first?.timestamp ?? dateProvider(),
            submittedAt: submittedAt,
            guardrailValidation: currentGuardrailValidation,
            device: runtimeContextProvider.deviceContext(),
            airPods: runtimeContextProvider.airPodsContext(guardrailValidation: currentGuardrailValidation),
            audioSession: runtimeContextProvider.audioSessionContext(),
            environment: environment,
            fitSeal: StudyNo1FitSealContext(
                status: .confirmedPassed,
                confirmedAt: dateProvider(),
                limitations: "Participant confirmation; public iOS APIs do not expose Apple's Ear Tip Fit Test result."
            ),
            safety: StudyNo1SafetyContext(
                acknowledgedAt: dateProvider(),
                stopControlVisibleBeforePlayback: true,
                maximumLevelDBHL: 100.0,
                limitation: "Immediate stop is visible during playback; no clinical or diagnostic claim."
            ),
            thresholdSource: .healthKitAudiogram
        )

        return try StudyNo1LoudnessMatchPayloadBuilder().buildStudyNo1Payload(
            summary: summary,
            events: events,
            preflight: preflight
        )
    }

    func submitCompletedRun(
        scheduledTask: ScheduledTask,
        enrollment: StudyEnrollment,
        studyService: StudyServiceProtocol
    ) async {
        guard !isSubmitting else {
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let submittedAt = dateProvider()
            let payload = try makeStudyNo1Payload(
                scheduledTask: scheduledTask,
                enrollment: enrollment,
                submittedAt: submittedAt
            )
            let submission = try submissionExporter.makeSubmission(from: payload)
            try await studyService.submitLoudnessMatch(
                scheduledTaskID: scheduledTask.id,
                enrollmentID: enrollment.id,
                submission: submission
            )
            hasSubmitted = true
            message = nil
        } catch let error as StudyNo1PayloadValidationError {
            message = .incompletePayload(String(describing: error))
        } catch {
            message = .submissionFailed(error.localizedDescription)
        }
    }

    func makeOrientationThresholdPayload(
        result: StudyNo1OrientationThresholdResult,
        scheduledTask: ScheduledTask,
        enrollment: StudyEnrollment,
        submittedAt: Date? = nil
    ) throws -> StudyNo1OrientationThresholdRunPayload {
        guard let rightEar = result.rightEar?.studyNo1Context else {
            throw StudyNo1OrientationThresholdPayloadValidationError.missingRequiredFields(["rightEar.thresholdDBHL"])
        }
        guard let leftEar = result.leftEar?.studyNo1Context else {
            throw StudyNo1OrientationThresholdPayloadValidationError.missingRequiredFields(["leftEar.thresholdDBHL"])
        }
        guard let environment = environmentGateResult?.studyNo1Context else {
            throw StudyNo1OrientationThresholdPayloadValidationError.missingRequiredFields(["environment.samplesDBA"])
        }

        currentGuardrailValidation = guardrailProvider()
        return try StudyNo1OrientationThresholdPayloadBuilder().build(
            identifiers: StudyNo1IdentifierContext(
                participantId: enrollment.userID.uuidString,
                studySessionId: enrollment.id.uuidString,
                enrollmentId: enrollment.id.uuidString,
                scheduledTaskId: scheduledTask.id.uuidString
            ),
            startedAt: events.first?.timestamp ?? dateProvider(),
            completedAt: submittedAt ?? dateProvider(),
            submittedAt: submittedAt,
            guardrailValidation: currentGuardrailValidation,
            device: runtimeContextProvider.deviceContext(),
            airPods: runtimeContextProvider.airPodsContext(guardrailValidation: currentGuardrailValidation),
            audioSession: runtimeContextProvider.audioSessionContext(),
            environment: environment,
            rightEar: rightEar,
            leftEar: leftEar
        )
    }

    func makeOrientationThresholdSubmission(
        result: StudyNo1OrientationThresholdResult,
        scheduledTask: ScheduledTask,
        enrollment: StudyEnrollment
    ) throws -> StudyNo1OrientationThresholdSubmission {
        let submittedAt = dateProvider()
        let payload = try makeOrientationThresholdPayload(
            result: result,
            scheduledTask: scheduledTask,
            enrollment: enrollment,
            submittedAt: submittedAt
        )
        return try orientationThresholdExporter.makeSubmission(from: payload)
    }

    func submitOrientationThreshold(
        result: StudyNo1OrientationThresholdResult,
        scheduledTask: ScheduledTask,
        enrollment: StudyEnrollment,
        studyService: StudyServiceProtocol
    ) async -> Bool {
        guard !isSubmitting, !hasSubmitted else {
            return false
        }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let submission = try makeOrientationThresholdSubmission(
                result: result,
                scheduledTask: scheduledTask,
                enrollment: enrollment
            )
            try await studyService.submitStudyNo1OrientationThreshold(
                scheduledTaskID: scheduledTask.id,
                enrollmentID: enrollment.id,
                submission: submission
            )
            hasSubmitted = true
            message = nil
            return true
        } catch let error as StudyNo1OrientationThresholdPayloadValidationError {
            message = .incompletePayload(String(describing: error))
            return false
        } catch {
            message = .submissionFailed(error.localizedDescription)
            return false
        }
    }

    func clearMessage() {
        message = nil
    }

    private func syncFromEngine() {
        protocolState = engine.state
        if case .completed(let summary) = engine.state {
            completedSummary = summary
        }
    }

    private func startPlaybackGuardrailMonitoring() {
        guardrailMonitor?.startMonitoring { [weak self] validation in
            guard validation.state != .passed else {
                return
            }

            Task { @MainActor in
                guard let self else {
                    return
                }

                if self.shouldPauseForRouteInterruption(validation) {
                    self.evaluateAirPodsContinuity()
                    return
                }

                if self.isPlaying {
                    self.stopTone()
                }
                self.engine.applyGuardrailValidation(validation)
                self.currentGuardrailValidation = validation
                self.syncFromEngine()
            }
        }
    }

    private func shouldPauseForRouteInterruption(_ validation: CalibratedAudioGuardrailValidation) -> Bool {
        switch validation.error {
        case .routeChanged, .unsupportedRoute, .unverifiedHeadphoneProfile, .unavailableAudioSessionData:
            return true
        case .invalidVolume, .volumeChanged, .missingCalibrationProfile, nil:
            return false
        }
    }

    private var hasRequestedStimulus: Bool {
        events.contains { event in
            event.kind == .thresholdToneRequested
                || event.kind == .thresholdPlaybackPlanned
                || event.kind == .playRequested
                || event.kind == .playbackPlanned
        }
    }

    private var isReadyForLoudnessTrial: Bool {
        if case .readyForTrial = protocolState {
            return true
        }
        return false
    }
}

extension LoudnessMatchTaskFlowViewModel: StudyOrientationThresholdSubmissionBuilding {}

private enum OrientationThresholdPlaybackError: LocalizedError {
    case playbackAlreadyActive
    case playbackDisabled
    case preflightUnavailable

    var errorDescription: String? {
        switch self {
        case .playbackAlreadyActive:
            return "Another calibrated tone is already playing."
        case .playbackDisabled:
            return "Calibrated hearing-test playback is unavailable."
        case .preflightUnavailable:
            return "Your AirPods, room, or volume changed. Review the audio setup before continuing."
        }
    }
}

private extension StudyNo1OrientationThresholdEarResult {
    var studyNo1Context: StudyNo1OrientationThresholdEarContext? {
        guard let thresholdDBHL else {
            return nil
        }

        return StudyNo1OrientationThresholdEarContext(
            channel: channel,
            frequencyHz: 1_000,
            thresholdDBHL: thresholdDBHL,
            outputVolume: outputVolume,
            headphoneType: headphoneType,
            tonePlaybackDuration: tonePlaybackDuration,
            postStimulusDelay: postStimulusDelay,
            samples: samples.map(\.studyNo1Context)
        )
    }
}

private extension StudyNo1OrientationThresholdFrequencySample {
    var studyNo1Context: StudyNo1OrientationThresholdFrequencySampleContext {
        StudyNo1OrientationThresholdFrequencySampleContext(
            frequencyHz: frequencyHz,
            calculatedThresholdDBHL: calculatedThresholdDBHL,
            channel: channel,
            units: units.map(\.studyNo1Context)
        )
    }
}

private extension StudyNo1OrientationThresholdUnit {
    var studyNo1Context: StudyNo1OrientationThresholdUnitContext {
        StudyNo1OrientationThresholdUnitContext(
            levelDBHL: levelDBHL,
            startOfUnitTimeStamp: startOfUnitTimeStamp,
            preStimulusDelay: preStimulusDelay,
            userTapTimeStamp: userTapTimeStamp,
            timeoutTimeStamp: timeoutTimeStamp
        )
    }
}

struct EnvironmentGateTaskGeneration {
    typealias Token = UInt64

    private var currentToken: Token = 0

    @discardableResult
    mutating func begin() -> Token {
        advance()
    }

    @discardableResult
    mutating func invalidate() -> Token {
        advance()
    }

    func isCurrent(_ token: Token) -> Bool {
        token == currentToken
    }

    private mutating func advance() -> Token {
        currentToken &+= 1
        return currentToken
    }
}

private struct OneShotEnvironmentSPLGateMonitor: EnvironmentSPLGateMonitoring {
    let meter: EnvironmentSPLMeasuring

    func makeMonitor(
        configuration: TinnitusEnvironmentSPLGateConfiguration,
        reason: TinnitusEnvironmentSPLReacquisitionReason
    ) -> any EnvironmentSPLMonitorSession {
        OneShotEnvironmentSPLMonitorSession(
            meter: meter,
            configuration: configuration,
            reason: reason
        )
    }
}

@MainActor
private final class OneShotEnvironmentSPLMonitorSession: EnvironmentSPLMonitorSession {
    let events: AsyncThrowingStream<TinnitusEnvironmentSPLMonitorEvent, Error>
    private let continuation: AsyncThrowingStream<TinnitusEnvironmentSPLMonitorEvent, Error>.Continuation
    private var task: Task<Void, Never>?

    init(
        meter: EnvironmentSPLMeasuring,
        configuration: TinnitusEnvironmentSPLGateConfiguration,
        reason: TinnitusEnvironmentSPLReacquisitionReason
    ) {
        var captured: AsyncThrowingStream<TinnitusEnvironmentSPLMonitorEvent, Error>.Continuation!
        events = AsyncThrowingStream { captured = $0 }
        continuation = captured
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                self.continuation.yield(.warmingUp(reason))
                let result = try await meter.runGate(configuration: configuration)
                self.continuation.yield(.ready)
                for measurement in result.measurements {
                    self.continuation.yield(.measurement(measurement))
                }
                self.continuation.finish()
            } catch is CancellationError {
                self.continuation.finish()
            } catch {
                self.continuation.finish(throwing: error)
            }
        }
    }

    func stop() async {
        task?.cancel()
        task = nil
        continuation.finish()
    }
}
