import Foundation

enum TinnitusStudyProtocolKind: Equatable {
    case studyAFixedOneKilohertz
    case studyBTablePitchMatched
}

enum TinnitusLaterality: String, CaseIterable, Equatable {
    case left
    case right
    case bilateral
    case central
    case unclear
}

enum TinnitusStimulusKind: String, Equatable {
    case pureTone
    case narrowbandNoise
}

enum TinnitusPitchMatchStatus: Equatable {
    case notRequiredFixedFrequency
    case deferred
    case tableFrequency(Double)
}

enum TinnitusThresholdStatus: Equatable {
    case pending
    case measured(levelDBHL: Double)
    case unavailable(reason: String)

    var levelDBHL: Double? {
        if case .measured(let levelDBHL) = self {
            return levelDBHL
        }
        return nil
    }
}

enum TinnitusConfidenceRating: String, CaseIterable, Equatable {
    case low
    case medium
    case high
}

enum TinnitusLoudnessAdjustment: Equatable {
    case muchSofter
    case softer
    case louder
    case muchLouder

    var deltaDB: Double {
        switch self {
        case .muchSofter:
            return -5.0
        case .softer:
            return -1.0
        case .louder:
            return 1.0
        case .muchLouder:
            return 5.0
        }
    }
}

enum TinnitusProtocolQualityFlag: String, Equatable {
    case ambiguousLaterality
    case thresholdUnavailable
    case dbSLInvalid
    case highWithinSessionSpread
    case lowConfidence
    case guardrailNotEvaluated
    case guardrailFailed
    case restartRequired
    case playbackRefused
    case safetyLimitRefused
    case unsupportedFrequency
}

enum TinnitusProtocolAbortReason: Equatable {
    case participantStopped
    case guardrailNotEvaluated
    case guardrailFailed(String)
    case restartRequired(String)
    case safetyRefusal(String)
    case unsupportedFrequency(Double)
    case invalidState(String)
}

struct TinnitusProtocolConfiguration: Equatable {
    let kind: TinnitusStudyProtocolKind
    let stimulusKind: TinnitusStimulusKind
    let frequencyHz: Double
    let requiredTrialCount: Int
    let toneDuration: TimeInterval
    let rampDuration: TimeInterval
    let thresholdStartOffsetDBSL: Double
    let conservativeFallbackStartDBHL: Double
    let minimumLevelDBHL: Double
    let maximumLevelDBHL: Double
    let highSpreadThresholdDB: Double
    let supportedPitchFrequenciesHz: [Double]

    static let studyAFixedOneKilohertz = TinnitusProtocolConfiguration(
        kind: .studyAFixedOneKilohertz,
        stimulusKind: .pureTone,
        frequencyHz: 1_000,
        requiredTrialCount: 3,
        toneDuration: 1.0,
        rampDuration: CalibratedTonePlaybackDefaults.rampDuration,
        thresholdStartOffsetDBSL: 5.0,
        conservativeFallbackStartDBHL: 10.0,
        minimumLevelDBHL: -10.0,
        maximumLevelDBHL: 100.0,
        highSpreadThresholdDB: 10.0,
        supportedPitchFrequenciesHz: CalibratedHeadphoneProfile.airPodsPro2.supportedFrequenciesHz
    )
}

struct TinnitusLoudnessMatchTrial: Equatable {
    let trialIndex: Int
    let acceptedLevelDBHL: Double
    let estimatedDBSPL: Double?
    let dbSL: Double?
    let confidence: TinnitusConfidenceRating
    let acceptedAt: Date
}

struct TinnitusLoudnessMatchSummary: Equatable {
    let frequencyHz: Double
    let channel: CalibratedTonePlaybackChannel
    let thresholdStatus: TinnitusThresholdStatus
    let trials: [TinnitusLoudnessMatchTrial]
    let medianMatchedDBHL: Double
    let medianEstimatedDBSPL: Double?
    let medianDBSL: Double?
    let withinSessionSpreadDB: Double
    let qualityFlags: [TinnitusProtocolQualityFlag]
    let completedAt: Date
}

enum TinnitusProtocolEventKind: String, Equatable {
    case sessionStarted
    case lateralitySelected
    case pitchMatched
    case thresholdToneRequested
    case thresholdPlaybackPlanned
    case thresholdResponseRecorded
    case thresholdRecorded
    case thresholdUnavailable
    case trialStarted
    case levelAdjusted
    case playRequested
    case playbackPlanned
    case playbackRefused
    case stopRequested
    case levelAccepted
    case confidenceRecorded
    case guardrailChanged
    case abortRecorded
    case sessionCompleted
}

struct TinnitusProtocolEvent: Equatable {
    let timestamp: Date
    let kind: TinnitusProtocolEventKind
    let frequencyHz: Double?
    let presentedLevelDBHL: Double?
    let estimatedDBSPL: Double?
    let dbSL: Double?
    let channel: CalibratedTonePlaybackChannel?
    let laterality: TinnitusLaterality?
    let confidence: TinnitusConfidenceRating?
    let response: String?
    let guardrailMetadata: CalibratedAudioGuardrailMetadata?
    let playbackMetadata: CalibratedTonePlaybackMetadata?
    let reason: String?
    let qualityFlags: [TinnitusProtocolQualityFlag]
}

enum TinnitusProtocolState: Equatable {
    case collectingLaterality
    case awaitingThreshold(laterality: TinnitusLaterality, channel: CalibratedTonePlaybackChannel)
    case readyForTrial(index: Int, candidateLevelDBHL: Double)
    case awaitingConfidence(trial: PendingTinnitusLoudnessMatchTrial)
    case completed(TinnitusLoudnessMatchSummary)
    case aborted(TinnitusProtocolAbortReason)
    case restartRequired(TinnitusProtocolAbortReason)
}

struct PendingTinnitusLoudnessMatchTrial: Equatable {
    let trialIndex: Int
    let acceptedLevelDBHL: Double
    let estimatedDBSPL: Double?
    let dbSL: Double?
    let acceptedAt: Date
}

struct TinnitusProtocolPlaybackAttempt: Equatable {
    let request: CalibratedTonePlaybackRequest?
    let plan: CalibratedTonePlaybackPlan?
    let refusalReason: TinnitusProtocolAbortReason?
}
