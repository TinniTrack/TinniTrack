import Foundation
import Testing
@testable import TinniTrack

struct LoudnessCalibrationTests {
    @Test
    func airPodsPro2CalibrationConvertsNormalizedAmplitudeToSPLHLAndSL() {
        let result = LoudnessCalibrationCalculator.calibrate(
            LoudnessCalibrationInput(
                normalizedAmplitude: 0.5,
                systemOutputVolume: 0.5,
                didSystemOutputVolumeChange: false,
                isSupportedRoute: true,
                isAmbientQuiet: true,
                calibrationProfile: CalibrationProfileCatalog.airPodsPro2OneKilohertz,
                audiogramThreshold: AudiogramThresholdAtFrequency(
                    frequencyHz: 1_000,
                    leftDBHL: 10,
                    rightDBHL: 15,
                    sourceAudiogramID: UUID(),
                    measuredAt: Date(timeIntervalSince1970: 1_740_000_000),
                    derivation: "exact_1000hz_no_interpolation"
                )
            )
        )

        #expect(result.validationStatus == .acceptedValid)
        #expect(result.qualityFlags == [.routeNameCalibrationInferred])
        #expect(abs((result.peakDBFS ?? 0) - -6.020599913279624) < 0.000001)
        #expect(abs((result.rmsDBFS ?? 0) - -9.030899869919436) < 0.000001)
        #expect(abs((result.estimatedDBSPL ?? 0) - 45.63910008672037) < 0.000001)
        #expect(abs((result.estimatedDBHL ?? 0) - 36.36910008672037) < 0.000001)
        #expect(abs((result.estimatedDBSLBilateralMean ?? 0) - 23.86910008672037) < 0.000001)
        #expect(result.volumeCurveLookup?.quantizedSystemOutputVolume == 0.5)
        #expect(result.volumeCurveLookup?.offsetDB == -29)
    }

    @Test
    func missingAudiogramThresholdPreventsAcceptedDBSLSubmission() {
        let result = LoudnessCalibrationCalculator.calibrate(
            LoudnessCalibrationInput(
                normalizedAmplitude: 0.5,
                systemOutputVolume: 0.5,
                didSystemOutputVolumeChange: false,
                isSupportedRoute: true,
                isAmbientQuiet: true,
                calibrationProfile: CalibrationProfileCatalog.airPodsPro2OneKilohertz,
                audiogramThreshold: nil
            )
        )

        #expect(result.validationStatus == .invalid)
        #expect(result.qualityFlags.contains(.missingAudiogramThreshold))
        #expect(result.estimatedDBHL != nil)
        #expect(result.estimatedDBSLBilateralMean == nil)
    }

    @Test
    func airPodsPro3RouteRemainsInvalidUntilCalibrationTableExists() {
        let result = LoudnessCalibrationCalculator.calibrate(
            LoudnessCalibrationInput(
                normalizedAmplitude: 0.5,
                systemOutputVolume: 0.5,
                didSystemOutputVolumeChange: false,
                isSupportedRoute: true,
                isAmbientQuiet: true,
                calibrationProfile: CalibrationProfileCatalog.airPodsPro3CalibrationUnavailable,
                audiogramThreshold: AudiogramThresholdAtFrequency(
                    frequencyHz: 1_000,
                    leftDBHL: 10,
                    rightDBHL: 15,
                    sourceAudiogramID: nil,
                    measuredAt: nil,
                    derivation: "exact_1000hz_no_interpolation"
                )
            )
        )

        #expect(result.validationStatus == .invalid)
        #expect(result.qualityFlags.contains(.calibrationUnavailable))
        #expect(result.qualityFlags.contains(.missingFrequencyCalibration))
        #expect(result.estimatedDBSPL == nil)
    }
}
