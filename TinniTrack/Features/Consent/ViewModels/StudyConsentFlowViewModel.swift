//
//  StudyConsentFlowViewModel.swift
//  TinniTrack
//

import Combine
import Foundation

@MainActor
final class StudyConsentFlowViewModel: ObservableObject {
    @Published private(set) var enrollmentOperation: EnrollmentOperation = .idle
    @Published var hasScrolledToConsentEnd = false
    @Published var firstName = ""
    @Published var lastName = ""
    @Published var signatureImageData: Data?
    @Published private(set) var enrollmentRecoveryStatus: EnrollmentRecoveryStatus = .notChecked

    enum EnrollmentSource: Equatable {
        case signedConsent
        case recovery
    }

    enum EnrollmentOperation: Equatable {
        case idle
        case submitting(EnrollmentSource)
        case failed(source: EnrollmentSource, message: String)
        case succeeded(StudyEnrollment)
    }

    enum EnrollmentRecoveryStatus: Equatable {
        case notChecked
        case checking
        case unavailable
        case available(ConsentEnrollmentRecovery)
        case failed(message: String)
    }

    private let study: Study
    let definition: StudyConsentDefinition
    private let consentService: ConsentServiceProtocol
    private let artifactGenerator: ConsentArtifactGenerating
    private let now: () -> Date
    private var pendingConsentCompletion: StudyConsentCompletion?

    init(
        study: Study,
        definition: StudyConsentDefinition,
        consentService: ConsentServiceProtocol,
        artifactGenerator: ConsentArtifactGenerating = ConsentArtifactGenerator(),
        now: @escaping () -> Date = Date.init
    ) {
        self.study = study
        self.definition = definition
        self.consentService = consentService
        self.artifactGenerator = artifactGenerator
        self.now = now
    }

    var visibleSections: [StudyConsentSection] {
        definition.sections
    }

    var canContinueToSignature: Bool {
        hasScrolledToConsentEnd
    }

    var canReviewConsent: Bool {
        guard case .unavailable = enrollmentRecoveryStatus else { return false }
        return canBeginEnrollmentOperation
    }

    var hasAvailableEnrollmentRecovery: Bool {
        guard case .available = enrollmentRecoveryStatus else { return false }
        return true
    }

    var canResumeEnrollment: Bool {
        hasAvailableEnrollmentRecovery && canBeginEnrollmentOperation
    }

    var isEnrollmentInProgress: Bool {
        guard case .submitting = enrollmentOperation else { return false }
        return true
    }

    var isResumingEnrollment: Bool {
        enrollmentOperation == .submitting(.recovery)
    }

    var isFinalizingSignedConsent: Bool {
        enrollmentOperation == .submitting(.signedConsent)
    }

    var errorMessage: String? {
        guard case .failed(_, let message) = enrollmentOperation else { return nil }
        return message
    }

    var shouldRetryEnrollmentRecoveryFromAlert: Bool {
        guard case .failed(.recovery, _) = enrollmentOperation else { return false }
        return hasAvailableEnrollmentRecovery
    }

    var hasSignedConsentError: Bool {
        guard case .failed(.signedConsent, _) = enrollmentOperation else { return false }
        return true
    }

