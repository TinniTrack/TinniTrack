//
//  ConsentServiceProtocol.swift
//  TinniTrack
//

import Foundation

protocol ConsentServiceProtocol {
    func finalizeConsentAndEnroll(
        study: Study,
        consent: StudyConsentCompletion
    ) async throws
}

enum ConsentServiceError: LocalizedError, Equatable {
    case noActiveSession
    case missingCatalogDefinition(studySlug: String)
    case studyMismatch
    case invalidConsentCompletion
    case missingSignedArtifact

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
        }
    }
}
