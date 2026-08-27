import Foundation
import Testing
@testable import TinniTrack

@MainActor
struct ConsentFinalizationLifecycleTests {
    @Test
    func freshFinalizationReturnsCanonicalEnrollment() async throws {
        let fixture = try LifecycleFixture()
        defer { fixture.remove() }
        fixture.remote.publishRecordOnInsert = true

        let enrollment = try await fixture.service.finalizeConsentAndEnroll(
            study: fixture.study,
            consent: fixture.completion
        )

        #expect(enrollment == fixture.remote.enrollment)
        #expect(fixture.remote.events == [
            .currentUser,
            .existingConsent,
            .upload,
            .insert,
            .existingConsent,
            .enroll
        ])
    }

    @Test
    func pendingEvidenceIsDurableBeforeUploadAndSurvivesUploadFailure() async throws {
        let fixture = try LifecycleFixture()
        defer { fixture.remove() }
        fixture.remote.uploadFailure = .unavailable
        fixture.remote.downloadFailure = .unavailable

        var observedError: LifecycleFailure?
        do {
            _ = try await fixture.service.finalizeConsentAndEnroll(
                study: fixture.study,
                consent: fixture.completion
            )
        } catch let error as LifecycleFailure {
            observedError = error
        }
        let pending = try await fixture.store.load(for: fixture.key)

        #expect(observedError == .unavailable)
        #expect(fixture.remote.pendingWasPresentAtUpload)
        #expect(pending == fixture.completion)
        #expect(fixture.remote.events == [
            .currentUser,
            .existingConsent,
            .upload,
            .existingConsent,
            .download
        ])
    }

    @Test
    func cancellationRetainsPendingEvidenceWithoutStartingRecoveryWrites() async throws {
        let fixture = try LifecycleFixture()
        defer { fixture.remove() }
        fixture.remote.cancelUpload = true

        var observedCancellation = false
        do {
            _ = try await fixture.service.finalizeConsentAndEnroll(
                study: fixture.study,
                consent: fixture.completion
            )
        } catch is CancellationError {
            observedCancellation = true
        }
        let pending = try await fixture.store.load(for: fixture.key)

        #expect(observedCancellation)
        #expect(pending == fixture.completion)
        #expect(fixture.remote.events == [
            .currentUser,
            .existingConsent,
            .upload
        ])
    }

    @Test
    func relaunchedChangedSignatureCannotReplacePendingEvidence() async throws {
        let fixture = try LifecycleFixture()
        defer { fixture.remove() }
        fixture.remote.uploadFailure = .unavailable
        fixture.remote.downloadFailure = .unavailable
        var initialError: LifecycleFailure?
        do {
            _ = try await fixture.service.finalizeConsentAndEnroll(
                study: fixture.study,
                consent: fixture.completion
            )
        } catch let error as LifecycleFailure {
            initialError = error
        }
        #expect(initialError == .unavailable)

        let relaunchedStore = ProtectedPendingConsentStore(
            baseDirectory: fixture.baseDirectory
        )
        fixture.remote.pendingStore = relaunchedStore
        fixture.remote.events.removeAll()
        fixture.remote.uploadFailure = nil
        fixture.remote.downloadFailure = nil
        let relaunchedService = SupabaseConsentService(
            remote: fixture.remote,
            deviceMetadataProvider: EmptyDeviceMetadataProvider(),
            pendingConsentStore: relaunchedStore,
            now: { Date(timeIntervalSince1970: 1_750_000_500) }
        )
        let changedCompletion = fixture.makeCompletion(
            pdfData: Data("newly signed PDF".utf8),
            signedAt: Date(timeIntervalSince1970: 1_750_000_500),
            givenName: "Morgan",
            signatureImageSHA256Hex: String(repeating: "d", count: 64)
        )

        var observedError: ConsentServiceError?
        do {
            _ = try await relaunchedService.finalizeConsentAndEnroll(
                study: fixture.study,
                consent: changedCompletion
            )
        } catch let error as ConsentServiceError {
            observedError = error
        }
        let pending = try await relaunchedStore.load(for: fixture.key)

        #expect(observedError == .conflictingPendingArtifact)
        #expect(pending == fixture.completion)
        #expect(fixture.remote.events == [.currentUser, .existingConsent])
    }

    @Test
    func relaunchedPendingEvidenceCanBeExplicitlyResumed() async throws {
        let fixture = try LifecycleFixture()
        defer { fixture.remove() }
        fixture.remote.uploadFailure = .unavailable
        fixture.remote.downloadFailure = .unavailable
        var initialError: LifecycleFailure?
        do {
            _ = try await fixture.service.finalizeConsentAndEnroll(
                study: fixture.study,
                consent: fixture.completion
            )
        } catch let error as LifecycleFailure {
            initialError = error
        }
        #expect(initialError == .unavailable)

        let relaunchedStore = ProtectedPendingConsentStore(
            baseDirectory: fixture.baseDirectory
        )
        fixture.remote.pendingStore = relaunchedStore
        fixture.remote.uploadFailure = nil
        fixture.remote.downloadFailure = nil
        fixture.remote.publishRecordOnInsert = true
        fixture.remote.events.removeAll()
        let relaunchedService = SupabaseConsentService(
            remote: fixture.remote,
            deviceMetadataProvider: EmptyDeviceMetadataProvider(),
            pendingConsentStore: relaunchedStore,
            now: { Date(timeIntervalSince1970: 1_750_000_500) }
        )

        let recovery = try await relaunchedService.availableEnrollmentRecovery(
            for: fixture.study
        )
        fixture.remote.events.removeAll()
        let enrollment = try await relaunchedService.resumeEnrollment(for: fixture.study)
        let pending = try await relaunchedStore.load(for: fixture.key)

        #expect(recovery == .pendingUpload)
        #expect(enrollment == fixture.remote.enrollment)
        #expect(pending == nil)
        #expect(fixture.remote.events == [
            .currentUser,
            .existingConsent,
            .currentUser,
            .existingConsent,
            .upload,
            .insert,
            .existingConsent,
            .enroll
        ])
    }

    @Test
    func acknowledgedInsertIsNotClearedUntilExactRowCanBeConfirmed() async throws {
        let fixture = try LifecycleFixture()
        defer { fixture.remove() }

        var observedError: ConsentServiceError?
        do {
            _ = try await fixture.service.finalizeConsentAndEnroll(
                study: fixture.study,
                consent: fixture.completion
            )
        } catch let error as ConsentServiceError {
            observedError = error
        }
        let pending = try await fixture.store.load(for: fixture.key)

        #expect(observedError == .consentRecordConfirmationFailed)
        #expect(pending == fixture.completion)
        #expect(fixture.remote.events == [
            .currentUser,
            .existingConsent,
            .upload,
            .insert,
            .existingConsent
        ])
    }

    @Test
    func committedInsertWithLostResponseConfirmsClearsAndEnrolls() async throws {
        let fixture = try LifecycleFixture()
        defer { fixture.remove() }
        fixture.remote.publishRecordOnInsert = true
        fixture.remote.insertFailure = .unavailable

        let enrollment = try await fixture.service.finalizeConsentAndEnroll(
            study: fixture.study,
            consent: fixture.completion
        )
        let pending = try await fixture.store.load(for: fixture.key)

        #expect(pending == nil)
        #expect(enrollment == fixture.remote.enrollment)
        #expect(fixture.remote.events == [
            .currentUser,
            .existingConsent,
            .upload,
            .insert,
            .existingConsent,
            .enroll
        ])
    }

    @Test
    func enrollmentFailureRetriesExactConfirmedServerRowWithoutReupload() async throws {
        let fixture = try LifecycleFixture()
        defer { fixture.remove() }
        fixture.remote.publishRecordOnInsert = true
        fixture.remote.enrollFailuresRemaining = 1

        var firstError: LifecycleFailure?
        do {
            _ = try await fixture.service.finalizeConsentAndEnroll(
                study: fixture.study,
                consent: fixture.completion
            )
        } catch let error as LifecycleFailure {
            firstError = error
        }
        let pendingAfterConfirmation = try await fixture.store.load(for: fixture.key)
        fixture.remote.events.removeAll()

        let enrollment = try await fixture.service.finalizeConsentAndEnroll(
            study: fixture.study,
            consent: fixture.completion
        )

        #expect(firstError == .unavailable)
        #expect(enrollment == fixture.remote.enrollment)
        #expect(pendingAfterConfirmation == nil)
        #expect(fixture.remote.events == [
            .currentUser,
            .existingConsent,
            .enroll
        ])
    }

    @Test
    func relaunchedConfirmedConsentCanResumeEnrollmentWithoutResigning() async throws {
        let fixture = try LifecycleFixture()
        defer { fixture.remove() }
        fixture.remote.publishRecordOnInsert = true
        fixture.remote.enrollFailuresRemaining = 1
        var initialError: LifecycleFailure?
        do {
            _ = try await fixture.service.finalizeConsentAndEnroll(
                study: fixture.study,
                consent: fixture.completion
            )
        } catch let error as LifecycleFailure {
            initialError = error
        }
        #expect(initialError == .unavailable)
        let pending = try await fixture.store.load(for: fixture.key)
        let relaunchedStore = ProtectedPendingConsentStore(
            baseDirectory: fixture.baseDirectory
        )
        fixture.remote.pendingStore = relaunchedStore
        fixture.remote.events.removeAll()
        let relaunchedService = SupabaseConsentService(
            remote: fixture.remote,
            deviceMetadataProvider: EmptyDeviceMetadataProvider(),
            pendingConsentStore: relaunchedStore,
            now: { Date(timeIntervalSince1970: 1_750_000_500) }
        )

        let recovery = try await relaunchedService.availableEnrollmentRecovery(
            for: fixture.study
        )
        fixture.remote.events.removeAll()
        let enrollment = try await relaunchedService.resumeEnrollment(for: fixture.study)

        #expect(pending == nil)
        #expect(recovery == .pendingEnrollment)
        #expect(enrollment == fixture.remote.enrollment)
        #expect(fixture.remote.events == [
            .currentUser,
            .existingConsent,
            .enroll
        ])
    }

    @Test
    func changedConsentCannotMasqueradeAsConfirmedServerEvidence() async throws {
        let fixture = try LifecycleFixture()
        defer { fixture.remove() }
        fixture.remote.publishRecordOnInsert = true
        fixture.remote.enrollFailuresRemaining = 1
        var initialError: LifecycleFailure?
        do {
            _ = try await fixture.service.finalizeConsentAndEnroll(
                study: fixture.study,
                consent: fixture.completion
            )
        } catch let error as LifecycleFailure {
            initialError = error
        }
        #expect(initialError == .unavailable)
        fixture.remote.events.removeAll()
        let changedCompletion = fixture.makeCompletion(
            pdfData: Data("changed signed PDF".utf8),
            signedAt: Date(timeIntervalSince1970: 1_750_000_500),
            givenName: "Morgan",
            signatureImageSHA256Hex: String(repeating: "d", count: 64)
        )

        var observedError: ConsentServiceError?
        do {
            _ = try await fixture.service.finalizeConsentAndEnroll(
                study: fixture.study,
                consent: changedCompletion
            )
        } catch let error as ConsentServiceError {
            observedError = error
        }

        #expect(observedError == .conflictingPendingArtifact)
        #expect(fixture.remote.events == [.currentUser, .existingConsent])
    }

    @Test
    func malformedAuthoritativeRowCannotBeOfferedForRecovery() async throws {
        let fixture = try LifecycleFixture()
        defer { fixture.remove() }
        let artifact = try #require(fixture.completion.artifact)
        fixture.remote.existingRow = ExistingConsentRow(
            id: fixture.key.attemptID,
            userID: fixture.userID,
            studyID: fixture.study.id,
            consentVersion: fixture.key.consentVersion,
            consentPDFBucket: StudyConsentCatalog.consentStorageBucket,
            consentPDFPath: SupabaseConsentService.storagePath(
                userID: fixture.userID,
                studyID: fixture.study.id,
                consentVersion: fixture.key.consentVersion,
                consentID: fixture.key.attemptID
            ),
            consentPDFSHA256: artifact.pdfSHA256Hex,
            consentContentSHA256: StudyConsentCatalog.studyNo1.contentSHA256Hex,
            signatureImageSHA256: "not-a-sha256",
            collectionMethod: StudyConsentCatalog.nativeCollectionMethod,
            attestationText: StudyConsentCatalog.studyNo1.attestation.text,
            attestationVersion: StudyConsentCatalog.studyNo1.attestation.version
        )

        var observedError: ConsentServiceError?
        do {
            _ = try await fixture.service.availableEnrollmentRecovery(
                for: fixture.study
            )
        } catch let error as ConsentServiceError {
            observedError = error
        }

        #expect(observedError == .conflictingPendingArtifact)
        #expect(fixture.remote.events == [.currentUser, .existingConsent])
    }

    @Test
    func localPersistenceFailurePreventsAnyUpload() async throws {
        let parentDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: parentDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: parentDirectory) }
        let blockedDirectory = parentDirectory.appendingPathComponent("not-a-directory")
        try Data([0]).write(to: blockedDirectory)

        let fixture = try LifecycleFixture(baseDirectory: blockedDirectory)
        var observedError: ConsentServiceError?
        do {
            _ = try await fixture.service.finalizeConsentAndEnroll(
                study: fixture.study,
                consent: fixture.completion
            )
        } catch let error as ConsentServiceError {
            observedError = error
        }

        #expect(observedError == .pendingArtifactPersistenceFailed)
        #expect(fixture.remote.events == [.currentUser, .existingConsent])
    }
}

