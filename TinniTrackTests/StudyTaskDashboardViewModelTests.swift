import Foundation
import Testing
@testable import TinniTrack

@MainActor
struct StudyTaskDashboardViewModelTests {
    @Test
    func refreshNeedsPermissionBeforeUnlockStaysBlocked() async {
        let coordinator = MockAudiogramImportCoordinator()
        coordinator.enqueuePrerequisite(.needsPermission)

        let viewModel = StudyTaskDashboardViewModel(
            study: Self.sampleStudyNo1(),
            coordinator: coordinator
        )

        await viewModel.refresh()

        #expect(viewModel.contentState == .blocked(.needsPermission))
        #expect(viewModel.orientationImportState == .waitingForPermission)
        #expect(viewModel.readySyncWarning == nil)
        #expect(viewModel.isAudiogramPrerequisiteMet == false)
    }

    @Test
    func connectHealthThenImportSuccessUpdatesToReadyState() async {
        let hearingTestDate = Date(timeIntervalSince1970: 1_710_000_000)
        let coordinator = MockAudiogramImportCoordinator()
        coordinator.enqueuePrerequisite(.needsPermission)
        coordinator.importResult = .success(
            .imported(newRecords: 1, latestMeasuredAt: hearingTestDate)
        )
        coordinator.enqueuePrerequisite(.met(latestMeasuredAt: hearingTestDate))

        let viewModel = StudyTaskDashboardViewModel(
            study: Self.sampleStudyNo1(),
            coordinator: coordinator
        )

        await viewModel.refresh()
        #expect(viewModel.orientationImportState == .waitingForPermission)
        #expect(viewModel.isAudiogramPrerequisiteMet == false)

        await viewModel.connectAppleHealthForOrientation()

        #expect(viewModel.orientationImportState == .success(hearingTestDate: hearingTestDate))
        #expect(viewModel.contentState == .ready(latestAudiogramDate: hearingTestDate))
        #expect(viewModel.readySyncWarning == nil)
        #expect(viewModel.isAudiogramPrerequisiteMet)
    }

    @Test
    func connectHealthAuthorizedButNoHearingTestKeepsBlockedState() async {
        let coordinator = MockAudiogramImportCoordinator()
        coordinator.enqueuePrerequisite(.needsPermission)
        coordinator.importResult = .success(.noAudiogramInHealth)
        coordinator.enqueuePrerequisite(.noAudiogramInHealth)

        let viewModel = StudyTaskDashboardViewModel(
            study: Self.sampleStudyNo1(),
            coordinator: coordinator
        )

        await viewModel.refresh()
        await viewModel.connectAppleHealthForOrientation()

        #expect(viewModel.orientationImportState == .authorizedNoHearingTest)
        #expect(viewModel.contentState == .blocked(.noAudiogramInHealth))
        #expect(viewModel.readySyncWarning == nil)
        #expect(viewModel.isAudiogramPrerequisiteMet == false)
    }

    @Test
    func refreshShowsDeniedStateWhenPermissionAlreadyDenied() async {
        let coordinator = MockAudiogramImportCoordinator()
        coordinator.enqueuePrerequisite(.permissionDenied)

        let viewModel = StudyTaskDashboardViewModel(
            study: Self.sampleStudyNo1(),
            coordinator: coordinator
        )

        await viewModel.refresh()

        #expect(viewModel.orientationImportState == .permissionDenied)
        #expect(viewModel.contentState == .blocked(.permissionDenied))
        #expect(viewModel.readySyncWarning == nil)
        #expect(viewModel.isAudiogramPrerequisiteMet == false)
    }

    @Test
    func connectHealthDeniedAfterPromptShowsDeniedState() async {
        let coordinator = MockAudiogramImportCoordinator()
        coordinator.enqueuePrerequisite(.needsPermission)
        coordinator.importResult = .failure(AudiogramImportCoordinatorError.authorizationDenied)
        coordinator.enqueuePrerequisite(.permissionDenied)

        let viewModel = StudyTaskDashboardViewModel(
            study: Self.sampleStudyNo1(),
            coordinator: coordinator
        )

        await viewModel.refresh()
        await viewModel.connectAppleHealthForOrientation()

        #expect(viewModel.orientationImportState == .permissionDenied)
        #expect(viewModel.contentState == .blocked(.permissionDenied))
        #expect(viewModel.readySyncWarning == nil)
        #expect(viewModel.isAudiogramPrerequisiteMet == false)
    }

