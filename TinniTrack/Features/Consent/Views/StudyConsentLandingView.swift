import SwiftUI
import UIKit

struct StudyConsentLandingView: View {
    let definition: StudyConsentDefinition
    let reviewConsent: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(definition.landing.title)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(LoudnessMatchModalColors.text)
                        .lineLimit(2)
                        .minimumScaleFactor(0.86)

                    Text(definition.landing.subtitle)
                        .font(.system(size: 16))
                        .lineSpacing(3)
                        .foregroundStyle(StudyConsentReadableColors.bodyText)
                }

                StudyConsentAtAGlanceCard(rows: definition.landing.atAGlanceRows)

                StudyConsentTextSection(
                    title: "What you'll do:",
                    bodyText: definition.landing.whatYouWillDo
                )

                VStack(alignment: .leading, spacing: 10) {
                    Text("You may be eligible if:")
                        .font(.system(size: 16, weight: .bold))

                    ForEach(definition.landing.eligibilityItems, id: \.self) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(LoudnessMatchModalColors.primary)
                                .frame(width: 5, height: 5)
                                .padding(.top, 7)

                            Text(item)
                                .font(.system(size: 14))
                                .foregroundStyle(LoudnessMatchModalColors.text)
                        }
                    }
                }

                StudyConsentCallout(
                    systemName: "info.circle",
                    title: definition.landing.beforeEnrollTitle,
                    bodyText: definition.landing.beforeEnrollBody
                )

                Button(action: reviewConsent) {
                    StudyConsentPrimaryNavigationLabel(title: definition.landing.primaryActionTitle)
                }
                .buttonStyle(AppCapsuleButtonStyle())
                .accessibilityIdentifier("study_consent_review_button")
                .padding(.top, 2)

                Text(definition.landing.footerNote)
                    .font(.footnote)
                    .foregroundStyle(StudyConsentReadableColors.bodyText)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 34)
            .padding(.bottom, 28)
        }
        .background(LoudnessMatchModalColors.background)
        .accessibilityIdentifier("study_consent_landing")
    }
}

private struct StudyConsentAtAGlanceCard: View {
    let rows: [StudyConsentAtAGlanceRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("At a glance")
                .font(.system(size: 16, weight: .bold))
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 6)

            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 14) {
                    Image(systemName: row.symbolName)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(LoudnessMatchModalColors.primary)
                        .frame(width: 26)

                    Text(row.label)
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 112, alignment: .leading)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)

                    Text(row.value)
                        .font(.system(size: 14))
                        .foregroundStyle(LoudnessMatchModalColors.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)

                if index < rows.count - 1 {
                    Divider()
                        .padding(.leading, 54)
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(LoudnessMatchModalColors.controlStroke, lineWidth: 1)
        }
    }
}

private struct StudyConsentTextSection: View {
    let title: String
    let bodyText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 16, weight: .bold))
            Text(bodyText)
                .font(.system(size: 15))
                .lineSpacing(3)
                .foregroundStyle(StudyConsentReadableColors.bodyText)
        }
    }
}

struct StudyConsentPrimaryNavigationLabel: View {
    let title: String
    var isEnabled = true

    var body: some View {
        Text(title)
            .font(.headline)
            .fontWeight(.semibold)
            .lineLimit(2)
            .minimumScaleFactor(0.82)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 58)
            .padding(.horizontal, 18)
            .background(isEnabled ? LoudnessMatchModalColors.primary : LoudnessMatchModalColors.disabledFill)
            .foregroundStyle(isEnabled ? LoudnessMatchModalColors.primaryText : LoudnessMatchModalColors.disabledText)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(LoudnessMatchModalColors.buttonStroke, lineWidth: 1)
            }
    }
}
