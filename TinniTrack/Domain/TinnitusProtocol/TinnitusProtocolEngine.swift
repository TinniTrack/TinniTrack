import Foundation

struct TinnitusProtocolEngine {
    private let configuration: TinnitusProtocolConfiguration
    private let converter: CalibratedAudioConverter
    private let playbackPlanner: CalibratedTonePlaybackPlanner
    private let dateProvider: () -> Date

    private(set) var state: TinnitusProtocolState = .collectingLaterality
    private(set) var laterality: TinnitusLaterality?
    private(set) var channel: CalibratedTonePlaybackChannel?
    private(set) var pitchMatchStatus: TinnitusPitchMatchStatus
    private(set) var thresholdStatus: TinnitusThresholdStatus = .pending
    private(set) var trials: [TinnitusLoudnessMatchTrial] = []
    private(set) var events: [TinnitusProtocolEvent] = []
    private var sessionQualityFlags: [TinnitusProtocolQualityFlag] = []

    init(
        configuration: TinnitusProtocolConfiguration = .studyNo1FixedOneKilohertz,
        converter: CalibratedAudioConverter = CalibratedAudioConverter(),
        playbackPlanner: CalibratedTonePlaybackPlanner = CalibratedTonePlaybackPlanner(),
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.configuration = configuration
        self.converter = converter
        self.playbackPlanner = playbackPlanner
        self.dateProvider = dateProvider
        pitchMatchStatus = configuration.kind == .studyNo1FixedOneKilohertz
            ? .notRequiredFixedFrequency
            : .deferred

        appendEvent(kind: .sessionStarted)
    }

    var frequencyHz: Double {
        configuration.frequencyHz
    }

    var currentCandidateLevelDBHL: Double? {
        guard case .readyForTrial(_, let candidateLevelDBHL) = state else {
            return nil
        }
        return candidateLevelDBHL
    }

    mutating func selectLaterality(_ laterality: TinnitusLaterality) {
        guard case .collectingLaterality = state else {
            abort(.invalidState("Laterality can only be selected before threshold collection."))
            return
        }

        let selectedChannel = Self.channel(for: laterality)
        self.laterality = laterality
        channel = selectedChannel
        if laterality == .bilateral || laterality == .central || laterality == .unclear {
            insertQualityFlag(.ambiguousLaterality)
        }

        state = .awaitingThreshold(laterality: laterality, channel: selectedChannel)
        appendEvent(
            kind: .lateralitySelected,
            channel: selectedChannel,
            laterality: laterality,
            response: "study_no_1_rule_unilateral_affected_else_left_first"
        )
    }

    mutating func selectLaterality(
        _ laterality: TinnitusLaterality,
        healthKitAudiogramThresholdDBHL: Double
    ) {
        guard case .collectingLaterality = state else {
            abort(.invalidState("Laterality can only be selected before loudness matching starts."))
            return
        }

        let selectedChannel = Self.channel(for: laterality)
        self.laterality = laterality
        channel = selectedChannel
        if laterality == .bilateral || laterality == .central || laterality == .unclear {
            insertQualityFlag(.ambiguousLaterality)
        }

        appendEvent(
            kind: .lateralitySelected,
            channel: selectedChannel,
            laterality: laterality,
            response: "study_no_1_rule_unilateral_affected_else_left_first"
        )

        thresholdStatus = .measured(levelDBHL: healthKitAudiogramThresholdDBHL)
        appendEvent(
            kind: .thresholdRecorded,
            frequencyHz: configuration.frequencyHz,
            presentedLevelDBHL: healthKitAudiogramThresholdDBHL,
            estimatedDBSPL: estimatedDBSPL(for: healthKitAudiogramThresholdDBHL),
            dbSL: 0.0,
            channel: selectedChannel,
            response: "healthkit_audiogram"
        )
        startNextTrial()
    }

    mutating func recordThreshold(levelDBHL: Double) {
        guard let channel, case .awaitingThreshold = state else {
            abort(.invalidState("Threshold can only be recorded after laterality selection."))
            return
        }

        thresholdStatus = .measured(levelDBHL: levelDBHL)
        appendEvent(
            kind: .thresholdRecorded,
            frequencyHz: configuration.frequencyHz,
            presentedLevelDBHL: levelDBHL,
            estimatedDBSPL: estimatedDBSPL(for: levelDBHL),
            dbSL: 0.0,
            channel: channel
        )
        startNextTrial()
    }