@MainActor
private struct LifecycleFixture {
    let baseDirectory: URL
    let store: ProtectedPendingConsentStore
    let remote: MockConsentPersistenceRemote
    let service: SupabaseConsentService
    let userID: UUID
    let study: Study
    let key: PendingConsentKey
    let completion: StudyConsentCompletion

    init(baseDirectory: URL? = nil) throws {
        let resolvedUserID = UUID(
            uuidString: "11111111-2222-3333-4444-555555555555"
        )!
        userID = resolvedUserID
        let resolvedDirectory = baseDirectory ?? FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        if baseDirectory == nil {
            try FileManager.default.createDirectory(
                at: resolvedDirectory,
                withIntermediateDirectories: true
            )
        }
        self.baseDirectory = resolvedDirectory

        let studyID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        study = Study(
            id: studyID,
            slug: StudyConsentCatalog.studyNo1.studySlug,
            title: "Study No. 1",
            description: "Baseline tinnitus study",
            status: .recruiting,
            createdAt: nil
        )
        key = PendingConsentKey(
            userID: resolvedUserID,
            studyID: studyID,
            consentVersion: StudyConsentCatalog.studyNo1ConsentVersion
        )
        completion = Self.makeCompletion(
            pdfData: Data("original signed PDF".utf8),
            signedAt: Date(timeIntervalSince1970: 1_750_000_000)
        )
        store = ProtectedPendingConsentStore(baseDirectory: resolvedDirectory)
        remote = MockConsentPersistenceRemote(
            userID: resolvedUserID,
            studyID: studyID
        )
        remote.pendingStore = store
        remote.pendingKey = key
        service = SupabaseConsentService(
            remote: remote,
            deviceMetadataProvider: EmptyDeviceMetadataProvider(),
            pendingConsentStore: store,
            now: { Date(timeIntervalSince1970: 1_750_000_000) }
        )
    }

