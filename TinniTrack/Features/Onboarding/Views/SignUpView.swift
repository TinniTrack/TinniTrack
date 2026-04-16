//
//  SignUpView.swift
//  TinniTrack
//

import SwiftUI
import UIKit

struct SignUpView: View {
    private enum Field: Hashable {
        case firstName
        case lastName
        case email
        case password
    }

    @EnvironmentObject private var sessionStore: SessionStore

    @State private var currentStep = 1
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var dateOfBirth = Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()
    @FocusState private var focusedField: Field?

    private let draftStore: SignupDraftStoring

    private let focusColor = Color(red: 0.0, green: 0.48, blue: 1.0)
    private let fieldBorderColor = Color(red: 0.82, green: 0.82, blue: 0.84)
    private let actionColor = Color(red: 0.06, green: 0.24, blue: 0.44)
    private let secondaryTextColor = Color(red: 0.24, green: 0.24, blue: 0.28)

    init(draftStore: SignupDraftStoring = SignupDraftStore()) {
        self.draftStore = draftStore
    }

    private var isStepOneValid: Bool {
        email.trimmingCharacters(in: .whitespacesAndNewlines).contains("@") && password.count >= 6
    }

    private var isStepTwoValid: Bool {
        !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && dateOfBirth <= Date()
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.white, Color(red: 0.95, green: 0.95, blue: 0.97)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    VStack(spacing: 10) {
                        Text("Create your account")
                            .font(.system(size: 31, weight: .bold))
                            .foregroundStyle(.black)
                            .multilineTextAlignment(.center)

                        Text(currentStep == 1 ? "Step 1 of 2: account credentials." : "Step 2 of 2: complete your profile.")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(secondaryTextColor)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 12)

                    if currentStep == 1 {
                        VStack(spacing: 14) {
                            FloatingInputField(
                                label: "Email",
                                text: $email,
                                isSecure: false,
                                isFocused: focusedField == .email,
                                borderColor: fieldBorderColor,
                                focusedBorderColor: focusColor,
                                keyboardType: .emailAddress,
                                accessibilityIdentifier: "signup_email_field",
                                clearAction: { email = "" }
                            )
                            .focused($focusedField, equals: .email)

                            FloatingInputField(
                                label: "Password",
                                text: $password,
                                isSecure: true,
                                isFocused: focusedField == .password,
                                borderColor: fieldBorderColor,
                                focusedBorderColor: focusColor,
                                accessibilityIdentifier: "signup_password_field"
                            )
                            .focused($focusedField, equals: .password)
                        }

                        Button("Continue") {
                            currentStep = 2
                            persistDraft()
                        }
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(actionColor)
                        .clipShape(Capsule())
                        .padding(.top, 8)
                        .disabled(!isStepOneValid || sessionStore.state.isBusy)
                        .accessibilityIdentifier("signup_continue_button")
                    } else {
                        VStack(spacing: 14) {
                            FloatingInputField(
                                label: "First Name",
                                text: $firstName,
                                isSecure: false,
                                isFocused: focusedField == .firstName,
                                borderColor: fieldBorderColor,
                                focusedBorderColor: focusColor,
                                accessibilityIdentifier: "signup_first_name_field"
                            )
                            .focused($focusedField, equals: .firstName)

                            FloatingInputField(
                                label: "Last Name",
                                text: $lastName,
                                isSecure: false,
                                isFocused: focusedField == .lastName,
                                borderColor: fieldBorderColor,
                                focusedBorderColor: focusColor,
                                accessibilityIdentifier: "signup_last_name_field"
                            )
                            .focused($focusedField, equals: .lastName)

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Date of Birth")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(secondaryTextColor)
                                DatePicker(
                                    "",
                                    selection: $dateOfBirth,
                                    in: ...Date(),
                                    displayedComponents: .date
                                )
                                .datePickerStyle(.compact)
                                .labelsHidden()
                                .tint(focusColor)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 14)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(fieldBorderColor, lineWidth: 1.2)
                            )
                        }

