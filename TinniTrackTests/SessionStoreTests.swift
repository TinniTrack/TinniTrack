import Foundation
import Testing
@testable import TinniTrack

@MainActor
struct SessionStoreTests {
    @Test
    func startMovesToUnauthenticatedWhenNoSession() async {
        let auth = MockAuthService(currentSession: nil)
        let profile = MockProfileService(profile: nil)
        let pending = MockEmailVerificationPendingStore(pending: nil)
        let store = SessionStore(authService: auth, profileService: profile, emailVerificationPendingStore: pending)

        await store.start()

        #expect(store.state.route == .unauthenticated)
    }

    @Test
    func startMovesToAwaitingVerificationWhenPendingEmailExists() async {
        let auth = MockAuthService(currentSession: nil)
        let profile = MockProfileService(profile: nil)
        let pending = MockEmailVerificationPendingStore(
            pending: PendingEmailVerification(
                email: "pending@example.com",
                createdAt: Date(),
                lastResendAt: nil
            )
        )
        let store = SessionStore(authService: auth, profileService: profile, emailVerificationPendingStore: pending)

        await store.start()

        #expect(store.state.route == .awaitingEmailVerification(email: "pending@example.com"))
        #expect(store.state.pendingVerificationEmail == "pending@example.com")
    }

    @Test
    func startMovesToNeedsOnboardingWhenSessionExistsWithoutCompletion() async {
        let userID = UUID()
        let auth = MockAuthService(currentSession: AuthSession(userID: userID))
        let profile = MockProfileService(
            profile: Profile(
                id: userID,
                participantID: nil,
                firstName: "Jane",
                lastName: "Doe",
                dateOfBirth: Date(),
                timezone: nil,
                createdAt: nil,
                onboardingCompletedAt: nil
            )
        )
        let pending = MockEmailVerificationPendingStore(pending: nil)
        let store = SessionStore(authService: auth, profileService: profile, emailVerificationPendingStore: pending)

        await store.start()

        if case .needsOnboarding(let loadedProfile) = store.state.route {
            #expect(loadedProfile?.id == userID)
        } else {
            #expect(Bool(false), "Expected .needsOnboarding route")
        }
    }

    @Test
    func startMovesToReadyWhenProfileCompleted() async {
        let userID = UUID()
        let auth = MockAuthService(currentSession: AuthSession(userID: userID))
        let profile = MockProfileService(
            profile: Profile(
                id: userID,
                participantID: nil,
                firstName: "Jane",
                lastName: "Doe",
                dateOfBirth: Date(),
                timezone: nil,
                createdAt: nil,
                onboardingCompletedAt: Date()
            )
        )
        let pending = MockEmailVerificationPendingStore(
            pending: PendingEmailVerification(email: "stale@example.com", createdAt: Date(), lastResendAt: nil)
        )
        let store = SessionStore(authService: auth, profileService: profile, emailVerificationPendingStore: pending)

        await store.start()

        if case .ready(let loadedProfile) = store.state.route {
            #expect(loadedProfile.id == userID)
        } else {
            #expect(Bool(false), "Expected .ready route")
        }
        #expect(store.state.pendingVerificationEmail == nil)
    }

    @Test
    func signUpAwaitingVerificationStoresPendingAndMovesToAwaitingRoute() async {
        let auth = MockAuthService(currentSession: nil, signUpResult: .awaitingEmailVerification)
        let profile = MockProfileService(profile: nil)
        let pending = MockEmailVerificationPendingStore(pending: nil)
        let store = SessionStore(authService: auth, profileService: profile, emailVerificationPendingStore: pending)

        await store.start()
        await store.signUp(
            email: "pending@example.com",
            password: "password123",
            firstName: "Jane",
            lastName: "Doe",
            dateOfBirth: Date()
        )

        #expect(store.state.route == .awaitingEmailVerification(email: "pending@example.com"))
        #expect(store.state.pendingVerificationEmail == "pending@example.com")
        #expect(pending.pending?.email == "pending@example.com")
    }

    @Test
    func signInUnconfirmedEmailMovesToAwaitingVerification() async {
        let auth = MockAuthService(
            currentSession: nil,
            signInError: AuthServiceError.emailNotConfirmed
        )
        let profile = MockProfileService(profile: nil)
        let pending = MockEmailVerificationPendingStore(pending: nil)
        let store = SessionStore(authService: auth, profileService: profile, emailVerificationPendingStore: pending)

        await store.start()
        await store.signIn(email: "pending@example.com", password: "password123")

        #expect(store.state.route == .awaitingEmailVerification(email: "pending@example.com"))
        #expect(store.state.pendingVerificationEmail == "pending@example.com")
        #expect(pending.pending?.email == "pending@example.com")
    }

