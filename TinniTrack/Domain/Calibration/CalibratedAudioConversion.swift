import Foundation

enum CalibratedHeadphoneIdentifier {
    static let airPodsPro2 = "AIRPODSPROV2"
}

enum CalibrationConversionError: Error, Equatable {
    case unsupportedHeadphoneProfile(String, supported: [String])
    case unsupportedFrequency(Double, supported: [Double])
    case invalidVolume(Double)
    case missingTableData(table: String, key: String)
    case clippingOrUnsafeAmplitude(
        linearAmplitude: Double,
        attenuationDB: Double,
        targetDBSPL: Double,
        maximumSafeLinearAmplitude: Double
    )
}

struct VolumeCurveBucket: Codable, Equatable {
    let outputVolume: Double
    let splOffsetDB: Double
}

struct CalibratedAudioCalibrationMetadata: Codable, Equatable {
    let headphoneIdentifier: String
    let supportedFrequenciesHz: [Double]
    let sourceRepositoryURL: String
    let vendoredResearchKitCommit: String
    let designDocumentResearchKitCommit: String
    let sourceFileNames: [String]
    let volumeBucketingPolicy: String
    let dBFSCalibrationPolicy: String
    let retsplDBFSPolicy: String
    let validationStatus: CalibrationValidationStatus
}

struct CalibratedHeadphoneProfile: Equatable {
    let headphoneIdentifier: String
    let metadata: CalibratedAudioCalibrationMetadata
    let frequencySensitivityDBSPL: [Double: Double]
    let retsplDBSPL: [Double: Double]
    let volumeCurveDB: [Double: Double]
    let retsplDBFSReference: [Double: Double]
    let dBFSCalibrationOffsetDB: Double
    let maximumSafeAttenuationDB: Double

    var supportedFrequenciesHz: [Double] {
        metadata.supportedFrequenciesHz
    }
}

struct CalibratedAudioConversion: Equatable {
    let headphoneIdentifier: String
    let frequencyHz: Double
    let requestedDBHL: Double
    let targetDBSPL: Double
    let outputVolume: Double
    let volumeBucket: VolumeCurveBucket
    let fullScaleDBSPL: Double
    let attenuationDB: Double
    let linearAmplitude: Double
    let calibrationMetadata: CalibratedAudioCalibrationMetadata
}

struct CalibratedAudioConverter {
    private let profilesByIdentifier: [String: CalibratedHeadphoneProfile]

    init(profiles: [CalibratedHeadphoneProfile] = [.airPodsPro2]) {
        profilesByIdentifier = Dictionary(
            uniqueKeysWithValues: profiles.map { ($0.headphoneIdentifier.uppercased(), $0) }
        )
    }

    func conversion(
        headphoneIdentifier: String = CalibratedHeadphoneIdentifier.airPodsPro2,
        frequencyHz: Double,
        levelDBHL: Double,
        outputVolume: Double
    ) throws -> CalibratedAudioConversion {
        let profile = try profile(for: headphoneIdentifier)
        let targetDBSPL = try targetDBSPL(
            headphoneIdentifier: headphoneIdentifier,
            frequencyHz: frequencyHz,
            levelDBHL: levelDBHL
        )
        let bucket = try volumeBucket(
            headphoneIdentifier: headphoneIdentifier,
            outputVolume: outputVolume
        )
        let fullScaleDBSPL = try fullScaleDBSPL(
            profile: profile,
            frequencyHz: frequencyHz,
            volumeBucket: bucket
        )
        let attenuationDB = targetDBSPL - fullScaleDBSPL
        let linearAmplitude = pow(10.0, attenuationDB / 20.0)

        try validateAmplitude(
            profile: profile,
            linearAmplitude: linearAmplitude,
            attenuationDB: attenuationDB,
            targetDBSPL: targetDBSPL
        )

        return CalibratedAudioConversion(
            headphoneIdentifier: profile.headphoneIdentifier,
            frequencyHz: frequencyHz,
            requestedDBHL: levelDBHL,
            targetDBSPL: targetDBSPL,
            outputVolume: outputVolume,
            volumeBucket: bucket,
            fullScaleDBSPL: fullScaleDBSPL,
            attenuationDB: attenuationDB,
            linearAmplitude: linearAmplitude,
            calibrationMetadata: profile.metadata
        )
    }

    func targetDBSPL(
        headphoneIdentifier: String = CalibratedHeadphoneIdentifier.airPodsPro2,
        frequencyHz: Double,
        levelDBHL: Double
    ) throws -> Double {
        let profile = try profile(for: headphoneIdentifier)
        try validateFrequency(frequencyHz, profile: profile)
        let retspl = try tableValue(
            profile.retsplDBSPL,
            tableName: profile.metadata.sourceFileNames[1],
            frequencyHz: frequencyHz
        )
        return retspl + levelDBHL
    }

