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

        let store = SignupDraftStore(defaults: defaults, key: "draft")
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let draft = SignupDraft(
            currentStep: 2,
            email: "user@example.com",
            password: "password123",
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
        #expect(cleared.currentStep == 1)
        #expect(cleared.email.isEmpty)
        #expect(cleared.password.isEmpty)
    }
}
