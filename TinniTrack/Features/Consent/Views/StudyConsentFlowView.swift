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
    case review
    case signature

    var depthFromLanding: Int {
        switch self {
        case .review:
            return 1
        case .signature:
            return 2
        }
    }
}

struct StudyConsentNavigationContext: Equatable {
    let landingPathCount: Int

    init(landingPathCount: Int) {
        self.landingPathCount = max(0, landingPathCount)
    }

    func canPresent(_ route: StudyConsentRoute, at currentPathCount: Int) -> Bool {
        currentPathCount == landingPathCount + route.depthFromLanding - 1
    }

    func presentedStepCount(at currentPathCount: Int) -> Int? {
        guard currentPathCount >= landingPathCount else { return nil }
        return currentPathCount - landingPathCount
    }
}

struct StudyConsentFlowView: View {
    let onCompleted: @MainActor (StudyEnrollment) -> Void

    @Binding private var navigationPath: NavigationPath
    @StateObject private var viewModel: StudyConsentFlowViewModel
    @State private var navigationContext: StudyConsentNavigationContext

    init(
        study: Study,
        definition: StudyConsentDefinition,
        consentService: ConsentServiceProtocol,
        navigationPath: Binding<NavigationPath>,
        onCompleted: @escaping @MainActor (StudyEnrollment) -> Void
    ) {
        self.onCompleted = onCompleted
        _navigationPath = navigationPath
        _navigationContext = State(initialValue: StudyConsentNavigationContext(
            landingPathCount: navigationPath.wrappedValue.count
        ))
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
        .foregroundStyle(LoudnessMatchModalColors.text)
        .background(LoudnessMatchModalColors.background.ignoresSafeArea())
        .navigationDestination(for: StudyConsentRoute.self) { route in
            consentDestination(for: route)
        }
        .task {
            await viewModel.probeEnrollmentRecoveryIfNeeded()
        }
        .alert("Unable to Finish Enrollment", isPresented: recoveryEnrollmentErrorPresentation) {
            Button("Try Again") {
                completeEnrollment(using: .recovery)
            }
            Button("Not Now", role: .cancel) {
                viewModel.dismissEnrollmentError()
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func consentDestination(for route: StudyConsentRoute) -> some View {
        switch route {
        case .review:
            StudyConsentReaderView(
                definition: viewModel.definition,
                visibleSections: viewModel.visibleSections,
                canContinueToSignature: viewModel.canContinueToSignature,
                markConsentReviewed: viewModel.markConsentScrolledToEnd,
                continueToSignature: presentSignature,
                declineConsent: { exitConsentToLanding(from: .review) }
            )
            .consentStepChrome(title: "Informed Consent")

        case .signature:
            StudyConsentSignatureView(
                definition: viewModel.definition,
                firstName: $viewModel.firstName,
                lastName: $viewModel.lastName,
                signatureImageData: $viewModel.signatureImageData,
                canSignAndEnroll: viewModel.canSignAndEnroll,
                isFinalizingEnrollment: viewModel.isFinalizingSignedConsent,
                clearSignature: viewModel.clearSignature,
                signAndEnroll: { completeEnrollment(using: .signedConsent) },
                declineConsent: { exitConsentToLanding(from: .signature) }
            )
            .consentStepChrome(title: "Sign Consent")
            .alert("Unable to Finish Enrollment", isPresented: signedEnrollmentErrorPresentation) {
                Button("Try Again") {
                    viewModel.dismissEnrollmentError()
                }
                Button("Cancel", role: .cancel) {
                    exitConsentToLanding(from: .signature)
                }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .navigationBarBackButtonHidden(viewModel.isFinalizingSignedConsent)
        }
    }

    private var recoveryEnrollmentErrorPresentation: Binding<Bool> {
        Binding(
            get: { viewModel.shouldRetryEnrollmentRecoveryFromAlert },
            set: dismissEnrollmentErrorIfNeeded
        )
    }

    private var signedEnrollmentErrorPresentation: Binding<Bool> {
        Binding(
            get: { viewModel.hasSignedConsentError },
            set: dismissEnrollmentErrorIfNeeded
        )
    }

    private func dismissEnrollmentErrorIfNeeded(_ isPresented: Bool) {
        if !isPresented {
            viewModel.dismissEnrollmentError()
        }
    }

    @MainActor
    private func presentConsentReview() {
        guard viewModel.canReviewConsent,
              navigationContext.canPresent(.review, at: navigationPath.count) else { return }
        viewModel.prepareConsentReview()
        navigationPath.append(StudyConsentRoute.review)
    }

    @MainActor
    private func presentSignature() {
        guard viewModel.canContinueToSignature,
              navigationContext.canPresent(.signature, at: navigationPath.count) else { return }
        navigationPath.append(StudyConsentRoute.signature)
    }

    @MainActor
    private func exitConsentToLanding(from _: StudyConsentRoute) {
        guard !viewModel.isEnrollmentInProgress else { return }
        popToConsentLanding()
    }

    @MainActor
    private func popToConsentLanding() {
        guard let count = navigationContext.presentedStepCount(at: navigationPath.count),
              count > 0 else { return }
        navigationPath.removeLast(count)
    }

    @MainActor
    private func completeEnrollment(using source: StudyConsentFlowViewModel.EnrollmentSource) {
        Task { @MainActor in
            guard let enrollment = await viewModel.completeEnrollment(using: source) else { return }
            if source == .signedConsent {
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    popToConsentLanding()
                }
            }
            onCompleted(enrollment)
        }
    }
}

private extension View {
    func consentStepChrome(title: String) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .foregroundStyle(LoudnessMatchModalColors.text)
            .background(LoudnessMatchModalColors.background.ignoresSafeArea())
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
