import Combine
import Foundation

@MainActor
protocol StudyOrientationThresholdSubmissionBuilding: AnyObject {
    func makeOrientationThresholdSubmission(
        result: StudyNo1OrientationThresholdResult,
        scheduledTask: ScheduledTask,
        enrollment: StudyEnrollment
    ) throws -> StudyNo1OrientationThresholdSubmission
}

@MainActor
final class StudyOrientationThresholdCoordinator: ObservableObject {
    enum RetryableFailure: Equatable {
        case preparation(message: String)
        case incompleteResult(message: String)

        var message: String {
            switch self {
            case .preparation(let message), .incompleteResult(let message):
                return message
            }
        }
    }

    enum State: Equatable {
        case idle
        case preparing
        case readyForTest
        case submitting
        case submissionFailure(message: String)
        case finalizing
        case preflightFailure(RetryableFailure)
        case finalizationFailure(message: String)
        case completed
    }

    @Published private(set) var state: State = .idle

    private let enrollment: StudyEnrollment
    private let studyService: StudyServiceProtocol
    private let submissionBuilder: StudyOrientationThresholdSubmissionBuilding
    private let completeOnboarding: @MainActor () async -> StudyOnboardingCompletionOutcome

    private var operation: Task<Void, Never>?
    private var operationGeneration: UInt64 = 0
    private var preparedTask: ScheduledTask?
    private var pendingResult: StudyNo1OrientationThresholdResult?
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

    func begin() {
        guard canBegin, operation == nil else {
            return
        }

        let generation = beginOperation(in: .preparing)
        operation = Task { @MainActor [weak self] in
            await self?.prepareThresholdTask(generation: generation)
        }
    }

    func submit(_ result: StudyNo1OrientationThresholdResult) {
        guard state == .readyForTest,
              operation == nil,
              let scheduledTask = preparedTask
        else {
            return
        }

        guard result.isComplete else {
            state = .preflightFailure(
                .incompleteResult(
                    message: "The hearing check did not return both 1 kHz ear thresholds. Review the setup and try again."
                )
            )
            return
        }

        pendingResult = result
        submitPendingResult(result, scheduledTask: scheduledTask)
    }

    func retrySubmission() {
        guard case .submissionFailure = state,
              operation == nil,
              let pendingResult,
              let preparedTask
        else {
            return
        }

        submitPendingResult(pendingResult, scheduledTask: preparedTask)
    }

    func retryFinalization() {
        guard case .finalizationFailure = state,
              submittedTaskID != nil,
              operation == nil
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
                || state != .idle
                || preparedTask != nil
                || pendingResult != nil
                || submittedTaskID != nil
        else {
            return
        }

        operationGeneration &+= 1
        operation?.cancel()
        operation = nil
        preparedTask = nil
        pendingResult = nil
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
                state = .readyForTest

            case .completed:
                submittedTaskID = task.id
                await finalizeOnboarding(generation: generation)

            case .missed, .skipped, .cancelled, .unknown:
                preparedTask = nil
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

    private func submitPendingResult(
        _ result: StudyNo1OrientationThresholdResult,
        scheduledTask: ScheduledTask
    ) {
        let generation = beginOperation(in: .submitting)
        operation = Task { @MainActor [weak self] in
            await self?.submitThresholdAndFinalize(
                result: result,
                scheduledTask: scheduledTask,
                generation: generation
            )
        }
    }

    private func submitThresholdAndFinalize(
        result: StudyNo1OrientationThresholdResult,
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
                pendingResult = nil
            }

            await finalizeOnboarding(generation: generation)
        } catch is CancellationError {
            return
        } catch {
            guard canContinue(generation: generation) else {
                return
            }
            state = .submissionFailure(message: error.localizedDescription)
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
            state = .finalizationFailure(
                message: "Finishing orientation was interrupted. Your hearing check was saved. Try again to complete setup."
            )
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
             .readyForTest,
             .submitting,
             .submissionFailure,
             .finalizing,
             .finalizationFailure,
             .completed:
            return false
        }
    }
}
