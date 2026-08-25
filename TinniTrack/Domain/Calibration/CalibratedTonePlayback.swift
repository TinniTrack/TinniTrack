import Foundation

nonisolated enum CalibratedTonePlaybackChannel: String, Equatable {
    case left
    case right
    case both
}

nonisolated enum CalibratedTonePlaybackError: Error, Equatable {
    case guardrailsNotEvaluated
    case guardrailsFailed(CalibratedAudioGuardrailError?)
    case guardrailsRestartRequired(CalibratedAudioGuardrailError?)
    case missingGuardrailOutputVolume
    case unsupportedGuardrailHeadphoneProfile(String?)
    case invalidDuration(Double)
    case invalidRampDuration(Double, duration: Double)
    case unsafeAmplitude(Double)
}

nonisolated struct CalibratedTonePlaybackRequest: Equatable {
    let frequencyHz: Double
    let levelDBHL: Double
    let channel: CalibratedTonePlaybackChannel
    let duration: TimeInterval
    let rampDuration: TimeInterval
    let stopsAfterDuration: Bool
    let headphoneIdentifier: String
    let guardrailValidation: CalibratedAudioGuardrailValidation

    init(
        frequencyHz: Double,
        levelDBHL: Double,
        channel: CalibratedTonePlaybackChannel,
        duration: TimeInterval,
        rampDuration: TimeInterval = CalibratedTonePlaybackDefaults.rampDuration,
        stopsAfterDuration: Bool = true,
        headphoneIdentifier: String = CalibratedHeadphoneIdentifier.airPodsPro2,
        guardrailValidation: CalibratedAudioGuardrailValidation
    ) {
        self.frequencyHz = frequencyHz
        self.levelDBHL = levelDBHL
        self.channel = channel
        self.duration = duration
        self.rampDuration = rampDuration
        self.stopsAfterDuration = stopsAfterDuration
        self.headphoneIdentifier = headphoneIdentifier
        self.guardrailValidation = guardrailValidation
    }
}

nonisolated enum CalibratedTonePlaybackDefaults {
    static let sampleRate = 44_100.0
    static let rampDuration: TimeInterval = 0.2
    static let levelAdjustmentRampDuration: TimeInterval = 0.05
    static let renderBufferFrameCount = 512
    static let mixerGainPolicy = "AVAudioEngine mainMixerNode.outputVolume fixed at 1.0; no app-level EQ, limiter, compressor, or extra gain is applied by the calibrated player."
}

nonisolated struct CalibratedTonePlaybackMetadata: Equatable {
    let frequencyHz: Double
    let channel: CalibratedTonePlaybackChannel
    let requestedDBHL: Double
    let targetDBSPL: Double
    let attenuationDB: Double
    let linearAmplitude: Double
    let duration: TimeInterval
    let rampDuration: TimeInterval
    let sampleRate: Double
    let bufferFrameCount: Int
    let routeGuardrailMetadata: CalibratedAudioGuardrailMetadata
    let calibrationMetadata: CalibratedAudioCalibrationMetadata
    let mixerGainPolicy: String
    let requestedAt: Date
    let startedAt: Date?
    let stoppedAt: Date?

    func started(at timestamp: Date) -> CalibratedTonePlaybackMetadata {
        CalibratedTonePlaybackMetadata(
            frequencyHz: frequencyHz,
            channel: channel,
            requestedDBHL: requestedDBHL,
            targetDBSPL: targetDBSPL,
            attenuationDB: attenuationDB,
            linearAmplitude: linearAmplitude,
            duration: duration,
            rampDuration: rampDuration,
            sampleRate: sampleRate,
            bufferFrameCount: bufferFrameCount,
            routeGuardrailMetadata: routeGuardrailMetadata,
            calibrationMetadata: calibrationMetadata,
            mixerGainPolicy: mixerGainPolicy,
            requestedAt: requestedAt,
            startedAt: timestamp,
            stoppedAt: stoppedAt
        )
    }

    func stopped(at timestamp: Date) -> CalibratedTonePlaybackMetadata {
        CalibratedTonePlaybackMetadata(
            frequencyHz: frequencyHz,
            channel: channel,
            requestedDBHL: requestedDBHL,
            targetDBSPL: targetDBSPL,
            attenuationDB: attenuationDB,
            linearAmplitude: linearAmplitude,
            duration: duration,
            rampDuration: rampDuration,
            sampleRate: sampleRate,
            bufferFrameCount: bufferFrameCount,
            routeGuardrailMetadata: routeGuardrailMetadata,
            calibrationMetadata: calibrationMetadata,
            mixerGainPolicy: mixerGainPolicy,
            requestedAt: requestedAt,
            startedAt: startedAt,
            stoppedAt: timestamp
        )
    }
}

