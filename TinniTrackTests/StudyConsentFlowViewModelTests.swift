import Foundation
import Testing
@testable import TinniTrack

@MainActor
struct StudyConsentFlowViewModelTests {
    @Test
    func declineDismissesWithoutGeneratingPdfOrFinalizing() async {
        let service = MockConsentService()
        let generator = MockConsentArtifactGenerator()
        let viewModel = Self.viewModel(service: service, generator: generator)

        await viewModel.probeEnrollmentRecovery()
        viewModel.reviewConsent()
        viewModel.declineOrCancel()

        #expect(viewModel.state == .dismissed)
        #expect(generator.generateCallCount == 0)
        #expect(await service.finalizeCallCount() == 0)
    }

    @Test
    func consentReaderRequiresScrollBeforeSignatureStep() async {
        let viewModel = Self.viewModel()

        await viewModel.probeEnrollmentRecovery()
        viewModel.reviewConsent()
        viewModel.continueToSignature()
        #expect(viewModel.state == .reviewingConsent)

        viewModel.markConsentScrolledToEnd()
        viewModel.continueToSignature()
        #expect(viewModel.state == .signing)
    }

    @Test
    func reviewingConsentResetsPreviousScrollProgress() async {
        let viewModel = Self.viewModel()

        await viewModel.probeEnrollmentRecovery()
        viewModel.reviewConsent()
        viewModel.markConsentScrolledToEnd()
        #expect(viewModel.canContinueToSignature)

        viewModel.reviewConsent()
        #expect(viewModel.state == .reviewingConsent)
        #expect(viewModel.canContinueToSignature == false)
    }

    @Test
    func exitConsentFlowReturnsToLandingWithoutDismissingStudyDetails() async {
        let viewModel = Self.viewModel()

        await viewModel.probeEnrollmentRecovery()
        viewModel.reviewConsent()
        viewModel.markConsentScrolledToEnd()
        viewModel.continueToSignature()

        viewModel.exitConsentFlowToStudyDetails()

        #expect(viewModel.state == .landing)
        #expect(viewModel.canContinueToSignature == false)
    }

    @Test
    func chromeBackDismissesLandingAndNavigatesWithinConsentFlow() async {
        let viewModel = Self.viewModel()

        viewModel.navigateBackOrDismiss()
        #expect(viewModel.state == .dismissed)

        let secondViewModel = Self.viewModel()
        await secondViewModel.probeEnrollmentRecovery()
        secondViewModel.reviewConsent()
        secondViewModel.navigateBackOrDismiss()
        #expect(secondViewModel.state == .landing)

        secondViewModel.reviewConsent()
        secondViewModel.markConsentScrolledToEnd()
        secondViewModel.continueToSignature()
        secondViewModel.navigateBackOrDismiss()
        #expect(secondViewModel.state == .reviewingConsent)
        #expect(secondViewModel.canContinueToSignature == false)
    }

    @Test
    func signatureStepRequiresNamesAndSignature() async {
        let viewModel = Self.viewModel()
        await viewModel.probeEnrollmentRecovery()
        viewModel.reviewConsent()
        viewModel.markConsentScrolledToEnd()
        viewModel.continueToSignature()

        #expect(viewModel.canSignAndEnroll == false)

        viewModel.firstName = "Taylor"
        viewModel.lastName = "Rivers"
        #expect(viewModel.canSignAndEnroll == false)

        viewModel.signatureImageData = Data([1, 2, 3])
        #expect(viewModel.canSignAndEnroll)
    }

    @Test
    func signatureDestinationRestoresSigningStateAfterReaderRefresh() async {
        let viewModel = Self.viewModel()
        await viewModel.probeEnrollmentRecovery()
        viewModel.reviewConsent()
        viewModel.markConsentScrolledToEnd()
        viewModel.continueToSignature()

        viewModel.reviewConsent()
        viewModel.firstName = "Taylor"
        viewModel.lastName = "Rivers"
        viewModel.signatureImageData = Data([1, 2, 3])
        #expect(viewModel.canSignAndEnroll == false)

        viewModel.restoreSignatureStepAfterNavigationPresentation()

        #expect(viewModel.state == .signing)
        #expect(viewModel.canSignAndEnroll)
    }

