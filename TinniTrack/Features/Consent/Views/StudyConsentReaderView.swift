import SwiftUI
import UIKit

struct StudyConsentReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: StudyConsentFlowViewModel
    let onEnrollmentCompleted: @MainActor () async -> Void
    @State private var isSignaturePresented = false
    @State private var isDeclineConfirmationPresented = false
    private let topAnchorID = "study_consent_reader_top"
    private let scrollCoordinateSpaceName = "study_consent_reader_scroll_space"

    var body: some View {
        GeometryReader { viewportProxy in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        StudyConsentProgressHeader(
                            stepText: "Step 1 of 2",
                            progress: 0.5,
                            title: "Informed Consent",
                            subtitle: viewModel.definition.landing.title
                        )
                        .id(topAnchorID)

                        StudyConsentKeyInfoCard(keyInformation: viewModel.definition.keyInformation)

                        ForEach(viewModel.visibleSections) { section in
                            StudyConsentSectionView(section: section)
                                .id(section.id)
                        }

                        StudyConsentBottomSentinel()
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 34)
                }
                .coordinateSpace(name: scrollCoordinateSpaceName)
                .accessibilityIdentifier("study_consent_reader_scroll")
                .onPreferenceChange(StudyConsentBottomSentinelPreferenceKey.self) { bottomY in
                    markConsentReviewedIfBottomIsVisible(
                        bottomY: bottomY,
                        viewportHeight: viewportProxy.size.height
                    )
                }
                .onAppear {
                    DispatchQueue.main.async {
                        proxy.scrollTo(topAnchorID, anchor: .top)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            StudyConsentBottomActionBar(
                secondaryTitle: "I do not agree",
                primaryTitle: "I agree, continue to signature",
                isPrimaryEnabled: viewModel.canContinueToSignature,
                secondaryAction: { isDeclineConfirmationPresented = true },
                primaryAction: {
                    guard viewModel.canContinueToSignature else { return }
                    viewModel.continueToSignature()
                    isSignaturePresented = true
                }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationDestination(isPresented: $isSignaturePresented) {
            StudyConsentSignatureView(
                viewModel: viewModel,
                onEnrollmentCompleted: handleCompletedEnrollment,
                exitConsentFlow: {
                    viewModel.exitConsentFlowToStudyDetails()
                    isSignaturePresented = false
                    dismiss()
                }
            )
            .navigationTitle("Sign Consent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .foregroundStyle(LoudnessMatchModalColors.text)
            .background(LoudnessMatchModalColors.background)
        }
        .onChange(of: isSignaturePresented) { wasPresented, isPresented in
            guard wasPresented, !isPresented else { return }
            viewModel.returnToReviewAfterSignatureNavigationPop()
        }
        .background(LoudnessMatchModalColors.background)
        .declineConsentConfirmation(isPresented: $isDeclineConfirmationPresented) {
            viewModel.exitConsentFlowToStudyDetails()
            dismiss()
        }
    }

    @MainActor
    private func handleCompletedEnrollment() async {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isSignaturePresented = false
        }
        await Task.yield()
        await onEnrollmentCompleted()
    }

    private func markConsentReviewedIfBottomIsVisible(bottomY: CGFloat, viewportHeight: CGFloat) {
        guard !viewModel.canContinueToSignature,
              viewportHeight > 0,
              bottomY > 0,
              bottomY <= viewportHeight + 16 else {
            return
        }
        viewModel.markConsentScrolledToEnd()
    }
}

private struct StudyConsentBottomSentinel: View {
    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(
                    key: StudyConsentBottomSentinelPreferenceKey.self,
                    value: proxy.frame(in: .named("study_consent_reader_scroll_space")).maxY
                )
        }
        .frame(height: 1)
        .accessibilityHidden(true)
    }
}

private struct StudyConsentBottomSentinelPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = .greatestFiniteMagnitude

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = min(value, nextValue())
    }
}

struct StudyConsentProgressHeader: View {
    let stepText: String
    let progress: CGFloat
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(stepText)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(LoudnessMatchModalColors.primary)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(uiColor: .systemGray5))
                    Capsule()
                        .fill(LoudnessMatchModalColors.primary)
                        .frame(width: proxy.size.width * progress)
                }
            }
            .frame(height: 4)
            .padding(.trailing, 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(LoudnessMatchModalColors.text)
                    .lineLimit(2)
                    .minimumScaleFactor(0.86)

                Text(subtitle)
                    .font(.system(size: 16))
                    .foregroundStyle(StudyConsentReadableColors.bodyText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct StudyConsentBottomActionBar: View {
    let secondaryTitle: String
    let primaryTitle: String
    let isPrimaryEnabled: Bool
    let secondaryAction: () -> Void
    let primaryAction: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: isPrimaryEnabled ? "checkmark.circle.fill" : "arrow.down.circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isPrimaryEnabled ? LoudnessMatchModalColors.success : LoudnessMatchModalColors.primary)
                Text(isPrimaryEnabled ? "Consent reviewed. You can continue." : "Scroll to the bottom of the consent form to continue.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(StudyConsentReadableColors.bodyText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("study_consent_scroll_gate_message")

            HStack(spacing: 14) {
                Button(secondaryTitle, action: secondaryAction)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(LoudnessMatchModalColors.primary)
                    .frame(width: 92)
                    .accessibilityIdentifier("study_consent_decline_button")

                Button(action: primaryAction) {
                    StudyConsentPrimaryNavigationLabel(
                        title: primaryTitle,
                        isEnabled: isPrimaryEnabled
                    )
                    .accessibilityIdentifier("study_consent_signature_button")
                }
                .buttonStyle(AppCapsuleButtonStyle())
                .disabled(!isPrimaryEnabled)
                .accessibilityIdentifier("study_consent_signature_button")
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 14)
        .padding(.bottom, 18)
        .background(Color(uiColor: .systemBackground))
        .overlay(alignment: .top) {
            Divider()
        }
    }
}
