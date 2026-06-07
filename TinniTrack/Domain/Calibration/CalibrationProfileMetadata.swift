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
    static let airPodsProPrototype = OutputDeviceMetadata(
        displayName: "AirPods Pro family",
        routeNameMatchers: ["airpods pro"],
        researchKitHeadphoneTypeIdentifier: "AirPodsProV2",
        notes: "Current app gate is broad route-name matching. Exact model/firmware verification remains future work."
    )

    static let studyNo1Prototype = CalibrationProfileMetadata(
        identifier: "study-no-1-unvalidated-normalized-output",
        version: "2026-06-06",
        source: "TinniTrack prototype tone generator plus route and ambient gates",
        validationStatus: .unvalidatedPrototype,
        supportedOutputDevices: [airPodsProPrototype],
        notes: "Stores normalized amplitude and metadata for future calibration; not valid dB HL or dB SL."
    )
}