    @Test
    func signatureFirstAndNameEditsStillFinalizeSuccessfully() async {
        let service = MockConsentService()
        let generator = MockConsentArtifactGenerator()
        let viewModel = Self.viewModel(service: service, generator: generator)

        await viewModel.probeEnrollmentRecovery()
        viewModel.reviewConsent()
        viewModel.markConsentScrolledToEnd()
        viewModel.continueToSignature()

        viewModel.signatureImageData = Data([9, 8, 7])
        viewModel.firstName = "   "
        viewModel.lastName = "Draft"
        #expect(viewModel.canSignAndEnroll == false)

        viewModel.firstName = "Alex"
        viewModel.lastName = ""
        #expect(viewModel.canSignAndEnroll == false)

        viewModel.lastName = "Rivers"
        #expect(viewModel.canSignAndEnroll)

        let didComplete = await viewModel.signAndEnroll()

        #expect(didComplete)
        #expect(viewModel.state == .completed)
        #expect(viewModel.canSignAndEnroll == false)
        #expect(generator.generateCallCount == 1)
        #expect(await service.finalizeCallCount() == 1)
    }

    @Test
    func signaturePresentationCannotRestoreCompletedState() async {
        let viewModel = Self.viewModel()

        await viewModel.probeEnrollmentRecovery()
        viewModel.reviewConsent()
        viewModel.markConsentScrolledToEnd()
        viewModel.continueToSignature()
        viewModel.signatureImageData = Data([9, 8, 7])
        viewModel.firstName = "Alex"
        viewModel.lastName = "Rivers"
        #expect(await viewModel.signAndEnroll())

        viewModel.restoreSignatureStepAfterNavigationPresentation()

        #expect(viewModel.state == .completed)
        #expect(viewModel.canSignAndEnroll == false)
    }

    @Test
    func finalizingConsentDisablesRepeatSubmission() async {
        let service = BlockingConsentService()
        let generator = MockConsentArtifactGenerator()
        let viewModel = Self.viewModel(service: service, generator: generator)

        await viewModel.probeEnrollmentRecovery()
        viewModel.reviewConsent()
        viewModel.markConsentScrolledToEnd()
        viewModel.continueToSignature()
        viewModel.firstName = "Taylor"
        viewModel.lastName = "Rivers"
        viewModel.signatureImageData = Data([1, 2, 3])

        let submissionTask = Task {
            await viewModel.signAndEnroll()
        }

        while await service.finalizeCallCount() == 0 {
            await Task.yield()
        }

        #expect(viewModel.state == .finalizing)
        #expect(viewModel.canSignAndEnroll == false)

        let duplicateDidComplete = await viewModel.signAndEnroll()
        #expect(duplicateDidComplete == false)
        #expect(await service.finalizeCallCount() == 1)

        await service.unblock()
        let firstDidComplete = await submissionTask.value
        #expect(firstDidComplete)
    }

    @Test
    func validNativeConsentGeneratesPdfAndFinalizesEnrollment() async {
        let service = MockConsentService()
        let generator = MockConsentArtifactGenerator()
        let viewModel = Self.viewModel(service: service, generator: generator)

        await viewModel.probeEnrollmentRecovery()
        viewModel.reviewConsent()
        viewModel.markConsentScrolledToEnd()
        viewModel.continueToSignature()
        viewModel.firstName = " Taylor "
        viewModel.lastName = " Rivers "
        viewModel.signatureImageData = Data([9, 8, 7])

        let didComplete = await viewModel.signAndEnroll()

        #expect(didComplete)
        #expect(viewModel.state == .completed)
        #expect(generator.generateCallCount == 1)
        #expect(await service.finalizeCallCount() == 1)
        let consent = await service.lastConsent()
        #expect(consent?.signerGivenName == "Taylor")
        #expect(consent?.signerFamilyName == "Rivers")
        #expect(consent?.consentVersion == "study-no-1-consent-v2")
        #expect(consent?.consentContentSHA256Hex == StudyConsentCatalog.studyNo1.contentSHA256Hex)
        #expect(consent?.collectionMethod == StudyConsentCatalog.nativeCollectionMethod)
        #expect(consent?.researchKitFinishState == nil)
    }

    @Test
    func unavailableRecoveryEnablesStartingNewConsent() async {
        let service = RecoveryUnavailableConsentService()
        let viewModel = Self.viewModel(service: service)

        #expect(viewModel.canReviewConsent == false)
        viewModel.reviewConsent()
        #expect(viewModel.state == .landing)

        await viewModel.probeEnrollmentRecovery()

        #expect(viewModel.canReviewConsent)
        viewModel.reviewConsent()
        #expect(viewModel.state == .reviewingConsent)
    }

