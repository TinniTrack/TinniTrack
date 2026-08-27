import Foundation
import Testing
@testable import TinniTrack

struct SupabaseConsentServiceTests {
    @Test
    func consentIDIsStableForOneUserStudyAndVersion() {
        let userID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let studyID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

        let first = SupabaseConsentService.consentID(
            userID: userID,
            studyID: studyID,
            consentVersion: "study-no-1-consent-v2"
        )
        let retry = SupabaseConsentService.consentID(
            userID: userID,
            studyID: studyID,
            consentVersion: "study-no-1-consent-v2"
        )
        let nextVersion = SupabaseConsentService.consentID(
            userID: userID,
            studyID: studyID,
            consentVersion: "study-no-1-consent-v3"
        )

        #expect(first == retry)
        #expect(first != nextVersion)
        #expect(first.uuidString.split(separator: "-")[2].first == "8")
    }

    @Test
    func consentHashUsesCanonicalLowercaseSHA256() {
        let digest = SupabaseConsentService.sha256Hex(for: Data("abc".utf8))

        #expect(digest == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test
    func recordedConsentMustMatchTheExactPendingEvidenceBeforeCleanup() {
        let userID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let studyID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let key = PendingConsentKey(
            userID: userID,
            studyID: studyID,
            consentVersion: StudyConsentCatalog.studyNo1ConsentVersion
        )
        let pdfData = Data("signed consent".utf8)
        let pdfSHA256 = SupabaseConsentService.sha256Hex(for: pdfData)
        let completion = StudyConsentCompletion(
            taskIdentifier: StudyConsentCatalog.studyNo1ConsentVersion,
            studySlug: StudyConsentCatalog.studyNo1.studySlug,
            consentVersion: StudyConsentCatalog.studyNo1ConsentVersion,
            consented: true,
            signerGivenName: "Taylor",
            signerFamilyName: "Rivers",
            signedAt: Date(timeIntervalSince1970: 1_750_000_000),
            artifact: StudyConsentArtifact(
                pdfData: pdfData,
                pdfSHA256Hex: pdfSHA256,
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
        let storagePath = SupabaseConsentService.storagePath(
            userID: userID,
            studyID: studyID,
            consentVersion: key.consentVersion,
            consentID: key.attemptID
        )
        let recorded = ExistingConsentRow(
            id: key.attemptID,
            userID: userID,
            studyID: studyID,
            consentVersion: key.consentVersion,
            consentPDFBucket: StudyConsentCatalog.consentStorageBucket,
            consentPDFPath: storagePath,
            consentPDFSHA256: pdfSHA256,
            consentContentSHA256: completion.consentContentSHA256Hex,
            signatureImageSHA256: completion.signatureImageSHA256Hex!,
            collectionMethod: completion.collectionMethod,
            attestationText: completion.attestationText,
            attestationVersion: completion.attestationVersion
        )
        let conflicting = ExistingConsentRow(
            id: key.attemptID,
            userID: userID,
            studyID: studyID,
            consentVersion: key.consentVersion,
            consentPDFBucket: StudyConsentCatalog.consentStorageBucket,
            consentPDFPath: storagePath,
            consentPDFSHA256: String(repeating: "d", count: 64),
            consentContentSHA256: completion.consentContentSHA256Hex,
            signatureImageSHA256: completion.signatureImageSHA256Hex!,
            collectionMethod: completion.collectionMethod,
            attestationText: completion.attestationText,
            attestationVersion: completion.attestationVersion
        )

        #expect(recorded.matches(completion, key: key, storagePath: storagePath))
        #expect(conflicting.matches(completion, key: key, storagePath: storagePath) == false)
    }

    @Test
    func storagePathUsesOwnUserFolderStudyVersionAndConsentPDFName() {
        let userID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let studyID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let consentID = UUID(uuidString: "99999999-8888-7777-6666-555555555555")!

        let path = SupabaseConsentService.storagePath(
            userID: userID,
            studyID: studyID,
            consentVersion: "study-no-1-consent-v2",
            consentID: consentID
        )

        #expect(path == "11111111-2222-3333-4444-555555555555/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee/study-no-1-consent-v2/99999999-8888-7777-6666-555555555555.pdf")
    }

    @Test
    func consentInsertPayloadEncodesExpectedMetadataFields() throws {
        let userID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let study = Study(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            slug: "study-no-1",
            title: "Study No. 1",
            description: "Baseline tinnitus study",
            status: .recruiting,
            createdAt: nil
        )
        let consentID = UUID(uuidString: "99999999-8888-7777-6666-555555555555")!
        let signedAt = Date(timeIntervalSince1970: 1_750_000_000)
        let completion = StudyConsentCompletion(
            taskIdentifier: "study-no-1-consent-v2",
            studySlug: "study-no-1",
            consentVersion: "study-no-1-consent-v2",
            consented: true,
            signerGivenName: " Taylor ",
            signerFamilyName: " Rivers ",
            signedAt: signedAt,
            artifact: StudyConsentArtifact(
                pdfData: Data([1, 2, 3]),
                pdfSHA256Hex: String(repeating: "a", count: 64),
                storageBucket: "study-consents",
                storagePath: ""
            ),
            researchKitFinishState: nil,
            consentContentSHA256Hex: String(repeating: "b", count: 64),
            signatureImageSHA256Hex: String(repeating: "c", count: 64),
            collectionMethod: StudyConsentCatalog.nativeCollectionMethod,
            attestationText: StudyConsentCatalog.studyNo1.attestation.text,
            attestationVersion: StudyConsentCatalog.studyNo1.attestation.version
        )
        let storagePath = SupabaseConsentService.storagePath(
            userID: userID,
            studyID: study.id,
            consentVersion: completion.consentVersion,
            consentID: consentID
        )

        let payload = try SupabaseConsentService.makeConsentInsertPayload(
            consentID: consentID,
            userID: userID,
            study: study,
            consent: completion,
            storagePath: storagePath,
            appVersion: "1.0 (7)",
            deviceInfo: ["system_name": .string("iOS")],
            fallbackSignedAt: Date(timeIntervalSince1970: 0)
        )

        #expect(payload.id == consentID)
        #expect(payload.userID == userID)
        #expect(payload.studyID == study.id)
        #expect(payload.consentVersion == "study-no-1-consent-v2")
        #expect(payload.signerGivenName == "Taylor")
        #expect(payload.signerFamilyName == "Rivers")
        #expect(payload.consentPDFBucket == "study-consents")
        #expect(payload.consentPDFPath == storagePath)
        #expect(payload.consentPDFSHA256 == String(repeating: "a", count: 64))
        #expect(payload.consentContentSHA256 == String(repeating: "b", count: 64))
        #expect(payload.signatureImageSHA256 == String(repeating: "c", count: 64))
        #expect(payload.collectionMethod == StudyConsentCatalog.nativeCollectionMethod)
        #expect(payload.attestationText == StudyConsentCatalog.studyNo1.attestation.text)
        #expect(payload.attestationVersion == StudyConsentCatalog.studyNo1.attestation.version)
        #expect(payload.researchKitTaskIdentifier == nil)
        #expect(payload.researchKitFinishState == nil)
        #expect(payload.appVersion == "1.0 (7)")
        #expect(payload.deviceInfo == ["system_name": .string("iOS")])
    }

    @Test
    func consentInsertPayloadRejectsInvalidCompletion() {
        let study = Study(
            id: UUID(),
            slug: "study-no-1",
            title: "Study No. 1",
            description: "Baseline tinnitus study",
            status: .recruiting,
            createdAt: nil
        )
        let completion = StudyConsentCompletion(
            taskIdentifier: "study-no-1-consent-v2",
            studySlug: "study-no-1",
            consentVersion: "study-no-1-consent-v2",
            consented: false,
            signerGivenName: "Taylor",
            signerFamilyName: "Rivers",
            signedAt: Date(),
            artifact: StudyConsentArtifact(
                pdfData: Data([1]),
                pdfSHA256Hex: String(repeating: "a", count: 64),
                storageBucket: "study-consents",
                storagePath: ""
            ),
            researchKitFinishState: nil,
            consentContentSHA256Hex: String(repeating: "b", count: 64),
            signatureImageSHA256Hex: String(repeating: "c", count: 64),
            collectionMethod: StudyConsentCatalog.nativeCollectionMethod,
            attestationText: StudyConsentCatalog.studyNo1.attestation.text,
            attestationVersion: StudyConsentCatalog.studyNo1.attestation.version
        )

        #expect(throws: ConsentServiceError.invalidConsentCompletion) {
            try SupabaseConsentService.makeConsentInsertPayload(
                consentID: UUID(),
                userID: UUID(),
                study: study,
                consent: completion,
                storagePath: "path.pdf",
                appVersion: nil,
                deviceInfo: [:],
                fallbackSignedAt: Date()
            )
        }
    }
}
