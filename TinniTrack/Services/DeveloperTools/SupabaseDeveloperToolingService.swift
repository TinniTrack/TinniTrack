//
//  SupabaseDeveloperToolingService.swift
//  TinniTrack
//

import Foundation
import Supabase

#if DEBUG
final class SupabaseDeveloperToolingService: DeveloperToolingServiceProtocol {
    private let client: SupabaseClient

    init(client: SupabaseClient = supabase) {
        self.client = client
    }

    func resetProfileOnboarding() async throws {
        try await client.rpc("dev_reset_profile_onboarding").execute()
    }

    func resetStudyNo1Orientation() async throws {
        try await client.rpc("dev_reset_study_no_1_orientation").execute()
    }

    func unenrollFromStudyNo1AndDeleteData() async throws {
        let rows: [ConsentPDFPathRow] = try await client
            .rpc("dev_study_no_1_consent_pdf_paths")
            .execute()
            .value

        let paths = rows.map(\.path).filter { !$0.isEmpty }
        if !paths.isEmpty {
            try await client.storage
                .from(StudyConsentCatalog.consentStorageBucket)
                .remove(paths: paths)
        }

        try await client.rpc("dev_unenroll_study_no_1").execute()
    }

    func makeNextLoudnessMatchAvailableNow() async throws {
        try await client.rpc("dev_make_next_loudness_match_available_now").execute()
    }

    func reopenLastCompletedLoudnessMatch() async throws {
        try await client.rpc("dev_reopen_last_completed_loudness_match").execute()
    }
}

private struct ConsentPDFPathRow: Decodable {
    let path: String
}
#endif