    mutating func playThresholdTone(
        levelDBHL: Double,
        guardrailValidation: CalibratedAudioGuardrailValidation
    ) -> TinnitusProtocolPlaybackAttempt {
        guard case .awaitingThreshold = state,
              let channel
        else {
            let reason = TinnitusProtocolAbortReason.invalidState("Threshold tone can only be played during threshold collection.")
            abort(reason)
            return TinnitusProtocolPlaybackAttempt(request: nil, plan: nil, refusalReason: reason)
        }

        appendEvent(
            kind: .thresholdToneRequested,
            frequencyHz: configuration.frequencyHz,
            presentedLevelDBHL: levelDBHL,
            estimatedDBSPL: estimatedDBSPL(for: levelDBHL),
            dbSL: nil,
            channel: channel,
            guardrailMetadata: guardrailValidation.metadata
        )

        if let refusal = guardrailRefusal(for: guardrailValidation) {
            applyPlaybackRefusal(refusal, validation: guardrailValidation, levelDBHL: levelDBHL)
            return TinnitusProtocolPlaybackAttempt(request: nil, plan: nil, refusalReason: refusal)
        }

        let request = CalibratedTonePlaybackRequest(
            frequencyHz: configuration.frequencyHz,
            levelDBHL: levelDBHL,
            channel: channel,
            duration: configuration.toneDuration,
            rampDuration: configuration.rampDuration,
            guardrailValidation: guardrailValidation
        )

        do {
            let plan = try playbackPlanner.makePlan(for: request)
            appendEvent(
                kind: .thresholdPlaybackPlanned,
                frequencyHz: plan.metadata.frequencyHz,
                presentedLevelDBHL: plan.metadata.requestedDBHL,
                estimatedDBSPL: plan.metadata.targetDBSPL,
                dbSL: nil,
                channel: plan.metadata.channel,
                guardrailMetadata: guardrailValidation.metadata,
                playbackMetadata: plan.metadata
            )
            return TinnitusProtocolPlaybackAttempt(request: request, plan: plan, refusalReason: nil)
        } catch let error as CalibrationConversionError {
            let reason: TinnitusProtocolAbortReason
            if case .unsupportedFrequency(let frequencyHz, _) = error {
                reason = .unsupportedFrequency(frequencyHz)
                insertQualityFlag(.unsupportedFrequency)
            } else {
                reason = .safetyRefusal(String(describing: error))
                insertQualityFlag(.safetyLimitRefused)
            }
            applyPlaybackRefusal(reason, validation: guardrailValidation, levelDBHL: levelDBHL)
            return TinnitusProtocolPlaybackAttempt(request: request, plan: nil, refusalReason: reason)
        } catch {
            let reason = TinnitusProtocolAbortReason.safetyRefusal(error.localizedDescription)
            insertQualityFlag(.playbackRefused)
            applyPlaybackRefusal(reason, validation: guardrailValidation, levelDBHL: levelDBHL)
            return TinnitusProtocolPlaybackAttempt(request: request, plan: nil, refusalReason: reason)
        }
    }

    mutating func recordThresholdResponse(
        levelDBHL: Double,
        response: TinnitusThresholdResponse
    ) {
        guard case .awaitingThreshold = state else {
            abort(.invalidState("Threshold responses can only be recorded during threshold collection."))
            return
        }

        appendEvent(
            kind: .thresholdResponseRecorded,
            frequencyHz: configuration.frequencyHz,
            presentedLevelDBHL: levelDBHL,
            estimatedDBSPL: estimatedDBSPL(for: levelDBHL),
            dbSL: nil,
            channel: channel,
            response: response.rawValue
        )
    }

    mutating func markThresholdUnavailable(reason: String) {
        guard case .awaitingThreshold = state else {
            abort(.invalidState("Threshold can only be marked unavailable after laterality selection."))
            return
        }

        thresholdStatus = .unavailable(reason: reason)
        insertQualityFlag(.thresholdUnavailable)
        insertQualityFlag(.dbSLInvalid)
        appendEvent(
            kind: .thresholdUnavailable,
            frequencyHz: configuration.frequencyHz,
            channel: channel,
            reason: reason,
            qualityFlags: [.thresholdUnavailable, .dbSLInvalid]
        )
        startNextTrial()
    }

