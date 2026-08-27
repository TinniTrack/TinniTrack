import Foundation
import Testing
@testable import TinniTrack

@MainActor
struct HomeDashboardViewModelTests {
    @Test
    func lifecycleRefreshCancellationPreservesLoadedContent() async {
        let service = MockStudyService(
            studies: [Self.sampleStudy()],
            enrollments: []
        )
        let viewModel = HomeDashboardViewModel(studyService: service)

        await viewModel.loadIfNeeded()
        #expect(viewModel.state == .loaded)
        #expect(viewModel.studies.count == 1)

        await service.setStudiesError(URLError(.cancelled))
        await viewModel.refreshForLifecycleEvent()

        #expect(viewModel.state == .loaded)
        #expect(viewModel.studies.count == 1)
    }

    @Test
    func lifecycleRefreshFailurePreservesLoadedContent() async {
        let service = MockStudyService(
            studies: [Self.sampleStudy()],
            enrollments: []
        )
        let viewModel = HomeDashboardViewModel(studyService: service)

        await viewModel.loadIfNeeded()
        #expect(viewModel.state == .loaded)
        #expect(viewModel.studies.count == 1)

        await service.setStudiesError(MockFailure(message: "Network unavailable"))
        await viewModel.refreshForLifecycleEvent()

        #expect(viewModel.state == .loaded)
        #expect(viewModel.studies.count == 1)
    }

    @Test
    func lifecycleRefreshSkipsUntilInitialLoadCompletes() async {
        let service = MockStudyService(
            studies: [Self.sampleStudy()],
            enrollments: []
        )
        let viewModel = HomeDashboardViewModel(studyService: service)

        await viewModel.refreshForLifecycleEvent()
        #expect(await service.fetchStudiesCallCount() == 0)
        #expect(await service.fetchMyEnrollmentsCallCount() == 0)
    }

    @Test
    func initialFailureShowsErrorStateWhenNoContentExists() async {
        let service = MockStudyService(
            studies: [Self.sampleStudy()],
            enrollments: []
        )
        await service.setStudiesError(MockFailure(message: "Network unavailable"))

        let viewModel = HomeDashboardViewModel(studyService: service)
        await viewModel.loadIfNeeded()

        switch viewModel.state {
        case .failed(let message):
            #expect(message == "Network unavailable")
        default:
            #expect(Bool(false), "Expected failed state when initial load has no cached content")
        }
        #expect(viewModel.studies.isEmpty)
    }

    @Test
    func enrollmentRefreshWaitsForInFlightRefreshThenReloadsLatestEnrollment() async {
        let study = Self.sampleStudy()
        let enrollment = Self.sampleEnrollment(studyID: study.id)
        let service = MockStudyService(
            studies: [study],
            enrollments: [],
            enrollmentResponses: [
                [],
                [],
                [enrollment]
            ]
        )
        let viewModel = HomeDashboardViewModel(studyService: service)

        await viewModel.loadIfNeeded()
        #expect(viewModel.studies.first?.isEnrolledActive == false)

        await service.setFetchDelay(nanoseconds: 200_000_000)
        let inFlightRefresh = Task {
            await viewModel.refresh(retainingCurrentContent: true)
        }
        await service.waitForFetchMyEnrollmentsCallCount(2)

        await service.setFetchDelay(nanoseconds: nil)
        await viewModel.refreshAfterEnrollment()
        await inFlightRefresh.value

        #expect(viewModel.studies.first?.isEnrolledActive == true)
        #expect(await service.fetchMyEnrollmentsCallCount() == 3)
    }

    private static func sampleStudy() -> Study {
        Study(
            id: UUID(),
            slug: "study-no-1",
            title: "Study No. 1",
            description: "Baseline tinnitus study",
            status: .recruiting,
            createdAt: Date()
        )
    }

    private static func sampleEnrollment(studyID: UUID) -> StudyEnrollment {
        StudyEnrollment(
            id: UUID(),
            userID: UUID(),
            studyID: studyID,
            status: .enrolled,
            enrolledAt: Date(),
            createdAt: Date()
        )
    }
}

private actor MockStudyService: StudyServiceProtocol {
    private var studies: [Study]
    private var enrollments: [StudyEnrollment]
    private var enrollmentResponses: [[StudyEnrollment]]
    private var studiesError: Error?
    private var enrollmentsError: Error?
    private var fetchDelayNanoseconds: UInt64?
    private var fetchStudiesCount = 0
    private var fetchEnrollmentsCount = 0

    init(
        studies: [Study],
        enrollments: [StudyEnrollment],
        enrollmentResponses: [[StudyEnrollment]] = [],
        studiesError: Error? = nil,
        enrollmentsError: Error? = nil,
        fetchDelayNanoseconds: UInt64? = nil
    ) {
        self.studies = studies
        self.enrollments = enrollments
        self.enrollmentResponses = enrollmentResponses
        self.studiesError = studiesError
        self.enrollmentsError = enrollmentsError
        self.fetchDelayNanoseconds = fetchDelayNanoseconds
    }

    func fetchStudies() async throws -> [Study] {
        fetchStudiesCount += 1
        if let fetchDelayNanoseconds {
            try? await Task.sleep(nanoseconds: fetchDelayNanoseconds)
        }
        if let studiesError {
            throw studiesError
        }
        return studies
    }

    func fetchMyEnrollments() async throws -> [StudyEnrollment] {
        fetchEnrollmentsCount += 1
        let response = enrollmentResponses.isEmpty ? enrollments : enrollmentResponses.removeFirst()
        if let fetchDelayNanoseconds {
            try? await Task.sleep(nanoseconds: fetchDelayNanoseconds)
        }
        if let enrollmentsError {
            throw enrollmentsError
        }
        return response
    }

    func fetchScheduledTasks(enrollmentID: UUID) async throws -> [ScheduledTask] {
        []
    }

    func beginStudyNo1OrientationThresholdTask(enrollmentID: UUID) async throws -> ScheduledTask {
        throw NSError(
            domain: "MockStudyService",
            code: 404,
            userInfo: [NSLocalizedDescriptionKey: "No orientation threshold task configured."]
        )
    }

    func completeStudyNo1Onboarding(enrollmentID: UUID, timezone: String) async throws {}

    func submitLoudnessMatch(
        scheduledTaskID: UUID,
        enrollmentID: UUID,
        submission: LoudnessMatchSubmission
    ) async throws {}

    func submitStudyNo1OrientationThreshold(
        scheduledTaskID: UUID,
        enrollmentID: UUID,
        submission: StudyNo1OrientationThresholdSubmission
    ) async throws {}

    func setStudiesError(_ error: Error?) {
        studiesError = error
    }

    func setFetchDelay(nanoseconds: UInt64?) {
        fetchDelayNanoseconds = nanoseconds
    }

    func fetchStudiesCallCount() -> Int {
        fetchStudiesCount
    }

    func fetchMyEnrollmentsCallCount() -> Int {
        fetchEnrollmentsCount
    }

    func waitForFetchMyEnrollmentsCallCount(_ count: Int) async {
        while fetchEnrollmentsCount < count {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

private struct MockFailure: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}
