//
//  CompleteOnboardingView.swift
//  TinniTrack
//

import SwiftUI

struct CompleteOnboardingView: View {
    @EnvironmentObject private var sessionStore: SessionStore

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var dateOfBirth = Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()

    private var canSubmit: Bool {
        !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && dateOfBirth <= Date()
    }

    var body: some View {
        Form {
            Section("Complete Profile") {
                TextField("First Name", text: $firstName)
                TextField("Last Name", text: $lastName)
                DatePicker("Date of Birth", selection: $dateOfBirth, in: ...Date(), displayedComponents: .date)
            }

            Section {
                Button("Finish Onboarding") {
                    Task {
                        await sessionStore.completeOnboarding(
                            firstName: firstName,
                            lastName: lastName,
                            dateOfBirth: dateOfBirth
                        )
                    }
                }
                .disabled(!canSubmit || sessionStore.state.isBusy)

                Button("Sign Out", role: .destructive) {
                    Task {
                        await sessionStore.signOut()
                    }
                }
            }
        }
        .navigationTitle("Onboarding")
        .onAppear {
            if let profile = sessionStore.state.profile {
                firstName = profile.firstName ?? firstName
                lastName = profile.lastName ?? lastName
                dateOfBirth = profile.dateOfBirth ?? dateOfBirth
            }
        }
    }
}

#Preview {
    CompleteOnboardingView()
        .environmentObject(SessionStoreFactory.makePreviewStore(.authenticatedNeedsOnboarding))
}
