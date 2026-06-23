import Combine
import Foundation

@MainActor
final class LoudnessMatchTaskFlowViewModel: ObservableObject {
    enum FlowMessage: Equatable {
        case playbackDisabled
        case environmentGateFailed
        case missingPreflight(String)
        case incompletePayload(String)
        case guardrailsUnavailable
        case environmentGateUnavailable(String)
        case playbackFailed(String)
        case submissionFailed(String)
    }

    @Published private(set) var protocolState: TinnitusProtocolState
    @Published private(set) var selectedLaterality: TinnitusLaterality?
    @Published var researchProtocolAirPodsPro2Verified = false {
        didSet {
            researchProtocolResolver?.airPodsPro2Verified = researchProtocolAirPodsPro2Verified
            refreshGuardrails()
        }
    }
    @Published var fitSealConfirmed = false
    @Published var safetyAcknowledged = false
    @Published private(set) var environmentGateResult: TinnitusEnvironmentSPLGateResult?
    @Published private(set) var environmentGateUpdate: TinnitusEnvironmentSPLGateUpdate?
    @Published private(set) var isRunningEnvironmentGate = false
    @Published private(set) var isVolumeGateMonitoring = false
    @Published private(set) var thresholdStaircase: TinnitusThresholdStaircase
    @Published private(set) var currentGuardrailValidation: CalibratedAudioGuardrailValidation
    @Published private(set) var message: FlowMessage?
    @Published private(set) var isPlaying = false
    @Published private(set) var canRecordThresholdResponse = false
    @Published private(set) var isSubmitting = false
    @Published private(set) var hasSubmitted = false
    @Published private(set) var completedSummary: TinnitusLoudnessMatchSummary?

    private var engine: TinnitusProtocolEngine
    private let player: CalibratedTonePlaying?
    private let guardrailMonitor: CalibratedAudioSessionGuardrailMonitor?
    private let guardrailProvider: () -> CalibratedAudioGuardrailValidation
    private let environmentMeter: EnvironmentSPLMeasuring
    private let environmentGateMonitor: EnvironmentSPLGateMonitoring
    private let allowsCalibratedPlayback: Bool
    private let runtimeContextProvider: Phase6RuntimeContextProviding
    private let submissionExporter: Phase6LoudnessMatchSubmissionExporter
    private let dateProvider: () -> Date
    private let researchProtocolResolver: ResearchProtocolCalibratedHeadphoneResolver?
    private var environmentGateTask: Task<Void, Never>?

    init(
        engine: TinnitusProtocolEngine? = nil,
        player: CalibratedTonePlaying? = nil,
        guardrailProvider: (() -> CalibratedAudioGuardrailValidation)? = nil,
        environmentMeter: EnvironmentSPLMeasuring? = nil,
        environmentGateMonitor: EnvironmentSPLGateMonitoring? = nil,
        allowsCalibratedPlayback: Bool = true,
        runtimeContextProvider: Phase6RuntimeContextProviding? = nil,
        submissionExporter: Phase6LoudnessMatchSubmissionExporter? = nil,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        let resolvedEngine = engine ?? TinnitusProtocolEngine()
        let resolver: ResearchProtocolCalibratedHeadphoneResolver?
        let monitor: CalibratedAudioSessionGuardrailMonitor?
        let resolvedPlayer: CalibratedTonePlaying?
        let resolvedGuardrailProvider: () -> CalibratedAudioGuardrailValidation

        if let guardrailProvider {
            resolver = nil
            monitor = nil
            resolvedGuardrailProvider = guardrailProvider
            resolvedPlayer = player
        } else {
            let researchResolver = ResearchProtocolCalibratedHeadphoneResolver()
            let guardrailMonitor = CalibratedAudioSessionGuardrailMonitor(profileResolver: researchResolver)
            resolver = researchResolver
            monitor = guardrailMonitor
            resolvedGuardrailProvider = {
                guardrailMonitor.validateCurrentGuardrails()
            }
            resolvedPlayer = player ?? CalibratedToneAudioPlayer()
        }

        self.engine = resolvedEngine
        self.player = resolvedPlayer
        self.guardrailMonitor = monitor
        self.guardrailProvider = resolvedGuardrailProvider
        let resolvedEnvironmentMeter = environmentMeter ?? AVAudioEnvironmentSPLMeter()
        self.environmentMeter = resolvedEnvironmentMeter
        self.environmentGateMonitor = environmentGateMonitor
            ?? (resolvedEnvironmentMeter as? EnvironmentSPLGateMonitoring)
            ?? OneShotEnvironmentSPLGateMonitor(meter: resolvedEnvironmentMeter)
        self.allowsCalibratedPlayback = allowsCalibratedPlayback
        self.runtimeContextProvider = runtimeContextProvider ?? SystemPhase6RuntimeContextProvider()
        self.submissionExporter = submissionExporter ?? Phase6LoudnessMatchSubmissionExporter()
        self.dateProvider = dateProvider
        self.researchProtocolResolver = resolver
        protocolState = resolvedEngine.state
        thresholdStaircase = TinnitusThresholdStaircase()
        currentGuardrailValidation = self.guardrailProvider()
    }

