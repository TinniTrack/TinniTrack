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
    private static let defaultRetentionInterval: TimeInterval = 24 * 60 * 60

    private let defaults: UserDefaults
    private let key: String
    private let legacyKey: String?
    private let retentionInterval: TimeInterval
    private let now: () -> Date
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        defaults: UserDefaults = .standard,
        key: String = "signup_draft_v2",
        legacyKey: String? = "signup_draft_v1",
        retentionInterval: TimeInterval = Self.defaultRetentionInterval,
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.key = key
        self.legacyKey = legacyKey
        self.retentionInterval = retentionInterval
        self.now = now
        removeInvalidOrExpiredCurrentDraft()
        migrateLegacyDraftIfNeeded()
    }

    func load(defaultDateOfBirth: Date) -> SignupDraft {
        guard let data = defaults.data(forKey: key) else {
            return .empty(defaultDateOfBirth: defaultDateOfBirth)
        }

        guard let decoded = try? decoder.decode(SignupDraft.self, from: data),
              !isExpired(decoded) else {
            defaults.removeObject(forKey: key)
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
        if let legacyKey {
            defaults.removeObject(forKey: legacyKey)
        }
    }

    private func migrateLegacyDraftIfNeeded() {
        guard let legacyKey,
              legacyKey != key,
              let legacyData = defaults.data(forKey: legacyKey) else {
            return
        }

        defer {
            defaults.removeObject(forKey: legacyKey)
        }

        guard defaults.data(forKey: key) == nil,
              let sanitizedDraft = try? decoder.decode(SignupDraft.self, from: legacyData),
              !isExpired(sanitizedDraft) else {
            return
        }

        save(sanitizedDraft)
    }

    private func removeInvalidOrExpiredCurrentDraft() {
        guard let data = defaults.data(forKey: key) else {
            return
        }

        guard let draft = try? decoder.decode(SignupDraft.self, from: data),
              !isExpired(draft) else {
            defaults.removeObject(forKey: key)
            return
        }
    }

    private func isExpired(_ draft: SignupDraft) -> Bool {
        let age = now().timeIntervalSince(draft.updatedAt)
        return age < 0 || age > retentionInterval
    }
}