    mutating func adjustLevel(_ adjustment: TinnitusLoudnessAdjustment) {
        guard case .readyForTrial(let index, let candidateLevelDBHL) = state else {
            abort(.invalidState("Level can only be adjusted during an active loudness trial."))
            return
        }

        let adjusted = clampedLevel(candidateLevelDBHL + adjustment.deltaDB)
        state = .readyForTrial(index: index, candidateLevelDBHL: adjusted)
        appendEvent(
            kind: .levelAdjusted,
            frequencyHz: configuration.frequencyHz,
            presentedLevelDBHL: adjusted,
            estimatedDBSPL: estimatedDBSPL(for: adjusted),
            dbSL: dbSL(for: adjusted),
            channel: channel,
            response: "\(adjustment)"
        )
    }

    mutating func playCurrentTone(
        guardrailValidation: CalibratedAudioGuardrailValidation
    ) -> TinnitusProtocolPlaybackAttempt {
        guard case .readyForTrial(_, let candidateLevelDBHL) = state,
              let channel
        else {
            let reason = TinnitusProtocolAbortReason.invalidState("Tone can only be played during an active loudness trial.")
            abort(reason)
            return TinnitusProtocolPlaybackAttempt(request: nil, plan: nil, refusalReason: reason)
        }

        appendEvent(
            kind: .playRequested,
            frequencyHz: configuration.frequencyHz,
            presentedLevelDBHL: candidateLevelDBHL,
            estimatedDBSPL: estimatedDBSPL(for: candidateLevelDBHL),
            dbSL: dbSL(for: candidateLevelDBHL),
            channel: channel,
            guardrailMetadata: guardrailValidation.metadata
        )

        if let refusal = guardrailRefusal(for: guardrailValidation) {
            applyPlaybackRefusal(refusal, validation: guardrailValidation, levelDBHL: candidateLevelDBHL)
            return TinnitusProtocolPlaybackAttempt(request: nil, plan: nil, refusalReason: refusal)
        }

        let request = CalibratedTonePlaybackRequest(
            frequencyHz: configuration.frequencyHz,
            levelDBHL: candidateLevelDBHL,
            channel: channel,
            duration: configuration.toneDuration,
            rampDuration: configuration.rampDuration,
            guardrailValidation: guardrailValidation
        )

        do {
            let plan = try playbackPlanner.makePlan(for: request)
            appendEvent(
                kind: .playbackPlanned,
                frequencyHz: plan.metadata.frequencyHz,
                presentedLevelDBHL: plan.metadata.requestedDBHL,
                estimatedDBSPL: plan.metadata.targetDBSPL,
                dbSL: dbSL(for: plan.metadata.requestedDBHL),
                channel: plan.metadata.channel,
                guardrailMetadata: guardrailValidation.metadata,
                playbackMetadata: plan.metadata
            )
            return TinnitusProtocolPlaybackAttempt(request: request, plan: plan, refusalReason: nil)
        } catch let error as CalibrationConversionError {
            let reason: TinnitusProtocolAbortReason
            if case .unsupportedFrequency(let frequencyHz, _) = error {
                reason = .unsupportedFrequency(frequencyHz)
                insertQualityFlag(.unsupportedFrequency)
            } else {
                reason = .safetyRefusal(String(describing: error))
                insertQualityFlag(.safetyLimitRefused)
            }
            applyPlaybackRefusal(reason, validation: guardrailValidation, levelDBHL: candidateLevelDBHL)
            return TinnitusProtocolPlaybackAttempt(request: request, plan: nil, refusalReason: reason)
        } catch {
            let reason = TinnitusProtocolAbortReason.safetyRefusal(error.localizedDescription)
            insertQualityFlag(.playbackRefused)
            applyPlaybackRefusal(reason, validation: guardrailValidation, levelDBHL: candidateLevelDBHL)
            return TinnitusProtocolPlaybackAttempt(request: request, plan: nil, refusalReason: reason)
        }
    }

    mutating func recordStop(playbackMetadata: CalibratedTonePlaybackMetadata? = nil) {
        appendEvent(
            kind: .stopRequested,
            frequencyHz: configuration.frequencyHz,
            presentedLevelDBHL: currentCandidateLevelDBHL,
            estimatedDBSPL: currentCandidateLevelDBHL.flatMap(estimatedDBSPL),
            dbSL: currentCandidateLevelDBHL.flatMap(dbSL),
            channel: channel,
            playbackMetadata: playbackMetadata
        )
    }

