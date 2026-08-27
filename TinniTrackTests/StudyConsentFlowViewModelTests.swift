import Foundation
import Testing
@testable import TinniTrack

@MainActor
struct StudyConsentFlowViewModelTests {
    @Test
    func routeBindingsOwnLandingReviewAndSignatureTransitions() {
        var route = StudyConsentRoute.landing

        route.setReviewPresented(true)
        #expect(route == .review)
        #expect(route.presentsReview)
        #expect(route.presentsSignature == false)

        route.setSignaturePresented(true)
        #expect(route == .signature)
        #expect(route.presentsReview)
        #expect(route.presentsSignature)

        route.setSignaturePresented(false)
        #expect(route == .review)

        route.setReviewPresented(false)
        #expect(route == .landing)
        #expect(route.presentsReview == false)
    }

    @Test
    func routeIgnoresInvalidPresentationAndStaysStableDuringCancelledPop() {
        var route = StudyConsentRoute.landing
        route.setSignaturePresented(true)
        #expect(route == .landing)

        route.setReviewPresented(true)
        route.setSignaturePresented(true)
        let routeBeforeCancelledEdgeSwipe = route

        #expect(routeBeforeCancelledEdgeSwipe == .signature)
        #expect(route == .signature)
    }

    @Test
    func reviewProgressIsIndependentFromEnrollmentOperation() async {
        let viewModel = Self.viewModel()
        await viewModel.probeEnrollmentRecovery()

        #expect(viewModel.canReviewConsent)
        #expect(viewModel.canContinueToSignature == false)

        viewModel.markConsentScrolledToEnd()
        #expect(viewModel.canContinueToSignature)

        viewModel.prepareConsentReview()
        #expect(viewModel.canContinueToSignature == false)
        #expect(viewModel.enrollmentOperation == .idle)
    }

    @Test
    func abandoningConsentReturnsOperationToIdleWithoutClearingFormState() async {
        let service = MockConsentService()
        let generator = MockConsentArtifactGenerator()
        let viewModel = Self.viewModel(service: service, generator: generator)
        viewModel.firstName = "Taylor"
        viewModel.lastName = "Rivers"
        viewModel.signatureImageData = Data([1, 2, 3])
        viewModel.markConsentScrolledToEnd()

        viewModel.abandonConsentAttempt()

        #expect(viewModel.enrollmentOperation == .idle)
        #expect(viewModel.canContinueToSignature == false)
        #expect(viewModel.firstName == "Taylor")
        #expect(viewModel.lastName == "Rivers")
        #expect(viewModel.signatureImageData == Data([1, 2, 3]))
        #expect(generator.generateCallCount == 0)
        #expect(await service.finalizeCallCount() == 0)
    }

    @Test
    func signatureFirstAndNameChurnReturnsCanonicalEnrollment() async {
        let expectedEnrollment = makeEnrollment(for: Self.study)
        let service = MockConsentService(enrollment: expectedEnrollment)
        let generator = MockConsentArtifactGenerator()
        let viewModel = Self.viewModel(service: service, generator: generator)

        viewModel.signatureImageData = Data([9, 8, 7])
        viewModel.firstName = "   "
        viewModel.lastName = "Draft"
        #expect(viewModel.canSignAndEnroll == false)

        viewModel.firstName = "Alex"
        viewModel.lastName = ""
        #expect(viewModel.canSignAndEnroll == false)

        viewModel.lastName = "Rivers"
        #expect(viewModel.canSignAndEnroll)

        let enrollment = await viewModel.completeEnrollment(using: .signedConsent)

        #expect(enrollment == expectedEnrollment)
        #expect(viewModel.enrollmentOperation == .succeeded(expectedEnrollment))
        #expect(viewModel.canSignAndEnroll == false)
        #expect(generator.generateCallCount == 1)
        #expect(await service.finalizeCallCount() == 1)
    }

