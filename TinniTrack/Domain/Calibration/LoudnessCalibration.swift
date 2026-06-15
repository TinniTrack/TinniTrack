import Foundation

enum LoudnessMatchValidationStatus: String, Equatable {
    case acceptedValid
    case invalid
}

enum LoudnessMatchQualityFlag: String, Equatable, Hashable {
    case routeNameCalibrationInferred
    case unsupportedRoute
    case missingCalibrationProfile
    case calibrationUnavailable
    case missingFrequencyCalibration
    case missingOutputVolume
    case outputVolumeChanged
    case ambientTooLoud
    case missingAudiogramThreshold
    case normalizedAmplitudeClamped
    case matchedAmplitudeBelowMinimum
    case matchedAmplitudeAboveSafeMaximum
    case estimatedLevelExceedsSafeHL
}

struct AudiogramThresholdAtFrequency: Equatable {
    let frequencyHz: Double
    let leftDBHL: Double?
    let rightDBHL: Double?
    let sourceAudiogramID: UUID?
    let measuredAt: Date?
    let derivation: String

    var hasAnyThreshold: Bool {
        leftDBHL != nil || rightDBHL != nil
    }

    var bilateralMeanDBHL: Double? {
        let values = [leftDBHL, rightDBHL].compactMap { $0 }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}

struct LoudnessCalibrationInput: Equatable {
    let normalizedAmplitude: Double
    let systemOutputVolume: Double?
    let didSystemOutputVolumeChange: Bool
    let isSupportedRoute: Bool
    let isAmbientQuiet: Bool
    let calibrationProfile: HeadphoneCalibrationProfile?
    let audiogramThreshold: AudiogramThresholdAtFrequency?
}

struct LoudnessCalibrationResult: Equatable {
    let validationStatus: LoudnessMatchValidationStatus
    let qualityFlags: [LoudnessMatchQualityFlag]
    let invalidationReasons: [String]
    let rawNormalizedAmplitude: Double
    let clampedNormalizedAmplitude: Double
    let peakDBFS: Double?
    let rmsDBFS: Double?
    let estimatedDBSPL: Double?
    let estimatedDBHL: Double?
    let estimatedDBSLLeft: Double?
    let estimatedDBSLRight: Double?
    let estimatedDBSLBilateralMean: Double?
    let volumeCurveLookup: VolumeCurveLookup?
    let calibrationProfile: HeadphoneCalibrationProfile?
    let audiogramThreshold: AudiogramThresholdAtFrequency?

    var isAcceptedValid: Bool {
        validationStatus == .acceptedValid
    }
}

enum LoudnessCalibrationCalculator {
    static let dBFSConvention = "matched_level is peak-normalized sine amplitude. peak_dBFS = 20*log10(amplitude); rms_dBFS = 20*log10(amplitude/sqrt(2)). estimated_dB_SPL uses rms_dBFS."