    mutating func acceptCurrentLevel() {
        guard case .readyForTrial(let index, let candidateLevelDBHL) = state else {
            abort(.invalidState("A loudness level can only be accepted during an active trial."))
            return
        }

        let pending = PendingTinnitusLoudnessMatchTrial(
            trialIndex: index,
            acceptedLevelDBHL: candidateLevelDBHL,
            estimatedDBSPL: estimatedDBSPL(for: candidateLevelDBHL),
            dbSL: dbSL(for: candidateLevelDBHL),
            acceptedAt: dateProvider()
        )
        state = .awaitingConfidence(trial: pending)
        appendEvent(
            kind: .levelAccepted,
            frequencyHz: configuration.frequencyHz,
            presentedLevelDBHL: candidateLevelDBHL,
            estimatedDBSPL: pending.estimatedDBSPL,
            dbSL: pending.dbSL,
            channel: channel
        )
    }

    mutating func recordConfidence(_ confidence: TinnitusConfidenceRating) {
        guard case .awaitingConfidence(let pending) = state else {
            abort(.invalidState("Confidence can only be recorded after accepting a loudness match."))
            return
        }

        if confidence == .low {
            insertQualityFlag(.lowConfidence)
        }

        let trial = TinnitusLoudnessMatchTrial(
            trialIndex: pending.trialIndex,
            acceptedLevelDBHL: pending.acceptedLevelDBHL,
            estimatedDBSPL: pending.estimatedDBSPL,
            dbSL: pending.dbSL,
            confidence: confidence,
            acceptedAt: pending.acceptedAt
        )
        trials.append(trial)
        appendEvent(
            kind: .confidenceRecorded,
            frequencyHz: configuration.frequencyHz,
            presentedLevelDBHL: trial.acceptedLevelDBHL,
            estimatedDBSPL: trial.estimatedDBSPL,
            dbSL: trial.dbSL,
            channel: channel,
            confidence: confidence
        )

        if trials.count >= configuration.requiredTrialCount {
            complete()
        } else {
            startNextTrial()
        }
    }

    mutating func applyGuardrailValidation(_ validation: CalibratedAudioGuardrailValidation) {
        appendEvent(
            kind: .guardrailChanged,
            guardrailMetadata: validation.metadata,
            reason: String(describing: validation.error)
        )

        switch validation.state {
        case .passed:
            return
        case .notEvaluated:
            insertQualityFlag(.guardrailNotEvaluated)
            state = .restartRequired(.guardrailNotEvaluated)
        case .failed:
            insertQualityFlag(.guardrailFailed)
            state = .restartRequired(.guardrailFailed(String(describing: validation.error)))
        case .restartRequired:
            insertQualityFlag(.restartRequired)
            state = .restartRequired(.restartRequired(String(describing: validation.error)))
        }
    }

    mutating func abort(_ reason: TinnitusProtocolAbortReason) {
        state = .aborted(reason)
        appendEvent(kind: .abortRecorded, reason: "\(reason)")
    }

    private mutating func startNextTrial() {
        let index = trials.count + 1
        let startLevel = clampedLevel(initialLevelDBHL())
        state = .readyForTrial(index: index, candidateLevelDBHL: startLevel)
        appendEvent(
            kind: .trialStarted,
            frequencyHz: configuration.frequencyHz,
            presentedLevelDBHL: startLevel,
            estimatedDBSPL: estimatedDBSPL(for: startLevel),
            dbSL: dbSL(for: startLevel),
            channel: channel,
            qualityFlags: thresholdStatus.levelDBHL == nil ? [.thresholdUnavailable, .dbSLInvalid] : []
        )
    }

    private mutating func complete() {
        guard let channel else {
            abort(.invalidState("Cannot complete without a playback channel."))
            return
        }

        let acceptedLevels = trials.map(\.acceptedLevelDBHL)
        let spread = (acceptedLevels.max() ?? 0.0) - (acceptedLevels.min() ?? 0.0)
        if spread > configuration.highSpreadThresholdDB {
            insertQualityFlag(.highWithinSessionSpread)
        }

        let summary = TinnitusLoudnessMatchSummary(
            frequencyHz: configuration.frequencyHz,
            channel: channel,
            thresholdStatus: thresholdStatus,
            trials: trials,
            medianMatchedDBHL: Self.median(acceptedLevels) ?? 0.0,
            medianEstimatedDBSPL: Self.median(trials.compactMap(\.estimatedDBSPL)),
            medianDBSL: Self.median(trials.compactMap(\.dbSL)),
            withinSessionSpreadDB: spread,
            qualityFlags: sessionQualityFlags,
            completedAt: dateProvider()
        )

        state = .completed(summary)
        appendEvent(
            kind: .sessionCompleted,
            frequencyHz: summary.frequencyHz,
            presentedLevelDBHL: summary.medianMatchedDBHL,
            estimatedDBSPL: summary.medianEstimatedDBSPL,
            dbSL: summary.medianDBSL,
            channel: summary.channel,
            qualityFlags: summary.qualityFlags
        )
    }