    @Test
    func signedConsentUsesTrimmedNamesAndExpectedMetadata() async {
        let service = MockConsentService()
        let generator = MockConsentArtifactGenerator()
        let viewModel = Self.viewModel(service: service, generator: generator)
        viewModel.firstName = " Taylor "
        viewModel.lastName = " Rivers "
        viewModel.signatureImageData = Data([9, 8, 7])

        let enrollment = await viewModel.completeEnrollment(using: .signedConsent)

        #expect(enrollment == makeEnrollment(for: Self.study))
        #expect(generator.generateCallCount == 1)
        let consent = await service.lastConsent()
        #expect(consent?.signerGivenName == "Taylor")
        #expect(consent?.signerFamilyName == "Rivers")
        #expect(consent?.consentVersion == "study-no-1-consent-v2")
        #expect(consent?.consentContentSHA256Hex == StudyConsentCatalog.studyNo1.contentSHA256Hex)
        #expect(consent?.collectionMethod == StudyConsentCatalog.nativeCollectionMethod)
        #expect(consent?.researchKitFinishState == nil)
    }

    @Test
    func concurrentFreshSubmissionsPersistOnceAndReturnOneSuccess() async {
        let expectedEnrollment = makeEnrollment(for: Self.study)
        let service = BlockingConsentService(enrollment: expectedEnrollment)
        let generator = MockConsentArtifactGenerator()
        let viewModel = Self.viewModel(service: service, generator: generator)
        viewModel.firstName = "Taylor"
        viewModel.lastName = "Rivers"
        viewModel.signatureImageData = Data([1, 2, 3])

        let firstSubmission = Task { @MainActor in
            await viewModel.completeEnrollment(using: .signedConsent)
        }
        await service.waitUntilFinalizeStarts()

        #expect(viewModel.enrollmentOperation == .submitting(.signedConsent))
        #expect(viewModel.canSignAndEnroll == false)
        let duplicateResult = await viewModel.completeEnrollment(using: .signedConsent)
        #expect(duplicateResult == nil)
        #expect(await service.finalizeCallCount() == 1)

        await service.unblock()
        let firstResult = await firstSubmission.value

        #expect(firstResult == expectedEnrollment)
        #expect(viewModel.enrollmentOperation == .succeeded(expectedEnrollment))
        #expect(generator.generateCallCount == 1)
        #expect(await service.finalizeCallCount() == 1)
    }

    @Test
    func retryReusesExactSignedArtifactAndReturnsCanonicalEnrollment() async throws {
        let expectedEnrollment = makeEnrollment(for: Self.study)
        let service = FailOnceConsentService(enrollment: expectedEnrollment)
        let generator = MockConsentArtifactGenerator()
        let viewModel = Self.viewModel(service: service, generator: generator)
        viewModel.firstName = "Taylor"
        viewModel.lastName = "Rivers"
        viewModel.signatureImageData = Data([9, 8, 7])

        let failedResult = await viewModel.completeEnrollment(using: .signedConsent)
        #expect(failedResult == nil)
        guard case .failed(.signedConsent, let message) = viewModel.enrollmentOperation else {
            Issue.record("Expected signed-consent failure")
            return
        }
        #expect(message.isEmpty == false)
        #expect(viewModel.canSignAndEnroll)

        viewModel.dismissEnrollmentError()
        let enrollment = await viewModel.completeEnrollment(using: .signedConsent)

        let attempts = await service.capturedConsents()
        #expect(enrollment == expectedEnrollment)
        #expect(viewModel.enrollmentOperation == .succeeded(expectedEnrollment))
        #expect(generator.generateCallCount == 1)
        #expect(attempts.count == 2)
        let firstAttempt = try #require(attempts.first)
        let retryAttempt = try #require(attempts.last)
        #expect(firstAttempt == retryAttempt)
    }

    @Test
    func cancelToLandingAfterFailurePreservesExactArtifactForReentry() async throws {
        let expectedEnrollment = makeEnrollment(for: Self.study)
        let service = FailOnceConsentService(enrollment: expectedEnrollment)
        let generator = MockConsentArtifactGenerator()
        let viewModel = Self.viewModel(service: service, generator: generator)
        viewModel.firstName = "Taylor"
        viewModel.lastName = "Rivers"
        viewModel.signatureImageData = Data([9, 8, 7])

        let failedResult = await viewModel.completeEnrollment(using: .signedConsent)
        #expect(failedResult == nil)

        viewModel.abandonConsentAttempt()
        #expect(viewModel.enrollmentOperation == .idle)

        let enrollment = await viewModel.completeEnrollment(using: .signedConsent)

        let attempts = await service.capturedConsents()
        #expect(enrollment == expectedEnrollment)
        #expect(generator.generateCallCount == 1)
        #expect(attempts.count == 2)
        let firstAttempt = try #require(attempts.first)
        let reentryAttempt = try #require(attempts.last)
        #expect(firstAttempt == reentryAttempt)
    }

