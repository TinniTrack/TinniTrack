//
//  SignupDraftStore.swift
//  TinniTrack
//

import Foundation

protocol SignupDraftStoring {
    func load(defaultDateOfBirth: Date) -> SignupDraft
    func save(_ draft: SignupDraft)
    func clear()
}

struct SignupDraftStore: SignupDraftStoring {
    private let defaults: UserDefaults
    private let key: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        defaults: UserDefaults = .standard,
        key: String = "signup_draft_v1"
    ) {
        self.defaults = defaults
        self.key = key
    }

    func load(defaultDateOfBirth: Date) -> SignupDraft {
        guard let data = defaults.data(forKey: key),
              let decoded = try? decoder.decode(SignupDraft.self, from: data) else {
            return .empty(defaultDateOfBirth: defaultDateOfBirth)
        }
        return decoded
    }

    func save(_ draft: SignupDraft) {
        guard let data = try? encoder.encode(draft) else { return }
        defaults.set(data, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}
