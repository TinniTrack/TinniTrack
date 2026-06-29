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
    let studyNo1OrientationThreshold: StudyNo1OrientationThresholdResearchKitResult?
}

enum ResearchKitTaskRequest: Equatable {
    case instruction(identifier: String, title: String, text: String)
    case toneAudiometry(identifier: String, toneDuration: TimeInterval)
    case dBHLToneAudiometry(identifier: String)
    case studyNo1OrientationThreshold(identifier: String)
    case environmentSPLMeter(identifier: String, thresholdDBA: Double)
    case speechInNoise(identifier: String)
}

struct StudyNo1OrientationThresholdResearchKitResult: Equatable {
    let taskIdentifier: String
    let rightEar: StudyNo1OrientationThresholdEarResult?
    let leftEar: StudyNo1OrientationThresholdEarResult?
    let environment: StudyNo1OrientationThresholdEnvironmentResult?

    var isComplete: Bool {
        rightEar?.thresholdDBHL != nil && leftEar?.thresholdDBHL != nil
    }
}

struct StudyNo1OrientationThresholdEnvironmentResult: Equatable {
    let thresholdDBA: Double
    let requiredContiguousSamples: Int
}

struct StudyNo1OrientationThresholdEarResult: Equatable {
    let channel: CalibratedTonePlaybackChannel
    let thresholdDBHL: Double?
    let outputVolume: Double
    let headphoneType: String?
    let tonePlaybackDuration: TimeInterval
    let postStimulusDelay: TimeInterval
    let samples: [StudyNo1OrientationThresholdFrequencySample]
}

struct StudyNo1OrientationThresholdFrequencySample: Equatable {
    let frequencyHz: Double
    let calculatedThresholdDBHL: Double?
    let channel: CalibratedTonePlaybackChannel
    let units: [StudyNo1OrientationThresholdUnit]
}

struct StudyNo1OrientationThresholdUnit: Equatable {
    let levelDBHL: Double
    let startOfUnitTimeStamp: TimeInterval
    let preStimulusDelay: TimeInterval
    let userTapTimeStamp: TimeInterval?
    let timeoutTimeStamp: TimeInterval?
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
            errorDescription: error?.localizedDescription,
            studyNo1OrientationThreshold: Self.extractStudyNo1OrientationThresholdResult(
                from: taskViewController.result,
                taskIdentifier: identifier
            )
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

        case .studyNo1OrientationThreshold(let identifier):
            return makeStudyNo1OrientationThresholdTask(identifier: identifier)

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

    private func makeStudyNo1OrientationThresholdTask(identifier: String) -> ORKOrderedTask {
        let rightInstruction = ORKInstructionStep(identifier: "\(identifier).right-ear-instruction")
        rightInstruction.title = "Right ear"
        rightInstruction.text = "Tap whenever you hear the tone."

        let rightStep = makeStudyNo1ThresholdStep(
            identifier: Self.studyNo1RightEarStepIdentifier,
            title: "1 kHz threshold",
            channel: .right
        )

        let leftInstruction = ORKInstructionStep(identifier: "\(identifier).left-ear-instruction")
        leftInstruction.title = "Left ear"
        leftInstruction.text = "Tap whenever you hear the tone."

        let leftStep = makeStudyNo1ThresholdStep(
            identifier: Self.studyNo1LeftEarStepIdentifier,
            title: "1 kHz threshold",
            channel: .left
        )

        let completion = ORKCompletionStep(identifier: "\(identifier).completion")
        completion.title = "Threshold check complete"
        completion.text = "Return to TinniTrack to finish orientation."

        return ORKOrderedTask(
            identifier: identifier,
            steps: [
                rightInstruction,
                rightStep,
                leftInstruction,
                leftStep,
                completion
            ]
        )
    }

