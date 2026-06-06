//
//  StudyEnrollment.swift
//  TinniTrack
//

import Foundation

struct StudyEnrollment: Identifiable, Equatable {
    let id: UUID
    let userID: UUID
    let studyID: UUID
    let status: StudyEnrollmentStatus
    let enrolledAt: Date?
    let createdAt: Date?
    let onboardingCompletedAt: Date?

    init(
        id: UUID,
        userID: UUID,
        studyID: UUID,
        status: StudyEnrollmentStatus,
        enrolledAt: Date?,
        createdAt: Date?,
        onboardingCompletedAt: Date? = nil
    ) {
        self.id = id
        self.userID = userID
        self.studyID = studyID
        self.status = status
        self.enrolledAt = enrolledAt
        self.createdAt = createdAt
        self.onboardingCompletedAt = onboardingCompletedAt
    }
}

enum StudyEnrollmentStatus: Equatable {
    case enrolled
    case withdrawn
    case completed
    case screenFailed
    case unknown(String)

    init(rawValue: String) {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "enrolled":
            self = .enrolled
        case "withdrawn":
            self = .withdrawn
        case "completed":
            self = .completed
        case "screen_failed":
            self = .screenFailed
        default:
            self = .unknown(rawValue)
        }
    }
}
