import SwiftUI
import UIKit

private enum StudyConsentSignatureField: Hashable {
    case firstName
    case lastName
}

struct StudyConsentSignatureView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: StudyConsentFlowViewModel
    let onEnrollmentCompleted: @MainActor () async -> Void
    let exitConsentFlow: () -> Void
    @State private var isSignatureCapturePresented = false
    @State private var isDeclineConfirmationPresented = false
    @FocusState private var focusedField: StudyConsentSignatureField?

    var body: some View {
        ScrollView {
            Color.clear
                .frame(height: 1)
                .contentShape(Rectangle())
                .onTapGesture { dismissTextFocus() }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 18) {
                StudyConsentProgressHeader(
                    stepText: "Step 2 of 2",
                    progress: 1,
                    title: "Sign Consent",
                    subtitle: "By signing below, you confirm that you reviewed the consent information and choose to participate in the Loudness Match Study."
                )
                .contentShape(Rectangle())
                .onTapGesture { dismissTextFocus() }

                StudyConsentAttestationCard(text: viewModel.definition.attestation.text)
                    .onTapGesture { dismissTextFocus() }

                StudyConsentTextField(
                    title: "First name",
                    text: $viewModel.firstName,
                    textContentType: .givenName,
                    accessibilityIdentifier: "study_consent_first_name_field",
                    focusedField: $focusedField,
                    field: .firstName,
                    submitLabel: .next
                )
                .onSubmit {
                    focusedField = .lastName
                }

                StudyConsentTextField(
                    title: "Last name",
                    text: $viewModel.lastName,
                    textContentType: .familyName,
                    accessibilityIdentifier: "study_consent_last_name_field",
                    focusedField: $focusedField,
                    field: .lastName,
                    submitLabel: .done
                )
                .onSubmit {
                    dismissTextFocus()
                }

                StudySignatureCaptureCard(
                    signatureImageData: viewModel.signatureImageData,
                    drawSignature: {
                        dismissTextFocus()
                        isSignatureCapturePresented = true
                    }
                )
                .contentShape(Rectangle())
                .onTapGesture { dismissTextFocus() }

                StudyConsentMetadataRows(signedAt: Date())
                    .contentShape(Rectangle())
                    .onTapGesture { dismissTextFocus() }

                LoudnessMatchModalPrimaryButton(
                    title: "Sign and Enroll",
                    isEnabled: viewModel.canSignAndEnroll,
                    isLoading: viewModel.state == .finalizing
                ) {
                    dismissTextFocus()
                    Task { @MainActor in
                        guard await viewModel.signAndEnroll() else { return }
                        await onEnrollmentCompleted()
                    }
                }
                .padding(.top, 8)

                Button("I do not agree") {
                    dismissTextFocus()
                    isDeclineConfirmationPresented = true
                }
                .font(.headline)
                .foregroundStyle(LoudnessMatchModalColors.primary)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 24)
                .accessibilityIdentifier("study_consent_signature_decline_button")
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 20)
            .background {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { dismissTextFocus() }
            }
        }
        .accessibilityIdentifier("study_consent_signature_scroll")
        .scrollDismissesKeyboard(.immediately)
        .background(LoudnessMatchModalColors.background)
        .overlay {
            if viewModel.state == .finalizing {
                StudyConsentFinalizingView()
            }
        }
        .sheet(isPresented: $isSignatureCapturePresented) {
            StudySignatureCaptureSheet(
                signatureImageData: $viewModel.signatureImageData,
                clear: viewModel.clearSignature
            )
            .presentationDetents([.height(390), .large])
            .presentationDragIndicator(.visible)
        }
        .declineConsentConfirmation(isPresented: $isDeclineConfirmationPresented) {
            exitConsentFlow()
        }
        .onChange(of: viewModel.state) { _, state in
            if state == .finalizing {
                dismissTextFocus()
            }
        }
        .accessibilityIdentifier("study_consent_signature")
    }

    private func dismissTextFocus() {
        focusedField = nil
    }
}

private struct StudyConsentAttestationCard: View {
    let text: String

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "person")
                .font(.system(size: 23, weight: .regular))
                .foregroundStyle(LoudnessMatchModalColors.primary)
                .frame(width: 34)
                .accessibilityHidden(true)

            Text(text)
                .font(.system(size: 14))
                .lineSpacing(3)
                .foregroundStyle(StudyConsentReadableColors.bodyText)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("study_consent_attestation_text")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(LoudnessMatchModalColors.controlStroke, lineWidth: 1)
        }
    }
}

private struct StudyConsentTextField: View {
    let title: String
    @Binding var text: String
    let textContentType: UITextContentType
    let accessibilityIdentifier: String
    let focusedField: FocusState<StudyConsentSignatureField?>.Binding
    let field: StudyConsentSignatureField
    let submitLabel: SubmitLabel

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(StudyConsentReadableColors.bodyText)

            TextField(title, text: $text)
                .textContentType(textContentType)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(submitLabel)
                .focused(focusedField, equals: field)
                .font(.system(size: 17))
                .padding(.horizontal, 13)
                .frame(height: 45)
                .background(Color(uiColor: .systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(LoudnessMatchModalColors.controlStroke, lineWidth: 1)
                }
                .accessibilityIdentifier(accessibilityIdentifier)
        }
    }
}

private struct StudyConsentMetadataRows: View {
    let signedAt: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "calendar")
                    .font(.system(size: 18, weight: .medium))
                Text("Signed today, \(Self.dateFormatter.string(from: signedAt))")
                    .font(.system(size: 14))
            }

            HStack(spacing: 12) {
                Image(systemName: "lock")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(StudyConsentReadableColors.bodyText)
                    .frame(width: 30, height: 30)
                    .background(Color(uiColor: .systemGray6))
                    .clipShape(Circle())
                Text("A signed consent copy will be saved securely.")
                    .font(.system(size: 14))
                    .foregroundStyle(StudyConsentReadableColors.bodyText)
            }
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

struct StudyConsentFinalizingView: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.32)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                Text("Finalizing Enrollment")
                    .font(.headline)
                Text("Saving your signed consent securely.")
                    .font(.subheadline)
                    .foregroundStyle(StudyConsentReadableColors.bodyText)
            }
            .padding(22)
            .frame(maxWidth: 300)
            .background(Color(uiColor: .systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(radius: 18)
        }
    }
}
