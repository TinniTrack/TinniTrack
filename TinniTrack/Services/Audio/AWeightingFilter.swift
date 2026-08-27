import Foundation

/// Streaming IEC-style A-weighting implemented as a digital pole/zero cascade.
/// The standard analog pole frequencies are mapped with a bilinear transform,
/// then the digital response is normalized to 0 dB at 1 kHz.
nonisolated struct AWeightingFilter: Sendable {
    static let algorithmVersion = "iec-a-weighting-bilinear-sos-v1"

    private var sections: [Biquad]
    let sampleRate: Double

    init(sampleRate: Double) throws {
        guard sampleRate.isFinite, sampleRate >= 40_000 else {
            throw AWeightingFilterError.unsupportedSampleRate
        }
        self.sampleRate = sampleRate
        sections = Self.makeSections(sampleRate: sampleRate)
    }

    mutating func process(_ sample: Float) -> Double {
        var value = Double(sample)
        for index in sections.indices {
            value = sections[index].process(value)
        }
        return value
    }

    mutating func reset() {
        for index in sections.indices {
            sections[index].reset()
        }
    }

    static func responseDB(frequencyHz: Double, sampleRate: Double) throws -> Double {
        guard frequencyHz.isFinite,
              frequencyHz > 0,
              frequencyHz < sampleRate / 2
        else {
            throw AWeightingFilterError.invalidFrequency
        }
        let sections = makeSections(sampleRate: sampleRate)
        let magnitude = sections.reduce(1.0) { partial, section in
            partial * section.magnitude(frequencyHz: frequencyHz, sampleRate: sampleRate)
        }
        return 20 * log10(max(magnitude, .leastNonzeroMagnitude))
    }

    private static func makeSections(sampleRate: Double) -> [Biquad] {
        let poleFrequencies = [20.598_997, 20.598_997, 107.652_65, 737.862_23, 12_194.217, 12_194.217]
        let mappedPoles = poleFrequencies.map { frequency -> Double in
            let analogPole = -2 * Double.pi * frequency
            let twoSampleRate = 2 * sampleRate
            return (twoSampleRate + analogPole) / (twoSampleRate - analogPole)
        }

        var result = [
            Biquad(zeros: (1, 1), poles: (mappedPoles[0], mappedPoles[1])),
            Biquad(zeros: (1, 1), poles: (mappedPoles[2], mappedPoles[3])),
            Biquad(zeros: (-1, -1), poles: (mappedPoles[4], mappedPoles[5]))
        ]

        let magnitudeAtOneKilohertz = result.reduce(1.0) { partial, section in
            partial * section.magnitude(frequencyHz: 1_000, sampleRate: sampleRate)
        }
        let normalization = 1 / max(magnitudeAtOneKilohertz, .leastNonzeroMagnitude)
        result[0].applyNumeratorGain(normalization)
        return result
    }
}

nonisolated enum AWeightingFilterError: Error, Equatable {
    case unsupportedSampleRate
    case invalidFrequency
}

private nonisolated struct Biquad: Sendable {
    private var b0: Double
    private var b1: Double
    private var b2: Double
    private let a1: Double
    private let a2: Double
    private var state1 = 0.0
    private var state2 = 0.0

    init(zeros: (Double, Double), poles: (Double, Double)) {
        b0 = 1
        b1 = -(zeros.0 + zeros.1)
        b2 = zeros.0 * zeros.1
        a1 = -(poles.0 + poles.1)
        a2 = poles.0 * poles.1
    }

    mutating func process(_ input: Double) -> Double {
        let output = (b0 * input) + state1
        state1 = (b1 * input) - (a1 * output) + state2
        state2 = (b2 * input) - (a2 * output)
        return output
    }

    mutating func reset() {
        state1 = 0
        state2 = 0
    }

    mutating func applyNumeratorGain(_ gain: Double) {
        b0 *= gain
        b1 *= gain
        b2 *= gain
    }

    func magnitude(frequencyHz: Double, sampleRate: Double) -> Double {
        let angle = -2 * Double.pi * frequencyHz / sampleRate
        let z1Real = cos(angle)
        let z1Imaginary = sin(angle)
        let z2Real = cos(2 * angle)
        let z2Imaginary = sin(2 * angle)

        let numeratorReal = b0 + (b1 * z1Real) + (b2 * z2Real)
        let numeratorImaginary = (b1 * z1Imaginary) + (b2 * z2Imaginary)
        let denominatorReal = 1 + (a1 * z1Real) + (a2 * z2Real)
        let denominatorImaginary = (a1 * z1Imaginary) + (a2 * z2Imaginary)
        let numeratorMagnitude = hypot(numeratorReal, numeratorImaginary)
        let denominatorMagnitude = hypot(denominatorReal, denominatorImaginary)
        return numeratorMagnitude / max(denominatorMagnitude, .leastNonzeroMagnitude)
    }
}
