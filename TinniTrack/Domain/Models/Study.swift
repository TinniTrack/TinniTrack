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

enum StudyCatalog {
    static func displayCopy(for slug: String) -> (title: String, description: String) {
        switch slug {
        case "study-no-1":
            return (
                title: "Loudness Matching Study",
                description: "Help us understand how tinnitus loudness changes throughout the day."
            )
        default:
            let title = slug
                .split(separator: "-")
                .map { String($0).capitalized }
                .joined(separator: " ")

            return (
                title: title.isEmpty ? "Study" : title,
                description: "Study details are available in the app."
            )
        }
    }
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
