//
//  StudyConsentDefinition.swift
//  TinniTrack
//

import CryptoKit
import Foundation

struct StudyConsentDefinition: Equatable, Sendable {
    let studySlug: String
    let studyTitle: String
    let consentVersion: String
    let documentTitle: String
    let reviewReasonForConsent: String
    let signaturePageTitle: String
    let signaturePageContent: String
    let principalInvestigator: StudyConsentContact
    let keyInformation: StudyConsentKeyInformation
    let landing: StudyConsentLandingContent
    let sections: [StudyConsentSection]
    let contacts: [StudyConsentContact]
    let consentChoices: StudyConsentChoices
    let attestation: StudyConsentAttestation
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

    var contentSHA256Hex: String {
        Self.sha256Hex(for: canonicalContentString)
    }

    var canonicalContentString: String {
        var lines: [String] = [
            "studySlug=\(studySlug)",
            "studyTitle=\(studyTitle)",
            "consentVersion=\(consentVersion)",
            "documentTitle=\(documentTitle)",
            "reviewReasonForConsent=\(reviewReasonForConsent)",
            "signaturePageTitle=\(signaturePageTitle)",
            "signaturePageContent=\(signaturePageContent)",
            principalInvestigator.canonicalLine(prefix: "principalInvestigator"),
            keyInformation.canonicalLine,
            landing.canonicalLine,
            consentChoices.canonicalLine,
            attestation.canonicalLine,
            "signatureRequirement=\(signatureRequirement.canonicalLine)"
        ]

        lines.append(contentsOf: sections.map(\.canonicalLine))
        lines.append(contentsOf: contacts.map { $0.canonicalLine(prefix: "contact") })
        return lines.joined(separator: "\n")
    }

