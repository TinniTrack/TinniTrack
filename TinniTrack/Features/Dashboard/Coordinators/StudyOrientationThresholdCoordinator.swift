import Combine
import Foundation

@MainActor
protocol StudyOrientationThresholdSubmissionBuilding: AnyObject {
    func makeOrientationThresholdSubmission(
        result: StudyNo1OrientationThresholdResearchKitResult,
        scheduledTask: ScheduledTask,
        enrollment: StudyEnrollment
    ) throws -> StudyNo1OrientationThresholdSubmission
}

@MainActor
final class StudyOrientationThresholdCoordinator: ObservableObject {
    struct Presentation: Identifiable, Equatable {
        let id: UUID
        let scheduledTask: ScheduledTask
        let request: ResearchKitTaskRequest

        init(
            id: UUID = UUID(),
            scheduledTask: ScheduledTask,
            request: ResearchKitTaskRequest = .studyNo1OrientationThreshold(
                identifier: "study-no-1-orientation-threshold"
            )
        ) {
            self.id = id
            self.scheduledTask = scheduledTask
            self.request = request
        }
    }

    enum RetryableFailure: Equatable {
        case preparation(message: String)
        case researchKitCancelled
        case researchKitIncomplete(message: String)
        case researchKitFailed(message: String)
        case submission(message: String)

        var message: String {
            switch self {
            case .preparation(let message),
                 .researchKitIncomplete(let message),
                 .researchKitFailed(let message),
                 .submission(let message):
                return message
            case .researchKitCancelled:
                return "The hearing threshold check was canceled. Review the setup and try again."
            }
        }
    }

    enum State: Equatable {
        case idle
        case preparing
        case presentingResearchKit
        case submitting
        case finalizing
        case preflightFailure(RetryableFailure)
        case finalizationFailure(message: String)
        case completed
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var presentation: Presentation?

    private let enrollment: StudyEnrollment
    private let studyService: StudyServiceProtocol
    private let submissionBuilder: StudyOrientationThresholdSubmissionBuilding
    private let completeOnboarding: @MainActor () async -> StudyOnboardingCompletionOutcome

    private var operation: Task<Void, Never>?
    private var operationGeneration: UInt64 = 0
    private var preparedTask: ScheduledTask?
    private var submittedTaskID: UUID?

    init(
        enrollment: StudyEnrollment,
        studyService: StudyServiceProtocol,
        submissionBuilder: StudyOrientationThresholdSubmissionBuilding,
        completeOnboarding: @escaping @MainActor () async -> StudyOnboardingCompletionOutcome
    ) {
        self.enrollment = enrollment
        self.studyService = studyService
        self.submissionBuilder = submissionBuilder
        self.completeOnboarding = completeOnboarding
    }

    var isPreparing: Bool {
        state == .preparing
    }

    var isFinishing: Bool {
        state == .submitting || state == .finalizing
    }

    func begin() {
        guard canBegin,
              operation == nil,
              presentation == nil
        else {
            return
        }

        let generation = beginOperation(in: .preparing)
        operation = Task { @MainActor [weak self] in
            await self?.prepareThresholdTask(generation: generation)
        }
    }

    func accept(
        _ summary: ResearchKitTaskResultSummary,
        for presentedTask: Presentation
    ) {
        guard presentation?.id == presentedTask.id,
              operation == nil
        else {
            return
        }

        presentation = nil

        guard summary.finishState == .completed else {
            state = .preflightFailure(Self.failure(for: summary))
            return
        }

        guard let result = summary.studyNo1OrientationThreshold,
              result.isComplete
        else {
            state = .preflightFailure(
                .researchKitIncomplete(
                    message: "The hearing threshold check did not return both 1 kHz ear thresholds. Review the setup and try again."
                )
            )
            return
        }

        let generation = beginOperation(in: .submitting)
        operation = Task { @MainActor [weak self] in
            await self?.submitThresholdAndFinalize(
                result: result,
                scheduledTask: presentedTask.scheduledTask,
                generation: generation
            )
        }
    }

    func presentationDismissed(_ presentedTask: Presentation) {
        guard presentation?.id == presentedTask.id,
              operation == nil
        else {
            return
        }

        presentation = nil
        state = .preflightFailure(.researchKitCancelled)
    }

    func retryFinalization() {
        guard case .finalizationFailure = state,
              submittedTaskID != nil,
              operation == nil,
              presentation == nil
        else {
            return
        }

        let generation = beginOperation(in: .finalizing)
        operation = Task { @MainActor [weak self] in
            await self?.finalizeOnboarding(generation: generation)
        }
    }

