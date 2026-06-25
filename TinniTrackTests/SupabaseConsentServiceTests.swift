import Foundation
import Testing
@testable import TinniTrack

struct SupabaseConsentServiceTests {
    @Test
    func storagePathUsesOwnUserFolderStudyVersionAndConsentPDFName() {
        let userID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let studyID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let consentID = UUID(uuidString: "99999999-8888-7777-6666-555555555555")!

        let path = SupabaseConsentService.storagePath(
            userID: userID,
            studyID: studyID,
            consentVersion: "study-no-1-consent-v1",
            consentID: consentID
        )

        #expect(path == "11111111-2222-3333-4444-555555555555/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee/study-no-1-consent-v1/99999999-8888-7777-6666-555555555555.pdf")
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
            taskIdentifier: "study-no-1-consent-v1",
            studySlug: "study-no-1",
            consentVersion: "study-no-1-consent-v1",
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
            researchKitFinishState: "completed"
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
        #expect(payload.consentVersion == "study-no-1-consent-v1")
        #expect(payload.signerGivenName == "Taylor")
        #expect(payload.signerFamilyName == "Rivers")
        #expect(payload.consentPDFBucket == "study-consents")
        #expect(payload.consentPDFPath == storagePath)
        #expect(payload.consentPDFSHA256 == String(repeating: "a", count: 64))
        #expect(payload.researchKitTaskIdentifier == "study-no-1-consent-v1")
        #expect(payload.researchKitFinishState == "completed")
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
            taskIdentifier: "study-no-1-consent-v1",
            studySlug: "study-no-1",
            consentVersion: "study-no-1-consent-v1",
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
            researchKitFinishState: "completed"
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
