//
//  ConsentServiceProtocol.swift
//  TinniTrack
//

import Foundation

nonisolated enum ConsentEnrollmentRecovery: Equatable, Sendable {
    case pendingUpload
    case pendingEnrollment
}

protocol ConsentServiceProtocol {
    func availableEnrollmentRecovery(
        for study: Study
    ) async throws -> ConsentEnrollmentRecovery?

    func resumeEnrollment(for study: Study) async throws -> StudyEnrollment

    func finalizeConsentAndEnroll(
        study: Study,
        consent: StudyConsentCompletion
    ) async throws -> StudyEnrollment
}

extension ConsentServiceProtocol {
    func availableEnrollmentRecovery(
        for study: Study
    ) async throws -> ConsentEnrollmentRecovery? {
        nil
    }

    func resumeEnrollment(for study: Study) async throws -> StudyEnrollment {
        throw ConsentServiceError.noRecoverableConsent
    }
}

enum ConsentServiceError: LocalizedError, Equatable {
    case noActiveSession
    case missingCatalogDefinition(studySlug: String)
    case studyMismatch
    case invalidConsentCompletion
    case missingSignedArtifact
    case conflictingPendingArtifact
    case pendingArtifactPersistenceFailed
    case consentRecordConfirmationFailed
    case noRecoverableConsent

    var errorDescription: String? {
        switch self {
        case .noActiveSession:
            return "No active session."
        case .missingCatalogDefinition:
            return "This study does not have an eConsent definition."
        case .studyMismatch:
            return "The signed consent does not match this study."
        case .invalidConsentCompletion:
            return "Consent must be completed, agreed to, signed, and saved before enrollment."
        case .missingSignedArtifact:
            return "Signed consent PDF is missing."
        case .conflictingPendingArtifact:
            return "A different signed consent is already pending or recorded. Retry the original attempt if it is still available, or contact the study team."
        case .pendingArtifactPersistenceFailed:
            return "The app could not securely recover your pending signed consent. Please retry; if this continues, contact the study team."
        case .consentRecordConfirmationFailed:
            return "The signed consent could not be confirmed on the server. Please retry before enrolling."
        case .noRecoverableConsent:
            return "No previous signed consent is available to resume. Please review and sign the consent form."
        }
    }
}
