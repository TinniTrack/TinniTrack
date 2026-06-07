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
    case normalizedAmplitude
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
                key: "lm_1khz_v1",
                version: 1,
                kind: .loudnessMatch,
                displayName: "1 kHz loudness match",
                stimulus: AudioStimulusDefinition(
                    waveform: "sine",
                    frequencyHz: 1_000,
                    channel: "current output route"
                ),
                outputDeviceRequirement: OutputDeviceRequirement(
                    allowedDevices: [CalibrationProfileCatalog.airPodsProPrototype],
                    enforcement: "route-name gate"
                ),
                ambientRequirement: AmbientNoiseRequirement(
                    threshold: StudyNo1Configuration.ambientThresholdDB,
                    unit: .estimatedDBA,
                    source: "AVAudioRecorder metering heuristic"
                ),
                measurementUnit: .normalizedAmplitude,
                researchKitModule: nil,
                requiresCalibratedOutput: false,
                notes: "Current implementation stores normalized playback level and traces only."
            )
        ],
        calibrationProfile: CalibrationProfileCatalog.studyNo1Prototype,
        resultPayload: MeasurementPayloadMetadata(
            schemaVersion: "study-no-1-lm-payload-v1",
            protocolVersion: "lm_v1",
            rawPayloadKeys: [
                "task_key",
                "task_version",
                "matched_level",
                "loudness_trace",
                "ambient_trace",
                "measurement_metadata"
            ],
            resultUnits: [.normalizedAmplitude, .estimatedDBA],
            validityNotice: "Prototype payload is not yet calibrated to dB HL, dB SL, or verified dB SPL."
        ),
        notes: "Defines the current app protocol without claiming scientific validity."
    )
}
