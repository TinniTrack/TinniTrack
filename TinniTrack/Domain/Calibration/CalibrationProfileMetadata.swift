import Foundation

enum CalibrationValidationStatus: String, Codable, Equatable {
    case researchKitReferenceAvailable
    case labValidationRequired
}

struct CalibrationProfileMetadata: Equatable {
    let identifier: String
    let version: String
    let source: String
    let validationStatus: CalibrationValidationStatus
    let supportedOutputDevices: [OutputDeviceMetadata]
    let notes: String
}

struct OutputDeviceMetadata: Equatable {
    let displayName: String
    let researchKitHeadphoneTypeIdentifier: String
    let notes: String
}

enum CalibrationProfileCatalog {
    static let airPodsPro2ResearchKitReference = OutputDeviceMetadata(
        displayName: "AirPods Pro 2",
        researchKitHeadphoneTypeIdentifier: "AIRPODSPROV2",
        notes: "Supported calibration profile for pure conversion and Phase 2 guardrails. Exact AirPods model and firmware proof still requires a conservative verification source beyond route names."
    )

    static let airPodsPro2ResearchKitCalibration = CalibrationProfileMetadata(
        identifier: "airpods-pro-2-researchkit-reference",
        version: "2026-06-21",
        source: "Vendored ResearchKit AirPods Pro 2 calibration tables",
        validationStatus: .researchKitReferenceAvailable,
        supportedOutputDevices: [airPodsPro2ResearchKitReference],
        notes: "Pure dB HL, dB SPL, attenuation, linear-amplitude conversion, and route/volume guardrail metadata. Playback and study validation are separate phases."
    )
}
