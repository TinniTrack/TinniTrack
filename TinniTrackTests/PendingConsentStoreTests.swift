import Foundation
import Testing
@testable import TinniTrack

struct PendingConsentStoreTests {
    @Test
    func protectedStoreRoundTripsTheExactSignedEnvelope() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let completion = Self.completion(
            pdfData: Data("%PDF-1.7\nUnicode consent: 你好".utf8),
            givenName: "Zoë",
            familyName: "Nguyễn",
            signedAt: Date(timeIntervalSinceReferenceDate: 123_456_789.125)
        )

        let saved = try await fixture.store.recoverOrSave(
            completion,
            for: fixture.key
        )
        let loaded = try await fixture.store.load(for: fixture.key)

        #expect(saved == completion)
        #expect(loaded == completion)
        #expect(loaded?.artifact?.pdfData == completion.artifact?.pdfData)

        #expect(
            ProtectedPendingConsentStore.protectedWritingOptions
                .contains(.completeFileProtection)
        )
        #expect(
            ProtectedPendingConsentStore.protectedWritingOptions
                .contains(.atomic)
        )
        let resourceValues = try fixture.fileURL.resourceValues(
            forKeys: [.isExcludedFromBackupKey]
        )
        #expect(resourceValues.isExcludedFromBackup == true)
    }

    @Test
    func changedRetryFailsClosedInsteadOfOverwritingTheFirstArtifact() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = Self.completion(
            pdfData: Data("first signed PDF".utf8),
            signedAt: Date(timeIntervalSince1970: 1_750_000_000)
        )
        let regenerated = Self.completion(
            pdfData: Data("new PDF after relaunch".utf8),
            signedAt: Date(timeIntervalSince1970: 1_750_000_100)
        )

        _ = try await fixture.store.recoverOrSave(original, for: fixture.key)
        var observedError: PendingConsentStoreError?
        do {
            _ = try await fixture.store.recoverOrSave(
                regenerated,
                for: fixture.key
            )
        } catch let error as PendingConsentStoreError {
            observedError = error
        }
        let loaded = try await fixture.store.load(for: fixture.key)

        #expect(observedError == .conflictingRecord)
        #expect(loaded == original)
    }

    @Test
    func relaunchedStoreAcceptsOnlyAnExactRetry() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let completion = Self.completion()
        _ = try await fixture.store.recoverOrSave(
            completion,
            for: fixture.key
        )
        let relaunchedStore = ProtectedPendingConsentStore(
            baseDirectory: fixture.baseDirectory
        )

        let recovered = try await relaunchedStore.recoverOrSave(
            completion,
            for: fixture.key
        )

        #expect(recovered == completion)
    }

    @Test
    func loadingAnExistingRecordReappliesBackupExclusion() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let completion = Self.completion()
        _ = try await fixture.store.recoverOrSave(
            completion,
            for: fixture.key
        )
        var fileURL = fixture.fileURL
        var values = URLResourceValues()
        values.isExcludedFromBackup = false
        try fileURL.setResourceValues(values)

        let loaded = try await fixture.store.load(for: fixture.key)
        let restoredValues = try fixture.fileURL.resourceValues(
            forKeys: [.isExcludedFromBackupKey]
        )

        #expect(loaded == completion)
        #expect(restoredValues.isExcludedFromBackup == true)
    }

    @Test
    func deterministicAttemptIdentityIsScopedByUserStudyAndVersion() {
        let userID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let studyID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let base = PendingConsentKey(
            userID: userID,
            studyID: studyID,
            consentVersion: "study-no-1-consent-v2"
        )
        let repeatKey = PendingConsentKey(
            userID: userID,
            studyID: studyID,
            consentVersion: "study-no-1-consent-v2"
        )
        let otherUser = PendingConsentKey(
            userID: UUID(),
            studyID: studyID,
            consentVersion: "study-no-1-consent-v2"
        )
        let otherStudy = PendingConsentKey(
            userID: userID,
            studyID: UUID(),
            consentVersion: "study-no-1-consent-v2"
        )
        let otherVersion = PendingConsentKey(
            userID: userID,
            studyID: studyID,
            consentVersion: "study-no-1-consent-v3"
        )

        #expect(base.attemptID == repeatKey.attemptID)
        let pinnedAttemptID = UUID(
            uuidString: "BDDAC5C3-507C-878B-BCAF-CE4FE5274498"
        )!
        #expect(base.attemptID == pinnedAttemptID)
        #expect(base.attemptID != otherUser.attemptID)
        #expect(base.attemptID != otherStudy.attemptID)
        #expect(base.attemptID != otherVersion.attemptID)
    }

    @Test
    func tamperedEnvelopeIdentityFailsClosedAndRemainsOnDisk() async throws {
        let fields = [
            "schemaVersion",
            "attemptID",
            "userID",
            "studyID",
            "consentVersion"
        ]

        for field in fields {
            let fixture = try Fixture()
            defer { fixture.remove() }
            _ = try await fixture.store.recoverOrSave(
                Self.completion(),
                for: fixture.key
            )
            let data = try Data(contentsOf: fixture.fileURL)
            var object = try #require(
                JSONSerialization.jsonObject(with: data) as? [String: Any]
            )

            switch field {
            case "schemaVersion":
                object[field] = 2
            case "consentVersion":
                object[field] = "tampered-version"
            default:
                object[field] = UUID().uuidString
            }

            try JSONSerialization.data(withJSONObject: object)
                .write(to: fixture.fileURL, options: .atomic)

            var observedError: PendingConsentStoreError?
            do {
                _ = try await fixture.store.load(for: fixture.key)
            } catch let error as PendingConsentStoreError {
                observedError = error
            }

            #expect(observedError == .invalidRecord, "Field: \(field)")
            #expect(FileManager.default.fileExists(atPath: fixture.fileURL.path))
        }
    }

    @Test
    func corruptRecordFailsClosedAndRemainsOnDisk() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        _ = try await fixture.store.recoverOrSave(
            Self.completion(),
            for: fixture.key
        )
        try Data("truncated".utf8).write(to: fixture.fileURL, options: .atomic)

        var observedError: PendingConsentStoreError?
        do {
            _ = try await fixture.store.load(for: fixture.key)
        } catch let error as PendingConsentStoreError {
            observedError = error
        }

        #expect(observedError == .invalidRecord)
        #expect(FileManager.default.fileExists(atPath: fixture.fileURL.path))
    }

    @Test
    func hashMismatchedRecordFailsClosed() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        _ = try await fixture.store.recoverOrSave(
            Self.completion(),
            for: fixture.key
        )

        let data = try Data(contentsOf: fixture.fileURL)
        var object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        var completion = try #require(object["completion"] as? [String: Any])
        var artifact = try #require(completion["artifact"] as? [String: Any])
        artifact["pdfData"] = Data("tampered PDF".utf8).base64EncodedString()
        completion["artifact"] = artifact
        object["completion"] = completion
        try JSONSerialization.data(withJSONObject: object)
            .write(to: fixture.fileURL, options: .atomic)

        var observedError: PendingConsentStoreError?
        do {
            _ = try await fixture.store.load(for: fixture.key)
        } catch let error as PendingConsentStoreError {
            observedError = error
        }

        #expect(observedError == .invalidRecord)
        #expect(FileManager.default.fileExists(atPath: fixture.fileURL.path))
    }

    @Test
    func clearRemovesOnlyTheScopedPendingRecord() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        _ = try await fixture.store.recoverOrSave(
            Self.completion(),
            for: fixture.key
        )

        try await fixture.store.clear(for: fixture.key)
        let loaded = try await fixture.store.load(for: fixture.key)

        #expect(loaded == nil)
        #expect(FileManager.default.fileExists(atPath: fixture.fileURL.path) == false)
    }

    private static func completion(
        pdfData: Data = Data("%PDF signed consent".utf8),
        givenName: String = "Taylor",
        familyName: String = "Rivers",
        signedAt: Date = Date(timeIntervalSince1970: 1_750_000_000)
    ) -> StudyConsentCompletion {
        StudyConsentCompletion(
            taskIdentifier: StudyConsentCatalog.studyNo1ConsentVersion,
            studySlug: StudyConsentCatalog.studyNo1.studySlug,
            consentVersion: StudyConsentCatalog.studyNo1ConsentVersion,
            consented: true,
            signerGivenName: givenName,
            signerFamilyName: familyName,
            signedAt: signedAt,
            artifact: StudyConsentArtifact(
                pdfData: pdfData,
                pdfSHA256Hex: SupabaseConsentService.sha256Hex(for: pdfData),
                storageBucket: StudyConsentCatalog.consentStorageBucket,
                storagePath: ""
            ),
            researchKitFinishState: nil,
            consentContentSHA256Hex: StudyConsentCatalog.studyNo1.contentSHA256Hex,
            signatureImageSHA256Hex: String(repeating: "c", count: 64),
            collectionMethod: StudyConsentCatalog.nativeCollectionMethod,
            attestationText: StudyConsentCatalog.studyNo1.attestation.text,
            attestationVersion: StudyConsentCatalog.studyNo1.attestation.version
        )
    }
}

private struct Fixture {
    let baseDirectory: URL
    let store: ProtectedPendingConsentStore
    let key: PendingConsentKey

    init() throws {
        baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: baseDirectory,
            withIntermediateDirectories: true
        )
        store = ProtectedPendingConsentStore(baseDirectory: baseDirectory)
        key = PendingConsentKey(
            userID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            studyID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            consentVersion: StudyConsentCatalog.studyNo1ConsentVersion
        )
    }

    var fileURL: URL {
        baseDirectory
            .appendingPathComponent(key.attemptID.uuidString.lowercased())
            .appendingPathExtension("json")
    }

    func remove() {
        try? FileManager.default.removeItem(at: baseDirectory)
    }
}
