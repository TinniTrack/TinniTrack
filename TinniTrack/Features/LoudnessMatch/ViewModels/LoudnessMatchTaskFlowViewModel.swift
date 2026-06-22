import Combine
import Foundation

@MainActor
final class LoudnessMatchTaskFlowViewModel: ObservableObject {
    enum FlowMessage: Equatable {
        case playbackDisabled
        case invalidThreshold
        case guardrailsUnavailable
        case playbackFailed(String)
    }

    @Published private(set) var protocolState: TinnitusProtocolState
    @Published private(set) var selectedLaterality: TinnitusLaterality?
    @Published var thresholdLevelText = ""
    @Published private(set) var currentGuardrailValidation: CalibratedAudioGuardrailValidation
    @Published private(set) var message: FlowMessage?
    @Published private(set) var isPlaying = false
    @Published private(set) var completedSummary: TinnitusLoudnessMatchSummary?

    private var engine: TinnitusProtocolEngine
    private let player: CalibratedTonePlaying?
    private let guardrailProvider: () -> CalibratedAudioGuardrailValidation
    private let allowsCalibratedPlayback: Bool

    init(
        engine: TinnitusProtocolEngine? = nil,
        player: CalibratedTonePlaying? = nil,
        guardrailProvider: (() -> CalibratedAudioGuardrailValidation)? = nil,
        allowsCalibratedPlayback: Bool = false
    ) {
        let resolvedEngine = engine ?? TinnitusProtocolEngine()
        self.engine = resolvedEngine
        self.player = player
        self.guardrailProvider = guardrailProvider ?? {
            CalibratedAudioGuardrailSession().validation
        }
        self.allowsCalibratedPlayback = allowsCalibratedPlayback
        protocolState = resolvedEngine.state
        currentGuardrailValidation = self.guardrailProvider()
    }

    var events: [TinnitusProtocolEvent] {
        engine.events
    }

    var canPlayTone: Bool {
        allowsCalibratedPlayback
            && currentGuardrailValidation.state == .passed
            && currentCandidateLevelDBHL != nil
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

    func clearMessage() {
        message = nil
    }

    private func syncFromEngine() {
        protocolState = engine.state
        if case .completed(let summary) = engine.state {
            completedSummary = summary
        }
    }
}
