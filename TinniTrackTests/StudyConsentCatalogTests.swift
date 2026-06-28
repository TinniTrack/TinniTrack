import Foundation
import Testing
@testable import TinniTrack

struct StudyConsentCatalogTests {
    @Test
    func studyNo1CatalogContainsExpectedVersionSectionsAndRequirements() {
        let definition = StudyConsentCatalog.studyNo1

        #expect(definition.studySlug == "study-no-1")
        #expect(definition.consentVersion == "study-no-1-consent-v2")
        #expect(definition.keyInformation.bulletItems.last == "This is research, not treatment.")
        #expect(definition.keyInformation.bulletItems.contains("You can stop at any time.") == false)
        #expect(definition.keyInformation.bulletItems.contains("Compensation is up to $100."))
        #expect(definition.keyInformation.checkItems.isEmpty)
        #expect(definition.landing.title == "Loudness Match Study")
        #expect(definition.landing.atAGlanceRows.map(\.value).contains("14 days"))
        #expect(definition.landing.atAGlanceRows.count == 5)
        #expect(definition.landing.atAGlanceRows.contains { $0.label == "You're in control" } == false)
        #expect(definition.landing.whatYouWillDo == "Take an Apple Hearing Test with your AirPods, complete loudness matching tasks, and answer brief check-ins throughout the day.")
        #expect(definition.landing.eligibilityItems.contains("You own Apple AirPods Pro Generation 2."))
        #expect(definition.sections.contains { $0.blocks.contains(.scheduleChips(["8 AM", "12 PM", "4 PM", "8 PM"])) })
        #expect(definition.sections.map(\.title) == [
            "Key information",
            "What you'll do",
            "Who can participate",
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
    func studyNo1ContentHashIsDeterministicAndHexEncoded() {
        let definition = StudyConsentCatalog.studyNo1

        #expect(definition.contentSHA256Hex.count == 64)
        #expect(definition.contentSHA256Hex == StudyConsentCatalog.studyNo1.contentSHA256Hex)
        #expect(definition.canonicalContentString.contains("study-no-1-consent-v2"))
        #expect(definition.canonicalContentString.contains("8 AM|12 PM|4 PM|8 PM"))
    }

    @Test
    func completionIsValidOnlyForCompletedConsentedSignedPdfWithSignerNames() {
        let valid = Self.completion()

        #expect(valid.isValidSignedConsent)
        #expect(Self.completion(consented: false).isValidSignedConsent == false)
        #expect(Self.completion(pdfData: Data()).isValidSignedConsent == false)
        #expect(Self.completion(pdfSHA256Hex: " ").isValidSignedConsent == false)
        #expect(Self.completion(pdfSHA256Hex: "abc").isValidSignedConsent == false)
        #expect(Self.completion(givenName: "").isValidSignedConsent == false)
        #expect(Self.completion(familyName: nil).isValidSignedConsent == false)
        #expect(Self.completion(signedAt: nil).isValidSignedConsent == false)
        #expect(Self.completion(contentSHA256Hex: "abc").isValidSignedConsent == false)
        #expect(Self.completion(signatureImageSHA256Hex: nil).isValidSignedConsent == false)
        #expect(Self.completion(collectionMethod: "researchkit").isValidSignedConsent == false)
    }

    private static func completion(
        consented: Bool = true,
        givenName: String? = "Taylor",
        familyName: String? = "Rivers",
        signedAt: Date? = Date(timeIntervalSince1970: 1_750_000_000),
        pdfData: Data = Data([0x25, 0x50, 0x44, 0x46]),
        pdfSHA256Hex: String = String(repeating: "a", count: 64),
        contentSHA256Hex: String = String(repeating: "b", count: 64),
        signatureImageSHA256Hex: String? = String(repeating: "c", count: 64),
        collectionMethod: String = StudyConsentCatalog.nativeCollectionMethod
    ) -> StudyConsentCompletion {
        StudyConsentCompletion(
            taskIdentifier: "study-no-1-consent-v2",
            studySlug: "study-no-1",
            consentVersion: "study-no-1-consent-v2",
            consented: consented,
            signerGivenName: givenName,
            signerFamilyName: familyName,
            signedAt: signedAt,
            artifact: StudyConsentArtifact(
                pdfData: pdfData,
                pdfSHA256Hex: pdfSHA256Hex,
                storageBucket: "study-consents",
                storagePath: "user/study/study-no-1-consent-v2/consent.pdf"
            ),
            researchKitFinishState: nil,
            consentContentSHA256Hex: contentSHA256Hex,
            signatureImageSHA256Hex: signatureImageSHA256Hex,
            collectionMethod: collectionMethod,
            attestationText: StudyConsentCatalog.studyNo1.attestation.text,
            attestationVersion: StudyConsentCatalog.studyNo1.attestation.version
        )
    }
}