    func makeCompletion(
        pdfData: Data,
        signedAt: Date,
        givenName: String = "Taylor",
        signatureImageSHA256Hex: String = String(repeating: "c", count: 64)
    ) -> StudyConsentCompletion {
        Self.makeCompletion(
            pdfData: pdfData,
            signedAt: signedAt,
            givenName: givenName,
            signatureImageSHA256Hex: signatureImageSHA256Hex
        )
    }

    func remove() {
        guard baseDirectory.path.hasPrefix(FileManager.default.temporaryDirectory.path) else {
            return
        }
        try? FileManager.default.removeItem(at: baseDirectory)
    }

    private static func makeCompletion(
        pdfData: Data,
        signedAt: Date,
        givenName: String = "Taylor",
        signatureImageSHA256Hex: String = String(repeating: "c", count: 64)
    ) -> StudyConsentCompletion {
        StudyConsentCompletion(
            taskIdentifier: StudyConsentCatalog.studyNo1ConsentVersion,
            studySlug: StudyConsentCatalog.studyNo1.studySlug,
            consentVersion: StudyConsentCatalog.studyNo1ConsentVersion,
            consented: true,
            signerGivenName: givenName,
            signerFamilyName: "Rivers",
            signedAt: signedAt,
            artifact: StudyConsentArtifact(
                pdfData: pdfData,
                pdfSHA256Hex: SupabaseConsentService.sha256Hex(for: pdfData),
                storageBucket: StudyConsentCatalog.consentStorageBucket,
                storagePath: ""
            ),
            researchKitFinishState: nil,
            consentContentSHA256Hex: StudyConsentCatalog.studyNo1.contentSHA256Hex,
            signatureImageSHA256Hex: signatureImageSHA256Hex,
            collectionMethod: StudyConsentCatalog.nativeCollectionMethod,
            attestationText: StudyConsentCatalog.studyNo1.attestation.text,
            attestationVersion: StudyConsentCatalog.studyNo1.attestation.version
        )
    }
}

