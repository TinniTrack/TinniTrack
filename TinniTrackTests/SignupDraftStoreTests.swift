import Foundation
import Testing
@testable import TinniTrack

struct SignupDraftStoreTests {
    @Test
    func saveLoadAndClearDraft() {
        let suiteName = "SignupDraftStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SignupDraftStore(defaults: defaults, key: "draft", legacyKey: nil)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let draft = SignupDraft(
            email: "user@example.com",
            firstName: "Jane",
            lastName: "Doe",
            dateOfBirth: date,
            updatedAt: date
        )

        store.save(draft)
        let loaded = store.load(defaultDateOfBirth: Date())
        #expect(loaded == draft)

        store.clear()
        let cleared = store.load(defaultDateOfBirth: date)
        #expect(cleared.email.isEmpty)
        #expect(defaults.data(forKey: "draft") == nil)
    }

    @Test
    func legacyDraftMigrationRemovesPersistedPassword() throws {
        struct LegacySignupDraft: Codable {
            let currentStep: Int
            let email: String
            let password: String
            let firstName: String
            let lastName: String
            let dateOfBirth: Date
            let updatedAt: Date
        }

        let suiteName = "SignupDraftStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let legacyDraft = LegacySignupDraft(
            currentStep: 2,
            email: "user@example.com",
            password: "password123",
            firstName: "Jane",
            lastName: "Doe",
            dateOfBirth: date,
            updatedAt: date
        )
        defaults.set(try JSONEncoder().encode(legacyDraft), forKey: "draft_v1")

        let store = SignupDraftStore(
            defaults: defaults,
            key: "draft_v2",
            legacyKey: "draft_v1"
        )
        let migrated = store.load(defaultDateOfBirth: Date())

        #expect(migrated.email == legacyDraft.email)
        #expect(migrated.firstName == legacyDraft.firstName)
        #expect(defaults.data(forKey: "draft_v1") == nil)

        let migratedData = try #require(defaults.data(forKey: "draft_v2"))
        let payload = try #require(
            JSONSerialization.jsonObject(with: migratedData) as? [String: Any]
        )
        #expect(payload["password"] == nil)
        #expect(payload["currentStep"] == nil)
    }
}
