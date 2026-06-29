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

    enum State: Equatable {
        case landing
        case reviewingConsent
        case signing
        case finalizing
        case completed
        case dismissed
        case failed
    }

    private let study: Study
    let definition: StudyConsentDefinition
    private let consentService: ConsentServiceProtocol
    private let artifactGenerator: ConsentArtifactGenerating
    private let now: () -> Date

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
        isSignatureFormComplete
            && state != .finalizing
            && state != .completed
            && state != .dismissed
    }

    func reviewConsent() {
        guard state != .finalizing else { return }
        resetConsentReviewProgress()
        state = .reviewingConsent
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
        guard state != .finalizing else { return }
        state = .signing
    }

    func exitConsentFlowToStudyDetails() {
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
        state = .dismissed
    }

    func clearSignature() {
        signatureImageData = nil
    }

    private func resetConsentReviewProgress() {
        hasScrolledToConsentEnd = false
    }

    func signAndEnroll() async {
        guard canSignAndEnroll else { return }
        guard definition.studySlug == study.slug else {
            fail(message: ConsentServiceError.studyMismatch.localizedDescription)
            return
        }

        let signedAt = now()
        guard let signatureImageData else {
            fail(message: "Draw your signature before enrolling.")
            return
        }

        state = .finalizing

        do {
            let artifact = try artifactGenerator.generateSignedConsentArtifact(
                definition: definition,
                signerGivenName: trimmedFirstName,
                signerFamilyName: trimmedLastName,
                signedAt: signedAt,
                signatureImageData: signatureImageData
            )

            let consentCompletion = StudyConsentCompletion(
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
                signatureImageSHA256Hex: artifactGenerator.sha256Hex(for: signatureImageData),
                collectionMethod: StudyConsentCatalog.nativeCollectionMethod,
                attestationText: definition.attestation.text,
                attestationVersion: definition.attestation.version
            )

            guard consentCompletion.isValidSignedConsent else {
                fail(message: "Consent must include your name, signature, signed PDF, and consent metadata.")
                return
            }

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
        errorMessage = nil
        state = .signing
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
