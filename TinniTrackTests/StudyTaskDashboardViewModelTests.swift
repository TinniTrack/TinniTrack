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