    @Test
    func callbackSignedInClearsPendingAndMovesForward() async {
        let userID = UUID()
        let auth = MockAuthService(
            currentSession: nil,
            callbackResult: .signedIn,
            callbackSession: AuthSession(userID: userID)
        )
        let profile = MockProfileService(profile: nil)
        let pending = MockEmailVerificationPendingStore(
            pending: PendingEmailVerification(
                email: "pending@example.com",
                createdAt: Date(),
                lastResendAt: nil
            )
        )
        let store = SessionStore(authService: auth, profileService: profile, emailVerificationPendingStore: pending)

        await store.start()
        await store.handleIncomingURL(URL(string: "tinnitrack://auth/confirm#access_token=123")!)

        #expect(store.state.pendingVerificationEmail == nil)
        #expect(pending.pending == nil)
        if case .needsOnboarding = store.state.route {
            #expect(Bool(true))
        } else {
            #expect(Bool(false), "Expected .needsOnboarding route")
        }
    }

    @Test
    func useDifferentEmailClearsPendingAndMovesToUnauthenticated() async {
        let auth = MockAuthService(currentSession: nil)
        let profile = MockProfileService(profile: nil)
        let pending = MockEmailVerificationPendingStore(
            pending: PendingEmailVerification(
                email: "pending@example.com",
                createdAt: Date(),
                lastResendAt: nil
            )
        )
        let store = SessionStore(authService: auth, profileService: profile, emailVerificationPendingStore: pending)

        await store.start()
        store.useDifferentEmailForVerification()

        #expect(store.state.route == .unauthenticated)
        #expect(store.state.pendingVerificationEmail == nil)
        #expect(pending.pending == nil)
    }

    @Test
    func refreshFailurePreservesExistingRouteAndShowsError() async {
        let userID = UUID()
        let profile = Profile(
            id: userID,
            participantID: nil,
            firstName: "Jane",
            lastName: "Doe",
            dateOfBirth: Date(),
            timezone: nil,
            createdAt: nil,
            onboardingCompletedAt: Date()
        )

        let auth = MockAuthService(currentSession: AuthSession(userID: userID))
        let profileService = MockProfileService(profile: profile)
        let pending = MockEmailVerificationPendingStore(pending: nil)
        let store = SessionStore(authService: auth, profileService: profileService, emailVerificationPendingStore: pending)

        await store.start()
        auth.currentSessionError = AuthServiceError.transport("Network unavailable")

        await store.checkEmailVerificationStatus()

        if case .ready = store.state.route {
            #expect(Bool(true))
        } else {
            #expect(Bool(false), "Expected existing .ready route to be preserved")
        }

        if case .error(let message)? = store.state.banner {
            #expect(message == "Network unavailable")
        } else {
            #expect(Bool(false), "Expected error banner after refresh failure")
        }
    }

    @Test
    func checkEmailVerificationStatusDoesNotOverwriteRefreshError() async {
        let auth = MockAuthService(currentSession: nil)
        let profile = MockProfileService(profile: nil)
        let pending = MockEmailVerificationPendingStore(
            pending: PendingEmailVerification(
                email: "pending@example.com",
                createdAt: Date(),
                lastResendAt: nil
            )
        )
        let store = SessionStore(authService: auth, profileService: profile, emailVerificationPendingStore: pending)

        await store.start()
        auth.currentSessionError = AuthServiceError.transport("Network unavailable")

        await store.checkEmailVerificationStatus()

        #expect(store.state.route == .awaitingEmailVerification(email: "pending@example.com"))
        if case .error(let message)? = store.state.banner {
            #expect(message == "Network unavailable")
        } else {
            #expect(Bool(false), "Expected refresh error banner to remain visible")
        }
    }

    @Test
    func concurrentRefreshRequestsRunSerialized() async {
        let recorder = CurrentSessionConcurrencyRecorder()
        let auth = MockAuthService(
            currentSession: nil,
            currentSessionDelayNanoseconds: 80_000_000,
            currentSessionRecorder: recorder
        )
        let profile = MockProfileService(profile: nil)
        let pending = MockEmailVerificationPendingStore(
            pending: PendingEmailVerification(
                email: "pending@example.com",
                createdAt: Date(),
                lastResendAt: nil
            )
        )
        let store = SessionStore(authService: auth, profileService: profile, emailVerificationPendingStore: pending)

        await store.start()

        let taskOne = Task { @MainActor in
            await store.checkEmailVerificationStatus()
        }
        let taskTwo = Task { @MainActor in
            await store.checkEmailVerificationStatus()
        }

        await taskOne.value
        await taskTwo.value

        #expect(recorder.snapshotMaxInFlight() == 1)
    }

