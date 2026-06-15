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
    case dBFS
    case estimatedDBA
    case systemOutputVolume
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
                    frequencyHz: StudyNo1Configuration.toneFrequencyHz,
                    channel: "current output route"
                ),
                outputDeviceRequirement: OutputDeviceRequirement(
                    allowedDevices: [
                        CalibrationProfileCatalog.airPodsPro2,
                        CalibrationProfileCatalog.airPodsPro3
                    ],
                    enforcement: "route-name generation marker gate"
                ),
                ambientRequirement: AmbientNoiseRequirement(
                    threshold: StudyNo1Configuration.ambientThresholdDB,
                    unit: .estimatedDBA,
                    source: "AVAudioRecorder metering heuristic"
                ),
                measurementUnit: .dBHL,
                researchKitModule: nil,
                requiresCalibratedOutput: true,
                notes: "Stores raw normalized amplitude, dBFS, estimated dB SPL, dB HL, and exact-threshold dB SL when available."
            )
        ],
        calibrationProfile: CalibrationProfileCatalog.studyNo1CalibrationReady,
        resultPayload: MeasurementPayloadMetadata(
            schemaVersion: "study-no-1-lm-payload-v2",
            protocolVersion: "lm_v1",
            rawPayloadKeys: [
                "task_key",
                "task_version",
                "stimulus",
                "raw_inputs",
                "derived_outputs",
                "trial_summary",
                "trials",
                "loudness_trace",
                "ambient_trace",
                "system_output_volume_trace",
                "gating",
                "quality",
                "device_info",
                "headphone_info",
                "measurement_metadata"
            ],
            resultUnits: [.normalizedAmplitude, .dBFS, .estimatedDBA, .systemOutputVolume, .dBSPL, .dBHL, .dBSL],
            validityNotice: "Estimated SPL/HL values are reproducible from recorded inputs and ORKAudiometry table provenance. dB SL is present only for exact 1,000 Hz audiogram thresholds. Lab validation is still required before clinical claims."
        ),
        notes: "Defines Study No. 1 loudness matching with reproducible AirPods Pro 2 calibration metadata and explicit validity flags."
    )
}
