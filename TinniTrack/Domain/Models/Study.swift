//
//  Study.swift
//  TinniTrack
//

import Foundation

struct Study: Identifiable, Equatable {
    let id: UUID
    let slug: String
    let title: String
    let description: String
    let status: StudyRecruitmentStatus
    let createdAt: Date?
}

enum StudyRecruitmentStatus: Equatable {
    case recruiting
    case recruitingPaused
    case closed
    case unknown(String)

    init(rawValue: String) {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "recruiting":
            self = .recruiting
        case "recruiting paused":
            self = .recruitingPaused
        case "closed":
            self = .closed
        default:
            self = .unknown(rawValue)
        }
    }
}
