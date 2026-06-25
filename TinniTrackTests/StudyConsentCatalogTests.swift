import Foundation
import Testing
@testable import TinniTrack

struct StudyConsentCatalogTests {
    @Test
    func studyNo1CatalogContainsExpectedVersionSectionsAndRequirements() {
        let definition = StudyConsentCatalog.studyNo1

        #expect(definition.studySlug == "study-no-1")
        #expect(definition.consentVersion == "study-no-1-consent-v1")
        #expect(definition.sections.map(\.title) == [
            "Purpose of the Study",
            "Who Can Participate",
            "What You Will Do",
            "Equipment",
            "Risks",
            "Benefits",
            "Compensation",
            "Privacy",
            "Questions",
            "Consent"
        ])
        #expect(definition.requiresScrollToBottom)
        #expect(definition.requiresName)
        #expect(definition.requiresSignatureImage)
    }

    @Test
    func completionIsValidOnlyForCompletedConsentedSignedPdfWithSignerNames() {
        let valid = Self.completion()

        #expect(valid.isValidSignedConsent)
        #expect(Self.completion(finishState: "discarded").isValidSignedConsent == false)
        #expect(Self.completion(consented: false).isValidSignedConsent == false)
        #expect(Self.completion(pdfData: Data()).isValidSignedConsent == false)
        #expect(Self.completion(pdfSHA256Hex: " ").isValidSignedConsent == false)
        #expect(Self.completion(givenName: "").isValidSignedConsent == false)
        #expect(Self.completion(familyName: nil).isValidSignedConsent == false)
        #expect(Self.completion(signedAt: nil).isValidSignedConsent == false)
    }

    private static func completion(
        finishState: String = "completed",
        consented: Bool = true,
        givenName: String? = "Taylor",
        familyName: String? = "Rivers",
        signedAt: Date? = Date(timeIntervalSince1970: 1_750_000_000),
        pdfData: Data = Data([0x25, 0x50, 0x44, 0x46]),
        pdfSHA256Hex: String = "abcdef123456"
    ) -> StudyConsentCompletion {
        StudyConsentCompletion(
            taskIdentifier: "study-no-1-consent-v1",
            studySlug: "study-no-1",
            consentVersion: "study-no-1-consent-v1",
            consented: consented,
            signerGivenName: givenName,
            signerFamilyName: familyName,
            signedAt: signedAt,
            artifact: StudyConsentArtifact(
                pdfData: pdfData,
                pdfSHA256Hex: pdfSHA256Hex,
                storageBucket: "study-consents",
                storagePath: "user/study/study-no-1-consent-v1/consent.pdf"
            ),
            researchKitFinishState: finishState
        )
    }
}
