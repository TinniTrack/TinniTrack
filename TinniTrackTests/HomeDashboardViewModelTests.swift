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
}

private actor MockStudyService: StudyServiceProtocol {
    private var studies: [Study]
    private var enrollments: [StudyEnrollment]
    private var studiesError: Error?
    private var enrollmentsError: Error?
    private var enrollError: Error?
    private var fetchStudiesCount = 0
    private var fetchEnrollmentsCount = 0

    init(
        studies: [Study],
        enrollments: [StudyEnrollment],
        studiesError: Error? = nil,
        enrollmentsError: Error? = nil,
        enrollError: Error? = nil
    ) {
        self.studies = studies
        self.enrollments = enrollments
        self.studiesError = studiesError
        self.enrollmentsError = enrollmentsError
        self.enrollError = enrollError
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
        if let enrollmentsError {
            throw enrollmentsError
        }
        return enrollments
    }

    func enroll(studyID: UUID) async throws {
        if let enrollError {
            throw enrollError
        }
    }

    func setStudiesError(_ error: Error?) {
        studiesError = error
    }

    func fetchStudiesCallCount() -> Int {
        fetchStudiesCount
    }

    func fetchMyEnrollmentsCallCount() -> Int {
        fetchEnrollmentsCount
    }
}

private struct MockFailure: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}
