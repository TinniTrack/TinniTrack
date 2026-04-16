//
//  Profile.swift
//  TinniTrack
//

import Foundation

struct Profile: Codable, Equatable {
    let id: UUID
    let participantID: Int?
    let firstName: String?
    let lastName: String?
    let dateOfBirth: Date?
    let timezone: String?
    let createdAt: Date?
    let onboardingCompletedAt: Date?

    var isOnboardingComplete: Bool {
        onboardingCompletedAt != nil
            && !(firstName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            && !(lastName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            && dateOfBirth != nil
    }

    enum CodingKeys: String, CodingKey {
        case id
        case participantID = "participant_id"
        case firstName = "first_name"
        case lastName = "last_name"
        case dateOfBirth = "date_of_birth"
        case timezone
        case createdAt = "created_at"
        case onboardingCompletedAt = "onboarding_completed_at"
    }
}
