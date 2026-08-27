import Foundation
import Testing
@testable import TinniTrack

struct AWeightingFilterTests {
    @Test(arguments: [44_100.0, 48_000.0])
    func responseMatchesRepresentativeAWeightingFrequencies(sampleRate: Double) throws {
        let at100Hz = try AWeightingFilter.responseDB(frequencyHz: 100, sampleRate: sampleRate)
        let atOneKilohertz = try AWeightingFilter.responseDB(frequencyHz: 1_000, sampleRate: sampleRate)
        let atFourKilohertz = try AWeightingFilter.responseDB(frequencyHz: 4_000, sampleRate: sampleRate)
        let atTenKilohertz = try AWeightingFilter.responseDB(frequencyHz: 10_000, sampleRate: sampleRate)
        let atSixteenKilohertz = try AWeightingFilter.responseDB(frequencyHz: 16_000, sampleRate: sampleRate)
        let atTwentyKilohertz = try AWeightingFilter.responseDB(frequencyHz: 20_000, sampleRate: sampleRate)

        #expect(abs(at100Hz - (-19.1)) < 0.25)
        #expect(abs(atOneKilohertz) < 0.01)
        #expect(abs(atFourKilohertz - 1.0) < 0.2)
        #expect(abs(atTenKilohertz - (-2.5)) < 0.35)
        #expect(abs(atSixteenKilohertz - (-6.7)) < 0.4)
        #expect(abs(atTwentyKilohertz - (-9.3)) < 0.4)
    }

    @Test(arguments: [44_100.0, 48_000.0])
    func amplitudeDoublingIsApproximatelySixDecibels(sampleRate: Double) throws {
        let low = try filteredRMS(amplitude: 0.1, sampleRate: sampleRate)
        let high = try filteredRMS(amplitude: 0.2, sampleRate: sampleRate)
        let difference = 20 * log10(high / low)

        #expect(abs(difference - 6.0206) < 0.02)
    }

    @Test
    func filterStateIsIndependentOfCallerBufferBoundaries() throws {
        let sampleRate = 48_000.0
        let samples = sine(amplitude: 0.2, frequency: 997, sampleRate: sampleRate, count: 96_000)
        var whole = try AWeightingFilter(sampleRate: sampleRate)
        let wholeOutput = samples.map { whole.process($0) }

        var chunked = try AWeightingFilter(sampleRate: sampleRate)
        var chunkedOutput: [Double] = []
        var cursor = 0
        let sizes = [1, 17, 257, 4_096, 31, 777]
        var sizeIndex = 0
        while cursor < samples.count {
            let end = min(samples.count, cursor + sizes[sizeIndex % sizes.count])
            chunkedOutput.append(contentsOf: samples[cursor..<end].map { chunked.process($0) })
            cursor = end
            sizeIndex += 1
        }

        #expect(wholeOutput == chunkedOutput)
    }

    @Test
    func resetRemovesPriorStreamState() throws {
        var filter = try AWeightingFilter(sampleRate: 48_000)
        let impulse = [Float(1)] + Array(repeating: 0, count: 128)
        let first = impulse.map { filter.process($0) }
        _ = (0..<2_000).map { _ in filter.process(Float.random(in: -0.5...0.5)) }
        filter.reset()
        let afterReset = impulse.map { filter.process($0) }

        #expect(first == afterReset)
    }

    private func filteredRMS(amplitude: Double, sampleRate: Double) throws -> Double {
        var filter = try AWeightingFilter(sampleRate: sampleRate)
        let samples = sine(
            amplitude: amplitude,
            frequency: 1_000,
            sampleRate: sampleRate,
            count: Int(sampleRate * 2)
        )
        let output = samples.map { filter.process($0) }.dropFirst(Int(sampleRate))
        return sqrt(output.reduce(0) { $0 + ($1 * $1) } / Double(output.count))
    }

    private func sine(
        amplitude: Double,
        frequency: Double,
        sampleRate: Double,
        count: Int
    ) -> [Float] {
        (0..<count).map { frame in
            Float(amplitude * sin(2 * .pi * frequency * Double(frame) / sampleRate))
        }
    }
}