    @Test
    func refreshAfterUnlockPermissionDeniedKeepsReadyAndShowsWarning() async {
        let hearingTestDate = Date(timeIntervalSince1970: 1_710_000_000)
        let coordinator = MockAudiogramImportCoordinator()
        coordinator.enqueuePrerequisite(.met(latestMeasuredAt: hearingTestDate))
        coordinator.enqueuePrerequisite(.permissionDenied)

        let viewModel = StudyTaskDashboardViewModel(
            study: Self.sampleStudyNo1(),
            coordinator: coordinator
        )

        await viewModel.refresh()
        await viewModel.refresh()

        #expect(viewModel.contentState == .ready(latestAudiogramDate: hearingTestDate))
        #expect(viewModel.orientationImportState == .permissionDenied)
        #expect(viewModel.readySyncWarning == .permissionDenied)
        #expect(viewModel.isAudiogramPrerequisiteMet)
    }

    @Test
    func refreshAfterUnlockNoAudiogramKeepsReadyAndShowsWarning() async {
        let hearingTestDate = Date(timeIntervalSince1970: 1_710_000_000)
        let coordinator = MockAudiogramImportCoordinator()
        coordinator.enqueuePrerequisite(.met(latestMeasuredAt: hearingTestDate))
        coordinator.enqueuePrerequisite(.noAudiogramInHealth)

        let viewModel = StudyTaskDashboardViewModel(
            study: Self.sampleStudyNo1(),
            coordinator: coordinator
        )

        await viewModel.refresh()
        await viewModel.refresh()

        #expect(viewModel.contentState == .ready(latestAudiogramDate: hearingTestDate))
        #expect(viewModel.orientationImportState == .authorizedNoHearingTest)
        #expect(viewModel.readySyncWarning == .noAudiogramInHealth)
        #expect(viewModel.isAudiogramPrerequisiteMet)
    }

    @Test
    func refreshAfterUnlockErrorKeepsReadyAndShowsWarning() async {
        let hearingTestDate = Date(timeIntervalSince1970: 1_710_000_000)
        let errorMessage = "Unable to sync at this time."
        let coordinator = MockAudiogramImportCoordinator()
        coordinator.enqueuePrerequisite(.met(latestMeasuredAt: hearingTestDate))
        coordinator.enqueuePrerequisite(.error(message: errorMessage))

        let viewModel = StudyTaskDashboardViewModel(
            study: Self.sampleStudyNo1(),
            coordinator: coordinator
        )

        await viewModel.refresh()
        await viewModel.refresh()

        #expect(viewModel.contentState == .ready(latestAudiogramDate: hearingTestDate))
        #expect(viewModel.orientationImportState == .error(message: errorMessage))
        #expect(viewModel.readySyncWarning == .error(message: errorMessage))
        #expect(viewModel.isAudiogramPrerequisiteMet)
    }

    @Test
    func refreshAfterUnlockMetAgainUpdatesDateAndClearsWarning() async {
        let initialDate = Date(timeIntervalSince1970: 1_710_000_000)
        let updatedDate = Date(timeIntervalSince1970: 1_720_000_000)
        let coordinator = MockAudiogramImportCoordinator()
        coordinator.enqueuePrerequisite(.met(latestMeasuredAt: initialDate))
        coordinator.enqueuePrerequisite(.permissionDenied)
        coordinator.enqueuePrerequisite(.met(latestMeasuredAt: updatedDate))

        let viewModel = StudyTaskDashboardViewModel(
            study: Self.sampleStudyNo1(),
            coordinator: coordinator
        )

        await viewModel.refresh()
        await viewModel.refresh()
        #expect(viewModel.contentState == .ready(latestAudiogramDate: initialDate))
        #expect(viewModel.readySyncWarning == .permissionDenied)

        await viewModel.refresh()
        #expect(viewModel.contentState == .ready(latestAudiogramDate: updatedDate))
        #expect(viewModel.orientationImportState == .success(hearingTestDate: updatedDate))
        #expect(viewModel.readySyncWarning == nil)
    }

