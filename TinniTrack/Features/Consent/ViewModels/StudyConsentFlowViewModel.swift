//
//  StudyConsentFlowViewModel.swift
//  TinniTrack
//

import Foundation
import Combine

@MainActor
final class StudyConsentFlowViewModel: ObservableObject {
    @Published private(set) var state: State = .reviewing
    @Published var errorMessage: String?

    enum State: Equatable {
        case reviewing
        case finalizing
        case completed
        case dismissed
        case failed
    }

    private let study: Study
    private let consentService: ConsentServiceProtocol
    private var hasHandledResult = false

    init(
        study: Study,
        consentService: ConsentServiceProtocol
    ) {
        self.study = study
        self.consentService = consentService
    }

    func handleResearchKitResult(_ summary: ResearchKitTaskResultSummary) async {
        guard !hasHandledResult else { return }
        hasHandledResult = true

        guard summary.finishState == .completed else {
            state = .dismissed
            return
        }

        guard let consentSummary = summary.studyConsent else {
            fail(message: "Consent did not return a signed result.")
            return
        }

        let consentCompletion = consentSummary.completion()
        guard consentCompletion.consented else {
            state = .dismissed
            return
        }

        guard consentCompletion.isValidSignedConsent else {
            fail(message: summary.errorDescription ?? "Consent must include your name, signature, signed PDF, and PDF hash.")
            return
        }

        state = .finalizing

        do {
            try await consentService.finalizeConsentAndEnroll(
                study: study,
                consent: consentCompletion
            )
            state = .completed
        } catch {
            fail(message: Self.userFacingErrorMessage(for: error))
        }
    }

    func retryAfterFailure() {
        hasHandledResult = false
        errorMessage = nil
        state = .reviewing
    }

    private func fail(message: String) {
        errorMessage = message
        state = .failed
    }

    private static func userFacingErrorMessage(for error: Error) -> String {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? "Unable to finish enrollment. Please try again." : message
    }
}