    func levelDBHL(
        headphoneIdentifier: String = CalibratedHeadphoneIdentifier.airPodsPro2,
        frequencyHz: Double,
        targetDBSPL: Double
    ) throws -> Double {
        let profile = try profile(for: headphoneIdentifier)
        try validateFrequency(frequencyHz, profile: profile)
        let retspl = try tableValue(
            profile.retsplDBSPL,
            tableName: profile.metadata.sourceFileNames[1],
            frequencyHz: frequencyHz
        )
        return targetDBSPL - retspl
    }

    func levelDBSPL(
        headphoneIdentifier: String = CalibratedHeadphoneIdentifier.airPodsPro2,
        frequencyHz: Double,
        linearAmplitude: Double,
        outputVolume: Double
    ) throws -> Double {
        let profile = try profile(for: headphoneIdentifier)
        try validateFrequency(frequencyHz, profile: profile)
        let bucket = try volumeBucket(headphoneIdentifier: headphoneIdentifier, outputVolume: outputVolume)
        let fullScale = try fullScaleDBSPL(profile: profile, frequencyHz: frequencyHz, volumeBucket: bucket)
        let attenuationDB = 20.0 * log10(linearAmplitude)

        try validateAmplitude(
            profile: profile,
            linearAmplitude: linearAmplitude,
            attenuationDB: attenuationDB,
            targetDBSPL: fullScale + attenuationDB
        )

        return fullScale + attenuationDB
    }

    func levelDBHL(
        headphoneIdentifier: String = CalibratedHeadphoneIdentifier.airPodsPro2,
        frequencyHz: Double,
        linearAmplitude: Double,
        outputVolume: Double
    ) throws -> Double {
        let targetDBSPL = try levelDBSPL(
            headphoneIdentifier: headphoneIdentifier,
            frequencyHz: frequencyHz,
            linearAmplitude: linearAmplitude,
            outputVolume: outputVolume
        )
        return try levelDBHL(
            headphoneIdentifier: headphoneIdentifier,
            frequencyHz: frequencyHz,
            targetDBSPL: targetDBSPL
        )
    }

    func volumeBucket(
        headphoneIdentifier: String = CalibratedHeadphoneIdentifier.airPodsPro2,
        outputVolume: Double
    ) throws -> VolumeCurveBucket {
        let profile = try profile(for: headphoneIdentifier)
        guard outputVolume.isFinite, outputVolume >= 0.0, outputVolume <= 1.0 else {
            throw CalibrationConversionError.invalidVolume(outputVolume)
        }

        let bucketIndex = min(max(Int(floor(outputVolume / Self.volumeStep)), 1), 16)
        let bucketedVolume = Double(bucketIndex) * Self.volumeStep
        guard let offset = profile.volumeCurveDB[bucketedVolume] else {
            throw CalibrationConversionError.missingTableData(
                table: profile.metadata.sourceFileNames[2],
                key: Self.volumeKey(bucketedVolume)
            )
        }

        return VolumeCurveBucket(outputVolume: bucketedVolume, splOffsetDB: offset)
    }

    private func profile(for headphoneIdentifier: String) throws -> CalibratedHeadphoneProfile {
        let key = headphoneIdentifier.uppercased()
        guard let profile = profilesByIdentifier[key] else {
            throw CalibrationConversionError.unsupportedHeadphoneProfile(
                headphoneIdentifier,
                supported: profilesByIdentifier.keys.sorted()
            )
        }
        return profile
    }

    private func validateFrequency(_ frequencyHz: Double, profile: CalibratedHeadphoneProfile) throws {
        guard profile.supportedFrequenciesHz.contains(frequencyHz) else {
            throw CalibrationConversionError.unsupportedFrequency(
                frequencyHz,
                supported: profile.supportedFrequenciesHz
            )
        }
    }

    private func tableValue(
        _ table: [Double: Double],
        tableName: String,
        frequencyHz: Double
    ) throws -> Double {
        guard let value = table[frequencyHz] else {
            throw CalibrationConversionError.missingTableData(
                table: tableName,
                key: Self.frequencyKey(frequencyHz)
            )
        }
        return value
    }

    private func fullScaleDBSPL(
        profile: CalibratedHeadphoneProfile,
        frequencyHz: Double,
        volumeBucket: VolumeCurveBucket
    ) throws -> Double {
        try validateFrequency(frequencyHz, profile: profile)
        let frequencySensitivity = try tableValue(
            profile.frequencySensitivityDBSPL,
            tableName: profile.metadata.sourceFileNames[0],
            frequencyHz: frequencyHz
        )
        return frequencySensitivity + volumeBucket.splOffsetDB + profile.dBFSCalibrationOffsetDB
    }

    private func validateAmplitude(
        profile: CalibratedHeadphoneProfile,
        linearAmplitude: Double,
        attenuationDB: Double,
        targetDBSPL: Double
    ) throws {
        let maximumSafeLinearAmplitude = pow(10.0, profile.maximumSafeAttenuationDB / 20.0)
        guard linearAmplitude.isFinite,
              linearAmplitude > 0.0,
              linearAmplitude <= maximumSafeLinearAmplitude,
              attenuationDB < profile.maximumSafeAttenuationDB
        else {
            throw CalibrationConversionError.clippingOrUnsafeAmplitude(
                linearAmplitude: linearAmplitude,
                attenuationDB: attenuationDB,
                targetDBSPL: targetDBSPL,
                maximumSafeLinearAmplitude: maximumSafeLinearAmplitude
            )
        }
    }

