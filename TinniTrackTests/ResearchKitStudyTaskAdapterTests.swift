import ResearchKit
import ResearchKitActiveTask
import ResearchKitUI
import Testing
@testable import TinniTrack

@MainActor
struct ResearchKitStudyTaskAdapterTests {
    @Test
    func environmentSPLTaskUsesValidStudyNo1SamplingPolicy() throws {
        let adapter = ResearchKitStudyTaskAdapter()
        let taskIdentifier = "quiet-environment"
        let thresholdDBA = 45.0

        let viewController = try #require(
            adapter.makeTaskViewController(
                for: .environmentSPLMeter(
                    identifier: taskIdentifier,
                    thresholdDBA: thresholdDBA
                ),
                completion: { _ in }
            ) as? ORKTaskViewController
        )
        let task = try #require(viewController.task as? ORKOrderedTask)
        let step = try #require(
            task.steps.first as? ORKEnvironmentSPLMeterStep
        )

        #expect(task.identifier == taskIdentifier)
        #expect(task.steps.count == 1)
        #expect(step.identifier == "\(taskIdentifier).environment-spl")
        #expect(step.thresholdValue == thresholdDBA)
        #expect(step.samplingInterval == 1.0)
        #expect(step.requiredContiguousSamples == 5)
    }
}
