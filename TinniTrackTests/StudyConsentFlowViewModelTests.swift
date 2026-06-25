import Foundation
import Testing
@testable import TinniTrack

@MainActor
struct StudyConsentFlowViewModelTests {
    @Test
    func discardedConsentDismissesWithoutFinalizing() async {
        let service = MockConsentService()
        let viewModel = StudyConsentFlowViewModel(
            study: Self.study,
            consentService: service
        )

        await viewModel.handleResearchKitResult(Self.summary(
            finishState: .discarded,
            consented: false
        ))

        #expect(viewModel.state == .dismissed)
        #expect(await service.finalizeCallCount() == 0)
    }

    @Test
    func declinedConsentDismissesWithoutFinalizing() async {
        let service = MockConsentService()
        let viewModel = StudyConsentFlowViewModel(
            study: Self.study,
            consentService: service
        )

        await viewModel.handleResearchKitResult(Self.summary(
            finishState: .completed,
            consented: false
        ))

        #expect(viewModel.state == .dismissed)
        #expect(await service.finalizeCallCount() == 0)
    }

    @Test
    func validCompletedConsentFinalizesEnrollment() async {
        let service = MockConsentService()
        let viewModel = StudyConsentFlowViewModel(
            study: Self.study,
            consentService: service
        )

        await viewModel.handleResearchKitResult(Self.summary(
            finishState: .completed,
            consented: true
        ))

        #expect(viewModel.state == .completed)
        #expect(await service.finalizeCallCount() == 1)
    }

    private static let study = Study(
        id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
        slug: "study-no-1",
        title: "Study No. 1",
        description: "Baseline tinnitus study",
        status: .recruiting,
        createdAt: nil
    )

    private static func summary(
        finishState: ResearchTaskFinishState,
        consented: Bool
    ) -> ResearchKitTaskResultSummary {
        ResearchKitTaskResultSummary(
            taskIdentifier: "study-no-1-consent-v1",
            finishState: finishState,
            errorDescription: nil,
            studyNo1OrientationThreshold: nil,
            studyConsent: StudyConsentResultSummary(
                taskIdentifier: "study-no-1-consent-v1",
                studySlug: "study-no-1",
                consentVersion: "study-no-1-consent-v1",
                consented: consented,
                givenName: "Taylor",
                familyName: "Rivers",
                signedAt: Date(timeIntervalSince1970: 1_750_000_000),
                pdfData: Data([1, 2, 3]),
                pdfSHA256Hex: String(repeating: "a", count: 64),
                finishState: finishState
            )
        )
    }
}

private actor MockConsentService: ConsentServiceProtocol {
    private var callCount = 0

    func finalizeConsentAndEnroll(
        study: Study,
        consent: StudyConsentCompletion
    ) async throws {
        callCount += 1
    }

    func finalizeCallCount() -> Int {
        callCount
    }
}
