//
//  StudyPrerequisiteRules.swift
//  TinniTrack
//

import Foundation

enum StudyPrerequisiteRules {
    static let studyNo1Slug = "study-no-1"

    static func requiresAudiogramImport(for studySlug: String) -> Bool {
        let normalizedSlug = studySlug
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalizedSlug == studyNo1Slug
    }
}
