import Foundation
import ResearchKit
import ResearchKitActiveTask
import ResearchKitUI
import UIKit

enum ResearchTaskFinishState: String, Equatable {
    case completed
    case discarded
    case failed
    case saved
    case earlyTermination
    case unknown
}

struct ResearchKitTaskResultSummary: Equatable {
    let taskIdentifier: String
    let finishState: ResearchTaskFinishState
    let errorDescription: String?
}

enum ResearchKitTaskRequest: Equatable {
    case instruction(identifier: String, title: String, text: String)
    case toneAudiometry(identifier: String, toneDuration: TimeInterval)
    case dBHLToneAudiometry(identifier: String)
    case environmentSPLMeter(identifier: String, thresholdDBA: Double)
    case speechInNoise(identifier: String)
}

@MainActor
protocol ResearchStudyTaskAdapting {
    func makeTaskViewController(
        for request: ResearchKitTaskRequest,
        completion: @escaping (ResearchKitTaskResultSummary) -> Void
    ) -> UIViewController

    func supportedFutureModules() -> [ResearchKitModule]
}

@MainActor
final class ResearchKitStudyTaskAdapter: NSObject, ResearchStudyTaskAdapting, ORKTaskViewControllerDelegate {
    private var completions: [ObjectIdentifier: (ResearchKitTaskResultSummary) -> Void] = [:]

    func makeTaskViewController(
        for request: ResearchKitTaskRequest,
        completion: @escaping (ResearchKitTaskResultSummary) -> Void
    ) -> UIViewController {
        let task = makeTask(for: request)
        let viewController = ORKTaskViewController(task: task, taskRun: nil)
        viewController.delegate = self
        let key = ObjectIdentifier(viewController)
        completions[key] = completion
        return viewController
    }

    func supportedFutureModules() -> [ResearchKitModule] {
        [
            .instructionStep,
            .formStep,
            .toneAudiometry,
            .dBHLToneAudiometry,
            .environmentSPLMeter,
            .speechInNoise
        ]
    }

    func taskViewController(
        _ taskViewController: ORKTaskViewController,
        didFinishWith reason: ORKTaskFinishReason,
        error: Error?
    ) {
        let identifier = taskViewController.task?.identifier ?? ""
        let finishState = ResearchTaskFinishState(reason)
        let key = ObjectIdentifier(taskViewController)

        let summary = ResearchKitTaskResultSummary(
            taskIdentifier: identifier,
            finishState: finishState,
            errorDescription: error?.localizedDescription
        )

        completions.removeValue(forKey: key)?(summary)
    }

    private func makeTask(for request: ResearchKitTaskRequest) -> ORKOrderedTask {
        switch request {
        case .instruction(let identifier, let title, let text):
            let step = ORKInstructionStep(identifier: "\(identifier).instruction")
            step.title = title
            step.text = text
            return ORKOrderedTask(identifier: identifier, steps: [step])

        case .toneAudiometry(let identifier, let toneDuration):
            return ORKOrderedTask.toneAudiometryTask(
                withIdentifier: identifier,
                intendedUseDescription: nil,
                speechInstruction: nil,
                shortSpeechInstruction: nil,
                toneDuration: toneDuration,
                options: []
            )

        case .dBHLToneAudiometry(let identifier):
            return ORKOrderedTask.dBHLToneAudiometryTask(
                withIdentifier: identifier,
                intendedUseDescription: nil,
                options: []
            )

        case .environmentSPLMeter(let identifier, let thresholdDBA):
            let step = ORKEnvironmentSPLMeterStep(identifier: "\(identifier).environment-spl")
            step.thresholdValue = thresholdDBA
            step.samplingInterval = 0.2
            step.requiredContiguousSamples = 3
            return ORKOrderedTask(identifier: identifier, steps: [step])

        case .speechInNoise(let identifier):
            return ORKOrderedTask.speechInNoiseTask(
                withIdentifier: identifier,
                intendedUseDescription: nil,
                options: []
            )
        }
    }

}

private extension ResearchTaskFinishState {
    init(_ reason: ORKTaskFinishReason) {
        switch reason {
        case .completed:
            self = .completed
        case .discarded:
            self = .discarded
        case .failed:
            self = .failed
        case .saved:
            self = .saved
        case .earlyTermination:
            self = .earlyTermination
        @unknown default:
            self = .unknown
        }
    }
}
