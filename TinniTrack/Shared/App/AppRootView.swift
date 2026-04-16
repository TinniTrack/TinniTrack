//
//  AppRootView.swift
//  TinniTrack
//

import SwiftUI

struct AppRootView: View {
    @EnvironmentObject private var sessionStore: SessionStore

    var body: some View {
        rootContent
        .alert(sessionStore.state.banner?.title ?? "Info", isPresented: Binding(
            get: { sessionStore.state.banner != nil },
            set: { shouldPresent in
                if !shouldPresent {
                    sessionStore.dismissBanner()
                }
            }
        )) {
            Button("OK", role: .cancel) { sessionStore.dismissBanner() }
        } message: {
            Text(sessionStore.state.banner?.message ?? "")
        }
        .fullScreenCover(isPresented: Binding(
            get: { sessionStore.state.passwordResetPresented },
            set: { isPresented in
                if !isPresented {
                    sessionStore.dismissPasswordResetSheet()
                }
            }
        )) {
            ResetPasswordView()
                .environmentObject(sessionStore)
        }
    }

    @ViewBuilder
    private var rootContent: some View {
        switch sessionStore.state.route {
        case .ready:
            HomeView()
        case .bootstrapping, .unauthenticated, .awaitingEmailVerification, .needsOnboarding:
            NavigationStack {
                switch sessionStore.state.route {
                case .bootstrapping:
                    ProgressView("Loading…")
                case .unauthenticated:
                    LoginView()
                case .awaitingEmailVerification:
                    EmailVerificationPendingView()
                case .needsOnboarding:
                    CompleteOnboardingView()
                case .ready:
                    EmptyView()
                }
            }
        }
    }
}

#Preview {
    AppRootView()
        .environmentObject(SessionStoreFactory.makePreviewStore())
}
