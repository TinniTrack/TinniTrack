//
//  StudyConsentDefinition.swift
//  TinniTrack
//

import Foundation

struct StudyConsentDefinition: Equatable, Sendable {
    let studySlug: String
    let studyTitle: String
    let consentVersion: String
    let documentTitle: String
    let reviewReasonForConsent: String
    let signaturePageTitle: String
    let signaturePageContent: String
    let sections: [StudyConsentSection]
    let signatureRequirement: StudyConsentSignatureRequirement

    var requiresScrollToBottom: Bool {
        signatureRequirement.requiresScrollToBottom
    }

    var requiresName: Bool {
        signatureRequirement.requiresName
    }

    var requiresSignatureImage: Bool {
        signatureRequirement.requiresSignatureImage
    }
}

struct StudyConsentSection: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let content: String
}

struct StudyConsentSignatureRequirement: Equatable, Sendable {
    let requiresScrollToBottom: Bool
    let requiresName: Bool
    let requiresSignatureImage: Bool

    static let studyEnrollment = StudyConsentSignatureRequirement(
        requiresScrollToBottom: true,
        requiresName: true,
        requiresSignatureImage: true
    )
}

struct StudyConsentArtifact: Equatable, Sendable {
    let pdfData: Data
    let pdfSHA256Hex: String
    let storageBucket: String
    let storagePath: String
}

struct StudyConsentCompletion: Equatable, Sendable {
    let taskIdentifier: String
    let studySlug: String
    let consentVersion: String
    let consented: Bool
    let signerGivenName: String?
    let signerFamilyName: String?
    let signedAt: Date?
    let artifact: StudyConsentArtifact?
    let researchKitFinishState: String

    var isValidSignedConsent: Bool {
        researchKitFinishState == "completed"
            && consented
            && signedAt != nil
            && artifact?.pdfData.isEmpty == false
            && artifact?.pdfSHA256Hex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && signerGivenName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && signerFamilyName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
}

enum StudyConsentCatalog {
    static let studyNo1ConsentVersion = "study-no-1-consent-v1"
    static let consentStorageBucket = "study-consents"

    static func definition(for studySlug: String) -> StudyConsentDefinition? {
        switch studySlug {
        case studyNo1.studySlug:
            return studyNo1
        default:
            return nil
        }
    }

    static let studyNo1 = StudyConsentDefinition(
        studySlug: "study-no-1",
        studyTitle: "Study No. 1",
        consentVersion: studyNo1ConsentVersion,
        documentTitle: "Informed Consent for Research Participation",
        reviewReasonForConsent: "I have reviewed the consent information and agree to participate in this study.",
        signaturePageTitle: "Participant Consent",
        signaturePageContent: "Type your first and last name, then draw your signature to confirm that you voluntarily agree to participate.",
        sections: [
            StudyConsentSection(
                id: "purpose",
                title: "Purpose of the Study",
                content: """
                This study measures how tinnitus loudness changes over time. The goal is to improve scientific understanding of tinnitus. This study is for research purposes and is not a treatment for tinnitus. Participation is voluntary and you can stop participating at any time.
                """
            ),
            StudyConsentSection(
                id: "eligibility",
                title: "Who Can Participate",
                content: """
                You may participate if you are 18 years or older, have daily tinnitus that has been present for at least 3 months, experience noticeable loudness increases at least twice per week, have primary or sensorineural non-pulsatile tinnitus, own an iPhone 11 or newer, own compatible AirPods Pro, and can complete brief phone assessments four times per day.
                """
            ),
            StudyConsentSection(
                id: "activities",
                title: "What You Will Do",
                content: """
                You will complete a baseline phone session with the researcher, learn how to use the app, complete questionnaires, complete the Apple Hearing Test with AirPods Pro, perform tinnitus loudness and pitch matching tasks, complete daily assessments for 14 days, and attend a short debrief session by Zoom.
                """
            ),
            StudyConsentSection(
                id: "equipment",
                title: "Equipment",
                content: """
                You will use the study app on your iPhone and Apple AirPods Pro with Active Noise Cancellation on. The app asks permission to import your audiogram from Apple HealthKit so tones can be calibrated to your personal hearing level. No other health data are accessed.
                """
            ),
            StudyConsentSection(
                id: "risks",
                title: "Risks",
                content: """
                Risks are minimal. You may become more aware of tinnitus because the study asks about it several times per day. Some participants may find this mildly uncomfortable. Loudness match sounds are quiet and Apple devices include maximum volume limits.
                """
            ),
            StudyConsentSection(
                id: "benefits",
                title: "Benefits",
                content: """
                You will not receive a direct benefit besides compensation. The study may improve understanding of tinnitus and guide future research and treatments. Educational tinnitus resources will be provided at the end of the study.
                """
            ),
            StudyConsentSection(
                id: "compensation",
                title: "Compensation",
                content: """
                You will receive $20 for completing the baseline session and up to $60 for completing daily assessments. Participants who complete 90% or more of assessments receive the full daily assessment amount. Lower completion is prorated and rounded up to the nearest $5.
                """
            ),
            StudyConsentSection(
                id: "privacy",
                title: "Privacy",
                content: """
                Your identity will be protected. Each participant receives a participant code, app data are stored using that code, and your name will not appear in the study dataset. Data are stored in a secure cloud database. Published or shared results will use de-identified data.
                """
            ),
            StudyConsentSection(
                id: "questions",
                title: "Questions",
                content: """
                For questions about the study, contact Thomas Armstrong, Ph.D. at armstrtr@whitman.edu. For questions about participant rights, contact the Whitman College Institutional Review Board at irb@whitman.edu.
                """
            ),
            StudyConsentSection(
                id: "consent",
                title: "Consent",
                content: """
                By selecting I Agree, you confirm that you are 18 years or older, have read and understood this information, understand that participation is voluntary, and agree to participate in this study.
                """
            )
        ],
        signatureRequirement: .studyEnrollment
    )
}