    @Test
    func onboardingCompletionGeneratesAndLoadsScheduledTasks() async {
        let hearingTestDate = Date(timeIntervalSince1970: 1_710_000_000)
        let coordinator = MockAudiogramImportCoordinator()
        coordinator.enqueuePrerequisite(.met(latestMeasuredAt: hearingTestDate))

        let enrollment = sampleEnrollment(onboardingCompletedAt: nil)
        let service = MockTaskStudyService()
        let scheduled = sampleScheduledTask(
            enrollmentID: enrollment.id,
            status: .scheduled,
            scheduledFor: Date(timeIntervalSince1970: 1_750_000_000),
            windowStart: Date(timeIntervalSince1970: 1_750_000_000),
            windowEnd: Date(timeIntervalSince1970: 1_750_003_600)
        )
        await service.setScheduledTasks([scheduled], for: enrollment.id)

        let viewModel = StudyTaskDashboardViewModel(
            study: Self.sampleStudyNo1(),
            enrollment: enrollment,
            coordinator: coordinator,
            studyService: service,
            profileTimezone: "America/Los_Angeles"
        )

        await viewModel.refresh()
        #expect(viewModel.requiresStudyOnboardingCompletion)
        #expect(viewModel.futureTasks.isEmpty)

        await viewModel.completeStudyOnboarding()

        #expect(viewModel.requiresStudyOnboardingCompletion == false)
        #expect(viewModel.futureTasks.count == 1)
        #expect(await service.completeOnboardingCallCount() == 1)
    }

    @Test
    func scheduledTasksAreGroupedAndSorted() async {
        let hearingTestDate = Date(timeIntervalSince1970: 1_710_000_000)
        let coordinator = MockAudiogramImportCoordinator()
        coordinator.enqueuePrerequisite(.met(latestMeasuredAt: hearingTestDate))

        let enrollment = sampleEnrollment(onboardingCompletedAt: Date())
        let service = MockTaskStudyService()

        let futureEarly = sampleScheduledTask(
            enrollmentID: enrollment.id,
            status: .scheduled,
            scheduledFor: Date(timeIntervalSince1970: 1_750_100_000),
            windowStart: Date(timeIntervalSince1970: 1_750_100_000),
            windowEnd: Date(timeIntervalSince1970: 1_750_103_600),
            dayIndex: 1,
            slotIndex: 1
        )
        let futureLate = sampleScheduledTask(
            enrollmentID: enrollment.id,
            status: .scheduled,
            scheduledFor: Date(timeIntervalSince1970: 1_750_200_000),
            windowStart: Date(timeIntervalSince1970: 1_750_200_000),
            windowEnd: Date(timeIntervalSince1970: 1_750_203_600),
            dayIndex: 3,
            slotIndex: 2
        )
        let completedOld = sampleScheduledTask(
            enrollmentID: enrollment.id,
            status: .completed,
            scheduledFor: Date(timeIntervalSince1970: 1_749_900_000),
            windowStart: Date(timeIntervalSince1970: 1_749_900_000),
            windowEnd: Date(timeIntervalSince1970: 1_749_903_600),
            completedAt: Date(timeIntervalSince1970: 1_750_300_000)
        )
        let completedNew = sampleScheduledTask(
            enrollmentID: enrollment.id,
            status: .completed,
            scheduledFor: Date(timeIntervalSince1970: 1_749_800_000),
            windowStart: Date(timeIntervalSince1970: 1_749_800_000),
            windowEnd: Date(timeIntervalSince1970: 1_749_803_600),
            completedAt: Date(timeIntervalSince1970: 1_750_400_000)
        )

        await service.setScheduledTasks([futureLate, completedOld, futureEarly, completedNew], for: enrollment.id)

        let viewModel = StudyTaskDashboardViewModel(
            study: Self.sampleStudyNo1(),
            enrollment: enrollment,
            coordinator: coordinator,
            studyService: service
        )

        await viewModel.refresh()

        #expect(viewModel.futureTasks.map(\.id) == [futureEarly.id, futureLate.id])
        #expect(viewModel.completedTasks.map(\.id) == [completedNew.id, completedOld.id])
    }

