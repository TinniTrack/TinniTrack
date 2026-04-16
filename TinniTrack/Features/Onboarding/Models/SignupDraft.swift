//
//  SignupDraft.swift
//  TinniTrack
//

import Foundation

struct SignupDraft: Codable, Equatable {
    var currentStep: Int
    var email: String
    var password: String
    var firstName: String
    var lastName: String
    var dateOfBirth: Date
    var updatedAt: Date

    static func empty(defaultDateOfBirth: Date) -> SignupDraft {
        SignupDraft(
            currentStep: 1,
            email: "",
            password: "",
            firstName: "",
            lastName: "",
            dateOfBirth: defaultDateOfBirth,
            updatedAt: Date()
        )
    }
}
