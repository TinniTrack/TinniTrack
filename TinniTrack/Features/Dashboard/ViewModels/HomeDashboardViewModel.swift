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
    @Published private(set) var isRefreshing = false

    enum State: Equatable {
        case loading
        case loaded
        case empty
        case failed(message: String)
    }

    private let studyService: StudyServiceProtocol
    private var hasLoadedOnce = false
    private var locallyConfirmedEnrollments: [UUID: StudyEnrollment] = [:]
    private var isEnrollmentReconciliationPending = false

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

    func confirmEnrollment(_ enrollment: StudyEnrollment) {
        locallyConfirmedEnrollments[enrollment.studyID] = enrollment

        let updatedStudies = applyingLocallyConfirmedEnrollments(to: studies)
        guard updatedStudies != studies else { return }

        studies = updatedStudies
        state = .loaded
        hasLoadedOnce = true
    }

    func reconcileAfterEnrollment() async {
        isEnrollmentReconciliationPending = true
        guard !isRefreshing else { return }
        await refresh(retainingCurrentContent: true)
    }

    func refresh(retainingCurrentContent: Bool = false) async {
        guard !isRefreshing else { return }
        isEnrollmentReconciliationPending = false

        let previousStudies = studies
        let previousState = state
        let shouldShowBlockingLoading = !retainingCurrentContent || previousStudies.isEmpty
        if shouldShowBlockingLoading {
            state = .loading
        }

        isRefreshing = true

        do {
            async let studiesTask = studyService.fetchStudies()
            async let enrollmentsTask = studyService.fetchMyEnrollments()

            let studyRows = try await studiesTask
            let enrollmentRows = try await enrollmentsTask
            let enrollmentByStudyID = reconciledEnrollmentByStudyID(
                authoritativeEnrollments: enrollmentRows
            )

            studies = studyRows.map {
                DashboardStudyCard(study: $0, enrollment: enrollmentByStudyID[$0.id])
            }

            state = studies.isEmpty ? .empty : .loaded
            hasLoadedOnce = true
        } catch {
            let restoredStudies = applyingLocallyConfirmedEnrollments(to: previousStudies)
            if Self.isCancellation(error) {
                studies = restoredStudies
                state = restoredStudies == previousStudies ? previousState : .loaded
            } else {
                hasLoadedOnce = true
                if restoredStudies.isEmpty {
                    studies = []
                    state = .failed(message: Self.userFacingErrorMessage(for: error))
                } else {
                    studies = restoredStudies
                    state = .loaded
                }
            }
        }

        isRefreshing = false
        if isEnrollmentReconciliationPending, !Task.isCancelled {
            await refresh(retainingCurrentContent: true)
        }
    }

    private func reconciledEnrollmentByStudyID(
        authoritativeEnrollments: [StudyEnrollment]
    ) -> [UUID: StudyEnrollment] {
        var enrollmentByStudyID = Dictionary(
            authoritativeEnrollments.map { ($0.studyID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let reconciledStudyIDs: [UUID] = locallyConfirmedEnrollments.compactMap { entry -> UUID? in
            let (studyID, confirmedEnrollment) = entry
            guard let authoritativeEnrollment = enrollmentByStudyID[studyID],
                  Self.hasMatchingIdentity(authoritativeEnrollment, confirmedEnrollment) else {
                return nil
            }
            return studyID
        }
        for studyID in reconciledStudyIDs {
            locallyConfirmedEnrollments.removeValue(forKey: studyID)
        }

        for (studyID, confirmedEnrollment) in locallyConfirmedEnrollments {
            enrollmentByStudyID[studyID] = confirmedEnrollment
        }
        return enrollmentByStudyID
    }

    private func applyingLocallyConfirmedEnrollments(
        to studyCards: [DashboardStudyCard]
    ) -> [DashboardStudyCard] {
        studyCards.map { studyCard in
            guard let enrollment = locallyConfirmedEnrollments[studyCard.study.id] else {
                return studyCard
            }
            return DashboardStudyCard(study: studyCard.study, enrollment: enrollment)
        }
    }

    private static func hasMatchingIdentity(
        _ lhs: StudyEnrollment,
        _ rhs: StudyEnrollment
    ) -> Bool {
        lhs.id == rhs.id
            && lhs.userID == rhs.userID
            && lhs.studyID == rhs.studyID
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
            return "ENROLLED"
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