    @Test
    func signInMaintainsRouteStabilityWithoutBootstrappingFlicker() async {
        let userID = UUID()
        let auth = MockAuthService(
            currentSession: nil,
            sessionAfterSignIn: AuthSession(userID: userID),
            signInDelayNanoseconds: 80_000_000
        )
        let profile = MockProfileService(profile: nil)
        let pending = MockEmailVerificationPendingStore(pending: nil)
        let store = SessionStore(authService: auth, profileService: profile, emailVerificationPendingStore: pending)

        await store.start()

        let task = Task { @MainActor in
            await store.signIn(email: "person@example.com", password: "password123")
        }

        try? await Task.sleep(nanoseconds: 20_000_000)

        #expect(store.state.route == .unauthenticated)
        #expect(store.state.activity == .signingIn)

        await task.value

        if case .needsOnboarding = store.state.route {
            #expect(Bool(true))
        } else {
            #expect(Bool(false), "Expected .needsOnboarding after successful sign-in")
        }
        #expect(store.state.route != .bootstrapping)
    }
}

private final class MockAuthService: AuthServiceProtocol {
    private var storedSession: AuthSession?
    private let signUpResult: SignUpResult
    private let signInError: Error?
    private let callbackResult: AuthCallbackResult
    private let callbackSession: AuthSession?
    private let sessionAfterSignIn: AuthSession?
    private let signInDelayNanoseconds: UInt64
    var currentSessionError: Error?
    private let currentSessionDelayNanoseconds: UInt64
    private let currentSessionRecorder: CurrentSessionConcurrencyRecorder?

    init(
        currentSession: AuthSession?,
        signUpResult: SignUpResult = .signedIn,
        signInError: Error? = nil,
        callbackResult: AuthCallbackResult = .none,
        callbackSession: AuthSession? = nil,
        sessionAfterSignIn: AuthSession? = nil,
        signInDelayNanoseconds: UInt64 = 0,
        currentSessionError: Error? = nil,
        currentSessionDelayNanoseconds: UInt64 = 0,
        currentSessionRecorder: CurrentSessionConcurrencyRecorder? = nil
    ) {
        self.storedSession = currentSession
        self.signUpResult = signUpResult
        self.signInError = signInError
        self.callbackResult = callbackResult
        self.callbackSession = callbackSession
        self.sessionAfterSignIn = sessionAfterSignIn
        self.signInDelayNanoseconds = signInDelayNanoseconds
        self.currentSessionError = currentSessionError
        self.currentSessionDelayNanoseconds = currentSessionDelayNanoseconds
        self.currentSessionRecorder = currentSessionRecorder
    }

    func signUp(email: String, password: String, metadata: SignUpMetadata) async throws -> SignUpResult {
        signUpResult
    }

    func signIn(email: String, password: String) async throws {
        if signInDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: signInDelayNanoseconds)
        }
        if let signInError {
            throw signInError
        }
        if let sessionAfterSignIn {
            storedSession = sessionAfterSignIn
        }
    }

    func signOut() async throws {
        storedSession = nil
    }

    func currentSession() async throws -> AuthSession? {
        currentSessionRecorder?.begin()
        defer { currentSessionRecorder?.end() }

        if currentSessionDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: currentSessionDelayNanoseconds)
        }
        if let currentSessionError {
            throw currentSessionError
        }
        return storedSession
    }

    func authStateStream() -> AsyncStream<AuthStateChange> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func resendSignUpVerification(email: String, redirectURL: URL) async throws {}

    func requestPasswordReset(email: String, redirectURL: URL) async throws {}

    func handleAuthCallback(url: URL) async throws -> AuthCallbackResult {
        if callbackResult == .signedIn {
            storedSession = callbackSession
        }
        return callbackResult
    }

    func updatePassword(newPassword: String) async throws {}
}

private final class MockProfileService: ProfileServiceProtocol {
    private(set) var profile: Profile?

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

private final class MockEmailVerificationPendingStore: EmailVerificationPendingStoring {
    var pending: PendingEmailVerification?

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

private final class CurrentSessionConcurrencyRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var inFlight = 0
    private var maxInFlight = 0

    func begin() {
        lock.lock()
        defer { lock.unlock() }
        inFlight += 1
        if inFlight > maxInFlight {
            maxInFlight = inFlight
        }
    }

    func end() {
        lock.lock()
        defer { lock.unlock() }
        inFlight = max(0, inFlight - 1)
    }

    func snapshotMaxInFlight() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return maxInFlight
    }
}
