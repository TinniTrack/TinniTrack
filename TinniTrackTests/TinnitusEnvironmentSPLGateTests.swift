import Foundation
import Testing
@testable import TinniTrack

struct TinnitusEnvironmentSPLGateTests {
    @Test
    func gatePassesAfterRequiredContiguousQuietSamples() {
        let result = TinnitusEnvironmentSPLGateEvaluator().evaluate(
            samplesDBA: [50, 44, 43, 42, 41, 40],
            configuration: .studyA
        )

        #expect(result.gateResult == .passed)
        #expect(result.phase6Context.gateResult == .passed)
        #expect(result.phase6Context.samplesDBA == [50, 44, 43, 42, 41, 40])
    }

    @Test
    func gateFailsWithoutContiguousQuietSamples() {
        let result = TinnitusEnvironmentSPLGateEvaluator().evaluate(
            samplesDBA: [44, 43, 46, 42, 41, 47, 40],
            configuration: .studyA
        )

        #expect(result.gateResult == .failed)
        #expect(result.passed == false)
    }

    @Test
    func gateDropsNonFiniteSamples() {
        let result = TinnitusEnvironmentSPLGateEvaluator().evaluate(
            samplesDBA: [Double.nan, 41, 42, 43, 44, 40],
            configuration: .studyA
        )

        #expect(result.gateResult == .passed)
        #expect(result.samplesDBA == [41, 42, 43, 44, 40])
    }
}