    @Test
    func availableRecoveryReturnsCanonicalEnrollmentWithoutGeneratingArtifact() async {
        let expectedEnrollment = makeEnrollment(for: Self.study)
        let service = RecoveryConsentService(enrollment: expectedEnrollment)
        let generator = MockConsentArtifactGenerator()
        let viewModel = Self.viewModel(service: service, generator: generator)

        await viewModel.probeEnrollmentRecovery()
        #expect(viewModel.hasAvailableEnrollmentRecovery)
        #expect(viewModel.canReviewConsent == false)

        let enrollment = await viewModel.completeEnrollment(using: .recovery)

        #expect(enrollment == expectedEnrollment)
        #expect(viewModel.enrollmentOperation == .succeeded(expectedEnrollment))
        #expect(viewModel.enrollmentRecoveryStatus == .unavailable)
        #expect(generator.generateCallCount == 0)
        #expect(await service.resumeCallCount() == 1)
        #expect(await service.finalizeCallCount() == 0)
    }

    @Test
    func concurrentRecoveryAttemptsResumeOnceAndReturnOneSuccess() async {
        let expectedEnrollment = makeEnrollment(for: Self.study)
        let service = BlockingRecoveryConsentService(enrollment: expectedEnrollment)
        let viewModel = Self.viewModel(service: service)
        await viewModel.probeEnrollmentRecovery()

        let firstResume = Task { @MainActor in
            await viewModel.completeEnrollment(using: .recovery)
        }
        await service.waitUntilResumeStarts()

        #expect(viewModel.enrollmentOperation == .submitting(.recovery))
        #expect(viewModel.canResumeEnrollment == false)
        let duplicateResult = await viewModel.completeEnrollment(using: .recovery)
        #expect(duplicateResult == nil)
        #expect(await service.resumeCallCount() == 1)

        await service.unblockResume()
        let firstResult = await firstResume.value

        #expect(firstResult == expectedEnrollment)
        #expect(viewModel.enrollmentOperation == .succeeded(expectedEnrollment))
        #expect(await service.resumeCallCount() == 1)
    }

