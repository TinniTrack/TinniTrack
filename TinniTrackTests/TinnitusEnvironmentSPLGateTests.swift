import Foundation
import Testing
@testable import TinniTrack

struct TinnitusEnvironmentSPLGateTests {
    @Test
    func gatePassesAfterRequiredContiguousQuietSamples() {
        let result = TinnitusEnvironmentSPLGateEvaluator().evaluate(
            samplesDBA: [50, 44, 43, 42, 41, 40],
            configuration: .studyNo1
        )

        #expect(result.gateResult == .passed)
        #expect(result.studyNo1Context.gateResult == .passed)
        #expect(result.studyNo1Context.samplesDBA == [50, 44, 43, 42, 41, 40])
    }

    @Test
    func gateFailsWithoutContiguousQuietSamples() {
        let result = TinnitusEnvironmentSPLGateEvaluator().evaluate(
            samplesDBA: [44, 43, 46, 42, 41, 47, 40],
            configuration: .studyNo1
        )

        #expect(result.gateResult == .failed)
        #expect(result.passed == false)
    }

    @Test
    func gateDropsNonFiniteSamples() {
        let result = TinnitusEnvironmentSPLGateEvaluator().evaluate(
            samplesDBA: [Double.nan, 41, 42, 43, 44, 40],
            configuration: .studyNo1
        )

        #expect(result.gateResult == .passed)
        #expect(result.samplesDBA == [41, 42, 43, 44, 40])
    }

    @Test
    func streamingUpdateTracksContiguousQuietSamples() {
        let update = TinnitusEnvironmentSPLGateEvaluator().update(
            samplesDBA: [50, 44, 43],
            configuration: .studyNo1
        )

        #expect(update.status == .measuring)
        #expect(update.contiguousPassingSamples == 2)
        #expect(update.latestSampleDBA == 43)
        #expect(update.result == nil)
    }

    @Test
    func streamingUpdateResetsCounterAtThreshold() {
        let update = TinnitusEnvironmentSPLGateEvaluator().update(
            samplesDBA: [44, 43, 45, 42],
            configuration: .studyNo1
        )

        #expect(update.status == .measuring)
        #expect(update.contiguousPassingSamples == 1)
        #expect(update.result == nil)
    }

    @Test
    func streamingUpdateReportsTooLoudWithoutFailing() {
        let update = TinnitusEnvironmentSPLGateEvaluator().update(
            samplesDBA: [44, 43, 46],
            configuration: .studyNo1
        )

        #expect(update.status == .tooLoud)
        #expect(update.contiguousPassingSamples == 0)
        #expect(update.result == nil)
    }

    @Test
    func streamingUpdatePassPreservesFiniteSamples() {
        let update = TinnitusEnvironmentSPLGateEvaluator().update(
            samplesDBA: [Double.nan, 44, 43, 42, 41, 40],
            configuration: .studyNo1
        )

        #expect(update.status == .passed)
        #expect(update.result?.gateResult == .passed)
        #expect(update.result?.samplesDBA == [44, 43, 42, 41, 40])
    }
}
