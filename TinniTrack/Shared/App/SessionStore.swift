//
//  SessionStore.swift
//  TinniTrack
//

import Foundation
import Combine

@MainActor
final class SessionStore: ObservableObject {
    struct SessionState: Equatable {
        enum Route: Equatable {
            case bootstrapping
            case unauthenticated
            case awaitingEmailVerification(email: String)
            case needsOnboarding(profile: Profile?)
            case ready(profile: Profile)
        }

        enum Activity: Equatable {
            case idle
            case signingIn
            case signingUp
            case completingOnboarding
            case signingOut
            case requestingPasswordReset
            case handlingAuthCallback
            case updatingPassword
            case resendingVerificationEmail
            case checkingVerificationStatus
        }

        enum Banner: Equatable {
            case info(String)
            case error(String)

            var title: String {
                switch self {
                case .info:
                    return "Info"
                case .error:
                    return "Error"
                }
            }

            var message: String {
                switch self {
                case .info(let message):
                    return message
                case .error(let message):
                    return message
                }
            }
        }

        var route: Route
        var activity: Activity
        var banner: Banner?
        var passwordResetPresented: Bool

        static let bootstrapping = SessionState(
            route: .bootstrapping,
            activity: .idle,
            banner: nil,
            passwordResetPresented: false
        )

        var isBusy: Bool {
            activity != .idle
        }

        var profile: Profile? {
            switch route {
            case .needsOnboarding(let profile):
                return profile
            case .ready(let profile):
                return profile
            case .bootstrapping, .unauthenticated, .awaitingEmailVerification:
                return nil
            }
        }

        var pendingVerificationEmail: String? {
            if case .awaitingEmailVerification(let email) = route {
                return email
            }
            return nil
        }

        var isUnauthenticated: Bool {
            if case .unauthenticated = route {
                return true
            }
            return false
        }
    }

    @Published private(set) var state: SessionState

    private let authService: AuthServiceProtocol
    private let profileService: ProfileServiceProtocol
    private let emailVerificationPendingStore: EmailVerificationPendingStoring
    private let engine = SessionEngine()
    private var authStateTask: Task<Void, Never>?
    private var hasStarted: Bool

    init(
        authService: AuthServiceProtocol,
        profileService: ProfileServiceProtocol,
        emailVerificationPendingStore: EmailVerificationPendingStoring? = nil,
        initialState: SessionState = SessionState(
            route: .bootstrapping,
            activity: .idle,
            banner: nil,
            passwordResetPresented: false
        ),
        hasStarted: Bool = false
    ) {
        self.state = initialState
        self.authService = authService
        self.profileService = profileService
        self.emailVerificationPendingStore = emailVerificationPendingStore ?? EmailVerificationPendingStore()
        self.hasStarted = hasStarted
    }

    deinit {
        authStateTask?.cancel()
    }

    func start() async {
        await engine.run { [self] in
            guard !hasStarted else { return }
            hasStarted = true
            startAuthStateListener()
            state = .bootstrapping
            await refreshRoute(preserveRouteOnFailure: false)
        }
    }

