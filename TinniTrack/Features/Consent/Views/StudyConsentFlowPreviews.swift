import SwiftUI

#if DEBUG
#Preview("Landing") {
    StudyConsentFlowPreview()
}

#Preview("Reader") {
    StudyConsentReaderView(
        definition: StudyConsentCatalog.studyNo1,
        visibleSections: StudyConsentCatalog.studyNo1.sections,
        canContinueToSignature: true,
        markConsentReviewed: {},
        continueToSignature: {},
        declineConsent: {}
    )
}

#Preview("Signature") {
    StudyConsentSignatureView(
        definition: StudyConsentCatalog.studyNo1,
        firstName: .constant("Alex"),
        lastName: .constant("Morgan"),
        signatureImageData: .constant(nil),
        canSignAndEnroll: false,
        isFinalizingEnrollment: false,
        clearSignature: {},
        signAndEnroll: {},
        declineConsent: {}
    )
}

private struct StudyConsentFlowPreview: View {
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
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
                navigationPath: $navigationPath,
                onCompleted: { _ in }
            )
        }
    }
}

private struct PreviewConsentService: ConsentServiceProtocol {
    func finalizeConsentAndEnroll(
        study: Study,
        consent: StudyConsentCompletion
    ) async throws -> StudyEnrollment {
        StudyEnrollment(
            id: UUID(),
            userID: UUID(),
            studyID: study.id,
            status: .enrolled,
            enrolledAt: Date(),
            createdAt: Date()
        )
    }
}
#endif