    var events: [TinnitusProtocolEvent] {
        engine.events
    }

    var canPlayTone: Bool {
        allowsCalibratedPlayback
            && currentGuardrailValidation.state == .passed
            && preflightReady
            && currentCandidateLevelDBHL != nil
    }

    var canPlayThresholdTone: Bool {
        allowsCalibratedPlayback
            && currentGuardrailValidation.state == .passed
            && preflightReady
            && !thresholdStaircase.isComplete
    }

    var preflightReady: Bool {
        currentGuardrailValidation.state == .passed
            && environmentGateResult?.passed == true
            && fitSealConfirmed
            && safetyAcknowledged
    }

    var canSubmit: Bool {
        completedSummary != nil
            && preflightReady
            && !isSubmitting
            && !hasSubmitted
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
        if currentGuardrailValidation.state != .passed, hasRequestedStimulus {
            engine.applyGuardrailValidation(currentGuardrailValidation)
            syncFromEngine()
        }
    }

    func selectLaterality(_ laterality: TinnitusLaterality) {
        selectedLaterality = laterality
        thresholdStaircase = TinnitusThresholdStaircase()
        engine.selectLaterality(laterality)
        syncFromEngine()
    }

    func markThresholdUnavailable() {
        engine.markThresholdUnavailable(reason: "Threshold estimator is not enabled in this Phase 4 scaffold.")
        syncFromEngine()
    }

    func runEnvironmentGate() async {
        guard !isRunningEnvironmentGate else {
            return
        }

        isRunningEnvironmentGate = true
        environmentGateResult = nil
        environmentGateUpdate = TinnitusEnvironmentSPLGateUpdate(
            samplesDBA: [],
            latestSampleDBA: nil,
            contiguousPassingSamples: 0,
            status: .measuring,
            result: nil
        )
        defer { isRunningEnvironmentGate = false }

        do {
            let result = try await environmentMeter.runGate(configuration: .studyA)
            environmentGateResult = result
            environmentGateUpdate = TinnitusEnvironmentSPLGateEvaluator().update(
                samplesDBA: result.samplesDBA,
                configuration: result.configuration
            )
            message = result.passed ? nil : .environmentGateFailed
        } catch {
            message = .environmentGateUnavailable(error.localizedDescription)
        }
    }

    func startContinuousEnvironmentGate() {
        guard !isRunningEnvironmentGate else {
            return
        }

        environmentGateResult = nil
        environmentGateUpdate = TinnitusEnvironmentSPLGateUpdate(
            samplesDBA: [],
            latestSampleDBA: nil,
            contiguousPassingSamples: 0,
            status: .measuring,
            result: nil
        )
        isRunningEnvironmentGate = true
        message = nil

        let stream = environmentGateMonitor.monitorGate(configuration: .studyA)
        environmentGateTask = Task { [weak self] in
            do {
                for try await update in stream {
                    guard let self else {
                        return
                    }

                    self.environmentGateUpdate = update
                    if let result = update.result {
                        self.environmentGateResult = result
                        self.isRunningEnvironmentGate = false
                        self.environmentGateTask = nil
                        self.message = nil
                        return
                    }
                }

                guard let self else {
                    return
                }
                self.isRunningEnvironmentGate = false
                self.environmentGateTask = nil
            } catch {
                guard let self else {
                    return
                }
                self.isRunningEnvironmentGate = false
                self.environmentGateTask = nil
                self.message = .environmentGateUnavailable(error.localizedDescription)
            }
        }
    }

