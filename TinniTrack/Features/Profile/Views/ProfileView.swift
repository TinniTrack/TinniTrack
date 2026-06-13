//
//  ProfileView.swift
//  TinniTrack
//

import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var dateOfBirth = Self.defaultDateOfBirth
    @State private var loginEmail = ""
    @State private var didLoadInitialValues = false
    @State private var isDeleteConfirmationPresented = false

    private let calendar = Calendar(identifier: .gregorian)

    var body: some View {
        Form {
            Section("Account") {
                TextField("Login Email", text: $loginEmail)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("profile_email_field")

                LabeledContent("Age", value: ageText)
            }

            Section("Profile") {
                TextField("First Name", text: $firstName)
                    .textContentType(.givenName)
                    .accessibilityIdentifier("profile_first_name_field")

                TextField("Last Name", text: $lastName)
                    .textContentType(.familyName)
                    .accessibilityIdentifier("profile_last_name_field")

                DatePicker(
                    "Date of Birth",
                    selection: $dateOfBirth,
                    in: ...Date(),
                    displayedComponents: .date
                )
                .accessibilityIdentifier("profile_date_of_birth_picker")
            }

            Section("Research") {
                LabeledContent("Participant ID", value: participantIDText)
                LabeledContent("User ID", value: sessionStore.state.profile?.id.uuidString ?? "Unavailable")
                LabeledContent("Time Zone", value: sessionStore.state.profile?.timezone ?? "Unavailable")
                LabeledContent("Created", value: formattedTimestamp(sessionStore.state.profile?.createdAt))
                LabeledContent("Onboarding Completed", value: formattedTimestamp(sessionStore.state.profile?.onboardingCompletedAt))
            }

            Section {
                Button {
                    Task { await saveChanges() }
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text("Save Changes")
                    }
                }
                .disabled(!canSave)
                .accessibilityIdentifier("profile_save_button")
            }

            Section {
                Button(role: .destructive) {
                    Task { await sessionStore.signOut() }
                } label: {
                    Text("Log Out")
                }
                .disabled(sessionStore.state.isBusy)

                Button(role: .destructive) {
                    isDeleteConfirmationPresented = true
                } label: {
                    if isDeleting {
                        ProgressView()
                    } else {
                        Text("Delete Account")
                    }
                }
                .disabled(sessionStore.state.isBusy)
                .accessibilityIdentifier("profile_delete_account_button")
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadInitialValuesIfNeeded)
        .alert("Delete Account?", isPresented: $isDeleteConfirmationPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Account", role: .destructive) {
                Task { await sessionStore.deleteAccount() }
            }
            .accessibilityIdentifier("profile_confirm_delete_account_button")
        } message: {
            Text("This permanently deletes your TinniTrack account and study data.")
        }
    }

    private var isSaving: Bool {
        sessionStore.state.activity == .updatingProfile || sessionStore.state.activity == .updatingEmail
    }

    private var isDeleting: Bool {
        sessionStore.state.activity == .deletingAccount
    }

    private var trimmedFirstName: String {
        firstName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedLastName: String {
        lastName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedEmail: String {
        loginEmail.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedFirstName.isEmpty
            && !trimmedLastName.isEmpty
            && !trimmedEmail.isEmpty
            && !sessionStore.state.isBusy
            && hasChanges
    }

    private var hasChanges: Bool {
        guard let profile = sessionStore.state.profile else { return false }
        let currentFirstName = profile.firstName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let currentLastName = profile.lastName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let currentEmail = sessionStore.state.loginEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let dateChanged = profile.dateOfBirth.map { !calendar.isDate($0, inSameDayAs: dateOfBirth) } ?? true

        return currentFirstName != trimmedFirstName
            || currentLastName != trimmedLastName
            || currentEmail != trimmedEmail
            || dateChanged
    }

    private var ageText: String {
        guard let age = Profile(
            id: sessionStore.state.profile?.id ?? UUID(),
            participantID: nil,
            firstName: nil,
            lastName: nil,
            dateOfBirth: dateOfBirth,
            timezone: nil,
            createdAt: nil,
            onboardingCompletedAt: nil
        ).age(calendar: calendar) else {
            return "Unavailable"
        }
        return "\(age)"
    }

    private var participantIDText: String {
        guard let participantID = sessionStore.state.profile?.participantID else { return "Unavailable" }
        return String(participantID)
    }

    private func loadInitialValuesIfNeeded() {
        guard !didLoadInitialValues, let profile = sessionStore.state.profile else { return }
        didLoadInitialValues = true
        firstName = profile.firstName ?? ""
        lastName = profile.lastName ?? ""
        dateOfBirth = profile.dateOfBirth ?? Self.defaultDateOfBirth
        loginEmail = sessionStore.state.loginEmail ?? ""
    }

    @MainActor
    private func saveChanges() async {
        guard let profile = sessionStore.state.profile else { return }

        let dateChanged = profile.dateOfBirth.map { !calendar.isDate($0, inSameDayAs: dateOfBirth) } ?? true
        let profileChanged = (profile.firstName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") != trimmedFirstName
            || (profile.lastName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") != trimmedLastName
            || dateChanged
        let emailChanged = (sessionStore.state.loginEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") != trimmedEmail

        if profileChanged {
            await sessionStore.updateProfile(
                firstName: trimmedFirstName,
                lastName: trimmedLastName,
                dateOfBirth: dateOfBirth
            )
        }

        if emailChanged {
            await sessionStore.updateLoginEmail(trimmedEmail)
        }
    }

    private func formattedTimestamp(_ date: Date?) -> String {
        guard let date else { return "Unavailable" }
        return Self.timestampFormatter.string(from: date)
    }

    private static let defaultDateOfBirth: Date = {
        Calendar(identifier: .gregorian).date(byAdding: .year, value: -18, to: Date()) ?? Date()
    }()

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

#Preview {
    NavigationStack {
        ProfileView()
    }
    .environmentObject(SessionStoreFactory.makePreviewStore(.authenticatedReady))
}