    @Test
    func recoveryFailureStaysAvailableForRetry() async {
        let service = ResumeFailingRecoveryConsentService()
        let generator = MockConsentArtifactGenerator()
        let viewModel = Self.viewModel(service: service, generator: generator)

        await viewModel.probeEnrollmentRecovery()
        let enrollment = await viewModel.completeEnrollment(using: .recovery)

        #expect(enrollment == nil)
        #expect(viewModel.hasAvailableEnrollmentRecovery)
        #expect(viewModel.errorMessage?.isEmpty == false)
        #expect(viewModel.shouldRetryEnrollmentRecoveryFromAlert)
        #expect(generator.generateCallCount == 0)
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

        await viewModel.retryEnrollmentRecoveryProbe()

        #expect(viewModel.enrollmentRecoveryStatus == .unavailable)
        #expect(viewModel.canReviewConsent)
        #expect(await service.probeCallCount() == 2)
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
    private let enrollment: StudyEnrollment?
    private var callCount = 0
    private var capturedConsent: StudyConsentCompletion?

    init(enrollment: StudyEnrollment? = nil) {
        self.enrollment = enrollment
    }

    func finalizeConsentAndEnroll(
        study: Study,
        consent: StudyConsentCompletion
    ) async throws -> StudyEnrollment {
        callCount += 1
        capturedConsent = consent
        return enrollment ?? makeEnrollment(for: study)
    }

    func finalizeCallCount() -> Int {
        callCount
    }

    func lastConsent() -> StudyConsentCompletion? {
        capturedConsent
    }
}

private actor BlockingConsentService: ConsentServiceProtocol {
    private let enrollment: StudyEnrollment
    private var callCount = 0
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var continuation: CheckedContinuation<Void, Never>?

    init(enrollment: StudyEnrollment) {
        self.enrollment = enrollment
    }

    func finalizeConsentAndEnroll(
        study: Study,
        consent: StudyConsentCompletion
    ) async throws -> StudyEnrollment {
        callCount += 1
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        return enrollment
    }

    func waitUntilFinalizeStarts() async {
        guard callCount == 0 else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
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
    private let enrollment: StudyEnrollment
    private var attempts: [StudyConsentCompletion] = []

    init(enrollment: StudyEnrollment) {
        self.enrollment = enrollment
    }

    func finalizeConsentAndEnroll(
        study: Study,
        consent: StudyConsentCompletion
    ) async throws -> StudyEnrollment {
        attempts.append(consent)
        if attempts.count == 1 {
            throw Failure.unavailable
        }
        return enrollment
    }

    func capturedConsents() -> [StudyConsentCompletion] {
        attempts
    }

    private enum Failure: Error {
        case unavailable
    }
}

private actor RecoveryConsentService: ConsentServiceProtocol {
    private let enrollment: StudyEnrollment
    private var resumeCount = 0
    private var finalizeCount = 0

    init(enrollment: StudyEnrollment) {
        self.enrollment = enrollment
    }

    func availableEnrollmentRecovery(for study: Study) async throws -> ConsentEnrollmentRecovery? {
        .pendingUpload
    }

    func resumeEnrollment(for study: Study) async throws -> StudyEnrollment {
        resumeCount += 1
        return enrollment
    }

    func finalizeConsentAndEnroll(
        study: Study,
        consent: StudyConsentCompletion
    ) async throws -> StudyEnrollment {
        finalizeCount += 1
        return enrollment
    }

    func resumeCallCount() -> Int {
        resumeCount
    }

    func finalizeCallCount() -> Int {
        finalizeCount
    }
}

private actor BlockingRecoveryConsentService: ConsentServiceProtocol {
    private let enrollment: StudyEnrollment
    private var resumeCount = 0
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var continuation: CheckedContinuation<Void, Never>?

    init(enrollment: StudyEnrollment) {
        self.enrollment = enrollment
    }

    func availableEnrollmentRecovery(for study: Study) async throws -> ConsentEnrollmentRecovery? {
        .pendingEnrollment
    }

    func resumeEnrollment(for study: Study) async throws -> StudyEnrollment {
        resumeCount += 1
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        return enrollment
    }

    func finalizeConsentAndEnroll(
        study: Study,
        consent: StudyConsentCompletion
    ) async throws -> StudyEnrollment {
        enrollment
    }

    func waitUntilResumeStarts() async {
        guard resumeCount == 0 else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func resumeCallCount() -> Int {
        resumeCount
    }

    func unblockResume() {
        continuation?.resume()
        continuation = nil
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

    func resumeEnrollment(for study: Study) async throws -> StudyEnrollment {
        makeEnrollment(for: study)
    }

    func finalizeConsentAndEnroll(
        study: Study,
        consent: StudyConsentCompletion
    ) async throws -> StudyEnrollment {
        makeEnrollment(for: study)
    }

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

    func resumeEnrollment(for study: Study) async throws -> StudyEnrollment {
        throw Failure.unavailable
    }

    func finalizeConsentAndEnroll(
        study: Study,
        consent: StudyConsentCompletion
    ) async throws -> StudyEnrollment {
        makeEnrollment(for: study)
    }

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

private func makeEnrollment(for study: Study) -> StudyEnrollment {
    StudyEnrollment(
        id: UUID(uuidString: "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF")!,
        userID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
        studyID: study.id,
        status: .enrolled,
        enrolledAt: Date(timeIntervalSince1970: 1_750_000_100),
        createdAt: Date(timeIntervalSince1970: 1_750_000_100),
        onboardingCompletedAt: Date(timeIntervalSince1970: 1_750_000_200)
    )
}
