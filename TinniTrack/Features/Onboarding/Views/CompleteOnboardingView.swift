//
//  CompleteOnboardingView.swift
//  TinniTrack
//

import SwiftUI

struct CompleteOnboardingView: View {
    private enum Field: Hashable {
        case firstName
        case lastName
    }

    @EnvironmentObject private var sessionStore: SessionStore

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var dateOfBirth = Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()
    @FocusState private var focusedField: Field?

    private var canSubmit: Bool {
        !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && dateOfBirth <= Date()
    }

    var body: some View {
        Form {
            Section("Complete Profile") {
                TextField("First Name", text: $firstName)
                    .textContentType(.givenName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focusedField, equals: .firstName)
                    .onSubmit { focusedField = .lastName }
                TextField("Last Name", text: $lastName)
                    .textContentType(.familyName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($focusedField, equals: .lastName)
                    .onSubmit { dismissTextFocus() }
                DatePicker("Date of Birth", selection: $dateOfBirth, in: ...Date(), displayedComponents: .date)
                    .onTapGesture { dismissTextFocus() }
            }

            Section {
                Button("Finish Onboarding") {
                    dismissTextFocus()
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
                    dismissTextFocus()
                    Task {
                        await sessionStore.signOut()
                    }
                }
            }
        }
        .navigationTitle("Onboarding")
        .scrollDismissesKeyboard(.immediately)
        .onAppear {
            if let profile = sessionStore.state.profile {
                firstName = profile.firstName ?? firstName
                lastName = profile.lastName ?? lastName
                dateOfBirth = profile.dateOfBirth ?? dateOfBirth
            }
        }
    }

    private func dismissTextFocus() {
        focusedField = nil
    }
}

#if DEBUG
#Preview {
    CompleteOnboardingView()
        .environmentObject(SessionStoreFactory.makePreviewStore(.authenticatedNeedsOnboarding))
}
#endif
