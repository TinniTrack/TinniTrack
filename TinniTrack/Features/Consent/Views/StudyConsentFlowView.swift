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
    @State private var isCompletionHandlingRequested = false

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
            reviewConsent: { isReviewPresented = true }
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
                    isCompletionHandlingRequested: $isCompletionHandlingRequested
                )
                .navigationTitle("Informed Consent")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.hidden, for: .tabBar)
                .foregroundStyle(LoudnessMatchModalColors.text)
                .background(LoudnessMatchModalColors.background)
            }
            .task(id: viewModel.state) {
                if viewModel.state == .completed {
                    await handleCompletedEnrollment()
                } else if viewModel.state == .dismissed {
                    dismiss()
                }
            }
            .task(id: isCompletionHandlingRequested) {
                guard isCompletionHandlingRequested else { return }
                await handleCompletedEnrollment()
            }
            .alert("Unable to Finish Enrollment", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { shouldShow in
                    if !shouldShow {
                        viewModel.errorMessage = nil
                    }
                }
            )) {
                Button("Try Again") {
                    viewModel.retryAfterFailure()
                }
                Button("Cancel", role: .cancel) {
                    viewModel.declineOrCancel()
                }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
    }

    @MainActor
    private func handleCompletedEnrollment() async {
        guard !hasHandledCompletion else {
            isCompletionHandlingRequested = false
            return
        }
        hasHandledCompletion = true
        isCompletionHandlingRequested = false
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
