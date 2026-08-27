import Foundation
import Testing
@testable import TinniTrack

@MainActor
struct StudyOrientationThresholdCoordinatorTests {
    @Test
    func stopDuringSuspendedPreparationPreventsLateReadyState() async {
        let task = orientationTask()
        let service = CoordinatorStudyService(
            beginBehavior: .suspendedIgnoringCancellation(task)
        )
        let completion = OnboardingCompletionStub(outcomes: [.completed])
        let coordinator = makeCoordinator(
            service: service,
            completion: completion
        )

        coordinator.begin()

        #expect(await waitUntil { await service.beginCallCount() == 1 })
        #expect(isPreparing(coordinator.state))

        coordinator.stop()
        await service.releaseSuspendedBegin()

        #expect(await waitUntil { isIdle(coordinator.state) })
        for _ in 0..<5 {
            await Task.yield()
        }

        #expect(isIdle(coordinator.state))
        #expect(await service.submissionCallCount() == 0)
        #expect(completion.callCount == 0)
    }

    @Test
    func finalizationFailureCanRetryWithoutResubmittingThreshold() async throws {
        let service = CoordinatorStudyService(
            beginBehavior: .immediate(orientationTask())
        )
        let builder = CoordinatorSubmissionBuilder()
        let completion = OnboardingCompletionStub(
            outcomes: [
                .failed(message: "Onboarding is temporarily unavailable."),
                .completed
            ]
        )
        let coordinator = makeCoordinator(
            service: service,
            builder: builder,
            completion: completion
        )

        try await prepareForTest(coordinator)
        coordinator.submit(completeThresholdResult())

        #expect(await waitUntil {
            isFinalizationFailure(
                coordinator.state,
                message: "Onboarding is temporarily unavailable."
            )
        })
        #expect(await service.submissionCallCount() == 1)
        #expect(builder.callCount == 1)
        #expect(completion.callCount == 1)

        coordinator.retryFinalization()

        #expect(await waitUntil { isCompleted(coordinator.state) })
        #expect(await service.submissionCallCount() == 1)
        #expect(builder.callCount == 1)
        #expect(completion.callCount == 2)
    }

    @Test
    func independentlyCancelledFinalizationBecomesRetryableWithoutResubmitting() async throws {
        let service = CoordinatorStudyService(
            beginBehavior: .immediate(orientationTask())
        )
        let builder = CoordinatorSubmissionBuilder()
        let completion = OnboardingCompletionStub(outcomes: [.cancelled, .completed])
        let coordinator = makeCoordinator(
            service: service,
            builder: builder,
            completion: completion
        )

        try await prepareForTest(coordinator)
        coordinator.submit(completeThresholdResult())

        #expect(await waitUntil {
            isFinalizationFailure(
                coordinator.state,
                message: "Finishing orientation was interrupted. Your hearing check was saved. Try again to complete setup."
            )
        })
        #expect(await service.submissionCallCount() == 1)
        #expect(builder.callCount == 1)
        #expect(completion.callCount == 1)

        coordinator.retryFinalization()

        #expect(await waitUntil { isCompleted(coordinator.state) })
        #expect(await service.submissionCallCount() == 1)
        #expect(builder.callCount == 1)
        #expect(completion.callCount == 2)
    }

    @Test
    func duplicateNativeCompletionSubmitsAndFinalizesExactlyOnce() async throws {
        let service = CoordinatorStudyService(
            beginBehavior: .immediate(orientationTask()),
            submissionBehavior: .suspendedIgnoringCancellation
        )
        let builder = CoordinatorSubmissionBuilder()
        let completion = OnboardingCompletionStub(outcomes: [.completed])
        let coordinator = makeCoordinator(
            service: service,
            builder: builder,
            completion: completion
        )
        let result = completeThresholdResult()

        try await prepareForTest(coordinator)
        coordinator.submit(result)
        coordinator.submit(result)

        #expect(await waitUntil { await service.submissionCallCount() == 1 })
        #expect(builder.callCount == 1)

        await service.releaseSuspendedSubmission()

        #expect(await waitUntil { isCompleted(coordinator.state) })
        #expect(await service.submissionCallCount() == 1)
        #expect(builder.callCount == 1)
        #expect(completion.callCount == 1)
    }

    @Test
    func unavailableScheduledTasksReturnToPreflightWithoutConsequentialWork() async {
        let unavailableStatuses: [ScheduledTaskStatus] = [
            .missed,
            .skipped,
            .cancelled,
            .unknown("future-status")
        ]

        for status in unavailableStatuses {
            let service = CoordinatorStudyService(
                beginBehavior: .immediate(orientationTask(status: status))
            )
            let builder = CoordinatorSubmissionBuilder()
            let completion = OnboardingCompletionStub(outcomes: [.completed])
            let coordinator = makeCoordinator(
                service: service,
                builder: builder,
                completion: completion
            )

            coordinator.begin()

            #expect(
                await waitUntil { isPreparationFailure(coordinator.state) },
                "Expected retryable preparation state for \(status.rawValue)."
            )
            #expect(await service.submissionCallCount() == 0)
            #expect(builder.callCount == 0)
            #expect(completion.callCount == 0)
        }
    }

    @Test
    func incompleteNativeResultReturnsToPreflightWithoutConsequentialWork() async throws {
        let service = CoordinatorStudyService(
            beginBehavior: .immediate(orientationTask())
        )
        let builder = CoordinatorSubmissionBuilder()
        let completion = OnboardingCompletionStub(outcomes: [.completed])
        let coordinator = makeCoordinator(
            service: service,
            builder: builder,
            completion: completion
        )
        let incompleteResult = StudyNo1OrientationThresholdResult(
            taskIdentifier: taskIdentifier,
            rightEar: orientationEar(channel: .right, threshold: 18),
            leftEar: nil,
            environment: nil
        )

        try await prepareForTest(coordinator)
        coordinator.submit(incompleteResult)

        #expect(await waitUntil { isIncompleteResultFailure(coordinator.state) })
        #expect(await service.submissionCallCount() == 0)
        #expect(builder.callCount == 0)
        #expect(completion.callCount == 0)
    }

    @Test
    func submissionFailureRetriesPendingResultWithoutRepeatingTest() async throws {
        let service = CoordinatorStudyService(
            beginBehavior: .immediate(orientationTask()),
            submissionBehavior: .failureOnce(CoordinatorTestError.submissionFailed)
        )
        let builder = CoordinatorSubmissionBuilder()
        let completion = OnboardingCompletionStub(outcomes: [.completed])
        let coordinator = makeCoordinator(
            service: service,
            builder: builder,
            completion: completion
        )
        let result = completeThresholdResult()

        try await prepareForTest(coordinator)
        coordinator.submit(result)

        #expect(await waitUntil {
            isSubmissionFailure(
                coordinator.state,
                message: "Threshold submission failed."
            )
        })
        #expect(await service.submissionCallCount() == 1)
        #expect(builder.callCount == 1)
        #expect(builder.lastResult == result)
        #expect(completion.callCount == 0)

        coordinator.retrySubmission()

        #expect(await waitUntil { isCompleted(coordinator.state) })
        #expect(await service.beginCallCount() == 1)
        #expect(await service.submissionCallCount() == 2)
        #expect(builder.callCount == 2)
        #expect(builder.lastResult == result)
        #expect(completion.callCount == 1)
    }

    @Test
    func completedScheduledTaskFinalizesWithoutStartingNativeTest() async {
        let service = CoordinatorStudyService(
            beginBehavior: .immediate(orientationTask(status: .completed))
        )
        let builder = CoordinatorSubmissionBuilder()
        let completion = OnboardingCompletionStub(outcomes: [.notRequired])
        let coordinator = makeCoordinator(
            service: service,
            builder: builder,
            completion: completion
        )

        coordinator.begin()

        #expect(await waitUntil { isCompleted(coordinator.state) })
        #expect(await service.submissionCallCount() == 0)
        #expect(builder.callCount == 0)
        #expect(completion.callCount == 1)
    }

    private func makeCoordinator(
        service: CoordinatorStudyService,
        builder: CoordinatorSubmissionBuilder? = nil,
        completion: OnboardingCompletionStub
    ) -> StudyOrientationThresholdCoordinator {
        StudyOrientationThresholdCoordinator(
            enrollment: enrollment(),
            studyService: service,
            submissionBuilder: builder ?? CoordinatorSubmissionBuilder(),
            completeOnboarding: {
                await completion.complete()
            }
        )
    }

    private func prepareForTest(
        _ coordinator: StudyOrientationThresholdCoordinator
    ) async throws {
        coordinator.begin()
        guard await waitUntil(condition: { isReadyForTest(coordinator.state) }) else {
            throw CoordinatorTestError.readyStateMissing
        }
        await Task.yield()
    }

    private func completeThresholdResult() -> StudyNo1OrientationThresholdResult {
        StudyNo1OrientationThresholdResult(
            taskIdentifier: taskIdentifier,
            rightEar: orientationEar(channel: .right, threshold: 18),
            leftEar: orientationEar(channel: .left, threshold: 12),
            environment: nil
        )
    }

    private func orientationEar(
        channel: CalibratedTonePlaybackChannel,
        threshold: Double
    ) -> StudyNo1OrientationThresholdEarResult {
        StudyNo1OrientationThresholdEarResult(
            channel: channel,
            thresholdDBHL: threshold,
            outputVolume: 1,
            headphoneType: "airPodsProGen2",
            tonePlaybackDuration: 1,
            postStimulusDelay: 1,
            samples: []
        )
    }

    private func enrollment() -> StudyEnrollment {
        StudyEnrollment(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            userID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            studyID: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            status: .enrolled,
            enrolledAt: timestamp,
            createdAt: timestamp
        )
    }

    private func orientationTask(
        status: ScheduledTaskStatus = .scheduled
    ) -> ScheduledTask {
        ScheduledTask(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            enrollmentID: enrollment().id,
            taskKey: "threshold_1khz_orientation_v1",
            taskVersion: 1,
            scheduledFor: timestamp,
            windowStart: timestamp.addingTimeInterval(-60),
            windowEnd: timestamp.addingTimeInterval(3_600),
            status: status,
            dayIndex: -1,
            slotIndex: 0,
            completedAt: status == .completed ? timestamp : nil
        )
    }

    private func isIdle(_ state: StudyOrientationThresholdCoordinator.State) -> Bool {
        if case .idle = state { return true }
        return false
    }

    private func isPreparing(_ state: StudyOrientationThresholdCoordinator.State) -> Bool {
        if case .preparing = state { return true }
        return false
    }

    private func isReadyForTest(_ state: StudyOrientationThresholdCoordinator.State) -> Bool {
        if case .readyForTest = state { return true }
        return false
    }

    private func isPreparationFailure(
        _ state: StudyOrientationThresholdCoordinator.State
    ) -> Bool {
        guard case .preflightFailure(let failure) = state else { return false }
        if case .preparation = failure { return true }
        return false
    }

    private func isIncompleteResultFailure(
        _ state: StudyOrientationThresholdCoordinator.State
    ) -> Bool {
        guard case .preflightFailure(let failure) = state else { return false }
        if case .incompleteResult = failure { return true }
        return false
    }

    private func isSubmissionFailure(
        _ state: StudyOrientationThresholdCoordinator.State,
        message: String
    ) -> Bool {
        if case .submissionFailure(let actualMessage) = state {
            return actualMessage == message
        }
        return false
    }

    private func isFinalizationFailure(
        _ state: StudyOrientationThresholdCoordinator.State,
        message: String
    ) -> Bool {
        if case .finalizationFailure(let actualMessage) = state {
            return actualMessage == message
        }
        return false
    }

    private func isCompleted(_ state: StudyOrientationThresholdCoordinator.State) -> Bool {
        if case .completed = state { return true }
        return false
    }

    private func waitUntil(
        timeout: TimeInterval = 1,
        condition: @escaping @MainActor () async -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return await condition()
    }

    private var timestamp: Date {
        Date(timeIntervalSince1970: 1_710_000_000)
    }

    private var taskIdentifier: String {
        "study-no-1-orientation-threshold"
    }
}

