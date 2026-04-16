//
//  EmailVerificationPendingStore.swift
//  TinniTrack
//

import Foundation

struct PendingEmailVerification: Codable, Equatable {
    let email: String
    let createdAt: Date
    var lastResendAt: Date?
}

protocol EmailVerificationPendingStoring {
    func load() -> PendingEmailVerification?
    func save(_ pending: PendingEmailVerification)
    func updateLastResend(at date: Date)
    func clear()
}

struct EmailVerificationPendingStore: EmailVerificationPendingStoring {
    private let defaults: UserDefaults
    private let key: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        defaults: UserDefaults = .standard,
        key: String = "email_verification_pending_v1"
    ) {
        self.defaults = defaults
        self.key = key
    }

    func load() -> PendingEmailVerification? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }
        return try? decoder.decode(PendingEmailVerification.self, from: data)
    }

    func save(_ pending: PendingEmailVerification) {
        guard let data = try? encoder.encode(pending) else { return }
        defaults.set(data, forKey: key)
    }

    func updateLastResend(at date: Date) {
        guard var pending = load() else { return }
        pending.lastResendAt = date
        save(pending)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}
