import SwiftUI
import UIKit

struct StudyConsentLandingView: View {
    let definition: StudyConsentDefinition
    let enrollmentRecoveryStatus: StudyConsentFlowViewModel.EnrollmentRecoveryStatus
    let isResumingEnrollment: Bool
    let canReviewConsent: Bool
    let reviewConsent: () -> Void
    let resumeEnrollment: () -> Void
    let retryEnrollmentRecoveryProbe: () -> Void

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

                enrollmentAction
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

    @ViewBuilder
    private var enrollmentAction: some View {
        switch enrollmentRecoveryStatus {
        case .notChecked, .checking:
            HStack(spacing: 12) {
                ProgressView()
                Text("Checking for an enrollment already in progress…")
                    .font(.subheadline)
                    .foregroundStyle(StudyConsentReadableColors.bodyText)
            }
            .frame(maxWidth: .infinity, minHeight: 58)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("study_consent_recovery_checking")

        case .unavailable:
            if canReviewConsent {
                Button(action: reviewConsent) {
                    StudyConsentPrimaryNavigationLabel(title: definition.landing.primaryActionTitle)
                }
                .buttonStyle(AppCapsuleButtonStyle())
                .accessibilityIdentifier("study_consent_review_button")
            } else {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Opening your study…")
                        .font(.subheadline)
                        .foregroundStyle(StudyConsentReadableColors.bodyText)
                }
                .frame(maxWidth: .infinity, minHeight: 58)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("study_consent_completion_routing")
            }

        case .available(let recovery):
            StudyConsentRecoveryCard(
                recovery: recovery,
                isResuming: isResumingEnrollment,
                resumeEnrollment: resumeEnrollment
            )

        case .failed(let message):
            VStack(alignment: .leading, spacing: 12) {
                Label("Enrollment status unavailable", systemImage: "exclamationmark.triangle")
                    .font(.headline)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(StudyConsentReadableColors.bodyText)

                Button(action: retryEnrollmentRecoveryProbe) {
                    StudyConsentPrimaryNavigationLabel(title: "Try Status Check Again")
                }
                .buttonStyle(AppCapsuleButtonStyle())
                .accessibilityIdentifier("study_consent_recovery_probe_retry_button")
            }
            .padding(16)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityIdentifier("study_consent_recovery_probe_error")
        }
    }
}

private struct StudyConsentRecoveryCard: View {
    let recovery: ConsentEnrollmentRecovery
    let isResuming: Bool
    let resumeEnrollment: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: "arrow.clockwise.circle.fill")
                .font(.headline)
                .foregroundStyle(LoudnessMatchModalColors.primary)
                .accessibilityIdentifier("study_consent_recovery_card")

            Text(message)
                .font(.subheadline)
                .lineSpacing(2)
                .foregroundStyle(StudyConsentReadableColors.bodyText)

            Button(action: resumeEnrollment) {
                HStack(spacing: 10) {
                    if isResuming {
                        ProgressView()
                            .tint(LoudnessMatchModalColors.primaryText)
                    }
                    Text(isResuming ? "Resuming Enrollment…" : "Resume Enrollment")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 58)
                .padding(.horizontal, 18)
                .background(LoudnessMatchModalColors.primary)
                .foregroundStyle(LoudnessMatchModalColors.primaryText)
                .clipShape(Capsule())
                .overlay {
                    Capsule()
                        .stroke(LoudnessMatchModalColors.buttonStroke, lineWidth: 1)
                }
            }
            .buttonStyle(AppCapsuleButtonStyle())
            .disabled(isResuming)
            .accessibilityIdentifier("study_consent_resume_enrollment_button")
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(LoudnessMatchModalColors.controlStroke, lineWidth: 1)
        }
    }

    private var title: String {
        switch recovery {
        case .pendingUpload:
            return "Your signed consent is ready to resume"
        case .pendingEnrollment:
            return "Your enrollment is ready to finish"
        }
    }

    private var message: String {
        switch recovery {
        case .pendingUpload:
            return "Your signed consent is saved securely on this device. Resume enrollment to upload it without signing again."
        case .pendingEnrollment:
            return "Your signed consent is already recorded. Resume enrollment to finish joining the study without signing again."
        }
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
