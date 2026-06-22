import Foundation

struct CalibratedToneRenderConfiguration: Equatable {
    let frequencyHz: Double
    let amplitude: Double
    let channel: CalibratedTonePlaybackChannel
    let duration: TimeInterval
    let rampDuration: TimeInterval
    let sampleRate: Double

    var frameCount: Int {
        Int((duration * sampleRate).rounded())
    }

    var rampFrameCount: Int {
        min(Int((rampDuration * sampleRate).rounded()), frameCount / 2)
    }
}

struct CalibratedTonePCMBuffer: Equatable {
    let left: [Float]
    let right: [Float]
    let sampleRate: Double

    var frameCount: Int {
        left.count
    }
}

enum CalibratedToneRendererError: Error, Equatable {
    case invalidConfiguration
    case unsafeAmplitude(Double)
}

struct CalibratedToneRenderer {
    private var phase = 0.0
    private var renderedFrameCount = 0

    init(initialPhase: Double = 0.0) {
        phase = initialPhase
    }

    static func render(_ configuration: CalibratedToneRenderConfiguration) throws -> CalibratedTonePCMBuffer {
        var renderer = CalibratedToneRenderer()
        return try renderer.renderNextFrames(configuration.frameCount, configuration: configuration)
    }

    mutating func renderNextFrames(
        _ frameCount: Int,
        configuration: CalibratedToneRenderConfiguration
    ) throws -> CalibratedTonePCMBuffer {
        try validate(configuration)
        guard frameCount >= 0 else {
            throw CalibratedToneRendererError.invalidConfiguration
        }

        var left = Array(repeating: Float.zero, count: frameCount)
        var right = Array(repeating: Float.zero, count: frameCount)
        let phaseIncrement = 2.0 * Double.pi * configuration.frequencyHz / configuration.sampleRate

        for localFrame in 0..<frameCount {
            let absoluteFrame = renderedFrameCount + localFrame
            let envelope = envelopeValue(
                absoluteFrame: absoluteFrame,
                totalFrames: configuration.frameCount,
                rampFrames: configuration.rampFrameCount
            )
            let sample = Float(sin(phase) * configuration.amplitude * envelope)

            switch configuration.channel {
            case .left:
                left[localFrame] = sample
            case .right:
                right[localFrame] = sample
            }

            phase += phaseIncrement
            if phase >= 2.0 * Double.pi {
                phase.formTruncatingRemainder(dividingBy: 2.0 * Double.pi)
            }
        }

        renderedFrameCount += frameCount

        return CalibratedTonePCMBuffer(
            left: left,
            right: right,
            sampleRate: configuration.sampleRate
        )
    }

    private func validate(_ configuration: CalibratedToneRenderConfiguration) throws {
        guard configuration.frequencyHz.isFinite,
              configuration.frequencyHz > 0.0,
              configuration.sampleRate.isFinite,
              configuration.sampleRate > 0.0,
              configuration.duration.isFinite,
              configuration.duration > 0.0,
              configuration.rampDuration.isFinite,
              configuration.rampDuration >= 0.0,
              configuration.frameCount > 0,
              configuration.rampFrameCount * 2 <= configuration.frameCount
        else {
            throw CalibratedToneRendererError.invalidConfiguration
        }

        guard configuration.amplitude.isFinite,
              configuration.amplitude > 0.0,
              configuration.amplitude < 1.0
        else {
            throw CalibratedToneRendererError.unsafeAmplitude(configuration.amplitude)
        }
    }

    private func envelopeValue(
        absoluteFrame: Int,
        totalFrames: Int,
        rampFrames: Int
    ) -> Double {
        guard rampFrames > 0 else {
            return 1.0
        }

        if absoluteFrame < rampFrames {
            return Double(absoluteFrame) / Double(rampFrames)
        }

        if absoluteFrame >= totalFrames - rampFrames {
            let remainingFrames = max(totalFrames - absoluteFrame - 1, 0)
            return Double(remainingFrames) / Double(rampFrames)
        }

        return 1.0
    }
}