    @Test
    func availableRecoveryBlocksNewConsentAndResumesWithoutGeneratingPdf() async {
        let service = BlockingEnrollmentRecoveryConsentService()
        let generator = MockConsentArtifactGenerator()
        let viewModel = Self.viewModel(service: service, generator: generator)

        await viewModel.probeEnrollmentRecovery()

        #expect(viewModel.hasAvailableEnrollmentRecovery)
        #expect(viewModel.canReviewConsent == false)
        viewModel.reviewConsent()
        #expect(viewModel.state == .landing)

        let resumeTask = Task {
            await viewModel.resumeEnrollment()
        }
        while await service.resumeCallCount() == 0 {
            await Task.yield()
        }

        #expect(viewModel.state == .finalizing)
        #expect(generator.generateCallCount == 0)

        await service.unblockResume()
        _ = await resumeTask.value

        #expect(viewModel.state == .completed)
        #expect(generator.generateCallCount == 0)
        #expect(await service.finalizeCallCount() == 0)
    }

    @Test
    func recoveryProbeFailureBlocksReviewUntilRetrySucceeds() async {
        let service = FailOnceRecoveryProbeConsentService()
        let viewModel = Self.viewModel(service: service)

        await viewModel.probeEnrollmentRecovery()

        guard case .failed(let message) = viewModel.enrollmentRecoveryStatus else {
            Issue.record("Expected a failed recovery probe")
            return
        }
        #expect(message.isEmpty == false)
        #expect(viewModel.canReviewConsent == false)
        viewModel.reviewConsent()
        #expect(viewModel.state == .landing)

        await viewModel.retryEnrollmentRecoveryProbe()

        #expect(viewModel.canReviewConsent)
        #expect(await service.probeCallCount() == 2)
    }

    @Test
    func resumeFailureReturnsToLandingWithRecoveryAndAlert() async {
        let service = ResumeFailingRecoveryConsentService()
        let generator = MockConsentArtifactGenerator()
        let viewModel = Self.viewModel(service: service, generator: generator)

        await viewModel.probeEnrollmentRecovery()
        await viewModel.resumeEnrollment()

        #expect(viewModel.state == .landing)
        #expect(viewModel.hasAvailableEnrollmentRecovery)
        #expect(viewModel.errorMessage?.isEmpty == false)
        #expect(viewModel.shouldRetryEnrollmentRecoveryFromAlert)
        #expect(generator.generateCallCount == 0)
    }

    @Test
    func retryReusesExactSignedArtifactAfterFinalizationFailure() async throws {
        let service = FailOnceConsentService()
        let generator = MockConsentArtifactGenerator()
        let viewModel = Self.viewModel(service: service, generator: generator)

        await viewModel.probeEnrollmentRecovery()
        viewModel.reviewConsent()
        viewModel.markConsentScrolledToEnd()
        viewModel.continueToSignature()
        viewModel.firstName = "Taylor"
        viewModel.lastName = "Rivers"
        viewModel.signatureImageData = Data([9, 8, 7])

        await viewModel.signAndEnroll()
        #expect(viewModel.state == .failed)

        viewModel.retryAfterFailure()
        await viewModel.signAndEnroll()

        let attempts = await service.capturedConsents()
        #expect(viewModel.state == .completed)
        #expect(generator.generateCallCount == 1)
        #expect(attempts.count == 2)
        let firstAttempt = try #require(attempts.first)
        let retryAttempt = try #require(attempts.last)
        #expect(firstAttempt == retryAttempt)
    }

    private static func viewModel(
        service: any ConsentServiceProtocol = MockConsentService(),
        generator: MockConsentArtifactGenerator = MockConsentArtifactGenerator()
    ) -> StudyConsentFlowViewModel {
        StudyConsentFlowViewModel(
            study: Self.study,
            definition: StudyConsentCatalog.studyNo1,
            consentService: service,
            artifactGenerator: generator,
            now: { Date(timeIntervalSince1970: 1_750_000_000) }
        )
    }

    private static let study = Study(
        id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
        slug: "study-no-1",
        title: "Study No. 1",
        description: "Baseline tinnitus study",
        status: .recruiting,
        createdAt: nil
    )
}

