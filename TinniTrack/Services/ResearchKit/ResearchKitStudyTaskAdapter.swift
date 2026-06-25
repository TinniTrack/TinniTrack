import Foundation
import CryptoKit
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
    let studyConsent: StudyConsentResultSummary?
}

enum ResearchKitTaskRequest: Equatable {
    case instruction(identifier: String, title: String, text: String)
    case toneAudiometry(identifier: String, toneDuration: TimeInterval)
    case dBHLToneAudiometry(identifier: String)
    case studyNo1OrientationThreshold(identifier: String)
    case studyConsent(StudyConsentDefinition)
    case environmentSPLMeter(identifier: String, thresholdDBA: Double)
    case speechInNoise(identifier: String)
}

struct StudyConsentResultSummary: Equatable {
    let taskIdentifier: String
    let studySlug: String
    let consentVersion: String
    let consented: Bool
    let givenName: String?
    let familyName: String?
    let signedAt: Date?
    let pdfData: Data?
    let pdfSHA256Hex: String?
    let finishState: ResearchTaskFinishState

    func completion(storageBucket: String = StudyConsentCatalog.consentStorageBucket, storagePath: String = "") -> StudyConsentCompletion {
        StudyConsentCompletion(
            taskIdentifier: taskIdentifier,
            studySlug: studySlug,
            consentVersion: consentVersion,
            consented: consented,
            signerGivenName: givenName,
            signerFamilyName: familyName,
            signedAt: signedAt,
            artifact: pdfData.map {
                StudyConsentArtifact(
                    pdfData: $0,
                    pdfSHA256Hex: pdfSHA256Hex ?? "",
                    storageBucket: storageBucket,
                    storagePath: storagePath
                )
            },
            researchKitFinishState: finishState.rawValue
        )
    }
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
    private var consentDefinitions: [ObjectIdentifier: StudyConsentDefinition] = [:]

    func makeTaskViewController(
        for request: ResearchKitTaskRequest,
        completion: @escaping (ResearchKitTaskResultSummary) -> Void
    ) -> UIViewController {
        let task = makeTask(for: request)
        let viewController = ORKTaskViewController(task: task, taskRun: nil)
        viewController.delegate = self
        let key = ObjectIdentifier(viewController)
        completions[key] = completion
        if case .studyConsent(let definition) = request {
            consentDefinitions[key] = definition
        }
        return viewController
    }