    private static let volumeStep = 0.0625

    private static func frequencyKey(_ frequencyHz: Double) -> String {
        String(format: "%.0f", frequencyHz)
    }

    private static func volumeKey(_ outputVolume: Double) -> String {
        String(format: "%.4f", outputVolume)
    }
}

extension CalibratedHeadphoneProfile {
    static let airPodsPro2 = CalibratedHeadphoneProfile(
        headphoneIdentifier: CalibratedHeadphoneIdentifier.airPodsPro2,
        metadata: CalibratedAudioCalibrationMetadata(
            headphoneIdentifier: CalibratedHeadphoneIdentifier.airPodsPro2,
            supportedFrequenciesHz: [125, 250, 500, 750, 1_000, 1_500, 2_000, 3_000, 4_000, 6_000, 8_000],
            sourceRepositoryURL: "https://github.com/ResearchKit/ResearchKit",
            vendoredResearchKitCommit: "55d57711949ce08c745883d51af0b1dc025d022f",
            designDocumentResearchKitCommit: "daba8c9f103477bd0279cc52a924a85b480df601",
            sourceFileNames: [
                "frequency_dBSPL_AIRPODSPROV2.plist",
                "retspl_AIRPODSPROV2.plist",
                "volume_curve_AIRPODSPROV2.plist",
                "retspl_dBFS_AIRPODSPROV2.plist"
            ],
            volumeBucketingPolicy: "Floor AVAudioSession.outputVolume to 1/16 buckets, clamp below 0.0625 to 0.0625, and reject values outside 0.0...1.0.",
            dBFSCalibrationPolicy: "Use ResearchKit generator's inspected hardcoded +30 dB dBFS calibration offset for this reference conversion.",
            retsplDBFSPolicy: "Bundle includes retspl_dBFS_AIRPODSPROV2.plist, but the inspected generator does not consume it; it is recorded as reference data and not used blindly.",
            validationStatus: .researchKitReferenceAvailable
        ),
        frequencySensitivityDBSPL: [
            125: 84.05,
            250: 83.16,
            500: 84.13,
            750: 83.95,
            1_000: 83.67,
            1_500: 84.79,
            2_000: 86.52,
            3_000: 89.24,
            4_000: 86.64,
            6_000: 86.50,
            8_000: 90.11
        ],
        retsplDBSPL: [
            125: 34.04,
            250: 23.52,
            500: 12.99,
            750: 11.13,
            1_000: 9.27,
            1_500: 11.69,
            2_000: 14.11,
            3_000: 13.42,
            4_000: 12.72,
            6_000: 14.62,
            8_000: 16.51
        ],
        volumeCurveDB: [
            0.0625: -65.5,
            0.1250: -58.5,
            0.1875: -52.5,
            0.2500: -47.0,
            0.3125: -42.0,
            0.3750: -37.5,
            0.4375: -33.0,
            0.5000: -29.0,
            0.5625: -25.0,
            0.6250: -21.0,
            0.6875: -17.0,
            0.7500: -13.5,
            0.8125: -10.0,
            0.8750: -6.5,
            0.9375: -3.0,
            1.0000: 0.0
        ],
        retsplDBFSReference: [
            250.0000: -85.0000,
            306.0092: -87.4644,
            364.2145: -90.0254,
            425.0334: -92.7014,
            488.9024: -95.5117,
            500.0000: -96.0000,
            556.2799: -96.1125,
            627.6493: -96.2552,
            703.5228: -96.4070,
            784.4448: -96.5688,
            870.9962: -96.7419,
            963.7980: -96.9275,
            1_000.0000: -97.0000,
            1_063.5161: -96.8729,
            1_170.8662: -96.6582,
            1_286.6186: -96.4267,
            1_411.6040: -96.1767,
            1_546.7192: -95.9065,
            1_692.9339: -95.6141,
            1_851.2974: -95.2974,
            2_000.0000: -95.0000,
            2_022.9461: -95.0688,
            2_209.1117: -95.6273,
            2_411.1302: -96.2333,
            2_630.4514: -96.8913,
            2_868.6490: -97.6059,
            3_127.4325: -97.6177,
            3_408.6590: -96.7740,
            3_714.3464: -95.8569,
            4_000.0000: -95.0000,
            4_046.6886: -94.9066,
            4_408.0704: -94.1838,
            4_801.0852: -93.3978,
            5_228.5533: -92.5428,
            5_693.5422: -91.6129,
            6_000.0000: -91.0000,
            6_199.3889: -90.8006,
            6_749.7233: -90.2502,
            7_348.4947: -89.6515,
            8_000.0000: -89.0000
        ],
        dBFSCalibrationOffsetDB: 30.0,
        maximumSafeAttenuationDB: -1.0
    )
}
