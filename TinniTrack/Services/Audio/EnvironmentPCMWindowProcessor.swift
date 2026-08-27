import Foundation

nonisolated struct EnvironmentPCMProcessingResult: Equatable, Sendable {
    let didCompleteWarmUp: Bool
    let measurements: [TinnitusEnvironmentSPLMeasurement]
}

/// Converts streaming Float32 PCM into exact, buffer-boundary-independent
/// A-weighted energy windows. This type owns no audio session and no files.
nonisolated struct EnvironmentPCMWindowProcessor: Sendable {
    private(set) var input: TinnitusEnvironmentInputConfiguration
    private let calibration: TinnitusEnvironmentCalibrationProfile
    private let windowDuration: TimeInterval
    private let targetFrameCount: Int
    private var filters: [AWeightingFilter]
    private var warmUpFramesRemaining: Int
    private var hasCompletedWarmUp: Bool
    private var framesInWindow = 0
    private var energySum = 0.0
    private var currentInvalidReason: TinnitusEnvironmentMeasurementFailureReason?
    private var windowStartedAt: Date?
    private var expectedNextSampleTime: Int64?

    init(
        input: TinnitusEnvironmentInputConfiguration,
        windowDuration: TimeInterval = 1.0,
        warmUpDuration: TimeInterval = 0.5,
        calibration: TinnitusEnvironmentCalibrationProfile = .provisionalBuiltInMicrophone
    ) throws {
        guard input.sampleRate.isFinite,
              input.sampleRate > 0,
              input.channelCount > 0,
              windowDuration.isFinite,
              windowDuration > 0,
              warmUpDuration.isFinite,
              warmUpDuration >= 0
        else {
            throw EnvironmentPCMWindowProcessorError.invalidFormat
        }

        self.input = input
        self.windowDuration = windowDuration
        self.calibration = calibration
        targetFrameCount = max(1, Int((input.sampleRate * windowDuration).rounded()))
        warmUpFramesRemaining = max(0, Int((input.sampleRate * warmUpDuration).rounded()))
        hasCompletedWarmUp = warmUpFramesRemaining == 0
        filters = try (0..<input.channelCount).map { _ in
            try AWeightingFilter(sampleRate: input.sampleRate)
        }
    }

    mutating func process(
        channels: [[Float]],
        timestamp: Date,
        sampleTime: Int64? = nil
    ) -> EnvironmentPCMProcessingResult {
        guard channels.count == input.channelCount,
              let frameCount = channels.first?.count,
              frameCount > 0,
              channels.allSatisfy({ $0.count == frameCount })
        else {
            return EnvironmentPCMProcessingResult(
                didCompleteWarmUp: false,
                measurements: [invalidMeasurement(reason: .emptyInput, timestamp: timestamp)]
            )
        }

        if let sampleTime,
           let expectedNextSampleTime,
           sampleTime != expectedNextSampleTime {
            resetWindowAndFilterState()
            self.expectedNextSampleTime = sampleTime + Int64(frameCount)
            return EnvironmentPCMProcessingResult(
                didCompleteWarmUp: false,
                measurements: [invalidMeasurement(reason: .discontinuousSampleTime, timestamp: timestamp)]
            )
        }
        if let sampleTime {
            expectedNextSampleTime = sampleTime + Int64(frameCount)
        }

        var completedWarmUpInThisBuffer = false
        var completedMeasurements: [TinnitusEnvironmentSPLMeasurement] = []

        for frameIndex in 0..<frameCount {
            var frameEnergy = 0.0
            var invalidReason: TinnitusEnvironmentMeasurementFailureReason?

            for channelIndex in channels.indices {
                let rawSample = channels[channelIndex][frameIndex]
                if !rawSample.isFinite {
                    invalidReason = .invalidPCM
                } else if abs(rawSample) >= 1.0 {
                    invalidReason = .clippedPCM
                }

                let finiteSample = rawSample.isFinite ? rawSample : 0
                let weighted = filters[channelIndex].process(finiteSample)
                if !weighted.isFinite {
                    invalidReason = .invalidPCM
                } else {
                    frameEnergy += weighted * weighted
                }
            }

            if warmUpFramesRemaining > 0 {
                warmUpFramesRemaining -= 1
                if warmUpFramesRemaining == 0 {
                    hasCompletedWarmUp = true
                    completedWarmUpInThisBuffer = true
                    resetWindowOnly()
                }
                continue
            }

            if !hasCompletedWarmUp {
                continue
            }

            if windowStartedAt == nil {
                let secondsIntoBuffer = Double(frameIndex) / input.sampleRate
                windowStartedAt = timestamp.addingTimeInterval(secondsIntoBuffer)
            }
            if let invalidReason {
                currentInvalidReason = currentInvalidReason ?? invalidReason
            }
            energySum += frameEnergy
            framesInWindow += 1

            if framesInWindow == targetFrameCount {
                completedMeasurements.append(completeWindow())
            }
        }

        return EnvironmentPCMProcessingResult(
            didCompleteWarmUp: completedWarmUpInThisBuffer,
            measurements: completedMeasurements
        )
    }

    mutating func invalidate(
        reason: TinnitusEnvironmentMeasurementFailureReason,
        timestamp: Date
    ) -> TinnitusEnvironmentSPLMeasurement {
        let measurement = invalidMeasurement(reason: reason, timestamp: timestamp)
        resetWindowAndFilterState()
        return measurement
    }

    private mutating func completeWindow() -> TinnitusEnvironmentSPLMeasurement {
        let start = windowStartedAt ?? Date()
        let duration = Double(targetFrameCount) / input.sampleRate
        let end = start.addingTimeInterval(duration)
        let validity: TinnitusEnvironmentMeasurementValidity
        let digitalLevel: Double?
        let estimatedLevel: Double?

        if let currentInvalidReason {
            validity = .invalid(currentInvalidReason)
            digitalLevel = nil
            estimatedLevel = nil
        } else {
            let sampleValueCount = Double(targetFrameCount * input.channelCount)
            let meanSquare = energySum / sampleValueCount
            // A finite floor keeps silence JSON-safe while retaining the clear
            // digital reference that unity RMS is 0 dBFS.
            digitalLevel = 10 * log10(max(meanSquare, 1e-16))
            estimatedLevel = calibration.estimatedDBAOffset.map { digitalLevel! + $0 }
            validity = .valid
        }

        let measurement = TinnitusEnvironmentSPLMeasurement(
            schemaVersion: TinnitusEnvironmentSPLMeasurement.currentSchemaVersion,
            windowStartedAt: start,
            windowEndedAt: end,
            duration: duration,
            aWeightedDigitalLevelDBFS: digitalLevel,
            provisionalEstimatedDBA: estimatedLevel,
            validity: validity,
            input: input,
            algorithmVersion: "\(TinnitusEnvironmentSPLMeasurement.currentAlgorithmVersion)+\(AWeightingFilter.algorithmVersion)",
            calibration: calibration
        )
        resetWindowOnly(nextWindowStart: end)
        return measurement
    }

    private func invalidMeasurement(
        reason: TinnitusEnvironmentMeasurementFailureReason,
        timestamp: Date
    ) -> TinnitusEnvironmentSPLMeasurement {
        let partialDuration = Double(framesInWindow) / input.sampleRate
        return TinnitusEnvironmentSPLMeasurement(
            schemaVersion: TinnitusEnvironmentSPLMeasurement.currentSchemaVersion,
            windowStartedAt: windowStartedAt ?? timestamp,
            windowEndedAt: timestamp,
            duration: partialDuration,
            aWeightedDigitalLevelDBFS: nil,
            provisionalEstimatedDBA: nil,
            validity: .invalid(reason),
            input: input,
            algorithmVersion: "\(TinnitusEnvironmentSPLMeasurement.currentAlgorithmVersion)+\(AWeightingFilter.algorithmVersion)",
            calibration: calibration
        )
    }

    private mutating func resetWindowAndFilterState() {
        resetWindowOnly()
        expectedNextSampleTime = nil
        for index in filters.indices {
            filters[index].reset()
        }
    }

    private mutating func resetWindowOnly(nextWindowStart: Date? = nil) {
        framesInWindow = 0
        energySum = 0
        currentInvalidReason = nil
        windowStartedAt = nextWindowStart
    }
}

nonisolated enum EnvironmentPCMWindowProcessorError: Error, Equatable {
    case invalidFormat
}