@MainActor
private final class MockConsentPersistenceRemote: ConsentPersistenceRemote {
    let userID: UUID
    let enrollment: StudyEnrollment
    var events: [ConsentRemoteEvent] = []
    var existingRow: ExistingConsentRow?
    var pendingStore: ProtectedPendingConsentStore?
    var pendingKey: PendingConsentKey?
    var pendingWasPresentAtUpload = false
    var uploadFailure: LifecycleFailure?
    var cancelUpload = false
    var downloadFailure: LifecycleFailure?
    var insertFailure: LifecycleFailure?
    var publishRecordOnInsert = false
    var enrollFailuresRemaining = 0

    init(userID: UUID, studyID: UUID) {
        self.userID = userID
        enrollment = StudyEnrollment(
            id: UUID(uuidString: "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF")!,
            userID: userID,
            studyID: studyID,
            status: .enrolled,
            enrolledAt: Date(timeIntervalSince1970: 1_750_000_100),
            createdAt: Date(timeIntervalSince1970: 1_750_000_100)
        )
    }

    func currentUserID() async throws -> UUID {
        events.append(.currentUser)
        return userID
    }

    func existingConsent(
        userID: UUID,
        studyID: UUID,
        consentVersion: String
    ) async throws -> ExistingConsentRow? {
        events.append(.existingConsent)
        return existingRow
    }

