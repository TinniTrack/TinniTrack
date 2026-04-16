//
//  ResetPasswordView.swift
//  TinniTrack
//

import SwiftUI

struct ResetPasswordView: View {
    @EnvironmentObject private var sessionStore: SessionStore

    @State private var newPassword = ""
    @State private var confirmPassword = ""

    private var canSubmit: Bool {
        newPassword.count >= 6 && newPassword == confirmPassword
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Set New Password") {
                    SecureField("New Password", text: $newPassword)
                    SecureField("Confirm Password", text: $confirmPassword)
                }

                Section {
                    Button("Update Password") {
                        Task {
                            await sessionStore.submitNewPassword(newPassword)
                        }
                    }
                    .disabled(!canSubmit || sessionStore.state.isBusy)
                }
            }
            .navigationTitle("Reset Password")
        }
    }
}

#Preview {
    ResetPasswordView()
        .environmentObject(SessionStoreFactory.makePreviewStore())
}
