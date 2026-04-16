//
//  TinniTrackApp.swift
//  TinniTrack
//

import SwiftUI
import Foundation

@main
struct TinniTrackApp: App {
    @StateObject private var sessionStore: SessionStore

    init() {
        _sessionStore = StateObject(wrappedValue: SessionStoreFactory.makeAppStore())
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(sessionStore)
                .task {
                    await sessionStore.start()
                }
                .onOpenURL { url in
                    Task {
                        await sessionStore.handleIncomingURL(url)
                    }
                }
        }
    }
}

enum SessionStoreFactory {
    static func makeAppStore(processInfo: ProcessInfo = .processInfo) -> SessionStore {
        let pendingStore = EmailVerificationPendingStore()

        if processInfo.environment["XCTestConfigurationFilePath"] != nil {
            let env = processInfo.environment
            if env["UITEST_CLEAR_PENDING_VERIFICATION"] == "1" {
                pendingStore.clear()
            }
            if env["UITEST_CLEAR_SIGNUP_DRAFT"] == "1" {
                let draftStore = SignupDraftStore()
                draftStore.clear()
            }
            if let pendingEmail = env["UITEST_PENDING_VERIFICATION_EMAIL"]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !pendingEmail.isEmpty {
                pendingStore.save(
                    PendingEmailVerification(
                        email: pendingEmail,
                        createdAt: Date(),
                        lastResendAt: nil
                    )
                )
            }

            return SessionStore(
                authService: NoopAuthService(processInfo: processInfo),
                profileService: NoopProfileService(),
                emailVerificationPendingStore: pendingStore
            )
        }

        return SessionStore(
            authService: SupabaseAuthService(),
            profileService: SupabaseProfileService(),
            emailVerificationPendingStore: pendingStore
        )
    }

    #if DEBUG
    enum PreviewScenario {
        case unauthenticated
        case awaitingEmailVerification(email: String)
        case authenticatedNeedsOnboarding
        case authenticatedReady
    }

    static func makePreviewStore(_ scenario: PreviewScenario = .unauthenticated) -> SessionStore {
        let previewUserID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let previewDateOfBirth = Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()

        let pending: PendingEmailVerification?
        let session: AuthSession?
        let profile: Profile?
        let route: SessionStore.SessionState.Route

        switch scenario {
        case .unauthenticated:
            pending = nil
            session = nil
            profile = nil
            route = .unauthenticated
        case .awaitingEmailVerification(let email):
            let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
            let safeEmail = trimmedEmail.isEmpty ? "pending@example.com" : trimmedEmail
            pending = PendingEmailVerification(email: safeEmail, createdAt: Date(), lastResendAt: nil)
            session = nil
            profile = nil
            route = .awaitingEmailVerification(email: safeEmail)
        case .authenticatedNeedsOnboarding:
            pending = nil
            session = AuthSession(userID: previewUserID)
            profile = Profile(
                id: previewUserID,
                participantID: nil,
                firstName: "Taylor",
                lastName: "Rivers",
                dateOfBirth: previewDateOfBirth,
                timezone: "America/New_York",
                createdAt: Date(),
                onboardingCompletedAt: nil
            )
            route = .needsOnboarding(profile: profile)
        case .authenticatedReady:
            pending = nil
            session = AuthSession(userID: previewUserID)
            profile = Profile(
                id: previewUserID,
                participantID: 1001,
                firstName: "Taylor",
                lastName: "Rivers",
                dateOfBirth: previewDateOfBirth,
                timezone: "America/New_York",
                createdAt: Date(),
                onboardingCompletedAt: Date()
            )
            route = .ready(profile: profile!)
        }

        return SessionStore(
            authService: PreviewAuthService(session: session),
            profileService: StaticProfileService(profile: profile),
            emailVerificationPendingStore: InMemoryEmailVerificationPendingStore(pending: pending),
            initialState: SessionStore.SessionState(
                route: route,
                activity: .idle,
                banner: nil,
                passwordResetPresented: false
            ),
            hasStarted: true
        )
    }
    #endif
}

private final class NoopAuthService: AuthServiceProtocol {
    private var currentSessionCallCount = 0
    private let verifyAfterSessionChecks: Int?

    init(processInfo: ProcessInfo = .processInfo) {
        if let raw = processInfo.environment["UITEST_NOOP_VERIFY_AFTER_SESSION_CHECKS"] {
            verifyAfterSessionChecks = Int(raw)
        } else {
            verifyAfterSessionChecks = nil
        }
    }

    func signUp(email: String, password: String, metadata: SignUpMetadata) async throws -> SignUpResult {
        .awaitingEmailVerification
    }

    func signIn(email: String, password: String) async throws {}

    func signOut() async throws {}

    func currentSession() async throws -> AuthSession? {
        currentSessionCallCount += 1
        guard let verifyAfterSessionChecks else { return nil }
        guard currentSessionCallCount >= verifyAfterSessionChecks else { return nil }
        return AuthSession(userID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
    }

    func authStateStream() -> AsyncStream<AuthStateChange> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func resendSignUpVerification(email: String, redirectURL: URL) async throws {}

    func requestPasswordReset(email: String, redirectURL: URL) async throws {}

    func handleAuthCallback(url: URL) async throws -> AuthCallbackResult { .none }

    func updatePassword(newPassword: String) async throws {}
}

private final class NoopProfileService: ProfileServiceProtocol {
    func fetchMyProfile() async throws -> Profile? { nil }

    func completeOnboarding(firstName: String, lastName: String, dateOfBirth: Date) async throws {}
}

#if DEBUG
private final class PreviewAuthService: AuthServiceProtocol {
    private var session: AuthSession?

    init(session: AuthSession?) {
        self.session = session
    }

    func signUp(email: String, password: String, metadata: SignUpMetadata) async throws -> SignUpResult {
        .awaitingEmailVerification
    }

    func signIn(email: String, password: String) async throws {
        let userID = session?.userID ?? UUID()
        session = AuthSession(userID: userID)
    }

    func signOut() async throws {
        session = nil
    }

    func currentSession() async throws -> AuthSession? {
        session
    }

    func authStateStream() -> AsyncStream<AuthStateChange> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func resendSignUpVerification(email: String, redirectURL: URL) async throws {}

    func requestPasswordReset(email: String, redirectURL: URL) async throws {}

    func handleAuthCallback(url: URL) async throws -> AuthCallbackResult { .none }

    func updatePassword(newPassword: String) async throws {}
}

private final class StaticProfileService: ProfileServiceProtocol {
    private var profile: Profile?

    init(profile: Profile?) {
        self.profile = profile
    }

    func fetchMyProfile() async throws -> Profile? {
        profile
    }

    func completeOnboarding(firstName: String, lastName: String, dateOfBirth: Date) async throws {
        profile = Profile(
            id: profile?.id ?? UUID(),
            participantID: profile?.participantID,
            firstName: firstName,
            lastName: lastName,
            dateOfBirth: dateOfBirth,
            timezone: profile?.timezone,
            createdAt: profile?.createdAt,
            onboardingCompletedAt: Date()
        )
    }
}

private final class InMemoryEmailVerificationPendingStore: EmailVerificationPendingStoring {
    private var pending: PendingEmailVerification?

    init(pending: PendingEmailVerification?) {
        self.pending = pending
    }

    func load() -> PendingEmailVerification? {
        pending
    }

    func save(_ pending: PendingEmailVerification) {
        self.pending = pending
    }

    func updateLastResend(at date: Date) {
        guard var pending else { return }
        pending.lastResendAt = date
        self.pending = pending
    }

    func clear() {
        pending = nil
    }
}
#endif