    @Test
    func canStartOnlyInsideActiveWindow() async {
        let now = Date()
        let task = sampleScheduledTask(
            enrollmentID: UUID(),
            status: .scheduled,
            scheduledFor: now,
            windowStart: now.addingTimeInterval(-30),
            windowEnd: now.addingTimeInterval(30)
        )

        let viewModel = StudyTaskDashboardViewModel(
            study: Self.sampleStudyNo1(),
            coordinator: MockAudiogramImportCoordinator()
        )

        #expect(viewModel.canStart(task, at: now))
        #expect(viewModel.canStart(task, at: now.addingTimeInterval(-60)) == false)
        #expect(viewModel.canStart(task, at: now.addingTimeInterval(60)) == false)
        #expect(
            viewModel.canStart(
                sampleScheduledTask(
                    enrollmentID: UUID(),
                    status: .completed,
                    scheduledFor: now,
                    windowStart: now.addingTimeInterval(-30),
                    windowEnd: now.addingTimeInterval(30)
                ),
                at: now
            ) == false
        )
    }

    private static func sampleStudyNo1() -> Study {
        Study(
            id: UUID(),
            slug: StudyPrerequisiteRules.studyNo1Slug,
            title: "Study No. 1",
            description: "Study for audiogram import flow testing",
            status: .recruiting,
            createdAt: Date()
        )
    }

    private func sampleEnrollment(onboardingCompletedAt: Date?) -> StudyEnrollment {
        StudyEnrollment(
            id: UUID(),
            userID: UUID(),
            studyID: UUID(),
            status: .enrolled,
            enrolledAt: Date(),
            createdAt: Date(),
            onboardingCompletedAt: onboardingCompletedAt
        )
    }

    private func sampleScheduledTask(
        enrollmentID: UUID,
        status: ScheduledTaskStatus,
        scheduledFor: Date,
        windowStart: Date,
        windowEnd: Date,
        dayIndex: Int = 0,
        slotIndex: Int = 0,
        completedAt: Date? = nil
    ) -> ScheduledTask {
        ScheduledTask(
            id: UUID(),
            enrollmentID: enrollmentID,
            taskKey: "lm_1khz_v1",
            taskVersion: 1,
            scheduledFor: scheduledFor,
            windowStart: windowStart,
            windowEnd: windowEnd,
            status: status,
            dayIndex: dayIndex,
            slotIndex: slotIndex,
            completedAt: completedAt
        )
    }
}

@MainActor
private final class MockAudiogramImportCoordinator: AudiogramImportCoordinating {
    private var queuedPrerequisiteStates: [AudiogramPrerequisiteState] = []
    var importResult: Result<AudiogramImportResult, Error> = .success(.noAudiogramInHealth)

    func enqueuePrerequisite(_ state: AudiogramPrerequisiteState) {
        queuedPrerequisiteStates.append(state)
    }

    func evaluatePrerequisite() async -> AudiogramPrerequisiteState {
        if queuedPrerequisiteStates.isEmpty {
            return .needsPermission
        }
        return queuedPrerequisiteStates.removeFirst()
    }

    func importFromHealthKit() async throws -> AudiogramImportResult {
        try importResult.get()
    }
}

private actor MockTaskStudyService: StudyServiceProtocol {
    private var scheduledTasksByEnrollment: [UUID: [ScheduledTask]] = [:]
    private var completeOnboardingCalls: [(enrollmentID: UUID, timezone: String)] = []

    func fetchStudies() async throws -> [Study] { [] }

    func fetchMyEnrollments() async throws -> [StudyEnrollment] { [] }

    func fetchScheduledTasks(enrollmentID: UUID) async throws -> [ScheduledTask] {
        scheduledTasksByEnrollment[enrollmentID] ?? []
    }

    func enroll(studyID: UUID) async throws {}

    func completeStudyNo1Onboarding(enrollmentID: UUID, timezone: String) async throws {
        completeOnboardingCalls.append((enrollmentID: enrollmentID, timezone: timezone))
    }

    func submitLoudnessMatch(
        scheduledTaskID: UUID,
        enrollmentID: UUID,
        submission: LoudnessMatchSubmission
    ) async throws {}

    func setScheduledTasks(_ tasks: [ScheduledTask], for enrollmentID: UUID) {
        scheduledTasksByEnrollment[enrollmentID] = tasks
    }

    func completeOnboardingCallCount() -> Int {
        completeOnboardingCalls.count
    }
}
