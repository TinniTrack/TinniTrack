import Foundation
import Testing
@testable import TinniTrack

struct EnvironmentPCMWindowProcessorTests {
    @Test(arguments: [44_100.0, 48_000.0])
    func producesExactOneSecondWindowsAtSupportedRates(sampleRate: Double) throws {
        var processor = try makeProcessor(sampleRate: sampleRate)
        let frames = Int(sampleRate)
        let samples = sine(amplitude: 0.1, sampleRate: sampleRate, count: frames)
        let result = processor.process(channels: [samples], timestamp: .reference)

        #expect(result.measurements.count == 1)
        #expect(result.measurements[0].duration == 1)
        #expect(result.measurements[0].input.sampleRate == sampleRate)
        #expect(result.measurements[0].input.channelCount == 1)
        #expect(result.measurements[0].isValid)
        #expect(abs((result.measurements[0].aWeightedDigitalLevelDBFS ?? 0) - (-23.0103)) < 0.1)
    }

    @Test
    func arbitraryBufferBoundariesDoNotChangeWindowEnergy() throws {
        let sampleRate = 48_000.0
        let samples = sine(amplitude: 0.15, frequency: 997, sampleRate: sampleRate, count: 96_000)
        var whole = try makeProcessor(sampleRate: sampleRate)
        let wholeMeasurements = whole.process(channels: [samples], timestamp: .reference).measurements

        var chunked = try makeProcessor(sampleRate: sampleRate)
        var chunkedMeasurements: [TinnitusEnvironmentSPLMeasurement] = []
        let sizes = [127, 4_093, 19, 8_192, 503]
        var cursor = 0
        var sizeIndex = 0
        while cursor < samples.count {
            let end = min(samples.count, cursor + sizes[sizeIndex % sizes.count])
            let timestamp = Date.reference.addingTimeInterval(Double(cursor) / sampleRate)
            chunkedMeasurements.append(contentsOf: chunked.process(
                channels: [Array(samples[cursor..<end])],
                timestamp: timestamp,
                sampleTime: Int64(cursor)
            ).measurements)
            cursor = end
            sizeIndex += 1
        }

        #expect(wholeMeasurements.count == 2)
        #expect(chunkedMeasurements.count == 2)
        #expect(abs((wholeMeasurements[0].aWeightedDigitalLevelDBFS ?? 0) - (chunkedMeasurements[0].aWeightedDigitalLevelDBFS ?? 1)) < 1e-10)
        #expect(abs((wholeMeasurements[1].aWeightedDigitalLevelDBFS ?? 0) - (chunkedMeasurements[1].aWeightedDigitalLevelDBFS ?? 1)) < 1e-10)
    }

    @Test
    func energyWindowDoesNotAverageDecibelValues() throws {
        let sampleRate = 48_000.0
        let half = Int(sampleRate / 2)
        let samples = sine(amplitude: 0.1, sampleRate: sampleRate, count: half)
            + sine(amplitude: 0.01, sampleRate: sampleRate, count: half, startingFrame: half)
        var processor = try makeProcessor(sampleRate: sampleRate)
        let measurement = try #require(
            processor.process(channels: [samples], timestamp: .reference).measurements.first
        )