    private static func sha256Hex(for text: String) -> String {
        let data = Data(text.utf8)
        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

struct StudyConsentLandingContent: Equatable, Sendable {
    let eyebrow: String
    let title: String
    let subtitle: String
    let atAGlanceRows: [StudyConsentAtAGlanceRow]
    let whatYouWillDo: String
    let eligibilityItems: [String]
    let beforeEnrollTitle: String
    let beforeEnrollBody: String
    let primaryActionTitle: String
    let footerNote: String

    var canonicalLine: String {
        [
            "landing",
            eyebrow,
            title,
            subtitle,
            atAGlanceRows.map(\.canonicalLine).joined(separator: "|"),
            whatYouWillDo,
            eligibilityItems.joined(separator: "|"),
            beforeEnrollTitle,
            beforeEnrollBody,
            primaryActionTitle,
            footerNote
        ].joined(separator: "\u{001f}")
    }
}

struct StudyConsentAtAGlanceRow: Equatable, Sendable {
    let symbolName: String
    let label: String
    let value: String

    var canonicalLine: String {
        [symbolName, label, value].joined(separator: "\u{001f}")
    }
}

struct StudyConsentKeyInformation: Equatable, Sendable {
    let title: String
    let bulletItems: [String]
    let checkItems: [String]

    var canonicalLine: String {
        [
            "keyInformation",
            title,
            bulletItems.joined(separator: "|"),
            checkItems.joined(separator: "|")
        ].joined(separator: "\u{001f}")
    }
}

struct StudyConsentSection: Identifiable, Equatable, Sendable {
    let id: String
    let tabTitle: String?
    let title: String
    let blocks: [StudyConsentContentBlock]

    var content: String {
        blocks.map(\.plainText).joined(separator: "\n\n")
    }

    var canonicalLine: String {
        [
            "section",
            id,
            tabTitle ?? "",
            title,
            blocks.map(\.canonicalLine).joined(separator: "\u{001e}")
        ].joined(separator: "\u{001f}")
    }
}

enum StudyConsentContentBlock: Equatable, Sendable {
    case paragraph(String)
    case bullets([String])
    case numberedActivities([StudyConsentNumberedActivity])
    case scheduleChips([String])
    case callout(title: String, body: String)
    case contacts([StudyConsentContact])

    var plainText: String {
        switch self {
        case .paragraph(let text):
            return text
        case .bullets(let items):
            return items.map { "- \($0)" }.joined(separator: "\n")
        case .numberedActivities(let activities):
            return activities.map { activity in
                let body = ([activity.body] + activity.bullets.map { "- \($0)" }).joined(separator: "\n")
                return "\(activity.index). \(activity.title)\n\(body)"
            }.joined(separator: "\n\n")
        case .scheduleChips(let times):
            return "Schedule: \(times.joined(separator: ", "))"
        case .callout(let title, let body):
            return "\(title)\n\(body)"
        case .contacts(let contacts):
            return contacts.map(\.displayText).joined(separator: "\n\n")
        }
    }

    var canonicalLine: String {
        switch self {
        case .paragraph(let text):
            return ["paragraph", text].joined(separator: "\u{001f}")
        case .bullets(let items):
            return ["bullets", items.joined(separator: "|")].joined(separator: "\u{001f}")
        case .numberedActivities(let activities):
            return [
                "numberedActivities",
                activities.map(\.canonicalLine).joined(separator: "|")
            ].joined(separator: "\u{001f}")
        case .scheduleChips(let times):
            return ["scheduleChips", times.joined(separator: "|")].joined(separator: "\u{001f}")
        case .callout(let title, let body):
            return ["callout", title, body].joined(separator: "\u{001f}")
        case .contacts(let contacts):
            return [
                "contacts",
                contacts.map { $0.canonicalLine(prefix: "contact") }.joined(separator: "|")
            ].joined(separator: "\u{001f}")
        }
    }
}

struct StudyConsentNumberedActivity: Equatable, Sendable {
    let index: Int
    let title: String
    let body: String
    let bullets: [String]

    var canonicalLine: String {
        [
            "\(index)",
            title,
            body,
            bullets.joined(separator: "|")
        ].joined(separator: "\u{001f}")
    }
}

struct StudyConsentContact: Equatable, Sendable {
    let title: String
    let name: String
    let affiliation: String?
    let email: String
    let addressLines: [String]

    var displayText: String {
        ([title, name] + [affiliation].compactMap { $0 } + [email] + addressLines).joined(separator: "\n")
    }

    func canonicalLine(prefix: String) -> String {
        [
            prefix,
            title,
            name,
            affiliation ?? "",
            email,
            addressLines.joined(separator: "|")
        ].joined(separator: "\u{001f}")
    }
}

struct StudyConsentChoices: Equatable, Sendable {
    let agreeText: String
    let declineText: String
    let finalAgreeLanguage: [String]

    var canonicalLine: String {
        [
            "consentChoices",
            agreeText,
            declineText,
            finalAgreeLanguage.joined(separator: "|")
        ].joined(separator: "\u{001f}")
    }
}

struct StudyConsentAttestation: Equatable, Sendable {
    let version: String
    let text: String

    var canonicalLine: String {
        ["attestation", version, text].joined(separator: "\u{001f}")
    }
}

struct StudyConsentSignatureRequirement: Equatable, Sendable {
    let requiresScrollToBottom: Bool
    let requiresName: Bool
    let requiresSignatureImage: Bool

    var canonicalLine: String {
        "\(requiresScrollToBottom)|\(requiresName)|\(requiresSignatureImage)"
    }

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
    let researchKitFinishState: String?
    let consentContentSHA256Hex: String
    let signatureImageSHA256Hex: String?
    let collectionMethod: String
    let attestationText: String
    let attestationVersion: String

    var isValidSignedConsent: Bool {
        consented
            && signedAt != nil
            && artifact?.pdfData.isEmpty == false
            && artifact?.pdfSHA256Hex.isValidSHA256Hex == true
            && consentContentSHA256Hex.isValidSHA256Hex
            && signatureImageSHA256Hex?.isValidSHA256Hex == true
            && collectionMethod == StudyConsentCatalog.nativeCollectionMethod
            && signerGivenName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && signerFamilyName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && attestationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && attestationVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
}

enum StudyConsentCatalog {
    static let studyNo1ConsentVersion = "study-no-1-consent-v2"
    static let consentStorageBucket = "study-consents"
    static let nativeCollectionMethod = "native_swiftui_v2"

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
        principalInvestigator: StudyConsentContact(
            title: "Principal Investigator",
            name: "Thomas Armstrong, Ph.D.",
            affiliation: "Associate Professor of Psychology, Whitman College",
            email: "armstrtr@whitman.edu",
            addressLines: []
        ),
        keyInformation: StudyConsentKeyInformation(
            title: "Key information",
            bulletItems: [
                "You'll complete a baseline session, 14 days of brief assessments, and a debrief.",
                "You'll use your iPhone and AirPods Pro.",
                "Risks are minimal but may include increased awareness of tinnitus.",
                "Participation is voluntary.",
                "Compensation is up to $100.",
                "Your data is coded and used for research only.",
                "This is research, not treatment."
            ],
            checkItems: []
        ),
        landing: StudyConsentLandingContent(
            eyebrow: "Study Details",
            title: "Loudness Match Study",
            subtitle: "Help us understand how tinnitus loudness changes throughout the day.",
            atAGlanceRows: [
                StudyConsentAtAGlanceRow(symbolName: "calendar", label: "Duration", value: "14 days"),
                StudyConsentAtAGlanceRow(symbolName: "clock", label: "Daily effort", value: "4 brief check-ins per day"),
                StudyConsentAtAGlanceRow(symbolName: "stopwatch", label: "Time per check-in", value: "About 1-3 minutes"),
                StudyConsentAtAGlanceRow(symbolName: "headphones", label: "Equipment", value: "iPhone + AirPods Pro Gen 2"),
                StudyConsentAtAGlanceRow(symbolName: "flask", label: "Type", value: "Research, not treatment")
            ],
            whatYouWillDo: "Take an Apple Hearing Test with your AirPods, complete loudness matching tasks, and answer brief check-ins throughout the day.",
            eligibilityItems: [
                "You are 18 years or older.",
                "Your tinnitus has been present for at least 3 months, occurs daily, and is always audible in a quiet room.",
                "You experience periods of more than one hour during which tinnitus seems noticeably louder than usual at least twice per week.",
                "Your tinnitus has been evaluated by a doctor or audiologist and determined to be primary tinnitus or sensorineural tinnitus, not related to a medical condition or structural issue. Your tinnitus does not have another known medical cause, such as vascular conditions, jaw disorders, Meniere's disease, or otosclerosis.",
                "Your tinnitus is non-pulsatile and does not seem to track your heartbeat or sound like a heartbeat.",
                "You own an iPhone 11 or newer, which is required for the study app.",
                "You own Apple AirPods Pro Generation 2.",
                "You are able to complete short assessments, about 3 minutes each, four times per day at 8 AM, 12 PM, 4 PM, and 8 PM for 14 days on your phone."
            ],
            beforeEnrollTitle: "Before you enroll",
            beforeEnrollBody: "You'll review the full study consent form and decide whether you want to participate. You can stop at any time.",
            primaryActionTitle: "Review Study Consent",
            footerNote: "You will not be enrolled until you sign."
        ),
        sections: [
            StudyConsentSection(
                id: "key-info",
                tabTitle: "Key Info",
                title: "Key information",
                blocks: [
                    .paragraph("Many people with tinnitus experience changes in how loud it sounds. This study measures how tinnitus loudness changes over time. The goal is to improve scientific understanding of tinnitus."),
                    .bullets([
                        "This study is for research purposes and is not a treatment for tinnitus.",
                        "Participation is entirely voluntary.",
                        "You can stop participating at any time and still receive compensation for the proportion of the study you completed."
                    ])
                ]
            ),
            StudyConsentSection(
                id: "what-you-will-do",
                tabTitle: "What You'll Do",
                title: "What you'll do",
                blocks: [
                    .numberedActivities([
                        StudyConsentNumberedActivity(
                            index: 1,
                            title: "Baseline session",
                            body: "This session takes place on the phone, in a Zoom meeting with the researcher. You will import your baseline audiogram data from Apple Health and complete a loudness-matching task.",
                            bullets: [
                                "Learn how to use the app.",
                                "Complete questionnaires about tinnitus and mood.",
                                "Complete the Apple Hearing Test in iOS Settings with your AirPods Pro connected.",
                                "Perform tinnitus loudness and pitch matching tasks.",
                                "Rate how loud your tinnitus seems."
                            ]
                        ),
                        StudyConsentNumberedActivity(
                            index: 2,
                            title: "Daily assessments (14 days)",
                            body: "You will complete brief check-ins four times each day: 8 AM, 12 PM, 4 PM, and 8 PM. Each check-in takes about 1-3 minutes.",
                            bullets: [
                                "A tinnitus loudness match.",
                                "A rating of how loud your tinnitus sounds.",
                                "Three questions about how tinnitus is affecting you."
                            ]
                        ),
                        StudyConsentNumberedActivity(
                            index: 3,
                            title: "Debrief session",
                            body: "Within one week of completing the study, you will meet briefly with the researcher via Zoom for about 5-10 minutes.",
                            bullets: [
                                "Answer a few open-ended questions about your experience using the app.",
                                "Ask any questions you have.",
                                "Receive more detailed information about the purpose and goals of the study."
                            ]
                        )
                    ]),
                    .scheduleChips(["8 AM", "12 PM", "4 PM", "8 PM"])
                ]
            ),
            StudyConsentSection(
                id: "eligibility",
                tabTitle: nil,
                title: "Who can participate",
                blocks: [
                    .paragraph("You are eligible to participate if:"),
                    .bullets([
                        "You are 18 years or older.",
                        "Your tinnitus has been present for at least 3 months, occurs daily, and is always audible in a quiet room.",
                        "You experience periods of more than one hour during which tinnitus seems noticeably louder than usual at least twice per week.",
                        "Your tinnitus has been evaluated by a doctor or audiologist and determined to be primary tinnitus or sensorineural tinnitus, not related to a medical condition or structural issue. Your tinnitus does not have another known medical cause, such as vascular conditions, jaw disorders, Meniere's disease, or otosclerosis.",
                        "Your tinnitus is non-pulsatile and does not seem to track your heartbeat or sound like a heartbeat.",
                        "You own an iPhone 11 or newer, which is required for the study app.",
                        "You own Apple AirPods Pro Generation 2.",
                        "You are able to complete short assessments, about 3 minutes each, four times per day at 8 AM, 12 PM, 4 PM, and 8 PM for 14 days on your phone."
                    ]),
                    .callout(title: "Eligibility questions", body: "If you have questions about eligibility, contact armstrtr@whitman.edu.")
                ]
            ),
            StudyConsentSection(
                id: "equipment",
                tabTitle: nil,
                title: "Equipment",
                blocks: [
                    .paragraph("You will download the app on your iPhone. Before the baseline session, you will complete the Apple Hearing Test in iOS Settings with your AirPods Pro connected."),
                    .paragraph("The app will ask for permission to access your hearing data via Apple HealthKit. This is used only to import your audiogram to calibrate the loudness match tones to your personal hearing level. No other health data are accessed."),
                    .paragraph("You will use your Apple AirPods Pro Generation 2 with Active Noise Cancellation on.")
                ]
            ),
            StudyConsentSection(
                id: "risks",
                tabTitle: "Risks",
                title: "Risks",
                blocks: [
                    .paragraph("Risks are minimal."),
                    .bullets([
                        "You may become more aware of your tinnitus because the study asks about it several times per day. Some participants may find this mildly uncomfortable.",
                        "Previous research using similar methods has found that repeated monitoring does not increase tinnitus distress on average.",
                        "The sounds used in the loudness match are very quiet. Most tinnitus loudness matches occur only 5-9 dB above hearing threshold, and Apple devices include built-in maximum volume limits."
                    ])
                ]
            ),
            StudyConsentSection(
                id: "benefits",
                tabTitle: nil,
                title: "Benefits",
                blocks: [
                    .paragraph("You will not receive any direct benefit from participating besides the compensation. However, the study may improve understanding of tinnitus and help guide future research and treatments."),
                    .paragraph("Educational resources on tinnitus will be provided at the end of the study.")
                ]
            ),
            StudyConsentSection(
                id: "compensation",
                tabTitle: "Compensation",
                title: "Compensation",
                blocks: [
                    .paragraph("You will receive:"),
                    .bullets([
                        "$20 for completing the baseline session.",
                        "Up to $60 for completing the daily assessments."
                    ]),
                    .paragraph("Participants who complete 90% or more of assessments receive the full $60. If fewer assessments are completed, compensation will be prorated based on completion. Payments are rounded up to the nearest $5.")
                ]
            ),
            StudyConsentSection(
                id: "privacy",
                tabTitle: "Privacy",
                title: "Privacy",
                blocks: [
                    .paragraph("Your identity will be protected."),
                    .bullets([
                        "Each participant receives a participant code.",
                        "Data collected in the app are stored using this code.",
                        "Your name will not appear in the study dataset."
                    ]),
                    .paragraph("Data are stored in a secure cloud database. A separate participant log linking names to participant codes will be stored in a password-protected account separately from the study data."),
                    .paragraph("If results are published or shared with other researchers, only de-identified data will be used. Identifying information will be deleted within one year after the study ends.")
                ]
            ),
            StudyConsentSection(
                id: "contacts",
                tabTitle: "Contacts",
                title: "Questions",
                blocks: [
                    .contacts([
                        StudyConsentContact(
                            title: "Study questions",
                            name: "Thomas Armstrong, Ph.D.",
                            affiliation: nil,
                            email: "armstrtr@whitman.edu",
                            addressLines: []
                        ),
                        StudyConsentContact(
                            title: "Participant rights",
                            name: "Whitman College Institutional Review Board",
                            affiliation: nil,
                            email: "irb@whitman.edu",
                            addressLines: [
                                "Whitman College",
                                "345 Boyer Avenue",
                                "Walla Walla, WA 99362"
                            ]
                        )
                    ])
                ]
            ),
            StudyConsentSection(
                id: "consent",
                tabTitle: nil,
                title: "Consent",
                blocks: [
                    .paragraph("By selecting I Agree, you confirm that:"),
                    .bullets([
                        "You are 18 years or older.",
                        "You have read and understood this information.",
                        "Participation is voluntary.",
                        "You agree to participate in this study."
                    ])
                ]
            )
        ],
        contacts: [
            StudyConsentContact(
                title: "Study questions",
                name: "Thomas Armstrong, Ph.D.",
                affiliation: nil,
                email: "armstrtr@whitman.edu",
                addressLines: []
            ),
            StudyConsentContact(
                title: "Participant rights",
                name: "Whitman College Institutional Review Board",
                affiliation: nil,
                email: "irb@whitman.edu",
                addressLines: [
                    "Whitman College",
                    "345 Boyer Avenue",
                    "Walla Walla, WA 99362"
                ]
            )
        ],
        consentChoices: StudyConsentChoices(
            agreeText: "I Agree",
            declineText: "I Do Not Agree",
            finalAgreeLanguage: [
                "You are 18 years or older.",
                "You have read and understood this information.",
                "Participation is voluntary.",
                "You agree to participate in this study."
            ]
        ),
        attestation: StudyConsentAttestation(
            version: "study-no-1-attestation-v1",
            text: "I am 18 or older, understand participation is voluntary, and agree to participate."
        ),
        signatureRequirement: .studyEnrollment
    )
}

private extension String {
    var isValidSHA256Hex: Bool {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 64 else { return false }
        return trimmed.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (97...102).contains(byte)
        }
    }
}