                        HStack(spacing: 10) {
                            Button("Back") {
                                currentStep = 1
                                persistDraft()
                            }
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(actionColor)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.white)
                            .clipShape(Capsule())

                            Button("Create Account") {
                                Task {
                                    await sessionStore.signUp(
                                        email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                                        password: password,
                                        firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
                                        lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines),
                                        dateOfBirth: dateOfBirth
                                    )

                                    if !sessionStore.state.isUnauthenticated {
                                        draftStore.clear()
                                    }
                                }
                            }
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(actionColor)
                            .clipShape(Capsule())
                            .disabled(!isStepTwoValid || sessionStore.state.isBusy)
                            .accessibilityIdentifier("signup_create_account_button")
                        }
                        .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 26)
                .background(Color.white.opacity(0.96))
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.85), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.05), radius: 18, x: 0, y: 10)
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }

            if sessionStore.state.isBusy {
                ProgressView()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: restoreDraft)
        .onChange(of: currentStep) { _ in persistDraft() }
        .onChange(of: email) { _ in persistDraft() }
        .onChange(of: password) { _ in persistDraft() }
        .onChange(of: firstName) { _ in persistDraft() }
        .onChange(of: lastName) { _ in persistDraft() }
        .onChange(of: dateOfBirth) { _ in persistDraft() }
    }

    private func restoreDraft() {
        let defaultDOB = Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()
        let draft = draftStore.load(defaultDateOfBirth: defaultDOB)
        currentStep = min(max(draft.currentStep, 1), 2)
        email = draft.email
        password = draft.password
        firstName = draft.firstName
        lastName = draft.lastName
        dateOfBirth = draft.dateOfBirth
    }

    private func persistDraft() {
        let draft = SignupDraft(
            currentStep: currentStep,
            email: email,
            password: password,
            firstName: firstName,
            lastName: lastName,
            dateOfBirth: dateOfBirth,
            updatedAt: Date()
        )
        draftStore.save(draft)
    }
}

private struct FloatingInputField: View {
    let label: String
    @Binding var text: String
    let isSecure: Bool
    let isFocused: Bool
    let borderColor: Color
    let focusedBorderColor: Color
    var keyboardType: UIKeyboardType = .default
    var accessibilityIdentifier: String? = nil
    var clearAction: (() -> Void)? = nil
    private let floatingLabelColor = Color(red: 0.24, green: 0.24, blue: 0.28)

    private var shouldFloat: Bool {
        isFocused || !text.isEmpty
    }

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isFocused ? focusedBorderColor : borderColor, lineWidth: 1.2)
                )
                .frame(height: 64)

            Text(label)
                .font(.system(size: shouldFloat ? 12 : 17, weight: shouldFloat ? .semibold : .regular))
                .foregroundStyle(shouldFloat ? floatingLabelColor : Color.gray)
                .padding(.horizontal, 14)
                .offset(y: shouldFloat ? -18 : 0)
                .animation(.easeInOut(duration: 0.16), value: shouldFloat)

            Group {
                if isSecure {
                    SecureField("", text: $text)
                        .accessibilityIdentifier(accessibilityIdentifier ?? "")
                } else {
                    TextField("", text: $text)
                        .keyboardType(keyboardType)
                        .accessibilityIdentifier(accessibilityIdentifier ?? "")
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.system(size: 17, weight: .regular))
            .foregroundStyle(.black)
            .padding(.top, shouldFloat ? 16 : 0)
            .padding(.leading, 14)
            .padding(.trailing, clearAction == nil ? 14 : 40)

            if let clearAction, !text.isEmpty, !isSecure {
                HStack {
                    Spacer()
                    Button(action: clearAction) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.gray.opacity(0.65))
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 12)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

#Preview {
    NavigationStack {
        SignUpView()
    }
    .environmentObject(SessionStoreFactory.makePreviewStore())
}
