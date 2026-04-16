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
