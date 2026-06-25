import Foundation
import Testing
@testable import TinniTrack

struct AudiogramThresholdResolverTests {
    private let resolver = AudiogramThresholdResolver()
    private let now = Date(timeIntervalSince1970: 1_800_050_000)

    @Test
    func resolvesLeftAndRightOneKilohertzThresholds() throws {
        let audiogram = sampleAudiogram(left: 12, right: 18)

        #expect(try resolver.resolveThresholdDBHL(for: .left, in: audiogram) == 12)
        #expect(try resolver.resolveThresholdDBHL(for: .right, in: audiogram) == 18)
    }

    @Test
    func refusesMissingAudiogramFrequencyAndEarThresholds() {
        #expect(throws: AudiogramThresholdResolutionError.missingAudiogram) {
            _ = try resolver.resolveThresholdDBHL(for: .left, in: nil)
        }

        #expect(throws: AudiogramThresholdResolutionError.missingFrequency(1_000)) {
            _ = try resolver.resolveThresholdDBHL(for: .left, in: sampleAudiogram(frequencyHz: 2_000, left: 12, right: 18))
        }

        #expect(throws: AudiogramThresholdResolutionError.missingEarThreshold(.right, frequencyHz: 1_000)) {
            _ = try resolver.resolveThresholdDBHL(for: .right, in: sampleAudiogram(left: 12, right: nil))
        }
    }

    private func sampleAudiogram(
        frequencyHz: Double = 1_000,
        left: Double?,
        right: Double?
    ) -> AudiogramRecord {
        AudiogramRecord(
            id: UUID(),
            measuredAt: now,
            source: "healthkit",
            headphoneName: "AirPods Pro 2",
            healthKitSampleUUID: UUID(),
            points: [
                AudiogramPoint(
                    frequencyHz: frequencyHz,
                    leftEarDBHL: left,
                    rightEarDBHL: right,
                    tests: []
                )
            ]
        )
    }
}