    func uploadPDF(storagePath: String, data: Data) async throws {
        events.append(.upload)
        if let pendingStore, let pendingKey {
            pendingWasPresentAtUpload = try await pendingStore.load(for: pendingKey) != nil
        }
        if cancelUpload {
            throw CancellationError()
        }
        if let uploadFailure {
            throw uploadFailure
        }
    }

    func downloadPDF(storagePath: String) async throws -> Data {
        events.append(.download)
        if let downloadFailure {
            throw downloadFailure
        }
        return Data()
    }

    func insertConsent(_ payload: ConsentInsertPayload) async throws {
        events.append(.insert)
        if publishRecordOnInsert {
            existingRow = ExistingConsentRow(
                id: payload.id,
                userID: payload.userID,
                studyID: payload.studyID,
                consentVersion: payload.consentVersion,
                consentPDFBucket: payload.consentPDFBucket,
                consentPDFPath: payload.consentPDFPath,
                consentPDFSHA256: payload.consentPDFSHA256,
                consentContentSHA256: payload.consentContentSHA256,
                signatureImageSHA256: payload.signatureImageSHA256 ?? "",
                collectionMethod: payload.collectionMethod,
                attestationText: payload.attestationText,
                attestationVersion: payload.attestationVersion
            )
        }
        if let insertFailure {
            throw insertFailure
        }
    }

    func enroll(studyID: UUID, consentID: UUID) async throws -> StudyEnrollment {
        events.append(.enroll)
        if enrollFailuresRemaining > 0 {
            enrollFailuresRemaining -= 1
            throw LifecycleFailure.unavailable
        }
        return enrollment
    }
}

nonisolated private enum ConsentRemoteEvent: Equatable {
    case currentUser
    case existingConsent
    case upload
    case download
    case insert
    case enroll
}

nonisolated private enum LifecycleFailure: Error, Equatable {
    case unavailable
}

@MainActor
private struct EmptyDeviceMetadataProvider: DeviceMetadataProviding {
    func currentDeviceInfo() -> [String: JSONValue] {
        [:]
    }
}
