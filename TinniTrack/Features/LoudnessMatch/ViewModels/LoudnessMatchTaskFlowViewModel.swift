import Combine
import Foundation

@MainActor
final class LoudnessMatchTaskFlowViewModel: ObservableObject {
    enum FlowMessage: Equatable {
        case playbackDisabled
        case invalidThreshold
        case invalidEnvironmentSamples
        case missingPreflight(String)
        case incompletePayload(String)
        case guardrailsUnavailable
        case playbackFailed(String)
        case submissionFailed(String)
    }

    @Published private(set) var protocolState: TinnitusProtocolState
    @Published private(set) var selectedLaterality: TinnitusLaterality?
    @Published var thresholdLevelText = ""
    @Published var environmentSamplesText = ""
    @Published var fitSealConfirmed = false
    @Published var safetyAcknowledged = false
    @Published private(set) var currentGuardrailValidation: CalibratedAudioGuardrailValidation
    @Published private(set) var message: FlowMessage?
    @Published private(set) var isPlaying = false
    @Published private(set) var isSubmitting = false
    @Published private(set) var hasSubmitted = false
    @Published private(set) var completedSummary: TinnitusLoudnessMatchSummary?

    private var engine: TinnitusProtocolEngine
    private let player: CalibratedTonePlaying?
    private let guardrailProvider: () -> CalibratedAudioGuardrailValidation
    private let allowsCalibratedPlayback: Bool
    private let runtimeContextProvider: Phase6RuntimeContextProviding
    private let submissionExporter: Phase6LoudnessMatchSubmissionExporter
    private let dateProvider: () -> Date

    private let environmentThresholdDBA = 45.0
    private let requiredEnvironmentSamples = 5
    private let environmentSamplingInterval = 1.0

    init(
        engine: TinnitusProtocolEngine? = nil,
        player: CalibratedTonePlaying? = nil,
        guardrailProvider: (() -> CalibratedAudioGuardrailValidation)? = nil,
        allowsCalibratedPlayback: Bool = false,
        runtimeContextProvider: Phase6RuntimeContextProviding? = nil,
        submissionExporter: Phase6LoudnessMatchSubmissionExporter? = nil,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        let resolvedEngine = engine ?? TinnitusProtocolEngine()
        self.engine = resolvedEngine
        self.player = player
        self.guardrailProvider = guardrailProvider ?? {
            CalibratedAudioGuardrailSession().validation
        }
        self.allowsCalibratedPlayback = allowsCalibratedPlayback
        self.runtimeContextProvider = runtimeContextProvider ?? SystemPhase6RuntimeContextProvider()
        self.submissionExporter = submissionExporter ?? Phase6LoudnessMatchSubmissionExporter()
        self.dateProvider = dateProvider
        protocolState = resolvedEngine.state
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

    var preflightReady: Bool {
        currentGuardrailValidation.state == .passed
            && environmentContextFromInput() != nil
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
        if currentGuardrailValidation.state != .passed {
            engine.applyGuardrailValidation(currentGuardrailValidation)
            syncFromEngine()
        }
    }

    func selectLaterality(_ laterality: TinnitusLaterality) {
        selectedLaterality = laterality
        engine.selectLaterality(laterality)
        syncFromEngine()
    }

    func recordThresholdFromInput() {
        guard let level = Double(thresholdLevelText.trimmingCharacters(in: .whitespacesAndNewlines)),
              level.isFinite
        else {
            message = .invalidThreshold
            return
        }

        engine.recordThreshold(levelDBHL: level)
        syncFromEngine()
    }

    func markThresholdUnavailable() {
        engine.markThresholdUnavailable(reason: "Threshold estimator is not enabled in this Phase 4 scaffold.")
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
            message = nil
        } catch {
            message = .playbackFailed(error.localizedDescription)
        }

        syncFromEngine()
    }

    func stopTone() {
        let metadata = player?.stop()
        isPlaying = false
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
        if isPlaying {
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
        guard let environment = environmentContextFromInput() else {
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
            thresholdSource: .manualScaffold
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

    private func environmentContextFromInput() -> Phase6EnvironmentSPLContext? {
        let tokens = environmentSamplesText
            .split { character in
                character == "," || character == "\n" || character == " "
            }
        let samples = tokens.compactMap { token -> Double? in
            guard let sample = Double(String(token).trimmingCharacters(in: .whitespacesAndNewlines)),
                  sample.isFinite else {
                return nil
            }
            return sample
        }

        guard samples.count == tokens.count, samples.count >= requiredEnvironmentSamples else {
            return nil
        }

        var contiguous = 0
        for sample in samples {
            if sample < environmentThresholdDBA {
                contiguous += 1
            } else {
                contiguous = 0
            }
        }

        let passed = samples.suffix(requiredEnvironmentSamples).allSatisfy { $0 < environmentThresholdDBA }
            || contiguous >= requiredEnvironmentSamples

        guard passed else {
            return nil
        }

        return Phase6EnvironmentSPLContext(
            thresholdDBA: environmentThresholdDBA,
            requiredContiguousSamples: requiredEnvironmentSamples,
            samplingInterval: environmentSamplingInterval,
            sensitivityOffsetDB: nil,
            samplesDBA: samples,
            gateResult: .recordedOnly
        )
    }

    private func syncFromEngine() {
        protocolState = engine.state
        if case .completed(let summary) = engine.state {
            completedSummary = summary
        }
    }
}