    private func initialLevelDBHL() -> Double {
        switch thresholdStatus {
        case .measured(let levelDBHL):
            return levelDBHL + configuration.thresholdStartOffsetDBSL
        case .pending, .unavailable:
            return configuration.conservativeFallbackStartDBHL
        }
    }

    private func clampedLevel(_ level: Double) -> Double {
        min(max(level, configuration.minimumLevelDBHL), configuration.maximumLevelDBHL)
    }

    private func estimatedDBSPL(for levelDBHL: Double) -> Double? {
        try? converter.targetDBSPL(
            frequencyHz: configuration.frequencyHz,
            levelDBHL: levelDBHL
        )
    }

    private func dbSL(for levelDBHL: Double) -> Double? {
        thresholdStatus.levelDBHL.map { levelDBHL - $0 }
    }

    private func guardrailRefusal(
        for validation: CalibratedAudioGuardrailValidation
    ) -> TinnitusProtocolAbortReason? {
        switch validation.state {
        case .passed:
            return nil
        case .notEvaluated:
            return .guardrailNotEvaluated
        case .failed:
            return .guardrailFailed(String(describing: validation.error))
        case .restartRequired:
            return .restartRequired(String(describing: validation.error))
        }
    }

    private mutating func applyPlaybackRefusal(
        _ reason: TinnitusProtocolAbortReason,
        validation: CalibratedAudioGuardrailValidation,
        levelDBHL: Double
    ) {
        switch reason {
        case .guardrailNotEvaluated:
            insertQualityFlag(.guardrailNotEvaluated)
            state = .restartRequired(reason)
        case .guardrailFailed:
            insertQualityFlag(.guardrailFailed)
            state = .restartRequired(reason)
        case .restartRequired:
            insertQualityFlag(.restartRequired)
            state = .restartRequired(reason)
        case .safetyRefusal:
            insertQualityFlag(.safetyLimitRefused)
        default:
            insertQualityFlag(.playbackRefused)
        }

        appendEvent(
            kind: .playbackRefused,
            frequencyHz: configuration.frequencyHz,
            presentedLevelDBHL: levelDBHL,
            estimatedDBSPL: estimatedDBSPL(for: levelDBHL),
            dbSL: dbSL(for: levelDBHL),
            channel: channel,
            guardrailMetadata: validation.metadata,
            reason: "\(reason)",
            qualityFlags: sessionQualityFlags
        )
    }

    private mutating func insertQualityFlag(_ flag: TinnitusProtocolQualityFlag) {
        guard !sessionQualityFlags.contains(flag) else { return }
        sessionQualityFlags.append(flag)
    }

    private mutating func appendEvent(
        kind: TinnitusProtocolEventKind,
        frequencyHz: Double? = nil,
        presentedLevelDBHL: Double? = nil,
        estimatedDBSPL: Double? = nil,
        dbSL: Double? = nil,
        channel: CalibratedTonePlaybackChannel? = nil,
        laterality: TinnitusLaterality? = nil,
        confidence: TinnitusConfidenceRating? = nil,
        response: String? = nil,
        guardrailMetadata: CalibratedAudioGuardrailMetadata? = nil,
        playbackMetadata: CalibratedTonePlaybackMetadata? = nil,
        reason: String? = nil,
        qualityFlags: [TinnitusProtocolQualityFlag] = []
    ) {
        events.append(TinnitusProtocolEvent(
            timestamp: dateProvider(),
            kind: kind,
            frequencyHz: frequencyHz,
            presentedLevelDBHL: presentedLevelDBHL,
            estimatedDBSPL: estimatedDBSPL,
            dbSL: dbSL,
            channel: channel,
            laterality: laterality,
            confidence: confidence,
            response: response,
            guardrailMetadata: guardrailMetadata,
            playbackMetadata: playbackMetadata,
            reason: reason,
            qualityFlags: qualityFlags
        ))
    }

    static func channel(for laterality: TinnitusLaterality) -> CalibratedTonePlaybackChannel {
        switch laterality {
        case .left:
            return .left
        case .right:
            return .right
        case .bilateral, .central, .unclear:
            return .left
        }
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2.0
        }
        return sorted[middle]
    }
}
