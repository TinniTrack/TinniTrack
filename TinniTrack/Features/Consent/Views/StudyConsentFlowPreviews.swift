import SwiftUI

#if DEBUG
#Preview("Landing") {
    StudyConsentFlowPreview()
}

#Preview("Reader") {
    StudyConsentReaderView(
        viewModel: StudyConsentFlowPreviewModel.makeReader(),
        onEnrollmentCompleted: {}
    )
}

#Preview("Signature") {
    StudyConsentSignatureView(
        viewModel: StudyConsentFlowPreviewModel.makeSignature(),
        onEnrollmentCompleted: {},
        exitConsentFlow: {}
    )
}

private struct StudyConsentFlowPreview: View {
    var body: some View {
        StudyConsentFlowView(
            study: Study(
                id: UUID(),
                slug: "study-no-1",
                title: "Study No. 1",
                description: "Baseline tinnitus study",
                status: .recruiting,
                createdAt: nil
            ),
            definition: StudyConsentCatalog.studyNo1,
            consentService: PreviewConsentService(),
            onCompleted: { false }
        )
    }
}

@MainActor
private enum StudyConsentFlowPreviewModel {
    static func makeReader() -> StudyConsentFlowViewModel {
        let model = base()
        model.reviewConsent()
        return model
    }

    static func makeSignature() -> StudyConsentFlowViewModel {
        let model = base()
        model.reviewConsent()
        model.markConsentScrolledToEnd()
        model.continueToSignature()
        model.firstName = "Alex"
        model.lastName = "Morgan"
        return model
    }

    private static func base() -> StudyConsentFlowViewModel {
        StudyConsentFlowViewModel(
            study: Study(
                id: UUID(),
                slug: "study-no-1",
                title: "Study No. 1",
                description: "Baseline tinnitus study",
                status: .recruiting,
                createdAt: nil
            ),
            definition: StudyConsentCatalog.studyNo1,
            consentService: PreviewConsentService()
        )
    }
}

private struct PreviewConsentService: ConsentServiceProtocol {
    func finalizeConsentAndEnroll(study: Study, consent: StudyConsentCompletion) async throws {}
}
#endif
