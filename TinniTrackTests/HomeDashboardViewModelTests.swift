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
    func confirmedEnrollmentUpdatesDashboardSynchronously() async {
        let study = Self.sampleStudy()
        let enrollment = Self.sampleEnrollment(studyID: study.id)
        let service = MockStudyService(
            studies: [study],
            enrollments: []
        )
        let viewModel = HomeDashboardViewModel(studyService: service)

        await viewModel.loadIfNeeded()
        #expect(viewModel.studies.first?.isEnrolledActive == false)

        viewModel.confirmEnrollment(enrollment)

        #expect(viewModel.state == .loaded)
        #expect(viewModel.studies.first?.enrollment == enrollment)
        #expect(await service.fetchMyEnrollmentsCallCount() == 1)
    }

    @Test
    func staleDelayedRefreshCannotRemoveConfirmedEnrollment() async {
        let study = Self.sampleStudy()
        let enrollment = Self.sampleEnrollment(studyID: study.id)
        let service = MockStudyService(
            studies: [study],
            enrollments: [],
            enrollmentResponses: [[], [], [enrollment]]
        )
        let viewModel = HomeDashboardViewModel(studyService: service)

        await viewModel.loadIfNeeded()
        await service.suspendNextEnrollmentFetch()
        let inFlightRefresh = Task {
            await viewModel.refresh(retainingCurrentContent: true)
        }
        #expect(await service.waitForFetchMyEnrollmentsCallCount(2))

        viewModel.confirmEnrollment(enrollment)
        await viewModel.reconcileAfterEnrollment()
        #expect(viewModel.studies.first?.enrollment == enrollment)
        #expect(viewModel.isRefreshing)

        await service.resumeEnrollmentFetch()
        await inFlightRefresh.value

        #expect(viewModel.state == .loaded)
        #expect(viewModel.studies.first?.enrollment == enrollment)
        #expect(await service.fetchMyEnrollmentsCallCount() == 3)
    }

    @Test
    func cancelledRefreshStartedBeforeConfirmationPreservesEnrollment() async {
        let study = Self.sampleStudy()
        let enrollment = Self.sampleEnrollment(studyID: study.id)
        let service = MockStudyService(studies: [study], enrollments: [])
        let viewModel = HomeDashboardViewModel(studyService: service)

        await viewModel.loadIfNeeded()
        await service.setEnrollmentsError(URLError(.cancelled))
        await service.suspendNextEnrollmentFetch()
        let inFlightRefresh = Task {
            await viewModel.refresh(retainingCurrentContent: true)
        }
        #expect(await service.waitForFetchMyEnrollmentsCallCount(2))

        viewModel.confirmEnrollment(enrollment)
        await service.resumeEnrollmentFetch()
        await inFlightRefresh.value

        #expect(viewModel.state == .loaded)
        #expect(viewModel.studies.first?.enrollment == enrollment)
    }

    @Test
    func failedRefreshStartedBeforeConfirmationPreservesEnrollment() async {
        let study = Self.sampleStudy()
        let enrollment = Self.sampleEnrollment(studyID: study.id)
        let service = MockStudyService(studies: [study], enrollments: [])
        let viewModel = HomeDashboardViewModel(studyService: service)

        await viewModel.loadIfNeeded()
        await service.setEnrollmentsError(MockFailure(message: "Network unavailable"))
        await service.suspendNextEnrollmentFetch()
        let inFlightRefresh = Task {
            await viewModel.refresh(retainingCurrentContent: true)
        }
        #expect(await service.waitForFetchMyEnrollmentsCallCount(2))

        viewModel.confirmEnrollment(enrollment)
        await service.resumeEnrollmentFetch()
        await inFlightRefresh.value

        #expect(viewModel.state == .loaded)
        #expect(viewModel.studies.first?.enrollment == enrollment)
    }

    @Test
    func localConfirmationClearsOnlyAfterMatchingAuthoritativeEnrollment() async {
        let study = Self.sampleStudy()
        let confirmedEnrollment = Self.sampleEnrollment(studyID: study.id)
        let conflictingEnrollment = Self.sampleEnrollment(studyID: study.id)
        let reconciledEnrollment = StudyEnrollment(
            id: confirmedEnrollment.id,
            userID: confirmedEnrollment.userID,
            studyID: confirmedEnrollment.studyID,
            status: .enrolled,
            enrolledAt: confirmedEnrollment.enrolledAt,
            createdAt: confirmedEnrollment.createdAt,
            onboardingCompletedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let service = MockStudyService(studies: [study], enrollments: [])
        let viewModel = HomeDashboardViewModel(studyService: service)

        await viewModel.loadIfNeeded()
        viewModel.confirmEnrollment(confirmedEnrollment)

        await service.setEnrollments([conflictingEnrollment])
        await viewModel.reconcileAfterEnrollment()
        #expect(viewModel.studies.first?.enrollment == confirmedEnrollment)

        await service.setEnrollments([reconciledEnrollment])
        await viewModel.reconcileAfterEnrollment()
        #expect(viewModel.studies.first?.enrollment == reconciledEnrollment)

        await service.setEnrollments([])
        await viewModel.refresh(retainingCurrentContent: true)
        #expect(viewModel.studies.first?.enrollment == nil)
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
    private var shouldSuspendNextEnrollmentFetch = false
    private var enrollmentFetchContinuation: CheckedContinuation<Void, Never>?
    private var fetchStudiesCount = 0
    private var fetchEnrollmentsCount = 0

    init(
        studies: [Study],
        enrollments: [StudyEnrollment],
        enrollmentResponses: [[StudyEnrollment]] = [],
        studiesError: Error? = nil,
        enrollmentsError: Error? = nil
    ) {
        self.studies = studies
        self.enrollments = enrollments
        self.enrollmentResponses = enrollmentResponses
        self.studiesError = studiesError
        self.enrollmentsError = enrollmentsError
    }

    func fetchStudies() async throws -> [Study] {
        fetchStudiesCount += 1
        if let studiesError {
            throw studiesError
        }
        return studies
    }

    func fetchMyEnrollments() async throws -> [StudyEnrollment] {
        fetchEnrollmentsCount += 1
        let response = enrollmentResponses.isEmpty ? enrollments : enrollmentResponses.removeFirst()
        let error = enrollmentsError
        if shouldSuspendNextEnrollmentFetch {
            shouldSuspendNextEnrollmentFetch = false
            await withCheckedContinuation { continuation in
                enrollmentFetchContinuation = continuation
            }
        }
        if let error {
            throw error
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

    func setEnrollmentsError(_ error: Error?) {
        enrollmentsError = error
    }

    func setEnrollments(_ enrollments: [StudyEnrollment]) {
        self.enrollments = enrollments
    }

    func suspendNextEnrollmentFetch() {
        shouldSuspendNextEnrollmentFetch = true
    }

    func resumeEnrollmentFetch() {
        enrollmentFetchContinuation?.resume()
        enrollmentFetchContinuation = nil
    }

    func fetchStudiesCallCount() -> Int {
        fetchStudiesCount
    }

    func fetchMyEnrollmentsCallCount() -> Int {
        fetchEnrollmentsCount
    }

    func waitForFetchMyEnrollmentsCallCount(
        _ count: Int,
        attempts: Int = 200
    ) async -> Bool {
        for _ in 0..<attempts {
            if fetchEnrollmentsCount >= count {
                return true
            }
            do {
                try await Task.sleep(nanoseconds: 10_000_000)
            } catch {
                return false
            }
        }
        return fetchEnrollmentsCount >= count
    }
}

private struct MockFailure: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}
