//
//  HomeDashboardViewModel.swift
//  TinniTrack
//

import Foundation
import Combine

@MainActor
final class HomeDashboardViewModel: ObservableObject {
    @Published private(set) var state: State = .loading
    @Published private(set) var studies: [DashboardStudyCard] = []
    @Published private(set) var enrollingStudyID: UUID?
    @Published private(set) var isRefreshing = false

    enum State: Equatable {
        case loading
        case loaded
        case empty
        case failed(message: String)
    }

    private let studyService: StudyServiceProtocol
    private var hasLoadedOnce = false

    init(studyService: StudyServiceProtocol) {
        self.studyService = studyService
    }

    func loadIfNeeded() async {
        guard !hasLoadedOnce else { return }
        await refresh()
    }

    func refreshForLifecycleEvent() async {
        guard hasLoadedOnce else { return }
        await refresh(retainingCurrentContent: true)
    }

    func refresh(retainingCurrentContent: Bool = false) async {
        guard !isRefreshing else { return }

        let previousStudies = studies
        let previousState = state
        let shouldShowBlockingLoading = !retainingCurrentContent || previousStudies.isEmpty
        if shouldShowBlockingLoading {
            state = .loading
        }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            async let studiesTask = studyService.fetchStudies()
            async let enrollmentsTask = studyService.fetchMyEnrollments()

            let studyRows = try await studiesTask
            let enrollmentRows = try await enrollmentsTask
            let enrollmentByStudyID = Dictionary(
                enrollmentRows.map { ($0.studyID, $0) },
                uniquingKeysWith: { first, _ in first }
            )

            studies = studyRows.map {
                DashboardStudyCard(study: $0, enrollment: enrollmentByStudyID[$0.id])
            }

            state = studies.isEmpty ? .empty : .loaded
            hasLoadedOnce = true
        } catch {
            if Self.isCancellation(error) {
                studies = previousStudies
                state = previousState
                return
            }

            hasLoadedOnce = true
            if previousStudies.isEmpty {
                studies = []
                state = .failed(message: Self.userFacingErrorMessage(for: error))
            } else {
                studies = previousStudies
                state = .loaded
            }
        }
    }

    func enroll(studyID: UUID) async throws {
        enrollingStudyID = studyID
        defer { enrollingStudyID = nil }
        try await studyService.enroll(studyID: studyID)
        await refresh()
    }

    private static func userFacingErrorMessage(for error: Error) -> String {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? "Unable to load studies right now. Please try again." : message
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }

        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }
}

struct DashboardStudyCard: Identifiable, Equatable {
    let study: Study
    let enrollment: StudyEnrollment?

    var id: UUID { study.id }

    var isEnrolledActive: Bool {
        enrollment?.status == .enrolled
    }

    var badgeText: String {
        if isEnrolledActive {
            return "ACTIVE"
        }

        switch study.status {
        case .recruiting:
            return "RECRUITING"
        case .recruitingPaused:
            return "PAUSED"
        case .closed:
            return "CLOSED"
        case .unknown(let raw):
            return raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        }
    }

    var callToActionText: String {
        isEnrolledActive ? "Go to Tasks" : "View Details"
    }
}