    func supportedFutureModules() -> [ResearchKitModule] {
        [
            .instructionStep,
            .formStep,
            .toneAudiometry,
            .dBHLToneAudiometry,
            .environmentSPLMeter,
            .speechInNoise,
            .consentReviewStep
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

        if let definition = consentDefinitions.removeValue(forKey: key) {
            Task { @MainActor in
                let consentExtraction = await Self.extractStudyConsentResult(
                    from: taskViewController.result,
                    taskIdentifier: identifier,
                    finishState: finishState,
                    definition: definition
                )
                let summary = ResearchKitTaskResultSummary(
                    taskIdentifier: identifier,
                    finishState: finishState,
                    errorDescription: error?.localizedDescription ?? consentExtraction.errorDescription,
                    studyNo1OrientationThreshold: nil,
                    studyConsent: consentExtraction.summary
                )

                completions.removeValue(forKey: key)?(summary)
            }
            return
        }

        let summary = ResearchKitTaskResultSummary(
            taskIdentifier: identifier,
            finishState: finishState,
            errorDescription: error?.localizedDescription,
            studyNo1OrientationThreshold: Self.extractStudyNo1OrientationThresholdResult(
                from: taskViewController.result,
                taskIdentifier: identifier
            ),
            studyConsent: nil
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

        case .studyConsent(let definition):
            return makeStudyConsentTask(definition: definition)

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

    private func makeStudyConsentTask(definition: StudyConsentDefinition) -> ORKOrderedTask {
        let document = Self.makeConsentDocument(definition: definition)
        let signature = Self.makeConsentSignature(definition: definition)
        document.signatures = [signature]

        let instructionSteps = definition.sections.map { section in
            let step = ORKInstructionStep(identifier: "\(definition.consentVersion).section.\(section.id)")
            step.title = section.title
            step.text = section.content
            return step
        }

        let reviewStep = ORKConsentReviewStep(
            identifier: Self.studyConsentReviewStepIdentifier(definition: definition),
            signature: signature,
            in: document
        )
        reviewStep.title = "Review Consent"
        reviewStep.text = "Review the full consent document before deciding whether to participate."
        reviewStep.reasonForConsent = definition.reviewReasonForConsent
        reviewStep.requiresScrollToBottom = definition.requiresScrollToBottom

        let completion = ORKCompletionStep(identifier: "\(definition.consentVersion).completion")
        completion.title = "Consent Complete"
        completion.text = "Return to TinniTrack to finish enrollment."

        return ORKOrderedTask(
            identifier: definition.consentVersion,
            steps: instructionSteps + [reviewStep, completion]
        )
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

    static func studyConsentReviewStepIdentifier(definition: StudyConsentDefinition) -> String {
        "\(definition.consentVersion).review"
    }

    static func studyConsentSignatureIdentifier(definition: StudyConsentDefinition) -> String {
        "\(definition.consentVersion).participant-signature"
    }

    static func makeConsentDocument(definition: StudyConsentDefinition) -> ORKConsentDocument {
        let document = ORKConsentDocument()
        document.title = definition.documentTitle
        document.signaturePageTitle = definition.signaturePageTitle
        document.signaturePageContent = definition.signaturePageContent
        document.sections = definition.sections.map { section in
            let consentSection = ORKConsentSection(type: .custom)
            consentSection.title = section.title
            consentSection.formalTitle = section.title
            consentSection.summary = section.content
            consentSection.content = section.content
            return consentSection
        }
        return document
    }

    static func makeConsentSignature(definition: StudyConsentDefinition) -> ORKConsentSignature {
        let signature = ORKConsentSignature(
            forPersonWithTitle: "Participant",
            dateFormatString: nil,
            identifier: studyConsentSignatureIdentifier(definition: definition)
        )
        signature.requiresName = definition.requiresName
        signature.requiresSignatureImage = definition.requiresSignatureImage
        return signature
    }

    static func extractStudyConsentResult(
        from result: ORKTaskResult,
        taskIdentifier: String,
        finishState: ResearchTaskFinishState,
        definition: StudyConsentDefinition
    ) async -> (summary: StudyConsentResultSummary?, errorDescription: String?) {
        let signatureResult = collectResults(from: result)
            .compactMap { $0 as? ORKConsentSignatureResult }
            .first { $0.identifier == studyConsentReviewStepIdentifier(definition: definition) }

        guard let signatureResult else {
            return (
                StudyConsentResultSummary(
                    taskIdentifier: taskIdentifier,
                    studySlug: definition.studySlug,
                    consentVersion: definition.consentVersion,
                    consented: false,
                    givenName: nil,
                    familyName: nil,
                    signedAt: nil,
                    pdfData: nil,
                    pdfSHA256Hex: nil,
                    finishState: finishState
                ),
                nil
            )
        }

        let signature = signatureResult.signature
        let signedAt = signatureResult.endDate

        guard finishState == .completed, signatureResult.consented else {
            return (
                StudyConsentResultSummary(
                    taskIdentifier: taskIdentifier,
                    studySlug: definition.studySlug,
                    consentVersion: definition.consentVersion,
                    consented: signatureResult.consented,
                    givenName: signature?.givenName,
                    familyName: signature?.familyName,
                    signedAt: signedAt,
                    pdfData: nil,
                    pdfSHA256Hex: nil,
                    finishState: finishState
                ),
                nil
            )
        }

        do {
            let signedDocument = makeConsentDocument(definition: definition)
            signedDocument.signatures = [makeConsentSignature(definition: definition)]
            signatureResult.apply(to: signedDocument)
            let pdfData = try await makePDF(document: signedDocument)
            return (
                StudyConsentResultSummary(
                    taskIdentifier: taskIdentifier,
                    studySlug: definition.studySlug,
                    consentVersion: definition.consentVersion,
                    consented: signatureResult.consented,
                    givenName: signature?.givenName,
                    familyName: signature?.familyName,
                    signedAt: signedAt,
                    pdfData: pdfData,
                    pdfSHA256Hex: sha256Hex(for: pdfData),
                    finishState: finishState
                ),
                nil
            )
        } catch {
            return (
                StudyConsentResultSummary(
                    taskIdentifier: taskIdentifier,
                    studySlug: definition.studySlug,
                    consentVersion: definition.consentVersion,
                    consented: signatureResult.consented,
                    givenName: signature?.givenName,
                    familyName: signature?.familyName,
                    signedAt: signedAt,
                    pdfData: nil,
                    pdfSHA256Hex: nil,
                    finishState: finishState
                ),
                error.localizedDescription
            )
        }
    }

    static func makePDF(document: ORKConsentDocument) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            document.makePDF { data, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "ResearchKitStudyTaskAdapter",
                        code: 500,
                        userInfo: [NSLocalizedDescriptionKey: "ResearchKit did not return a signed consent PDF."]
                    ))
                }
            }
        }
    }

    static func sha256Hex(for data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

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