    func signIn(email: String, password: String) async {
        await execute(activity: .signingIn) { [self] in
            let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)

            do {
                try await authService.signIn(email: normalizedEmail, password: password)
                clearPendingEmailVerification()
                await refreshRoute(preserveRouteOnFailure: true)
            } catch let authError as AuthServiceError {
                if case .emailNotConfirmed = authError {
                    setPendingEmailVerification(normalizedEmail)
                    state.route = .awaitingEmailVerification(email: normalizedEmail)
                    state.banner = .info("Please verify your email address before signing in.")
                } else {
                    setErrorBanner(from: authError)
                }
            } catch {
                setErrorBanner(from: error)
            }
        }
    }

    func signUp(email: String, password: String, firstName: String, lastName: String, dateOfBirth: Date) async {
        let metadata = SignUpMetadata(
            firstName: firstName,
            lastName: lastName,
            dateOfBirth: dateOfBirth
        )

        await execute(activity: .signingUp) { [self] in
            let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)

            do {
                let result = try await authService.signUp(
                    email: normalizedEmail,
                    password: password,
                    metadata: metadata
                )

                switch result {
                case .signedIn:
                    clearPendingEmailVerification()
                case .awaitingEmailVerification:
                    setPendingEmailVerification(normalizedEmail)
                    state.route = .awaitingEmailVerification(email: normalizedEmail)
                    state.banner = .info("Check your email to verify your account.")
                }

                await refreshRoute(preserveRouteOnFailure: true)
            } catch {
                setErrorBanner(from: error)
            }
        }
    }

    func completeOnboarding(firstName: String, lastName: String, dateOfBirth: Date) async {
        await execute(activity: .completingOnboarding) { [self] in
            do {
                try await profileService.completeOnboarding(
                    firstName: firstName,
                    lastName: lastName,
                    dateOfBirth: dateOfBirth
                )
                await refreshRoute(preserveRouteOnFailure: true)
            } catch {
                setErrorBanner(from: error)
            }
        }
    }

    func signOut() async {
        await execute(activity: .signingOut) { [self] in
            do {
                try await authService.signOut()
                clearPendingEmailVerification()
                state.route = routeForNoSession()
            } catch {
                setErrorBanner(from: error)
            }
        }
    }

    func requestPasswordReset(email: String) async {
        guard let redirectURL = URL(string: "tinnitrack://auth/reset") else { return }

        await execute(activity: .requestingPasswordReset) { [self] in
            do {
                try await authService.requestPasswordReset(email: email, redirectURL: redirectURL)
                state.banner = .info("If the account exists, a reset email has been sent.")
            } catch {
                setErrorBanner(from: error)
            }
        }
    }

    func handleIncomingURL(_ url: URL) async {
        await execute(activity: .handlingAuthCallback) { [self] in
            do {
                let result = try await authService.handleAuthCallback(url: url)
                switch result {
                case .passwordRecovery:
                    state.passwordResetPresented = true
                case .signedIn:
                    clearPendingEmailVerification()
                case .none:
                    break
                }
                await refreshRoute(preserveRouteOnFailure: true)
            } catch {
                setErrorBanner(from: error)
            }
        }
    }

    func submitNewPassword(_ newPassword: String) async {
        await execute(activity: .updatingPassword) { [self] in
            do {
                try await authService.updatePassword(newPassword: newPassword)
                state.passwordResetPresented = false
                state.banner = .info("Password updated.")
                await refreshRoute(preserveRouteOnFailure: true)
            } catch {
                setErrorBanner(from: error)
            }
        }
    }

    func dismissBanner() {
        state.banner = nil
    }

    func dismissPasswordResetSheet() {
        state.passwordResetPresented = false
    }

    func resendVerificationEmail() async {
        guard let pending = emailVerificationPendingStore.load(),
              let redirectURL = URL(string: "tinnitrack://auth/confirm") else {
            return
        }

        await execute(activity: .resendingVerificationEmail) { [self] in
            do {
                try await authService.resendSignUpVerification(email: pending.email, redirectURL: redirectURL)
                emailVerificationPendingStore.updateLastResend(at: Date())
                state.banner = .info("Verification email sent.")
            } catch {
                setErrorBanner(from: error)
            }
        }
    }

    func checkEmailVerificationStatus() async {
        await execute(activity: .checkingVerificationStatus) { [self] in
            await refreshRoute(preserveRouteOnFailure: true)
            if case .awaitingEmailVerification = state.route, state.banner == nil {
                state.banner = .info("Still waiting for verification. Open the email link on this device.")
            }
        }
    }

    func useDifferentEmailForVerification() {
        clearPendingEmailVerification()
        state.route = .unauthenticated
    }

    private func startAuthStateListener() {
        authStateTask?.cancel()
        authStateTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await _ in self.authService.authStateStream() {
                await self.engine.run { [self] in
                    await self.refreshRoute(preserveRouteOnFailure: true)
                }
            }
        }
    }

    private func execute(
        activity: SessionState.Activity,
        clearBanner: Bool = true,
        _ operation: @escaping @MainActor () async -> Void
    ) async {
        await engine.run { [self] in
            state.activity = activity
            if clearBanner {
                state.banner = nil
            }
            defer { state.activity = .idle }
            await operation()
        }
    }

    private func refreshRoute(preserveRouteOnFailure: Bool) async {
        let previousRoute = state.route

        do {
            let session = try await authService.currentSession()
            guard session != nil else {
                state.route = routeForNoSession()
                return
            }

            clearPendingEmailVerification()
            let latestProfile = try await profileService.fetchMyProfile()

            if let latestProfile, latestProfile.isOnboardingComplete {
                state.route = .ready(profile: latestProfile)
            } else {
                state.route = .needsOnboarding(profile: latestProfile)
            }
        } catch {
            setErrorBanner(from: error)
            if preserveRouteOnFailure {
                state.route = previousRoute
            } else {
                state.route = routeForNoSession()
            }
        }
    }

    private func setPendingEmailVerification(_ email: String) {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        emailVerificationPendingStore.save(
            PendingEmailVerification(
                email: normalized,
                createdAt: Date(),
                lastResendAt: nil
            )
        )
    }

    private func clearPendingEmailVerification() {
        emailVerificationPendingStore.clear()
    }

    private func routeForNoSession() -> SessionState.Route {
        guard let pending = emailVerificationPendingStore.load() else {
            return .unauthenticated
        }
        return .awaitingEmailVerification(email: pending.email)
    }

    private func setErrorBanner(from error: Error) {
        if let authError = error as? AuthServiceError,
           let description = authError.errorDescription,
           !description.isEmpty {
            state.banner = .error(description)
        } else {
            state.banner = .error(error.localizedDescription)
        }
    }
}

@MainActor
private final class SessionEngine {
    private var tail: Task<Void, Never>?

    func run(_ operation: @escaping @MainActor () async -> Void) async {
        let previous = tail
        await withCheckedContinuation { continuation in
            let current = Task { @MainActor in
                if let previous {
                    _ = await previous.result
                }
                await operation()
                continuation.resume()
            }
            tail = Task { @MainActor in
                _ = await current.result
            }
        }
    }
}