    static func calibrate(_ input: LoudnessCalibrationInput) -> LoudnessCalibrationResult {
        var flags = Set<LoudnessMatchQualityFlag>()
        var invalidationReasons: [String] = []

        let clampedAmplitude = min(
            max(input.normalizedAmplitude, StudyNo1Configuration.minimumMatchedNormalizedAmplitude),
            StudyNo1Configuration.maximumSafeNormalizedAmplitude
        )

        if clampedAmplitude != input.normalizedAmplitude {
            flags.insert(.normalizedAmplitudeClamped)
        }

        if input.normalizedAmplitude < StudyNo1Configuration.minimumMatchedNormalizedAmplitude {
            flags.insert(.matchedAmplitudeBelowMinimum)
            invalidationReasons.append("Matched amplitude is below the minimum finite calibration bound.")
        }

        if input.normalizedAmplitude > StudyNo1Configuration.maximumSafeNormalizedAmplitude {
            flags.insert(.matchedAmplitudeAboveSafeMaximum)
            invalidationReasons.append("Matched amplitude exceeds the safe playback bound.")
        }

        if !input.isSupportedRoute {
            flags.insert(.unsupportedRoute)
            invalidationReasons.append("Audio route is not supported for Study No. 1 loudness matching.")
        }

        if !input.isAmbientQuiet {
            flags.insert(.ambientTooLoud)
            invalidationReasons.append("Ambient noise is above the Study No. 1 threshold.")
        }

        if input.didSystemOutputVolumeChange {
            flags.insert(.outputVolumeChanged)
            invalidationReasons.append("System output volume changed during matching.")
        }

        guard let profile = input.calibrationProfile else {
            flags.insert(.missingCalibrationProfile)
            invalidationReasons.append("No headphone calibration profile matched the current route.")
            return makeResult(
                input: input,
                clampedAmplitude: clampedAmplitude,
                flags: flags,
                invalidationReasons: invalidationReasons
            )
        }

        flags.insert(.routeNameCalibrationInferred)

        if profile.supportStatus != .supported {
            flags.insert(.calibrationUnavailable)
            invalidationReasons.append("The detected route is allowed but has no usable calibration table.")
        }

        guard let frequencyCalibration = profile.frequencyCalibration else {
            flags.insert(.missingFrequencyCalibration)
            invalidationReasons.append("Calibration profile is missing a 1,000 Hz frequency table entry.")
            return makeResult(
                input: input,
                clampedAmplitude: clampedAmplitude,
                flags: flags,
                invalidationReasons: invalidationReasons,
                profile: profile
            )
        }

        guard let systemOutputVolume = input.systemOutputVolume,
              let volumeLookup = profile.volumeOffsetDB(forSystemOutputVolume: systemOutputVolume) else {
            flags.insert(.missingOutputVolume)
            invalidationReasons.append("System output volume is unavailable or cannot be mapped to the calibration volume curve.")
            return makeResult(
                input: input,
                clampedAmplitude: clampedAmplitude,
                flags: flags,
                invalidationReasons: invalidationReasons,
                profile: profile
            )
        }

        let peakDBFS = 20 * log10(clampedAmplitude)
        let rmsDBFS = 20 * log10(clampedAmplitude / sqrt(2))
        let estimatedDBSPL = frequencyCalibration.frequencyDBSPL + volumeLookup.offsetDB + rmsDBFS
        let estimatedDBHL = estimatedDBSPL - frequencyCalibration.retsplDBSPL

        if estimatedDBHL > 85 {
            flags.insert(.estimatedLevelExceedsSafeHL)
            invalidationReasons.append("Estimated dB HL exceeds the Study No. 1 safe analysis bound.")
        }

        let threshold = input.audiogramThreshold
        if threshold?.hasAnyThreshold != true {
            flags.insert(.missingAudiogramThreshold)
            invalidationReasons.append("No exact 1,000 Hz participant audiogram threshold is available for dB SL.")
        }

        let dBSLLeft = threshold?.leftDBHL.map { estimatedDBHL - $0 }
        let dBSLRight = threshold?.rightDBHL.map { estimatedDBHL - $0 }
        let dBSLBilateralMean = threshold?.bilateralMeanDBHL.map { estimatedDBHL - $0 }

        return LoudnessCalibrationResult(
            validationStatus: invalidationReasons.isEmpty ? .acceptedValid : .invalid,
            qualityFlags: orderedFlags(flags),
            invalidationReasons: invalidationReasons,
            rawNormalizedAmplitude: input.normalizedAmplitude,
            clampedNormalizedAmplitude: clampedAmplitude,
            peakDBFS: peakDBFS,
            rmsDBFS: rmsDBFS,
            estimatedDBSPL: estimatedDBSPL,
            estimatedDBHL: estimatedDBHL,
            estimatedDBSLLeft: dBSLLeft,
            estimatedDBSLRight: dBSLRight,
            estimatedDBSLBilateralMean: dBSLBilateralMean,
            volumeCurveLookup: volumeLookup,
            calibrationProfile: profile,
            audiogramThreshold: threshold
        )
    }

    private static func makeResult(
        input: LoudnessCalibrationInput,
        clampedAmplitude: Double,
        flags: Set<LoudnessMatchQualityFlag>,
        invalidationReasons: [String],
        profile: HeadphoneCalibrationProfile? = nil
    ) -> LoudnessCalibrationResult {
        LoudnessCalibrationResult(
            validationStatus: .invalid,
            qualityFlags: orderedFlags(flags),
            invalidationReasons: invalidationReasons,
            rawNormalizedAmplitude: input.normalizedAmplitude,
            clampedNormalizedAmplitude: clampedAmplitude,
            peakDBFS: nil,
            rmsDBFS: nil,
            estimatedDBSPL: nil,
            estimatedDBHL: nil,
            estimatedDBSLLeft: nil,
            estimatedDBSLRight: nil,
            estimatedDBSLBilateralMean: nil,
            volumeCurveLookup: nil,
            calibrationProfile: profile ?? input.calibrationProfile,
            audiogramThreshold: input.audiogramThreshold
        )
    }

    private static func orderedFlags(_ flags: Set<LoudnessMatchQualityFlag>) -> [LoudnessMatchQualityFlag] {
        flags.sorted { $0.rawValue < $1.rawValue }
    }
}
