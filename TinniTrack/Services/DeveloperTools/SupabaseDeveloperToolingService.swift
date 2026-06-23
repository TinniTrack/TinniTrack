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

    func makeNextLoudnessMatchAvailableNow() async throws {
        try await client.rpc("dev_make_next_loudness_match_available_now").execute()
    }

    func reopenLastCompletedLoudnessMatch() async throws {
        try await client.rpc("dev_reopen_last_completed_loudness_match").execute()
    }
}
#endif