private enum CoordinatorTestError: LocalizedError {
    case readyStateMissing
    case submissionFailed

    var errorDescription: String? {
        switch self {
        case .readyStateMissing:
            return "The coordinator did not become ready for the native hearing test."
        case .submissionFailed:
            return "Threshold submission failed."
        }
    }
}

@MainActor
private final class CoordinatorSubmissionBuilder: StudyOrientationThresholdSubmissionBuilding {
    private(set) var callCount = 0
    private(set) var lastResult: StudyNo1OrientationThresholdResult?

    func makeOrientationThresholdSubmission(
        result: StudyNo1OrientationThresholdResult,
        scheduledTask: ScheduledTask,
        enrollment: StudyEnrollment
    ) throws -> StudyNo1OrientationThresholdSubmission {
        callCount += 1
        lastResult = result

        return StudyNo1OrientationThresholdSubmission(
            startedAt: Date(timeIntervalSince1970: 1_710_000_000),
            completedAt: Date(timeIntervalSince1970: 1_710_000_100),
            matchedLevel: 15,
            gating: [:],
            rawPayload: [:],
            deviceInfo: [:],
            headphoneInfo: [:],
            appVersion: "1.0",
            calibrationVersion: "test"
        )
    }
}

@MainActor
private final class OnboardingCompletionStub {
    private var outcomes: [StudyOnboardingCompletionOutcome]
    private(set) var callCount = 0

