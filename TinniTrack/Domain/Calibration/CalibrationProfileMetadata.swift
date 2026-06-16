import Foundation

enum CalibrationValidationStatus: String, Equatable {
    case unvalidatedPrototype
    case researchKitReferenceAvailable
    case labValidationRequired
}

enum CalibrationProfileSupportStatus: String, Equatable {
    case supported
    case routeAllowedCalibrationUnavailable
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

struct HeadphoneFrequencyCalibration: Equatable {
    let frequencyHz: Double
    let frequencyDBSPL: Double
    let retsplDBSPL: Double
    let retsplDBFS: Double?
}

struct HeadphoneCalibrationProfile: Equatable {
    let identifier: String
    let version: String
    let displayName: String
    let outputDevice: OutputDeviceMetadata
    let supportStatus: CalibrationProfileSupportStatus
    let validationStatus: CalibrationValidationStatus
    let sourceTableVersion: String
    let sourceProvenance: String
    let frequencyCalibration: HeadphoneFrequencyCalibration?
    let volumeCurve: [Double: Double]
    let notes: String

    func volumeOffsetDB(forSystemOutputVolume systemOutputVolume: Double) -> VolumeCurveLookup? {
        guard !volumeCurve.isEmpty else { return nil }

        let clampedVolume = min(max(systemOutputVolume, 0), 1)
        let quantizedVolume = max(0.0625, floor(clampedVolume / 0.0625) * 0.0625)
        let roundedKey = (quantizedVolume * 10_000).rounded() / 10_000

        guard let offset = volumeCurve[roundedKey] else {
            return nil
        }

        return VolumeCurveLookup(
            rawSystemOutputVolume: clampedVolume,
            quantizedSystemOutputVolume: roundedKey,
            offsetDB: offset
        )
    }
}

struct VolumeCurveLookup: Equatable {
    let rawSystemOutputVolume: Double
    let quantizedSystemOutputVolume: Double
    let offsetDB: Double
}

enum CalibrationProfileCatalog {
    static let airPodsPro2 = OutputDeviceMetadata(
        displayName: "AirPods Pro 2",
        routeNameMatchers: [
            "airpods pro 2",
            "airpods pro (2",
            "2nd generation",
            "second generation"
        ],
        researchKitHeadphoneTypeIdentifier: "AIRPODSPROV2",
        notes: "Route-name generation markers are used until exact model and firmware APIs are available."
    )

    static let airPodsPro3 = OutputDeviceMetadata(
        displayName: "AirPods Pro 3",
        routeNameMatchers: [
            "airpods pro 3",
            "airpods pro (3",
            "3rd generation",
            "third generation"
        ],
        researchKitHeadphoneTypeIdentifier: nil,
        notes: "Route allowed for Study No. 1, but no ORKAudiometry AirPods Pro 3 calibration table is available in the pinned ResearchKit revision."
    )

    static let airPodsPro2OneKilohertz: HeadphoneCalibrationProfile = {
        let tableSet = ResearchKitAudiometryTableStore.airPodsPro2
        let manifest = tableSet.manifest

        return HeadphoneCalibrationProfile(
            identifier: manifest.profileID,
            version: "researchkit-\(manifest.sourceCommit.prefix(7))-\(manifest.retrievedAt)",
            displayName: "AirPods Pro 2 1 kHz",
            outputDevice: airPodsPro2,
            supportStatus: .supported,
            validationStatus: .researchKitReferenceAvailable,
            sourceTableVersion: "ResearchKit/ResearchKit commit \(manifest.sourceCommit), retrieved \(manifest.retrievedAt)",
            sourceProvenance: "\(manifest.sourceTreeURL): \(manifest.files.map(\.name).joined(separator: ", ")).",
            frequencyCalibration: tableSet.frequencyCalibration(at: StudyNo1Configuration.toneFrequencyHz),
            volumeCurve: tableSet.volumeCurve,
            notes: "Frequency dB SPL and RETSPL values are table lookups for 1,000 Hz from vendored ResearchKit plists. The app converts its peak-normalized sine amplitude to both peak and RMS dBFS, and uses RMS dBFS for estimated dB SPL."
        )
    }()

    static let airPodsPro3CalibrationUnavailable = HeadphoneCalibrationProfile(
        identifier: "airpods-pro-3-calibration-unavailable",
        version: "2026-06-15",
        displayName: "AirPods Pro 3",
        outputDevice: airPodsPro3,
        supportStatus: .routeAllowedCalibrationUnavailable,
        validationStatus: .labValidationRequired,
        sourceTableVersion: "No AirPods Pro 3 ORKAudiometry table available in StanfordBDHG/ResearchKit 3.1.4.",
        sourceProvenance: "Route gate can detect AirPods Pro 3 by route name, but no frequency_dBSPL, volume_curve, or RETSPL table is present for AirPods Pro 3.",
        frequencyCalibration: nil,
        volumeCurve: [:],
        notes: "Submission must remain invalid until an AirPods Pro 3 calibration profile is added."
    )

    static let studyNo1CalibrationReady = CalibrationProfileMetadata(
        identifier: "study-no-1-ork-airpods-pro-2-1khz",
        version: "2026-06-15",
        source: "TinniTrack 1 kHz tone generator plus Apple/ResearchKit ORKAudiometry AirPods Pro 2 calibration tables",
        validationStatus: .researchKitReferenceAvailable,
        supportedOutputDevices: [airPodsPro2, airPodsPro3],
        notes: "Produces reproducible estimated dB SPL and dB HL for AirPods Pro 2. dB SL is emitted only from exact 1,000 Hz participant audiogram thresholds. AirPods Pro 3 remains route-allowed but invalid without a calibration table."
    )

    static func profile(for route: AudioOutputRoute?) -> HeadphoneCalibrationProfile? {
        switch StudyNo1Configuration.supportedHeadphoneGeneration(for: route?.name) {
        case "AirPods Pro 2":
            return airPodsPro2OneKilohertz
        case "AirPods Pro 3":
            return airPodsPro3CalibrationUnavailable
        default:
            return nil
        }
    }
}