    func cancelEnvironmentGate() {
        environmentGateTask?.cancel()
        environmentGateTask = nil
        isRunningEnvironmentGate = false
        if environmentGateResult?.passed != true {
            environmentGateResult = nil
        }
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

    func playThresholdTone() {
        guard allowsCalibratedPlayback else {
            message = .playbackDisabled
            return
        }

        guard preflightReady else {
            message = .missingPreflight("Complete audio guardrails, AirPods Pro 2 research verification, quiet-room gate, fit/seal confirmation, and safety acknowledgement before threshold playback.")
            return
        }

        currentGuardrailValidation = guardrailProvider()
        guard currentGuardrailValidation.state == .passed else {
            let attempt = engine.playThresholdTone(
                levelDBHL: thresholdStaircase.currentLevelDBHL,
                guardrailValidation: currentGuardrailValidation
            )
            message = attempt.refusalReason == nil ? .guardrailsUnavailable : .guardrailsUnavailable
            syncFromEngine()
            return
        }

        let attempt = engine.playThresholdTone(
            levelDBHL: thresholdStaircase.currentLevelDBHL,
            guardrailValidation: currentGuardrailValidation
        )
        guard let request = attempt.request, attempt.refusalReason == nil else {
            message = .guardrailsUnavailable
            syncFromEngine()
            return
        }

        do {
            _ = try player?.play(request)
            isPlaying = true
            canRecordThresholdResponse = true
            startPlaybackGuardrailMonitoring()
            message = nil
        } catch {
            message = .playbackFailed(error.localizedDescription)
        }

        syncFromEngine()
    }

    func recordThresholdResponse(_ response: TinnitusThresholdResponse) {
        guard canRecordThresholdResponse else {
            message = .missingPreflight("Play the threshold tone before recording a heard or not-heard response.")
            return
        }

        let presentedLevel = thresholdStaircase.currentLevelDBHL
        if isPlaying {
            stopTone()
        }
        canRecordThresholdResponse = false

        engine.recordThresholdResponse(levelDBHL: presentedLevel, response: response)
        thresholdStaircase.recordResponse(response)

        if let measuredThreshold = thresholdStaircase.measuredThresholdDBHL {
            engine.recordThreshold(levelDBHL: measuredThreshold)
        }

        syncFromEngine()
    }

    func adjustLevel(_ adjustment: TinnitusLoudnessAdjustment) {
        engine.adjustLevel(adjustment)
        syncFromEngine()
    }

    func playTone() {
        guard allowsCalibratedPlayback else {
            message = .playbackDisabled
            return
        }

        guard preflightReady else {
            message = .missingPreflight("Complete audio guardrails, quiet-room samples, fit/seal confirmation, and safety acknowledgement before playback.")
            return
        }

        currentGuardrailValidation = guardrailProvider()
        guard currentGuardrailValidation.state == .passed else {
            let attempt = engine.playCurrentTone(guardrailValidation: currentGuardrailValidation)
            message = attempt.refusalReason == nil ? .guardrailsUnavailable : .guardrailsUnavailable
            syncFromEngine()
            return
        }

        let attempt = engine.playCurrentTone(guardrailValidation: currentGuardrailValidation)
        guard let request = attempt.request, attempt.refusalReason == nil else {
            message = .guardrailsUnavailable
            syncFromEngine()
            return
        }

        do {
            _ = try player?.play(request)
            isPlaying = true
            startPlaybackGuardrailMonitoring()
            message = nil
        } catch {
            message = .playbackFailed(error.localizedDescription)
        }

        syncFromEngine()
    }

    func stopTone() {
        guardrailMonitor?.stopMonitoring()
        let metadata = player?.stop()
        isPlaying = false
        canRecordThresholdResponse = false
        engine.recordStop(playbackMetadata: metadata)
        syncFromEngine()
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
        cancelEnvironmentGate()
        stopVolumeGateMonitoring()
        if isPlaying {
            guardrailMonitor?.stopMonitoring()
            _ = player?.stop()
            isPlaying = false
        }
        engine.abort(.participantStopped)
        syncFromEngine()
    }

    func makePhase6Payload(
        scheduledTask: ScheduledTask,
        enrollment: StudyEnrollment,
        submittedAt: Date? = nil
    ) throws -> Phase6LoudnessMatchRunPayload {
        guard let summary = completedSummary else {
            throw Phase6PayloadValidationError.incompleteStudyA(reason: "Study A is not complete.")
        }
        guard let environment = environmentGateResult?.phase6Context else {
            throw Phase6PayloadValidationError.missingRequiredFields(["environment.samplesDBA"])
        }
        guard fitSealConfirmed else {
            throw Phase6PayloadValidationError.missingRequiredFields(["fitSeal.status"])
        }
        guard safetyAcknowledged else {
            throw Phase6PayloadValidationError.missingRequiredFields(["safety.acknowledgedAt"])
        }

        currentGuardrailValidation = guardrailProvider()
        let preflight = Phase6PreflightContext(
            identifiers: Phase6IdentifierContext(
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
            fitSeal: Phase6FitSealContext(
                status: .confirmedPassed,
                confirmedAt: dateProvider(),
                limitations: "Participant confirmation; public iOS APIs do not expose Apple's Ear Tip Fit Test result."
            ),
            safety: Phase6SafetyContext(
                acknowledgedAt: dateProvider(),
                stopControlVisibleBeforePlayback: true,
                maximumLevelDBHL: 100.0,
                limitation: "Immediate stop is visible during playback; no clinical or diagnostic claim."
            ),
            thresholdSource: .measured
        )

        return try Phase6LoudnessMatchPayloadBuilder().buildStudyAPayload(
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
            let payload = try makePhase6Payload(
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
        } catch let error as Phase6PayloadValidationError {
            message = .incompletePayload(String(describing: error))
        } catch {
            message = .submissionFailed(error.localizedDescription)
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

                if self.isPlaying {
                    self.stopTone()
                }
                self.engine.applyGuardrailValidation(validation)
                self.currentGuardrailValidation = validation
                self.syncFromEngine()
            }
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
}

private struct OneShotEnvironmentSPLGateMonitor: EnvironmentSPLGateMonitoring {
    let meter: EnvironmentSPLMeasuring

    func monitorGate(
        configuration: TinnitusEnvironmentSPLGateConfiguration
    ) -> AsyncThrowingStream<TinnitusEnvironmentSPLGateUpdate, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let result = try await meter.runGate(configuration: configuration)
                    let update = TinnitusEnvironmentSPLGateEvaluator().update(
                        samplesDBA: result.samplesDBA,
                        configuration: result.configuration
                    )
                    continuation.yield(update)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
