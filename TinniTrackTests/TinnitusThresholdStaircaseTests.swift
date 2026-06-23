import Foundation
import Testing
@testable import TinniTrack

struct TinnitusThresholdStaircaseTests {
    @Test
    func staircaseMeasuresThresholdFromDescendingAndAscendingResponses() {
        var staircase = TinnitusThresholdStaircase()

        for response in [
            TinnitusThresholdResponse.heard,
            .heard,
            .heard,
            .notHeard,
            .notHeard,
            .heard,
            .notHeard,
            .notHeard,
            .heard
        ] {
            staircase.recordResponse(response)
        }

        #expect(staircase.measuredThresholdDBHL == 10)
        #expect(staircase.isComplete)
        #expect(staircase.presentations.map(\.levelDBHL) == [30, 20, 10, 0, 5, 10, 0, 5, 10])
    }

    @Test
    func completeStaircaseIgnoresAdditionalResponses() {
        var staircase = TinnitusThresholdStaircase()

        for response in [
            TinnitusThresholdResponse.heard,
            .heard,
            .heard,
            .notHeard,
            .notHeard,
            .heard,
            .notHeard,
            .notHeard,
            .heard,
            .notHeard
        ] {
            staircase.recordResponse(response)
        }

        #expect(staircase.measuredThresholdDBHL == 10)
        #expect(staircase.presentations.count == 9)
    }
}
