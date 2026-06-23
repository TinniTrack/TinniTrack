import Foundation
import Testing
@testable import TinniTrack

struct CalibratedAudioConversionTests {
    private let converter = CalibratedAudioConverter()

    @Test
    func airPodsPro2KnownOneKilohertzExampleMatchesDesignDocument() throws {
        let conversion = try converter.conversion(
            frequencyHz: 1_000,
            levelDBHL: 30,
            outputVolume: 1.0
        )

        #expect(conversion.headphoneIdentifier == "AIRPODSPROV2")
        #expect(abs(conversion.targetDBSPL - 39.27) < 0.000_001)
        #expect(abs(conversion.fullScaleDBSPL - 113.67) < 0.000_001)
        #expect(abs(conversion.attenuationDB - (-74.40)) < 0.000_001)
        #expect(abs(conversion.linearAmplitude - 0.000_190_5) < 0.000_000_1)
        #expect(conversion.volumeBucket == VolumeCurveBucket(outputVolume: 1.0, splOffsetDB: 0.0))
    }

    @Test
    func volumeBucketingCoversAllSixteenResearchKitBuckets() throws {
        let expectedOffsets: [Double] = [
            -65.5,
            -58.5,
            -52.5,
            -47.0,
            -42.0,
            -37.5,
            -33.0,
            -29.0,
            -25.0,
            -21.0,
            -17.0,
            -13.5,
            -10.0,
            -6.5,
            -3.0,
            0.0
        ]

        for index in 1...16 {
            let volume = Double(index) / 16.0
            let bucket = try converter.volumeBucket(outputVolume: volume)

            #expect(bucket.outputVolume == volume)
            #expect(bucket.splOffsetDB == expectedOffsets[index - 1])
        }
    }

    @Test
    func volumeBucketingFloorsIntermediateValuesAndClampsZeroToMinimumBucket() throws {
        #expect(try converter.volumeBucket(outputVolume: 0.0).outputVolume == 0.0625)
        #expect(try converter.volumeBucket(outputVolume: 0.061).outputVolume == 0.0625)
        #expect(try converter.volumeBucket(outputVolume: 0.13).outputVolume == 0.125)
        #expect(try converter.volumeBucket(outputVolume: 0.999).outputVolume == 0.9375)
        #expect(try converter.volumeBucket(outputVolume: 1.0).outputVolume == 1.0)
    }

    @Test
    func dbHLAndDBSPLAreInverseConsistentAtSupportedFrequencies() throws {
        for frequency in CalibratedHeadphoneProfile.airPodsPro2.supportedFrequenciesHz {
            for levelDBHL in [-10.0, 0.0, 30.0, 65.0] {
                let targetDBSPL = try converter.targetDBSPL(frequencyHz: frequency, levelDBHL: levelDBHL)
                let roundTripDBHL = try converter.levelDBHL(frequencyHz: frequency, targetDBSPL: targetDBSPL)

                #expect(abs(roundTripDBHL - levelDBHL) < 0.000_001)
            }
        }
    }

    @Test
    func linearAmplitudeInvertsToDBSPLAndDBHL() throws {
        let conversion = try converter.conversion(
            frequencyHz: 2_000,
            levelDBHL: 25,
            outputVolume: 0.75
        )

        let inferredDBSPL = try converter.levelDBSPL(
            frequencyHz: conversion.frequencyHz,
            linearAmplitude: conversion.linearAmplitude,
            outputVolume: conversion.outputVolume
        )
        let inferredDBHL = try converter.levelDBHL(
            frequencyHz: conversion.frequencyHz,
            linearAmplitude: conversion.linearAmplitude,
            outputVolume: conversion.outputVolume
        )

        #expect(abs(inferredDBSPL - conversion.targetDBSPL) < 0.000_001)
        #expect(abs(inferredDBHL - conversion.requestedDBHL) < 0.000_001)
    }

    @Test
    func metadataRecordsResearchKitSourceAndDBFSReferencePolicy() throws {
        let conversion = try converter.conversion(
            frequencyHz: 1_000,
            levelDBHL: 30,
            outputVolume: 1.0
        )

        #expect(conversion.calibrationMetadata.sourceFileNames.contains("frequency_dBSPL_AIRPODSPROV2.plist"))
        #expect(conversion.calibrationMetadata.sourceFileNames.contains("retspl_AIRPODSPROV2.plist"))
        #expect(conversion.calibrationMetadata.sourceFileNames.contains("volume_curve_AIRPODSPROV2.plist"))
        #expect(conversion.calibrationMetadata.sourceFileNames.contains("retspl_dBFS_AIRPODSPROV2.plist"))
        #expect(conversion.calibrationMetadata.vendoredResearchKitCommit == "55d57711949ce08c745883d51af0b1dc025d022f")
        #expect(conversion.calibrationMetadata.validationStatus == .researchKitReferenceAvailable)
        #expect(CalibratedHeadphoneProfile.airPodsPro2.retsplDBFSReference[1_000] == -97.0)
        #expect(CalibratedHeadphoneProfile.airPodsPro2.dBFSCalibrationOffsetDB == 30.0)
    }

