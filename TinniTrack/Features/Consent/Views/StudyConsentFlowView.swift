//
//  StudyConsentFlowView.swift
//  TinniTrack
//

import SwiftUI
import UIKit

enum StudyConsentReadableColors {
    static let bodyText = Color(uiColor: .label)
}

struct StudyConsentFlowView: View {
    let onCompleted: @MainActor () async -> Bool

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: StudyConsentFlowViewModel
    @State private var isReviewPresented = false
    @State private var hasHandledCompletion = false

    init(
        study: Study,
        definition: StudyConsentDefinition,
        consentService: ConsentServiceProtocol,
        onCompleted: @escaping @MainActor () async -> Bool
    ) {
        self.onCompleted = onCompleted
        _viewModel = StateObject(wrappedValue: StudyConsentFlowViewModel(
            study: study,
            definition: definition,
            consentService: consentService
        ))
    }

    var body: some View {
        StudyConsentLandingView(
            definition: viewModel.definition,
            enrollmentRecoveryStatus: viewModel.enrollmentRecoveryStatus,
            isResumingEnrollment: viewModel.state == .finalizing,
            canReviewConsent: viewModel.canReviewConsent,
            reviewConsent: {
                guard viewModel.canReviewConsent else { return }
                isReviewPresented = true
            },
            resumeEnrollment: resumeEnrollmentAndHandleCompletion,
            retryEnrollmentRecoveryProbe: {
                Task {
                    await viewModel.retryEnrollmentRecoveryProbe()
                }
            }
        )
            .navigationTitle("Study Details")
            .navigationBarTitleDisplayMode(.inline)
            .foregroundStyle(LoudnessMatchModalColors.text)
            .background(LoudnessMatchModalColors.background)
            .onAppear {
                viewModel.returnToLandingAfterNavigationPop()
            }
            .navigationDestination(isPresented: $isReviewPresented) {
                StudyConsentReaderView(
                    viewModel: viewModel,
                    onEnrollmentCompleted: handleCompletedEnrollment
                )
                .navigationTitle("Informed Consent")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.hidden, for: .tabBar)
                .foregroundStyle(LoudnessMatchModalColors.text)
                .background(LoudnessMatchModalColors.background)
            }
            .task(id: viewModel.state) {
                switch viewModel.state {
                case .landing:
                    await viewModel.probeEnrollmentRecoveryIfNeeded()
                case .dismissed:
                    dismiss()
                case .reviewingConsent, .signing, .finalizing, .completed, .failed:
                    break
                }
            }
            .alert("Unable to Finish Enrollment", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { shouldShow in
                    if !shouldShow {
                        viewModel.errorMessage = nil
                    }
                }
            )) {
                if viewModel.shouldRetryEnrollmentRecoveryFromAlert {
                    Button("Try Again") {
                        resumeEnrollmentAndHandleCompletion()
                    }
                    Button("Not Now", role: .cancel) {
                        viewModel.dismissEnrollmentRecoveryError()
                    }
                } else {
                    Button("Try Again") {
                        viewModel.retryAfterFailure()
                    }
                    Button("Cancel", role: .cancel) {
                        viewModel.declineOrCancel()
                    }
                }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
    }

    @MainActor
    private func resumeEnrollmentAndHandleCompletion() {
        Task { @MainActor in
            guard await viewModel.resumeEnrollment() else { return }
            await handleCompletedEnrollment()
        }
    }

    @MainActor
    private func handleCompletedEnrollment() async {
        guard viewModel.state == .completed, !hasHandledCompletion else { return }
        hasHandledCompletion = true
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isReviewPresented = false
        }
        await Task.yield()

        let didRouteAfterCompletion = await onCompleted()
        if !didRouteAfterCompletion {
            dismiss()
        }
    }
}

extension View {
    func declineConsentConfirmation(
        isPresented: Binding<Bool>,
        exit: @escaping () -> Void
    ) -> some View {
        alert("Consent Required", isPresented: isPresented) {
            Button("Exit", role: .destructive, action: exit)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("If you do not agree to these terms, you cannot participate in this study.")
        }
    }
}
