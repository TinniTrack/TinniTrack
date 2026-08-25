//
//  SignupDraft.swift
//  TinniTrack
//

import Foundation

nonisolated struct SignupDraft: Codable, Equatable, Sendable {
    var email: String
    var firstName: String
    var lastName: String
    var dateOfBirth: Date
    var updatedAt: Date

    static func empty(defaultDateOfBirth: Date) -> SignupDraft {
        SignupDraft(
            email: "",
            firstName: "",
            lastName: "",
            dateOfBirth: defaultDateOfBirth,
            updatedAt: Date()
        )
    }
}
