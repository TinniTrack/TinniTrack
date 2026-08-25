import SwiftUI
import UIKit

struct StudyConsentCallout: View {
    let systemName: String
    let title: String
    let bodyText: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemName)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(LoudnessMatchModalColors.primary)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                StudyConsentEmailAwareText(text: bodyText, emailContext: title)
                    .font(.system(size: 13))
            }
        }
        .padding(12)
        .background(LoudnessMatchModalColors.primary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(LoudnessMatchModalColors.primary.opacity(0.35), lineWidth: 1)
        }
    }
}

private struct StudyConsentEmailAwareText: View {
    let text: String
    let emailContext: String?

    private var emailText: String? {
        StudyConsentEmailInteraction.firstEmail(in: text)
    }

    var body: some View {
        if let emailText,
           let emailRange = text.range(of: emailText) {
            let prefix = String(text[..<emailRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = String(text[emailRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)

            VStack(alignment: .leading, spacing: 2) {
                if !prefix.isEmpty {
                    Text(prefix)
                        .lineSpacing(2)
                }
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    StudyConsentEmailLink(email: emailText, context: emailContext)
                    if !suffix.isEmpty {
                        Text(suffix)
                            .lineSpacing(2)
                    }
                }
            }
        } else {
            Text(text)
                .lineSpacing(2)
        }
    }
}

struct StudyConsentKeyInfoCard: View {
    let keyInformation: StudyConsentKeyInformation

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(LoudnessMatchModalColors.primary)
                Text(keyInformation.title)
                    .font(.system(size: 15, weight: .bold))
            }

            ForEach(keyInformation.bulletItems + keyInformation.checkItems, id: \.self) { item in
                consentInfoRow(text: item)
            }
        }
        .padding(12)
        .background(LoudnessMatchModalColors.primary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(LoudnessMatchModalColors.primary.opacity(0.25), lineWidth: 1)
        }
    }

    private func consentInfoRow(text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(LoudnessMatchModalColors.primary)
                .frame(width: 5, height: 5)
                .frame(width: 13, height: 18)
                .padding(.top, 1)

            Text(text)
                .font(.system(size: 14))
                .lineSpacing(2)
                .foregroundStyle(StudyConsentReadableColors.bodyText)
        }
    }
}

struct StudyConsentSectionView: View {
    let section: StudyConsentSection

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(section.title)
                .font(.system(size: 16, weight: .bold))

            ForEach(Array(section.blocks.enumerated()), id: \.offset) { _, block in
                StudyConsentBlockView(block: block)
            }
        }
    }
}

private struct StudyConsentBlockView: View {
    let block: StudyConsentContentBlock

    var body: some View {
        switch block {
        case .paragraph(let text):
            Text(text)
                .font(.system(size: 14))
                .lineSpacing(3)
                .foregroundStyle(StudyConsentReadableColors.bodyText)
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 7) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 9) {
                        Circle()
                            .fill(LoudnessMatchModalColors.primary)
                            .frame(width: 5, height: 5)
                            .padding(.top, 7)
                        Text(item)
                            .font(.system(size: 14))
                            .lineSpacing(3)
                            .foregroundStyle(StudyConsentReadableColors.bodyText)
                    }
                }
            }
        case .numberedActivities(let activities):
            VStack(alignment: .leading, spacing: 18) {
                ForEach(activities, id: \.index) { activity in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(activity.index)")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(LoudnessMatchModalColors.primary)
                            .frame(width: 21, height: 21)
                            .background(LoudnessMatchModalColors.primary.opacity(0.16))
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 6) {
                            Text(activity.title)
                                .font(.system(size: 14, weight: .bold))
                            Text(activity.body)
                                .font(.system(size: 14))
                                .lineSpacing(3)
                                .foregroundStyle(LoudnessMatchModalColors.text)
                        }
                    }
                }
            }
        case .scheduleChips(let times):
            HStack(spacing: 6) {
                ForEach(times, id: \.self) { time in
                    Text(time)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(StudyConsentReadableColors.bodyText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .allowsTightening(true)
                        .frame(maxWidth: .infinity)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 9)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(LoudnessMatchModalColors.controlStroke, lineWidth: 1)
                    }
                }
            }
        case .callout(let title, let body):
            StudyConsentCallout(systemName: "info.circle", title: title, bodyText: body)
        case .contacts(let contacts):
            VStack(alignment: .leading, spacing: 10) {
                ForEach(contacts, id: \.email) { contact in
                    StudyConsentContactView(contact: contact)
                }
            }
        }
    }
}

private struct StudyConsentContactView: View {
    let contact: StudyConsentContact

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(contact.title)
            Text(contact.name)
            if let affiliation = contact.affiliation {
                Text(affiliation)
            }
            StudyConsentEmailLink(email: contact.email)
            ForEach(contact.addressLines, id: \.self) { addressLine in
                Text(addressLine)
            }
        }
        .font(.system(size: 14))
        .lineSpacing(3)
        .foregroundStyle(StudyConsentReadableColors.bodyText)
    }
}

struct StudyConsentEmailInteraction {
    static func firstEmail(in text: String) -> String? {
        let emailPattern = #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#
        guard let range = text.range(
            of: emailPattern,
            options: [.regularExpression, .caseInsensitive]
        ) else {
            return nil
        }

        return String(text[range])
    }

    static func mailtoURL(for email: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email
        return components.url
    }

    static func copyEmailToPasteboard(_ email: String) {
        UIPasteboard.general.string = email
    }

    static func accessibilityIdentifier(for email: String, context: String? = nil) -> String {
        let sanitized = email
            .lowercased()
            .map { character in
                character.isLetter || character.isNumber ? character : "_"
            }
        let baseIdentifier = "study_consent_email_\(String(sanitized))"
        guard let context else {
            return baseIdentifier
        }

        let sanitizedContext = context
            .lowercased()
            .map { character in
                character.isLetter || character.isNumber ? character : "_"
            }
        return "\(baseIdentifier)_\(String(sanitizedContext))"
    }
}

private struct StudyConsentEmailLink: View {
    let email: String
    var context: String?

    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            if let mailtoURL = StudyConsentEmailInteraction.mailtoURL(for: email) {
                openURL(mailtoURL)
            }
        } label: {
            Text(email)
                .underline()
                .foregroundStyle(.blue)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                StudyConsentEmailInteraction.copyEmailToPasteboard(email)
            } label: {
                Label("Copy Email", systemImage: "doc.on.doc")
            }
        }
        .accessibilityLabel("Email \(email)")
        .accessibilityHint("Opens a new email. Long press to copy the address.")
        .accessibilityIdentifier(StudyConsentEmailInteraction.accessibilityIdentifier(for: email, context: context))
    }
}
