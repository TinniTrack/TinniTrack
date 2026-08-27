import Foundation

enum ResearchKitModule: String, CaseIterable, Equatable {
    case instructionStep = "ORKInstructionStep"
    case formStep = "ORKFormStep"
    case toneAudiometry = "ORKToneAudiometryStep"
    case dBHLToneAudiometry = "ORKdBHLToneAudiometryStep"
    case environmentSPLMeter = "ORKEnvironmentSPLMeterStep"
    case speechInNoise = "ORKSpeechInNoiseStep"
}

enum StudyTaskKind: String, Equatable {
    case consent
    case instruction
    case survey
    case loudnessMatch
    case toneAudiometry
    case dBHLToneAudiometry
    case environmentSPLMeter
    case speechInNoise
}

enum MeasurementUnit: String, Equatable {
    case estimatedDBA
    case dBSPL
    case dBHL
    case dBSL
}

struct StudyProtocolDefinition: Equatable {
    let identifier: String
    let version: String
    let title: String
    let tasks: [AudioTaskDefinition]
    let calibrationProfile: CalibrationProfileMetadata
    let resultPayload: MeasurementPayloadMetadata
    let notes: String
}

struct AudioTaskDefinition: Equatable {
    let key: String
    let version: Int
    let kind: StudyTaskKind
    let displayName: String
    let stimulus: AudioStimulusDefinition?
    let outputDeviceRequirement: OutputDeviceRequirement
    let ambientRequirement: AmbientNoiseRequirement?
    let measurementUnit: MeasurementUnit
    let researchKitModule: ResearchKitModule?
    let requiresCalibratedOutput: Bool
    let notes: String
}

struct AudioStimulusDefinition: Equatable {
    let waveform: String
    let frequencyHz: Double
    let channel: String
}

struct OutputDeviceRequirement: Equatable {
    let allowedDevices: [OutputDeviceMetadata]
    let enforcement: String
}

struct AmbientNoiseRequirement: Equatable {
    let threshold: Double
    let unit: MeasurementUnit
    let source: String
}

struct MeasurementPayloadMetadata: Equatable {
    let schemaVersion: String
    let protocolVersion: String
    let rawPayloadKeys: [String]
    let resultUnits: [MeasurementUnit]
    let validityNotice: String
}

enum StudyProtocolCatalog {
    static let studyNo1 = StudyProtocolDefinition(
        identifier: StudyPrerequisiteRules.studyNo1Slug,
        version: "lm_v1",
        title: "Study No. 1",
        tasks: [
            AudioTaskDefinition(
                key: "lm_1khz_v2",
                version: 2,
                kind: .loudnessMatch,
                displayName: "1 kHz loudness match",
                stimulus: AudioStimulusDefinition(
                    waveform: "sine",
                    frequencyHz: 1_000,
                    channel: "current output route"
                ),
                outputDeviceRequirement: OutputDeviceRequirement(
                    allowedDevices: [CalibrationProfileCatalog.airPodsPro2ResearchKitReference],
                    enforcement: "Calibrated route and maximum-volume guardrails required before calibrated playback"
                ),
                ambientRequirement: AmbientNoiseRequirement(
                    threshold: StudyNo1Configuration.ambientThresholdDB,
                    unit: .estimatedDBA,
                    source: "deferred to calibrated quiet-room gate"
                ),
                measurementUnit: .dBHL,
                researchKitModule: nil,
                requiresCalibratedOutput: true,
                notes: "The Study No. 1 protocol supports fixed 1 kHz loudness matching decisions, repeated trials, and raw event logging. dB SL uses the imported HealthKit audiogram threshold."
            )
        ],
        calibrationProfile: CalibrationProfileCatalog.airPodsPro2ResearchKitCalibration,
        resultPayload: MeasurementPayloadMetadata(
            schemaVersion: "study-no-1-loudness-match-v3",
            protocolVersion: "lm_v1",
            rawPayloadKeys: [
                "task_key",
                "task_version",
                "laterality",
                "playback_channel",
                "threshold_dbhl",
                "matched_level_dbhl",
                "matched_level_dbspl",
                "matched_level_dbsl",
                "confidence",
                "protocol_events",
                "trial_summaries",
                "quality_flags",
                "calibration_metadata",
                "measurement_metadata"
            ],
            resultUnits: [.dBHL, .dBSPL, .dBSL],
            validityNotice: "Study No. 1 protocol logic is implemented, but participant calibrated result collection remains disabled until route, volume, quiet-room, and restart safety preflight are production-ready."
        ),
        notes: "Defines the calibrated Study No. 1 protocol over conversion, guardrails, and playback planning. Persistence and production collection remain deferred."
    )
}
