//
//  StudyConsentFlowViewModel.swift
//  TinniTrack
//

import Combine
import Foundation

@MainActor
final class StudyConsentFlowViewModel: ObservableObject {
    @Published private(set) var state: State = .landing
    @Published var errorMessage: String?
    @Published var hasScrolledToConsentEnd = false
    @Published var firstName = ""
    @Published var lastName = ""
    @Published var signatureImageData: Data?
    @Published private(set) var enrollmentRecoveryStatus: EnrollmentRecoveryStatus = .notChecked

    enum State: Equatable {
        case landing
        case reviewingConsent
        case signing
        case finalizing
        case completed
        case dismissed
        case failed
    }

    enum EnrollmentRecoveryStatus {
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
        guard state == .landing else { return false }
        guard case .unavailable = enrollmentRecoveryStatus else { return false }
        return true
    }

    var hasAvailableEnrollmentRecovery: Bool {
        guard case .available = enrollmentRecoveryStatus else { return false }
        return true
    }

    var canResumeEnrollment: Bool {
        state == .landing && hasAvailableEnrollmentRecovery
    }

    var shouldRetryEnrollmentRecoveryFromAlert: Bool {
        errorMessage != nil && state == .landing && hasAvailableEnrollmentRecovery
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
        isSignatureFormComplete && state == .signing
    }

    func reviewConsent() {
        guard canReviewConsent || state == .reviewingConsent || state == .signing else { return }
        resetConsentReviewProgress()
        state = .reviewingConsent
    }

    func probeEnrollmentRecoveryIfNeeded() async {
        guard case .notChecked = enrollmentRecoveryStatus else { return }
        await probeEnrollmentRecovery()
    }

    func probeEnrollmentRecovery() async {
        guard state == .landing else { return }
        enrollmentRecoveryStatus = .checking

        do {
            let recovery = try await consentService.availableEnrollmentRecovery(for: study)
            guard !Task.isCancelled, state == .landing else { return }
            if let recovery {
                enrollmentRecoveryStatus = .available(recovery)
            } else {
                enrollmentRecoveryStatus = .unavailable
            }
        } catch is CancellationError {
            guard state == .landing else { return }
            enrollmentRecoveryStatus = .notChecked
        } catch {
            guard state == .landing else { return }
            enrollmentRecoveryStatus = .failed(
                message: Self.userFacingErrorMessage(for: error)
            )
        }
    }

    func retryEnrollmentRecoveryProbe() async {
        guard case .failed = enrollmentRecoveryStatus else { return }
        await probeEnrollmentRecovery()
    }

    @discardableResult
    func resumeEnrollment() async -> Bool {
        guard canResumeEnrollment else { return false }
        guard case .available(let recovery) = enrollmentRecoveryStatus else { return false }

        errorMessage = nil
        state = .finalizing

        do {
            try await consentService.resumeEnrollment(for: study)
            enrollmentRecoveryStatus = .unavailable
            state = .completed
            return true
        } catch {
            enrollmentRecoveryStatus = .available(recovery)
            state = .landing
            errorMessage = Self.userFacingErrorMessage(for: error)
            return false
        }
    }

    func returnToLandingAfterNavigationPop() {
        switch state {
        case .reviewingConsent, .signing:
            resetConsentReviewProgress()
            state = .landing
        case .landing, .finalizing, .completed, .dismissed, .failed:
            break
        }
    }

    func markConsentScrolledToEnd() {
        hasScrolledToConsentEnd = true
    }

    func continueToSignature() {
        guard canContinueToSignature else { return }
        state = .signing
    }

    func restoreSignatureStepAfterNavigationPresentation() {
        guard state == .reviewingConsent || state == .signing else { return }
        state = .signing
    }

    func exitConsentFlowToStudyDetails() {
        pendingConsentCompletion = nil
        resetConsentReviewProgress()
        state = .landing
    }

    func goBack() {
        switch state {
        case .reviewingConsent:
            resetConsentReviewProgress()
            state = .landing
        case .signing:
            resetConsentReviewProgress()
            state = .reviewingConsent
        case .landing, .finalizing, .completed, .dismissed, .failed:
            break
        }
    }

    func navigateBackOrDismiss() {
        switch state {
        case .landing:
            declineOrCancel()
        case .reviewingConsent, .signing:
            goBack()
        case .finalizing, .completed, .dismissed, .failed:
            break
        }
    }

    func declineOrCancel() {
        pendingConsentCompletion = nil
        state = .dismissed
    }

    func clearSignature() {
        pendingConsentCompletion = nil
        signatureImageData = nil
    }

    private func resetConsentReviewProgress() {
        hasScrolledToConsentEnd = false
    }

    @discardableResult
    func signAndEnroll() async -> Bool {
        guard canSignAndEnroll else { return false }
        guard definition.studySlug == study.slug else {
            fail(message: ConsentServiceError.studyMismatch.localizedDescription)
            return false
        }

        guard let signatureImageData else {
            fail(message: "Draw your signature before enrolling.")
            return false
        }
        let signatureImageSHA256Hex = artifactGenerator.sha256Hex(for: signatureImageData)

        state = .finalizing

        do {
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
                fail(message: "Consent must include your name, signature, signed PDF, and consent metadata.")
                return false
            }

            try await consentService.finalizeConsentAndEnroll(
                study: study,
                consent: consentCompletion
            )
            pendingConsentCompletion = nil
            state = .completed
            return true
        } catch {
            fail(message: Self.userFacingErrorMessage(for: error))
            return false
        }
    }

    func retryAfterFailure() {
        errorMessage = nil
        state = .signing
    }

    func dismissEnrollmentRecoveryError() {
        errorMessage = nil
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
