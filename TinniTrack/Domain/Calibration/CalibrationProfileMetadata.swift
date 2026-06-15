import Foundation

enum CalibrationValidationStatus: String, Equatable {
    case unvalidatedPrototype
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
    let routeNameMatchers: [String]
    let researchKitHeadphoneTypeIdentifier: String?
    let notes: String
}

enum CalibrationProfileCatalog {
    static let airPodsPro2Prototype = OutputDeviceMetadata(
        displayName: "AirPods Pro 2",
        routeNameMatchers: [
            "airpods pro 2",
            "airpods pro (2",
            "2nd generation",
            "second generation"
        ],
        researchKitHeadphoneTypeIdentifier: "AirPodsProV2",
        notes: "Current app gate uses route-name generation markers until exact model and firmware APIs are available."
    )

    static let airPodsPro3Prototype = OutputDeviceMetadata(
        displayName: "AirPods Pro 3",
        routeNameMatchers: [
            "airpods pro 3",
            "airpods pro (3",
            "3rd generation",
            "third generation"
        ],
        researchKitHeadphoneTypeIdentifier: nil,
        notes: "Allowed for Study No. 1 V1 as route-name metadata; calibrated reference validation remains future work."
    )

    static let studyNo1Prototype = CalibrationProfileMetadata(
        identifier: "study-no-1-unvalidated-normalized-output",
        version: "2026-06-15",
        source: "TinniTrack 1 kHz tone generator plus route, ambient, and system-volume guards",
        validationStatus: .unvalidatedPrototype,
        supportedOutputDevices: [airPodsPro2Prototype, airPodsPro3Prototype],
        notes: "Stores normalized amplitude and metadata for future calibration; not valid dB HL or dB SL."
    )
}