    func stop() {
        guard operation != nil
                || presentation != nil
                || state != .idle
                || preparedTask != nil
                || submittedTaskID != nil
        else {
            return
        }

        operationGeneration &+= 1
        operation?.cancel()
        operation = nil
        presentation = nil
        preparedTask = nil
        submittedTaskID = nil
        state = .idle
    }

    private func prepareThresholdTask(generation: UInt64) async {
        defer { finishOperation(generation: generation) }

        guard canContinue(generation: generation) else {
            return
        }

        do {
            let task: ScheduledTask
            if let preparedTask {
                task = preparedTask
            } else {
                task = try await studyService.beginStudyNo1OrientationThresholdTask(
                    enrollmentID: enrollment.id
                )
            }

            guard canContinue(generation: generation) else {
                return
            }

            preparedTask = task

            switch task.status {
            case .scheduled:
                let nextPresentation = Presentation(scheduledTask: task)
                guard canContinue(generation: generation) else {
                    return
                }
                presentation = nextPresentation
                state = .presentingResearchKit

            case .completed:
                submittedTaskID = task.id
                await finalizeOnboarding(generation: generation)

            case .missed, .skipped, .cancelled, .unknown:
                state = .preflightFailure(
                    .preparation(
                        message: "The hearing threshold check is not available right now. Please try again."
                    )
                )
            }
        } catch is CancellationError {
            return
        } catch {
            guard canContinue(generation: generation) else {
                return
            }
            state = .preflightFailure(.preparation(message: error.localizedDescription))
        }
    }

    private func submitThresholdAndFinalize(
        result: StudyNo1OrientationThresholdResearchKitResult,
        scheduledTask: ScheduledTask,
        generation: UInt64
    ) async {
        defer { finishOperation(generation: generation) }

        guard canContinue(generation: generation) else {
            return
        }

        do {
            if submittedTaskID != scheduledTask.id {
                let submission = try submissionBuilder.makeOrientationThresholdSubmission(
                    result: result,
                    scheduledTask: scheduledTask,
                    enrollment: enrollment
                )

                guard canContinue(generation: generation) else {
                    return
                }

                try await studyService.submitStudyNo1OrientationThreshold(
                    scheduledTaskID: scheduledTask.id,
                    enrollmentID: enrollment.id,
                    submission: submission
                )

                guard canContinue(generation: generation) else {
                    return
                }

                submittedTaskID = scheduledTask.id
            }

            await finalizeOnboarding(generation: generation)
        } catch is CancellationError {
            return
        } catch {
            guard canContinue(generation: generation) else {
                return
            }
            state = .preflightFailure(.submission(message: error.localizedDescription))
        }
    }

    private func finalizeOnboarding(generation: UInt64) async {
        guard canContinue(generation: generation) else {
            return
        }

        state = .finalizing
        let outcome = await completeOnboarding()

        guard canContinue(generation: generation) else {
            return
        }

        switch outcome {
        case .completed, .notRequired:
            state = .completed
        case .cancelled:
            break
        case .failed(let message):
            state = .finalizationFailure(message: message)
        }
    }

    private func beginOperation(in nextState: State) -> UInt64 {
        operationGeneration &+= 1
        state = nextState
        return operationGeneration
    }

    private func finishOperation(generation: UInt64) {
        guard generation == operationGeneration else {
            return
        }
        operation = nil
    }

    private func canContinue(generation: UInt64) -> Bool {
        generation == operationGeneration && !Task.isCancelled
    }

    private var canBegin: Bool {
        switch state {
        case .idle, .preflightFailure:
            return true
        case .preparing,
             .presentingResearchKit,
             .submitting,
             .finalizing,
             .finalizationFailure,
             .completed:
            return false
        }
    }

    private static func failure(
        for summary: ResearchKitTaskResultSummary
    ) -> RetryableFailure {
        switch summary.finishState {
        case .discarded:
            return .researchKitCancelled
        case .saved, .earlyTermination:
            return .researchKitIncomplete(
                message: "The hearing threshold check was not completed. Review the setup and try again."
            )
        case .failed:
            return .researchKitFailed(
                message: summary.errorDescription
                    ?? "The hearing threshold check could not be completed. Please try again."
            )
        case .unknown:
            return .researchKitFailed(
                message: "The hearing threshold check ended unexpectedly. Please try again."
            )
        case .completed:
            return .researchKitIncomplete(
                message: "The hearing threshold check did not return a complete result. Please try again."
            )
        }
    }
}
