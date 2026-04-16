//
//  EmailVerificationPendingView.swift
//  TinniTrack
//

import SwiftUI

struct EmailVerificationPendingView: View {
    @EnvironmentObject private var sessionStore: SessionStore

    private let actionColor = Color(red: 0.06, green: 0.24, blue: 0.44)

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "envelope.badge")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(actionColor)
                .accessibilityHidden(true)

            Text("Verify your email")
                .font(.system(size: 31, weight: .bold))
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("email_verification_title")

            if let email = sessionStore.state.pendingVerificationEmail {
                Text("We sent a verification link to \(email). Open that email on this device to continue.")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .accessibilityIdentifier("email_verification_message")
            } else {
                Text("We sent a verification link to your email. Open that email on this device to continue.")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .accessibilityIdentifier("email_verification_message")
            }

            VStack(spacing: 12) {
                Button("Resend verification email") {
                    Task {
                        await sessionStore.resendVerificationEmail()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(actionColor)
                .accessibilityIdentifier("email_verification_resend_button")

                Button("I verified my email") {
                    Task {
                        await sessionStore.checkEmailVerificationStatus()
                    }
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("email_verification_check_button")

                Button("Use different email", role: .destructive) {
                    sessionStore.useDifferentEmailForVerification()
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .accessibilityIdentifier("email_verification_use_different_email_button")
            }
            .padding(.top, 8)

            Spacer()
        }
        .padding()
    }
}

#Preview {
    EmailVerificationPendingView()
        .environmentObject(
            SessionStoreFactory.makePreviewStore(.awaitingEmailVerification(email: "pending@example.com"))
        )
}
