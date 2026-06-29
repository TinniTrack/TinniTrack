import Foundation

enum AudiogramThresholdResolutionError: Error, Equatable, LocalizedError {
    case missingAudiogram
    case missingFrequency(Double)
    case missingEarThreshold(CalibratedTonePlaybackChannel, frequencyHz: Double)
    case missingBinauralThreshold(frequencyHz: Double)

    var errorDescription: String? {
        switch self {
        case .missingAudiogram:
            return "No imported hearing-test audiogram is available."
        case .missingFrequency(let frequencyHz):
            return "The imported hearing test does not include \(Int(frequencyHz)) Hz."
        case .missingEarThreshold(let channel, let frequencyHz):
            return "The imported hearing test does not include a \(channel.rawValue) ear threshold at \(Int(frequencyHz)) Hz."
        case .missingBinauralThreshold(let frequencyHz):
            return "The imported hearing test does not include both left and right ear thresholds at \(Int(frequencyHz)) Hz."
        }
    }
}

struct AudiogramThresholdResolver {
    let targetFrequencyHz: Double
    let toleranceHz: Double

    init(targetFrequencyHz: Double = 1_000, toleranceHz: Double = 0.5) {
        self.targetFrequencyHz = targetFrequencyHz
        self.toleranceHz = toleranceHz
    }

    func resolveThresholdDBHL(
        for channel: CalibratedTonePlaybackChannel,
        in audiogram: AudiogramRecord?
    ) throws -> Double {
        guard let audiogram else {
            throw AudiogramThresholdResolutionError.missingAudiogram
        }

        guard let point = audiogram.points.first(where: { abs($0.frequencyHz - targetFrequencyHz) <= toleranceHz }) else {
            throw AudiogramThresholdResolutionError.missingFrequency(targetFrequencyHz)
        }

        if channel == .both {
            guard let leftThreshold = point.leftEarDBHL,
                  let rightThreshold = point.rightEarDBHL
            else {
                throw AudiogramThresholdResolutionError.missingBinauralThreshold(frequencyHz: targetFrequencyHz)
            }

            return (leftThreshold + rightThreshold) / 2.0
        }

        let threshold = channel == .left ? point.leftEarDBHL : point.rightEarDBHL
        guard let threshold else {
            throw AudiogramThresholdResolutionError.missingEarThreshold(channel, frequencyHz: targetFrequencyHz)
        }

        return threshold
    }
}