private actor MockConsentService: ConsentServiceProtocol {
    private var callCount = 0
    private var capturedConsent: StudyConsentCompletion?

    func finalizeConsentAndEnroll(
        study: Study,
        consent: StudyConsentCompletion
    ) async throws {
        callCount += 1
        capturedConsent = consent
    }

    func finalizeCallCount() -> Int {
        callCount
    }

    func lastConsent() -> StudyConsentCompletion? {
        capturedConsent
    }
}

private actor BlockingConsentService: ConsentServiceProtocol {
    private var callCount = 0
    private var continuation: CheckedContinuation<Void, Never>?

    func finalizeConsentAndEnroll(
        study: Study,
        consent: StudyConsentCompletion
    ) async throws {
        callCount += 1
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func finalizeCallCount() -> Int {
        callCount
    }

    func unblock() {
        continuation?.resume()
        continuation = nil
    }
}

private actor FailOnceConsentService: ConsentServiceProtocol {
    private var attempts: [StudyConsentCompletion] = []

    func finalizeConsentAndEnroll(
        study: Study,
        consent: StudyConsentCompletion
    ) async throws {
        attempts.append(consent)
        if attempts.count == 1 {
            throw Failure.unavailable
        }
    }

    func capturedConsents() -> [StudyConsentCompletion] {
        attempts
    }

    private enum Failure: Error {
        case unavailable
    }
}

private actor RecoveryUnavailableConsentService: ConsentServiceProtocol {
    func availableEnrollmentRecovery(for study: Study) async throws -> ConsentEnrollmentRecovery? {
        nil
    }

    func resumeEnrollment(for study: Study) async throws {}

    func finalizeConsentAndEnroll(
        study: Study,
        consent: StudyConsentCompletion
    ) async throws {}
}

private actor BlockingEnrollmentRecoveryConsentService: ConsentServiceProtocol {
    private var resumeCount = 0
    private var finalizeCount = 0
    private var resumeContinuation: CheckedContinuation<Void, Never>?

    func availableEnrollmentRecovery(for study: Study) async throws -> ConsentEnrollmentRecovery? {
        .pendingUpload
    }

    func resumeEnrollment(for study: Study) async throws {
        resumeCount += 1
        await withCheckedContinuation { continuation in
            resumeContinuation = continuation
        }
    }

    func finalizeConsentAndEnroll(
        study: Study,
        consent: StudyConsentCompletion
    ) async throws {
        finalizeCount += 1
    }

    func resumeCallCount() -> Int {
        resumeCount
    }

    func finalizeCallCount() -> Int {
        finalizeCount
    }

    func unblockResume() {
        resumeContinuation?.resume()
        resumeContinuation = nil
    }
}

private actor FailOnceRecoveryProbeConsentService: ConsentServiceProtocol {
    private var probeCount = 0

    func availableEnrollmentRecovery(for study: Study) async throws -> ConsentEnrollmentRecovery? {
        probeCount += 1
        if probeCount == 1 {
            throw Failure.unavailable
        }
        return nil
    }

    func resumeEnrollment(for study: Study) async throws {}

    func finalizeConsentAndEnroll(
        study: Study,
        consent: StudyConsentCompletion
    ) async throws {}

    func probeCallCount() -> Int {
        probeCount
    }

    private enum Failure: Error {
        case unavailable
    }
}

private actor ResumeFailingRecoveryConsentService: ConsentServiceProtocol {
    func availableEnrollmentRecovery(for study: Study) async throws -> ConsentEnrollmentRecovery? {
        .pendingEnrollment
    }

    func resumeEnrollment(for study: Study) async throws {
        throw Failure.unavailable
    }

    func finalizeConsentAndEnroll(
        study: Study,
        consent: StudyConsentCompletion
    ) async throws {}

    private enum Failure: Error {
        case unavailable
    }
}

private final class MockConsentArtifactGenerator: ConsentArtifactGenerating {
    private(set) var generateCallCount = 0

    func generateSignedConsentArtifact(
        definition: StudyConsentDefinition,
        signerGivenName: String,
        signerFamilyName: String,
        signedAt: Date,
        signatureImageData: Data
    ) throws -> StudyConsentArtifact {
        generateCallCount += 1
        return StudyConsentArtifact(
            pdfData: Data([0x25, 0x50, 0x44, 0x46]),
            pdfSHA256Hex: String(repeating: "a", count: 64),
            storageBucket: StudyConsentCatalog.consentStorageBucket,
            storagePath: ""
        )
    }

    func sha256Hex(for data: Data) -> String {
        String(repeating: "c", count: 64)
    }
}