    init(outcomes: [StudyOnboardingCompletionOutcome]) {
        self.outcomes = outcomes
    }

    func complete() async -> StudyOnboardingCompletionOutcome {
        callCount += 1
        guard !outcomes.isEmpty else {
            return .completed
        }
        return outcomes.removeFirst()
    }
}

private actor CoordinatorStudyService: StudyServiceProtocol {
    enum BeginBehavior {
        case immediate(ScheduledTask)
        case suspendedIgnoringCancellation(ScheduledTask)
    }

    enum SubmissionBehavior {
        case immediate
        case suspendedIgnoringCancellation
        case failureOnce(Error)
    }

    private let beginBehavior: BeginBehavior
    private let submissionBehavior: SubmissionBehavior
    private var suspendedBeginContinuation: CheckedContinuation<ScheduledTask, Never>?
    private var suspendedSubmissionContinuation: CheckedContinuation<Void, Never>?
    private var beginCalls = 0
    private var submissionCalls = 0

    init(
        beginBehavior: BeginBehavior,
        submissionBehavior: SubmissionBehavior = .immediate
    ) {
        self.beginBehavior = beginBehavior
        self.submissionBehavior = submissionBehavior
    }

    func fetchStudies() async throws -> [Study] { [] }

    func fetchMyEnrollments() async throws -> [StudyEnrollment] { [] }

    func fetchScheduledTasks(enrollmentID: UUID) async throws -> [ScheduledTask] { [] }

    func beginStudyNo1OrientationThresholdTask(
        enrollmentID: UUID
    ) async throws -> ScheduledTask {
        beginCalls += 1
        switch beginBehavior {
        case .immediate(let task):
            return task
        case .suspendedIgnoringCancellation(let task):
            return await withCheckedContinuation { continuation in
                suspendedBeginContinuation = continuation
                if Task.isCancelled {
                    // Deliberately retain the continuation. This fake models a service
                    // that completes even after its caller has cancelled.
                    _ = task
                }
            }
        }
    }

    func completeStudyNo1Onboarding(enrollmentID: UUID, timezone: String) async throws {}

    func submitStudyNo1OrientationThreshold(
        scheduledTaskID: UUID,
        enrollmentID: UUID,
        submission: StudyNo1OrientationThresholdSubmission
    ) async throws {
        submissionCalls += 1
        switch submissionBehavior {
        case .immediate:
            return
        case .suspendedIgnoringCancellation:
            await withCheckedContinuation { continuation in
                suspendedSubmissionContinuation = continuation
            }
        case .failureOnce(let error):
            if submissionCalls == 1 {
                throw error
            }
        }
    }

    func submitLoudnessMatch(
        scheduledTaskID: UUID,
        enrollmentID: UUID,
        submission: LoudnessMatchSubmission
    ) async throws {}

    func releaseSuspendedBegin() {
        guard case .suspendedIgnoringCancellation(let task) = beginBehavior else {
            return
        }
        suspendedBeginContinuation?.resume(returning: task)
        suspendedBeginContinuation = nil
    }

    func releaseSuspendedSubmission() {
        suspendedSubmissionContinuation?.resume()
        suspendedSubmissionContinuation = nil
    }

    func beginCallCount() -> Int {
        beginCalls
    }

    func submissionCallCount() -> Int {
        submissionCalls
    }
}
