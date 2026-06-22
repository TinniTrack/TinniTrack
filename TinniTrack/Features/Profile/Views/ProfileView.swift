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
    @State private var isEditingPersonalInfo = false
    @State private var accountNoticeMessage: String?
    @State private var isDeleteConfirmationPresented = false
    #if DEBUG
    @StateObject private var developerToolsViewModel = DeveloperToolsViewModel(service: SupabaseDeveloperToolingService())
    #endif

    private let calendar = Calendar(identifier: .gregorian)

    var body: some View {
        Form {
            Section {
                profileHeader
            }

            Section {
                if isEditingPersonalInfo {
                    personalInfoEditor
                } else {
                    personalInfoSummary
                    if let accountNoticeMessage {
                        Text(accountNoticeMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("profile_account_notice")
                    }
                    Button {
                        beginEditing()
                    } label: {
                        Label("Change Personal Info", systemImage: "pencil")
                    }
                    .accessibilityIdentifier("profile_edit_info_button")
                }
            } header: {
                Text("Personal Info")
            } footer: {
                Text("Email changes require confirmation from your current and new inboxes before the new login email becomes active.")
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

            #if DEBUG
            ProfileDeveloperToolsSection(
                viewModel: developerToolsViewModel,
                environment: supabaseEnvironment
            ) {
                await sessionStore.refreshAfterDeveloperToolAction()
            }
            #endif
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadInitialValuesIfNeeded)
        .confirmationDialog("Delete Account?", isPresented: $isDeleteConfirmationPresented, titleVisibility: .visible) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Account", role: .destructive) {
                Task { await sessionStore.deleteAccount() }
            }
            .accessibilityIdentifier("profile_confirm_delete_account_button")
        } message: {
            Text("This permanently deletes your TinniTrack account and study data.")
        }
    }

    private var profileHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.16))
                Text(initials)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(displayEmail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 6)
    }

    private var personalInfoSummary: some View {
        Group {
            LabeledContent("Name", value: displayName)
            LabeledContent("Login Email", value: displayEmail)
            LabeledContent("Date of Birth", value: formattedDate(effectiveDateOfBirth))
            LabeledContent("Age", value: ageText)
        }
    }

    private var personalInfoEditor: some View {
        Group {
            TextField("First Name", text: $firstName)
                .textContentType(.givenName)
                .accessibilityIdentifier("profile_first_name_field")

            TextField("Last Name", text: $lastName)
                .textContentType(.familyName)
                .accessibilityIdentifier("profile_last_name_field")

            TextField("Login Email", text: $loginEmail)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
                .accessibilityIdentifier("profile_email_field")

            DatePicker(
                "Date of Birth",
                selection: $dateOfBirth,
                in: ...Date(),
                displayedComponents: .date
            )
            .accessibilityIdentifier("profile_date_of_birth_picker")

            LabeledContent("Age", value: ageText)

            HStack {
                Button {
                    cancelEditing()
                } label: {
                    Label("Cancel", systemImage: "xmark")
                }
                .disabled(sessionStore.state.isBusy)
                .accessibilityIdentifier("profile_cancel_edit_button")

                Spacer()

                Button {
                    Task { await saveChanges() }
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Label("Save Changes", systemImage: "checkmark")
                    }
                }
                .disabled(!canSave)
                .accessibilityIdentifier("profile_save_button")
            }
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

    private var displayName: String {
        let name = [sessionStore.state.profile?.firstName, sessionStore.state.profile?.lastName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return name.isEmpty ? "Participant" : name
    }

    private var displayEmail: String {
        let email = sessionStore.state.loginEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return email.isEmpty ? "Email unavailable" : email
    }

    private var initials: String {
        let components = [sessionStore.state.profile?.firstName, sessionStore.state.profile?.lastName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).first }
        let value = String(components.prefix(2)).uppercased()
        return value.isEmpty ? "TT" : value
    }

    private var effectiveDateOfBirth: Date {
        if isEditingPersonalInfo {
            return dateOfBirth
        }
        return sessionStore.state.profile?.dateOfBirth ?? dateOfBirth
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
            dateOfBirth: effectiveDateOfBirth,
            timezone: nil,
            createdAt: nil,
            onboardingCompletedAt: nil
        ).age(calendar: calendar) else {
            return "Unavailable"
        }
        return "\(age)"
    }

    private func loadInitialValuesIfNeeded() {
        guard !didLoadInitialValues, let profile = sessionStore.state.profile else { return }
        didLoadInitialValues = true
        loadEditableValues(from: profile)
    }

    private func loadEditableValues(from profile: Profile) {
        firstName = profile.firstName ?? ""
        lastName = profile.lastName ?? ""
        dateOfBirth = profile.dateOfBirth ?? Self.defaultDateOfBirth
        loginEmail = sessionStore.state.loginEmail ?? ""
    }

    private func beginEditing() {
        if let profile = sessionStore.state.profile {
            loadEditableValues(from: profile)
        }
        accountNoticeMessage = nil
        isEditingPersonalInfo = true
    }

    private func cancelEditing() {
        if let profile = sessionStore.state.profile {
            loadEditableValues(from: profile)
        }
        isEditingPersonalInfo = false
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
            guard !hasErrorBanner else { return }
        }

        if emailChanged {
            await sessionStore.updateLoginEmail(trimmedEmail)
            if case .info(let message) = sessionStore.state.banner {
                accountNoticeMessage = message
            }
        }

        if sessionStore.state.banner?.title == "Info" {
            isEditingPersonalInfo = false
        }
    }

    private var hasErrorBanner: Bool {
        switch sessionStore.state.banner {
        case .error, .titledError:
            return true
        case .info, nil:
            return false
        }
    }

    private func formattedDate(_ date: Date) -> String {
        Self.dateFormatter.string(from: date)
    }

    private static let defaultDateOfBirth: Date = {
        Calendar(identifier: .gregorian).date(byAdding: .year, value: -18, to: Date()) ?? Date()
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()
}

#if DEBUG
#Preview {
    NavigationStack {
        ProfileView()
    }
    .environmentObject(SessionStoreFactory.makePreviewStore(.authenticatedReady))
}
#endif