nonisolated struct CalibratedTonePlaybackPlan: Equatable {
    let request: CalibratedTonePlaybackRequest
    let conversion: CalibratedAudioConversion
    let renderConfiguration: CalibratedToneRenderConfiguration
    let metadata: CalibratedTonePlaybackMetadata
}

nonisolated struct CalibratedTonePlaybackPlanner {
    let converter: CalibratedAudioConverter
    let sampleRate: Double
    let bufferFrameCount: Int
    let mixerGainPolicy: String
    let dateProvider: () -> Date

    init(
        converter: CalibratedAudioConverter = CalibratedAudioConverter(),
        sampleRate: Double = CalibratedTonePlaybackDefaults.sampleRate,
        bufferFrameCount: Int = CalibratedTonePlaybackDefaults.renderBufferFrameCount,
        mixerGainPolicy: String = CalibratedTonePlaybackDefaults.mixerGainPolicy,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.converter = converter
        self.sampleRate = sampleRate
        self.bufferFrameCount = bufferFrameCount
        self.mixerGainPolicy = mixerGainPolicy
        self.dateProvider = dateProvider
    }

    func makePlan(for request: CalibratedTonePlaybackRequest) throws -> CalibratedTonePlaybackPlan {
        try validateGuardrails(request.guardrailValidation)
        try validateTiming(duration: request.duration, rampDuration: request.rampDuration)

        guard request.guardrailValidation.metadata.supportedHeadphoneIdentifier == request.headphoneIdentifier else {
            throw CalibratedTonePlaybackError.unsupportedGuardrailHeadphoneProfile(
                request.guardrailValidation.metadata.supportedHeadphoneIdentifier
            )
        }

        guard let outputVolume = request.guardrailValidation.metadata.rawOutputVolume else {
            throw CalibratedTonePlaybackError.missingGuardrailOutputVolume
        }

        let conversion = try converter.conversion(
            headphoneIdentifier: request.headphoneIdentifier,
            frequencyHz: request.frequencyHz,
            levelDBHL: request.levelDBHL,
            outputVolume: outputVolume
        )

        guard conversion.linearAmplitude.isFinite,
              conversion.linearAmplitude > 0.0,
              conversion.linearAmplitude < 1.0
        else {
            throw CalibratedTonePlaybackError.unsafeAmplitude(conversion.linearAmplitude)
        }

        let renderConfiguration = CalibratedToneRenderConfiguration(
            frequencyHz: conversion.frequencyHz,
            amplitude: conversion.linearAmplitude,
            channel: request.channel,
            duration: request.duration,
            rampDuration: request.rampDuration,
            stopsAfterDuration: request.stopsAfterDuration,
            sampleRate: sampleRate
        )
        let metadata = CalibratedTonePlaybackMetadata(
            frequencyHz: conversion.frequencyHz,
            channel: request.channel,
            requestedDBHL: conversion.requestedDBHL,
            targetDBSPL: conversion.targetDBSPL,
            attenuationDB: conversion.attenuationDB,
            linearAmplitude: conversion.linearAmplitude,
            duration: request.duration,
            rampDuration: request.rampDuration,
            sampleRate: sampleRate,
            bufferFrameCount: bufferFrameCount,
            routeGuardrailMetadata: request.guardrailValidation.metadata,
            calibrationMetadata: conversion.calibrationMetadata,
            mixerGainPolicy: mixerGainPolicy,
            requestedAt: dateProvider(),
            startedAt: nil,
            stoppedAt: nil
        )

        return CalibratedTonePlaybackPlan(
            request: request,
            conversion: conversion,
            renderConfiguration: renderConfiguration,
            metadata: metadata
        )
    }

    private func validateGuardrails(_ validation: CalibratedAudioGuardrailValidation) throws {
        switch validation.state {
        case .passed:
            return
        case .notEvaluated:
            throw CalibratedTonePlaybackError.guardrailsNotEvaluated
        case .failed:
            throw CalibratedTonePlaybackError.guardrailsFailed(validation.error)
        case .restartRequired:
            throw CalibratedTonePlaybackError.guardrailsRestartRequired(validation.error)
        }
    }

    private func validateTiming(duration: TimeInterval, rampDuration: TimeInterval) throws {
        guard duration.isFinite, duration > 0.0 else {
            throw CalibratedTonePlaybackError.invalidDuration(duration)
        }
        guard rampDuration.isFinite,
              rampDuration >= 0.0,
              rampDuration * 2.0 <= duration
        else {
            throw CalibratedTonePlaybackError.invalidRampDuration(rampDuration, duration: duration)
        }
        guard sampleRate.isFinite, sampleRate > 0.0 else {
            throw CalibratedTonePlaybackError.invalidDuration(duration)
        }
    }
}
