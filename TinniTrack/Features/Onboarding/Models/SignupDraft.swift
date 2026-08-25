//
//  SignupDraft.swift
//  TinniTrack
//

import Foundation

struct SignupDraft: Codable, Equatable {
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