    var trimmedFirstName: String {
        firstName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedLastName: String {
        lastName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isSignatureFormComplete: Bool {
        !trimmedFirstName.isEmpty
            && !trimmedLastName.isEmpty
            && signatureImageData?.isEmpty == false
    }

    var canSignAndEnroll: Bool {
        isSignatureFormComplete && canBeginEnrollmentOperation
    }

    func prepareConsentReview() {
        guard !isEnrollmentInProgress else { return }
        resetConsentReviewProgress()
        enrollmentOperation = .idle
    }

    func probeEnrollmentRecoveryIfNeeded() async {
        guard case .notChecked = enrollmentRecoveryStatus else { return }
        await probeEnrollmentRecovery()
    }

    func probeEnrollmentRecovery() async {
        enrollmentRecoveryStatus = .checking

        do {
            let recovery = try await consentService.availableEnrollmentRecovery(for: study)
            guard !Task.isCancelled else {
                enrollmentRecoveryStatus = .notChecked
                return
            }
            if let recovery {
                enrollmentRecoveryStatus = .available(recovery)
            } else {
                enrollmentRecoveryStatus = .unavailable
            }
        } catch is CancellationError {
            enrollmentRecoveryStatus = .notChecked
        } catch {
            enrollmentRecoveryStatus = .failed(
                message: Self.userFacingErrorMessage(for: error)
            )
        }
    }

    func retryEnrollmentRecoveryProbe() async {
        guard case .failed = enrollmentRecoveryStatus else { return }
        await probeEnrollmentRecovery()
    }

    func markConsentScrolledToEnd() {
        hasScrolledToConsentEnd = true
    }

    private func resetConsentReviewProgress() {
        hasScrolledToConsentEnd = false
    }

    func clearSignature() {
        guard !isEnrollmentInProgress else { return }
        pendingConsentCompletion = nil
        signatureImageData = nil
    }

    @discardableResult
    func completeEnrollment(using source: EnrollmentSource) async -> StudyEnrollment? {
        guard canBeginEnrollmentOperation else { return nil }

        let recovery: ConsentEnrollmentRecovery?
        switch source {
        case .signedConsent:
            guard definition.studySlug == study.slug else {
                enrollmentOperation = .failed(
                    source: source,
                    message: ConsentServiceError.studyMismatch.localizedDescription
                )
                return nil
            }
            guard isSignatureFormComplete else {
                enrollmentOperation = .failed(
                    source: source,
                    message: "Consent must include your first name, last name, and signature."
                )
                return nil
            }
            recovery = nil
        case .recovery:
            guard case .available(let availableRecovery) = enrollmentRecoveryStatus else {
                return nil
            }
            recovery = availableRecovery
        }

        enrollmentOperation = .submitting(source)

        do {
            let enrollment: StudyEnrollment
            switch source {
            case .signedConsent:
                enrollment = try await finalizeSignedConsent()
                pendingConsentCompletion = nil
            case .recovery:
                enrollment = try await consentService.resumeEnrollment(for: study)
                enrollmentRecoveryStatus = .unavailable
            }

            enrollmentOperation = .succeeded(enrollment)
            return enrollment
        } catch {
            if let recovery {
                enrollmentRecoveryStatus = .available(recovery)
            }
            enrollmentOperation = .failed(
                source: source,
                message: Self.userFacingErrorMessage(for: error)
            )
            return nil
        }
    }

    func dismissEnrollmentError() {
        guard case .failed = enrollmentOperation else { return }
        enrollmentOperation = .idle
    }

    private var canBeginEnrollmentOperation: Bool {
        switch enrollmentOperation {
        case .idle, .failed:
            return true
        case .submitting, .succeeded:
            return false
        }
    }

    private func finalizeSignedConsent() async throws -> StudyEnrollment {
        guard let signatureImageData else {
            throw ConsentSubmissionError.missingSignature
        }
        let signatureImageSHA256Hex = artifactGenerator.sha256Hex(for: signatureImageData)

        let consentCompletion: StudyConsentCompletion
        if let pending = pendingConsentCompletion,
           pending.signerGivenName == trimmedFirstName,
           pending.signerFamilyName == trimmedLastName,
           pending.signatureImageSHA256Hex == signatureImageSHA256Hex {
            consentCompletion = pending
        } else {
            let signedAt = now()
            let artifact = try artifactGenerator.generateSignedConsentArtifact(
                definition: definition,
                signerGivenName: trimmedFirstName,
                signerFamilyName: trimmedLastName,
                signedAt: signedAt,
                signatureImageData: signatureImageData
            )

            consentCompletion = StudyConsentCompletion(
                taskIdentifier: definition.consentVersion,
                studySlug: definition.studySlug,
                consentVersion: definition.consentVersion,
                consented: true,
                signerGivenName: trimmedFirstName,
                signerFamilyName: trimmedLastName,
                signedAt: signedAt,
                artifact: artifact,
                researchKitFinishState: nil,
                consentContentSHA256Hex: definition.contentSHA256Hex,
                signatureImageSHA256Hex: signatureImageSHA256Hex,
                collectionMethod: StudyConsentCatalog.nativeCollectionMethod,
                attestationText: definition.attestation.text,
                attestationVersion: definition.attestation.version
            )
            pendingConsentCompletion = consentCompletion
        }

        guard consentCompletion.isValidSignedConsent else {
            throw ConsentSubmissionError.invalidSignedConsent
        }

        return try await consentService.finalizeConsentAndEnroll(
            study: study,
            consent: consentCompletion
        )
    }

    private static func userFacingErrorMessage(for error: Error) -> String {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? "Unable to finish enrollment. Please try again." : message
    }
}

private enum ConsentSubmissionError: LocalizedError {
    case missingSignature
    case invalidSignedConsent

    var errorDescription: String? {
        switch self {
        case .missingSignature:
            return "Draw your signature before enrolling."
        case .invalidSignedConsent:
            return "Consent must include your name, signature, signed PDF, and consent metadata."
        }
    }
}