    @Test
    func unsupportedFrequencyReturnsStructuredError() {
        let error = calibrationError {
            try converter.conversion(frequencyHz: 999, levelDBHL: 30, outputVolume: 1.0)
        }

        #expect(error == .unsupportedFrequency(
            999,
            supported: CalibratedHeadphoneProfile.airPodsPro2.supportedFrequenciesHz
        ))
    }

    @Test
    func unsupportedHeadphoneProfileReturnsStructuredError() {
        let error = calibrationError {
            try converter.conversion(
                headphoneIdentifier: "AIRPODSMAX",
                frequencyHz: 1_000,
                levelDBHL: 30,
                outputVolume: 1.0
            )
        }

        #expect(error == .unsupportedHeadphoneProfile("AIRPODSMAX", supported: ["AIRPODSPROV2"]))
    }

    @Test
    func invalidVolumeReturnsStructuredError() {
        let lowError = calibrationError {
            try converter.volumeBucket(outputVolume: -0.01)
        }
        let highError = calibrationError {
            try converter.volumeBucket(outputVolume: 1.01)
        }

        #expect(lowError == .invalidVolume(-0.01))
        #expect(highError == .invalidVolume(1.01))
    }

    @Test
    func missingFrequencySensitivityTableDataReturnsStructuredError() {
        let base = CalibratedHeadphoneProfile.airPodsPro2
        let brokenProfile = CalibratedHeadphoneProfile(
            headphoneIdentifier: base.headphoneIdentifier,
            metadata: base.metadata,
            frequencySensitivityDBSPL: [:],
            retsplDBSPL: base.retsplDBSPL,
            volumeCurveDB: base.volumeCurveDB,
            retsplDBFSReference: base.retsplDBFSReference,
            dBFSCalibrationOffsetDB: base.dBFSCalibrationOffsetDB,
            maximumSafeAttenuationDB: base.maximumSafeAttenuationDB
        )
        let brokenConverter = CalibratedAudioConverter(profiles: [brokenProfile])

        let error = calibrationError {
            try brokenConverter.conversion(frequencyHz: 1_000, levelDBHL: 30, outputVolume: 1.0)
        }

        #expect(error == .missingTableData(table: "frequency_dBSPL_AIRPODSPROV2.plist", key: "1000"))
    }

    @Test
    func missingVolumeCurveTableDataReturnsStructuredError() {
        let base = CalibratedHeadphoneProfile.airPodsPro2
        let brokenProfile = CalibratedHeadphoneProfile(
            headphoneIdentifier: base.headphoneIdentifier,
            metadata: base.metadata,
            frequencySensitivityDBSPL: base.frequencySensitivityDBSPL,
            retsplDBSPL: base.retsplDBSPL,
            volumeCurveDB: [:],
            retsplDBFSReference: base.retsplDBFSReference,
            dBFSCalibrationOffsetDB: base.dBFSCalibrationOffsetDB,
            maximumSafeAttenuationDB: base.maximumSafeAttenuationDB
        )
        let brokenConverter = CalibratedAudioConverter(profiles: [brokenProfile])

        let error = calibrationError {
            try brokenConverter.volumeBucket(outputVolume: 1.0)
        }

        #expect(error == .missingTableData(table: "volume_curve_AIRPODSPROV2.plist", key: "1.0000"))
    }

    @Test
    func maximumOutputDetectionReturnsStructuredErrorBeforeClipping() {
        let error = calibrationError {
            try converter.conversion(frequencyHz: 1_000, levelDBHL: 105, outputVolume: 1.0)
        }

        guard case .clippingOrUnsafeAmplitude(
            let linearAmplitude,
            let attenuationDB,
            let targetDBSPL,
            let maximumSafeLinearAmplitude
        ) = error else {
            Issue.record("Expected clippingOrUnsafeAmplitude, got \(String(describing: error))")
            return
        }

        #expect(linearAmplitude > maximumSafeLinearAmplitude)
        #expect(attenuationDB >= -1.0)
        #expect(targetDBSPL == 114.27)
    }

    private func calibrationError<T>(from work: () throws -> T) -> CalibrationConversionError? {
        do {
            _ = try work()
            return nil
        } catch let error as CalibrationConversionError {
            return error
        } catch {
            return nil
        }
    }
}
