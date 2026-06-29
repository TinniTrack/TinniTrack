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

        viewModel.reviewConsent()
        viewModel.declineOrCancel()

        #expect(viewModel.state == .dismissed)
        #expect(generator.generateCallCount == 0)
        #expect(await service.finalizeCallCount() == 0)
    }

    @Test
    func consentReaderRequiresScrollBeforeSignatureStep() {
        let viewModel = Self.viewModel()

        viewModel.reviewConsent()
        viewModel.continueToSignature()
        #expect(viewModel.state == .reviewingConsent)

        viewModel.markConsentScrolledToEnd()
        viewModel.continueToSignature()
        #expect(viewModel.state == .signing)
    }

    @Test
    func reviewingConsentResetsPreviousScrollProgress() {
        let viewModel = Self.viewModel()

        viewModel.reviewConsent()
        viewModel.markConsentScrolledToEnd()
        #expect(viewModel.canContinueToSignature)

        viewModel.reviewConsent()
        #expect(viewModel.state == .reviewingConsent)
        #expect(viewModel.canContinueToSignature == false)
    }

    @Test
    func exitConsentFlowReturnsToLandingWithoutDismissingStudyDetails() {
        let viewModel = Self.viewModel()

        viewModel.reviewConsent()
        viewModel.markConsentScrolledToEnd()
        viewModel.continueToSignature()

        viewModel.exitConsentFlowToStudyDetails()

        #expect(viewModel.state == .landing)
        #expect(viewModel.canContinueToSignature == false)
    }

    @Test
    func chromeBackDismissesLandingAndNavigatesWithinConsentFlow() {
        let viewModel = Self.viewModel()

        viewModel.navigateBackOrDismiss()
        #expect(viewModel.state == .dismissed)

        let secondViewModel = Self.viewModel()
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
    func signatureStepRequiresNamesAndSignature() {
        let viewModel = Self.viewModel()
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
    func signatureDestinationRestoresSigningStateAfterReaderRefresh() {
        let viewModel = Self.viewModel()
        viewModel.reviewConsent()
        viewModel.markConsentScrolledToEnd()
        viewModel.continueToSignature()

        viewModel.reviewConsent()
        viewModel.firstName = "Taylor"
        viewModel.lastName = "Rivers"
        viewModel.signatureImageData = Data([1, 2, 3])
        #expect(viewModel.canSignAndEnroll == false)

        viewModel.restoreSignatureStepAfterNavigationPresentation()

        #expect(viewModel.canSignAndEnroll)
    }

    @Test
    func validNativeConsentGeneratesPdfAndFinalizesEnrollment() async {
        let service = MockConsentService()
        let generator = MockConsentArtifactGenerator()
        let viewModel = Self.viewModel(service: service, generator: generator)

        viewModel.reviewConsent()
        viewModel.markConsentScrolledToEnd()
        viewModel.continueToSignature()
        viewModel.firstName = " Taylor "
        viewModel.lastName = " Rivers "
        viewModel.signatureImageData = Data([9, 8, 7])

        await viewModel.signAndEnroll()

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

    private static func viewModel(
        service: MockConsentService = MockConsentService(),
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