        // Mean energy of the two halves is about -25.98 dBFS. Arithmetic
        // averaging their approximately -23/-43 dB levels would be -33 dB.
        #expect(abs((measurement.aWeightedDigitalLevelDBFS ?? 0) - (-25.98)) < 0.15)
    }

    @Test
    func channelEnergyUsesFrameCountTimesChannelCount() throws {
        let sampleRate = 48_000.0
        let samples = sine(amplitude: 0.1, sampleRate: sampleRate, count: 48_000)
        var mono = try makeProcessor(sampleRate: sampleRate)
        var stereo = try makeProcessor(sampleRate: sampleRate, channelCount: 2)

        let monoLevel = try #require(
            mono.process(channels: [samples], timestamp: .reference)
                .measurements.first?.aWeightedDigitalLevelDBFS
        )
        let stereoLevel = try #require(
            stereo.process(channels: [samples, samples], timestamp: .reference)
                .measurements.first?.aWeightedDigitalLevelDBFS
        )

        #expect(abs(monoLevel - stereoLevel) < 1e-10)
    }

    @Test
    func silenceIsAValidFiniteFloorMeasurement() throws {
        var processor = try makeProcessor(sampleRate: 48_000)
        let result = processor.process(
            channels: [Array(repeating: 0, count: 48_000)],
            timestamp: .reference
        )
        let measurement = try #require(result.measurements.first)

        #expect(measurement.isValid)
        #expect(measurement.aWeightedDigitalLevelDBFS == -160)
        #expect(measurement.provisionalEstimatedDBA == -160)
    }

    @Test(arguments: [Float.nan, Float.infinity, 1.0, -1.0])
    func invalidAndClippedPCMInvalidateTheWholeWindow(value: Float) throws {
        var processor = try makeProcessor(sampleRate: 48_000)
        var samples = sine(amplitude: 0.1, sampleRate: 48_000, count: 48_000)
        samples[12_345] = value
        let measurement = try #require(
            processor.process(channels: [samples], timestamp: .reference).measurements.first
        )

        #expect(measurement.isValid == false)
        #expect(measurement.aWeightedDigitalLevelDBFS == nil)
        if value.isFinite {
            #expect(measurement.validity == .invalid(.clippedPCM))
        } else {
            #expect(measurement.validity == .invalid(.invalidPCM))
        }
    }

    @Test
    func emptyInputProducesOnlyAnInvalidRecord() throws {
        var processor = try makeProcessor(sampleRate: 48_000)
        let result = processor.process(channels: [[]], timestamp: .reference)

        #expect(result.measurements.count == 1)
        #expect(result.measurements[0].validity == .invalid(.emptyInput))
        #expect(result.measurements[0].aWeightedDigitalLevelDBFS == nil)
    }

    @Test
    func warmUpFramesAreExcludedFromTheFirstCompleteWindow() throws {
        var processor = try makeProcessor(sampleRate: 48_000, warmUpDuration: 0.5)
        let warmUp = processor.process(
            channels: [sine(amplitude: 0.9, sampleRate: 48_000, count: 24_000)],
            timestamp: .reference
        )
        #expect(warmUp.didCompleteWarmUp)
        #expect(warmUp.measurements.isEmpty)

        let firstWindow = processor.process(
            channels: [sine(amplitude: 0.1, sampleRate: 48_000, count: 48_000, startingFrame: 24_000)],
            timestamp: Date.reference.addingTimeInterval(0.5)
        )

        #expect(firstWindow.measurements.count == 1)
        #expect(abs((firstWindow.measurements[0].aWeightedDigitalLevelDBFS ?? 0) - (-23.0103)) < 0.1)
    }

    @Test
    func discontinuousSampleTimeInvalidatesPartialWindow() throws {
        var processor = try makeProcessor(sampleRate: 48_000)
        _ = processor.process(
            channels: [Array(repeating: 0, count: 12_000)],
            timestamp: .reference,
            sampleTime: 0
        )
        let discontinuity = processor.process(
            channels: [Array(repeating: 0, count: 12_000)],
            timestamp: Date.reference.addingTimeInterval(0.25),
            sampleTime: 20_000
        )

        #expect(discontinuity.measurements.count == 1)
        #expect(discontinuity.measurements[0].validity == .invalid(.discontinuousSampleTime))
    }

    private func makeProcessor(
        sampleRate: Double,
        channelCount: Int = 1,
        warmUpDuration: TimeInterval = 0
    ) throws -> EnvironmentPCMWindowProcessor {
        try EnvironmentPCMWindowProcessor(
            input: TinnitusEnvironmentInputConfiguration(
                route: .builtInMicrophone,
                dataSourceOrientation: .bottom,
                sampleRate: sampleRate,
                channelCount: channelCount,
                inputGain: 1,
                isInputGainSettable: false
            ),
            warmUpDuration: warmUpDuration,
            calibration: TinnitusEnvironmentCalibrationProfile(
                identifier: "digital-only-test",
                status: .provisional,
                estimatedDBAOffset: 0,
                referenceSensitivityOffsetDB: nil,
                provenance: "Deterministic test fixture",
                uncertaintyDB: nil
            )
        )
    }

    private func sine(
        amplitude: Double,
        frequency: Double = 1_000,
        sampleRate: Double,
        count: Int,
        startingFrame: Int = 0
    ) -> [Float] {
        (0..<count).map { offset in
            let frame = startingFrame + offset
            return Float(amplitude * sin(2 * .pi * frequency * Double(frame) / sampleRate))
        }
    }
}

private extension Date {
    static let reference = Date(timeIntervalSince1970: 1_720_000_000)
}
