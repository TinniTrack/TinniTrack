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
        case birthMonth
        case birthDay
        case birthYear

        var isDateOfBirthField: Bool {
            switch self {
            case .birthMonth, .birthDay, .birthYear:
                return true
            case .firstName, .lastName, .email, .password:
                return false
            }
        }
    }

    @EnvironmentObject private var sessionStore: SessionStore

    @State private var currentStep = 1
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var dateOfBirth = Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()
    @State private var birthMonth = ""
    @State private var birthDay = ""
    @State private var birthYear = ""
    
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
        !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        isDOBValid
    }
    private var isDOBValid: Bool {
        guard
            birthMonth.count == 2,
            birthDay.count == 2,
            birthYear.count == 4,
            let month = Int(birthMonth),
            let day = Int(birthDay),
            let year = Int(birthYear),
            (1...12).contains(month),
            (1...31).contains(day),
            year > 1900
        else { return false }

        var components = DateComponents()
        components.calendar = Calendar.current
        components.year = year
        components.month = month
        components.day = day

        guard let date = Calendar.current.date(from: components) else {
            return false
        }
    

        let actual = Calendar.current.dateComponents([.year, .month, .day], from: date)

        return actual.year == year &&
               actual.month == month &&
               actual.day == day &&
               date <= Date()
    }
    private var shouldShowDOBError: Bool {
        let anyFieldFilled =
            !birthMonth.isEmpty ||
            !birthDay.isEmpty ||
            !birthYear.isEmpty

        return anyFieldFilled && !isDOBValid
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
                                textContentType: .username,
                                textInputAutocapitalization: .never,
                                accessibilityIdentifier: "signup_email_field",
                                submitLabel: .next,
                                onSubmit: { focusedField = .password },
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
                                textContentType: .newPassword,
                                textInputAutocapitalization: .never,
                                accessibilityIdentifier: "signup_password_field",
                                submitLabel: .continue,
                                onSubmit: continueToProfileStep
                            )
                            .focused($focusedField, equals: .password)
                        }

                        Button("Continue") {
                            continueToProfileStep()
                        }
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(actionColor)
                        .clipShape(Capsule())
                        .padding(.top, 8)
                        .buttonStyle(AppCapsuleButtonStyle())
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
                                textContentType: .givenName,
                                textInputAutocapitalization: .words,
                                accessibilityIdentifier: "signup_first_name_field",
                                submitLabel: .next,
                                onSubmit: { focusedField = .lastName }
                            )
                            .focused($focusedField, equals: .firstName)
                            
                            FloatingInputField(
                                label: "Last Name",
                                text: $lastName,
                                isSecure: false,
                                isFocused: focusedField == .lastName,
                                borderColor: fieldBorderColor,
                                focusedBorderColor: focusColor,
                                textContentType: .familyName,
                                textInputAutocapitalization: .words,
                                accessibilityIdentifier: "signup_last_name_field",
                                submitLabel: .next,
                                onSubmit: { focusedField = .birthMonth }
                            )
                            .focused($focusedField, equals: .lastName)
                            
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Date of Birth")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(secondaryTextColor)

                                HStack(spacing: 10) {
                                    FloatingInputField(
                                        label: "MM",
                                        text: $birthMonth,
                                        isSecure: false,
                                        isFocused: focusedField == .birthMonth,
                                        borderColor: fieldBorderColor,
                                        focusedBorderColor: focusColor,
                                        keyboardType: .numberPad,
                                        textContentType: .birthdateMonth,
                                        textInputAutocapitalization: .never,
                                        accessibilityIdentifier: "signup_birth_month_field"
                                    )
                                    .focused($focusedField, equals: .birthMonth)
                                    .frame(maxWidth: .infinity)

                                    FloatingInputField(
                                        label: "DD",
                                        text: $birthDay,
                                        isSecure: false,
                                        isFocused: focusedField == .birthDay,
                                        borderColor: fieldBorderColor,
                                        focusedBorderColor: focusColor,
                                        keyboardType: .numberPad,
                                        textContentType: .birthdateDay,
                                        textInputAutocapitalization: .never,
                                        accessibilityIdentifier: "signup_birth_day_field"
                                    )
                                    .focused($focusedField, equals: .birthDay)
                                    .frame(maxWidth: .infinity)

                                    FloatingInputField(
                                        label: "YYYY",
                                        text: $birthYear,
                                        isSecure: false,
                                        isFocused: focusedField == .birthYear,
                                        borderColor: fieldBorderColor,
                                        focusedBorderColor: focusColor,
                                        keyboardType: .numberPad,
                                        textContentType: .birthdateYear,
                                        textInputAutocapitalization: .never,
                                        accessibilityIdentifier: "signup_birth_year_field"
                                    )
                                    .focused($focusedField, equals: .birthYear)
                                    .frame(maxWidth: .infinity)
                                }

                                Text("Enter as month, day, and year.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(secondaryTextColor.opacity(0.9))
                                if shouldShowDOBError {
                                    Text("Please enter a valid date of birth")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.red)
                                }
                            }
                            
                            HStack(spacing: 10) {
                                Button("Back") {
                                    dismissTextFocus()
                                    currentStep = 1
                                    persistDraft()
                                }
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(actionColor)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(Color.white)
                                .clipShape(Capsule())
                                .buttonStyle(AppCapsuleButtonStyle())
                                
                                Button("Create Account") {
                                    dismissTextFocus()
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
                                .background(
                                    isStepTwoValid && !sessionStore.state.isBusy
                                    ? actionColor
                                    : Color.gray.opacity(0.4)
                                )
                                .clipShape(Capsule())
                                .buttonStyle(AppCapsuleButtonStyle())
                                .disabled(!isStepTwoValid || sessionStore.state.isBusy)
                                .accessibilityIdentifier("signup_create_account_button")
                            }
                            .padding(.top, 8)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 26)
                .background {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color.white.opacity(0.96))
                        .contentShape(Rectangle())
                        .onTapGesture { dismissTextFocus() }
                }
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
        .scrollDismissesKeyboard(.immediately)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if focusedField?.isDateOfBirthField == true {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        dismissTextFocus()
                    }
                    .accessibilityIdentifier("signup_keyboard_done_button")
                }
            }
        }
        .onAppear {
            restoreDraft()
        }
        .onChange(of: currentStep) { _ in persistDraft() }
        .onChange(of: email) { _ in persistDraft() }
        .onChange(of: password) { _ in persistDraft() }
        .onChange(of: firstName) { _ in persistDraft() }
        .onChange(of: lastName) { _ in persistDraft() }
        .onChange(of: birthMonth) { _ in
            updateDateOfBirthFromFields()
            advanceDateOfBirthFocusIfNeeded()
            persistDraft()
        }
        .onChange(of: birthDay) { _ in
            updateDateOfBirthFromFields()
            advanceDateOfBirthFocusIfNeeded()
            persistDraft()
        }
        .onChange(of: birthYear) { _ in
            updateDateOfBirthFromFields()
            advanceDateOfBirthFocusIfNeeded()
            persistDraft()
        }
        .onChange(of: dateOfBirth) { _ in persistDraft() }
    }

    private func continueToProfileStep() {
        guard isStepOneValid, !sessionStore.state.isBusy else { return }
        dismissTextFocus()
        currentStep = 2
        persistDraft()
    }

    private func dismissTextFocus() {
        focusedField = nil
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

        let hasSavedDraftContent =
            !draft.email.isEmpty ||
            !draft.password.isEmpty ||
            !draft.firstName.isEmpty ||
            !draft.lastName.isEmpty

        if hasSavedDraftContent {
            syncBirthFieldsFromDate()
        } else {
            birthMonth = ""
            birthDay = ""
            birthYear = ""
        }
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
    
    private func syncBirthFieldsFromDate() {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.month, .day, .year], from: dateOfBirth)

        birthMonth = components.month.map { String(format: "%02d", $0) } ?? ""
        birthDay = components.day.map { String(format: "%02d", $0) } ?? ""
        birthYear = components.year.map(String.init) ?? ""
    }

    private func sanitizeDOBFields() {
        birthMonth = String(birthMonth.filter(\.isNumber).prefix(2))
        birthDay = String(birthDay.filter(\.isNumber).prefix(2))
        birthYear = String(birthYear.filter(\.isNumber).prefix(4))
    }

    private func updateDateOfBirthFromFields() {
        sanitizeDOBFields()

        guard isDOBValid,
              let month = Int(birthMonth),
              let day = Int(birthDay),
              let year = Int(birthYear)
        else { return }

        var components = DateComponents()
        components.calendar = Calendar.current
        components.year = year
        components.month = month
        components.day = day

        if let newDate = Calendar.current.date(from: components) {
            dateOfBirth = newDate
        }
    }

    private func advanceDateOfBirthFocusIfNeeded() {
        switch focusedField {
        case .birthMonth where birthMonth.count == 2:
            focusedField = .birthDay
        case .birthDay where birthDay.count == 2:
            focusedField = .birthYear
        case .birthYear where birthYear.count == 4:
            dismissTextFocus()
        case .firstName, .lastName, .email, .password, .birthMonth, .birthDay, .birthYear, nil:
            break
        }
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
    var textContentType: UITextContentType? = nil
    var textInputAutocapitalization: TextInputAutocapitalization = .never
    var accessibilityIdentifier: String? = nil
    var submitLabel: SubmitLabel = .done
    var onSubmit: () -> Void = {}
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
                        .textContentType(textContentType)
                        .accessibilityIdentifier(accessibilityIdentifier ?? "")
                } else {
                    TextField("", text: $text)
                        .keyboardType(keyboardType)
                        .textContentType(textContentType)
                        .accessibilityIdentifier(accessibilityIdentifier ?? "")
                }
            }
            .textInputAutocapitalization(textInputAutocapitalization)
            .autocorrectionDisabled()
            .submitLabel(submitLabel)
            .onSubmit(onSubmit)
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
                    .buttonStyle(AppCircleButtonStyle())
                    .padding(.trailing, 12)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        SignUpView()
    }
    .environmentObject(SessionStoreFactory.makePreviewStore())
}
#endif