    private func makeStudyNo1ThresholdStep(
        identifier: String,
        title: String,
        channel: ORKAudioChannel
    ) -> ORKdBHLToneAudiometryStep {
        let step = ORKdBHLToneAudiometryStep(identifier: identifier)
        step.title = title
        step.frequencyList = [1_000]
        step.headphoneType = .airPodsProGen2
        step.earPreference = channel
        return step
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

private extension ResearchKitStudyTaskAdapter {
    static let studyNo1RightEarStepIdentifier = "study-no-1.orientation-threshold.right-ear"
    static let studyNo1LeftEarStepIdentifier = "study-no-1.orientation-threshold.left-ear"

    static func extractStudyNo1OrientationThresholdResult(
        from result: ORKTaskResult,
        taskIdentifier: String
    ) -> StudyNo1OrientationThresholdResearchKitResult? {
        let dBHLResults = collectResults(from: result).compactMap { $0 as? ORKdBHLToneAudiometryResult }
        guard !dBHLResults.isEmpty else {
            return nil
        }

        return StudyNo1OrientationThresholdResearchKitResult(
            taskIdentifier: taskIdentifier,
            rightEar: dBHLResults
                .first { $0.identifier == studyNo1RightEarStepIdentifier }
                .map { StudyNo1OrientationThresholdEarResult($0, fallbackChannel: .right) },
            leftEar: dBHLResults
                .first { $0.identifier == studyNo1LeftEarStepIdentifier }
                .map { StudyNo1OrientationThresholdEarResult($0, fallbackChannel: .left) },
            environment: nil
        )
    }

    static func collectResults(from result: ORKResult) -> [ORKResult] {
        var collected: [ORKResult] = [result]

        if let collection = result as? ORKCollectionResult {
            for child in collection.results ?? [] {
                collected.append(contentsOf: collectResults(from: child))
            }
        }

        return collected
    }
}

private extension StudyNo1OrientationThresholdEarResult {
    init(_ result: ORKdBHLToneAudiometryResult, fallbackChannel: CalibratedTonePlaybackChannel) {
        let mappedSamples = (result.samples ?? []).compactMap(StudyNo1OrientationThresholdFrequencySample.init)
        let resolvedChannel = mappedSamples.first?.channel ?? fallbackChannel
        let resolvedThreshold = mappedSamples
            .first { $0.frequencyHz == 1_000 && $0.channel == resolvedChannel }?
            .calculatedThresholdDBHL
        channel = resolvedChannel
        thresholdDBHL = resolvedThreshold
        outputVolume = result.outputVolume
        headphoneType = result.headphoneType?.rawValue
        tonePlaybackDuration = result.tonePlaybackDuration
        postStimulusDelay = result.postStimulusDelay
        samples = mappedSamples
    }
}

private extension StudyNo1OrientationThresholdFrequencySample {
    init?(_ sample: ORKdBHLToneAudiometryFrequencySample) {
        guard let channel = CalibratedTonePlaybackChannel(sample.channel) else {
            return nil
        }

        frequencyHz = sample.frequency
        calculatedThresholdDBHL = sample.calculatedThreshold == ORKInvalidDBHLValue
            ? nil
            : sample.calculatedThreshold
        self.channel = channel
        units = (sample.units ?? []).map(StudyNo1OrientationThresholdUnit.init)
    }
}

private extension StudyNo1OrientationThresholdUnit {
    init(_ unit: ORKdBHLToneAudiometryUnit) {
        levelDBHL = unit.dBHLValue
        startOfUnitTimeStamp = unit.startOfUnitTimeStamp
        preStimulusDelay = unit.preStimulusDelay
        userTapTimeStamp = unit.userTapTimeStamp > 0 ? unit.userTapTimeStamp : nil
        timeoutTimeStamp = unit.timeoutTimeStamp > 0 ? unit.timeoutTimeStamp : nil
    }
}

private extension CalibratedTonePlaybackChannel {
    init?(_ channel: ORKAudioChannel) {
        switch channel {
        case .left:
            self = .left
        case .right:
            self = .right
        @unknown default:
            return nil
        }
    }
}
