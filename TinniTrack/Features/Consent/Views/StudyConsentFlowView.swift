//
//  StudyConsentFlowView.swift
//  TinniTrack
//

import SwiftUI
import UIKit

enum StudyConsentReadableColors {
    static let bodyText = Color(uiColor: .label)
}

enum StudyConsentRoute: Hashable {
    case landing
    case review
    case signature

    var presentsReview: Bool {
        self != .landing
    }

    var presentsSignature: Bool {
        self == .signature
    }

    mutating func setReviewPresented(_ isPresented: Bool) {
        if isPresented {
            if self == .landing {
                self = .review
            }
        } else {
            self = .landing
        }
    }

    mutating func setSignaturePresented(_ isPresented: Bool) {
        if isPresented {
            if self == .review {
                self = .signature
            }
        } else if self == .signature {
            self = .review
        }
    }
}

struct StudyConsentFlowView: View {
    let onCompleted: @MainActor (StudyEnrollment) -> Void

    @StateObject private var viewModel: StudyConsentFlowViewModel
    @State private var route: StudyConsentRoute = .landing

    init(
        study: Study,
        definition: StudyConsentDefinition,
        consentService: ConsentServiceProtocol,
        onCompleted: @escaping @MainActor (StudyEnrollment) -> Void
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
            isResumingEnrollment: viewModel.isResumingEnrollment,
            canReviewConsent: viewModel.canReviewConsent,
            reviewConsent: presentConsentReview,
            resumeEnrollment: { completeEnrollment(using: .recovery) },
            retryEnrollmentRecoveryProbe: {
                Task { @MainActor in
                    await viewModel.retryEnrollmentRecoveryProbe()
                }
            }
        )
        .navigationTitle("Study Details")
        .navigationBarTitleDisplayMode(.inline)
        .foregroundStyle(LoudnessMatchModalColors.text)
        .background(LoudnessMatchModalColors.background)
        .navigationDestination(isPresented: reviewPresentation) {
            StudyConsentReaderView(
                definition: viewModel.definition,
                visibleSections: viewModel.visibleSections,
                canContinueToSignature: viewModel.canContinueToSignature,
                markConsentReviewed: viewModel.markConsentScrolledToEnd,
                continueToSignature: presentSignature,
                declineConsent: exitConsentToLanding
            )
            .navigationTitle("Informed Consent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .foregroundStyle(LoudnessMatchModalColors.text)
            .background(LoudnessMatchModalColors.background)
            .navigationDestination(isPresented: signaturePresentation) {
                StudyConsentSignatureView(
                    definition: viewModel.definition,
                    firstName: $viewModel.firstName,
                    lastName: $viewModel.lastName,
                    signatureImageData: $viewModel.signatureImageData,
                    canSignAndEnroll: viewModel.canSignAndEnroll,
                    isFinalizingEnrollment: viewModel.isFinalizingSignedConsent,
                    clearSignature: viewModel.clearSignature,
                    signAndEnroll: { completeEnrollment(using: .signedConsent) },
                    declineConsent: exitConsentToLanding
                )
                .navigationTitle("Sign Consent")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.hidden, for: .tabBar)
                .foregroundStyle(LoudnessMatchModalColors.text)
                .background(LoudnessMatchModalColors.background)
            }
        }
        .task {
            await viewModel.probeEnrollmentRecoveryIfNeeded()
        }
        .alert("Unable to Finish Enrollment", isPresented: enrollmentErrorPresentation) {
            if viewModel.shouldRetryEnrollmentRecoveryFromAlert {
                Button("Try Again") {
                    completeEnrollment(using: .recovery)
                }
                Button("Not Now", role: .cancel) {
                    viewModel.dismissEnrollmentError()
                }
            } else {
                Button("Try Again") {
                    viewModel.dismissEnrollmentError()
                }
                Button("Cancel", role: .cancel) {
                    exitConsentToLanding()
                }
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var reviewPresentation: Binding<Bool> {
        Binding(
            get: { route.presentsReview },
            set: { isPresented in
                let previousRoute = route
                route.setReviewPresented(isPresented)
                if previousRoute != route, route == .landing {
                    viewModel.resetConsentReviewProgress()
                }
            }
        )
    }

    private var signaturePresentation: Binding<Bool> {
        Binding(
            get: { route.presentsSignature },
            set: { isPresented in
                let previousRoute = route
                route.setSignaturePresented(isPresented)
                if previousRoute == .signature, route == .review {
                    viewModel.resetConsentReviewProgress()
                }
            }
        )
    }

    private var enrollmentErrorPresentation: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.dismissEnrollmentError()
                }
            }
        )
    }

    @MainActor
    private func presentConsentReview() {
        guard viewModel.canReviewConsent else { return }
        viewModel.prepareConsentReview()
        route = .review
    }

    @MainActor
    private func presentSignature() {
        guard route == .review, viewModel.canContinueToSignature else { return }
        route = .signature
    }

    @MainActor
    private func exitConsentToLanding() {
        guard !viewModel.isEnrollmentInProgress else { return }
        viewModel.abandonConsentAttempt()
        route = .landing
    }

    @MainActor
    private func completeEnrollment(using source: StudyConsentFlowViewModel.EnrollmentSource) {
        Task { @MainActor in
            guard let enrollment = await viewModel.completeEnrollment(using: source) else { return }
            onCompleted(enrollment)
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
