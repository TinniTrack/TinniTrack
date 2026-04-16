//
//  Supabase.swift
//  TinniTrack
//

import Foundation
import Supabase

enum SupabaseConfigurationError: LocalizedError {
    case missingURL
    case invalidURL
    case missingAnonKey

    var errorDescription: String? {
        switch self {
        case .missingURL:
            return "Missing SUPABASE_URL configuration."
        case .invalidURL:
            return "SUPABASE_URL is not a valid URL."
        case .missingAnonKey:
            return "Missing SUPABASE_ANON_KEY configuration."
        }
    }
}

enum SupabaseConfiguration {
    static func makeClient(bundle: Bundle = .main, processInfo: ProcessInfo = .processInfo) throws -> SupabaseClient {
        let env = processInfo.environment
        let urlString = firstNonEmptyValue(
            env["SUPABASE_URL"],
            bundle.object(forInfoDictionaryKey: "SUPABASE_URL") as? String
        )
        let anonKey = firstNonEmptyValue(
            env["SUPABASE_ANON_KEY"],
            bundle.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String
        )

        guard !urlString.isEmpty else { throw SupabaseConfigurationError.missingURL }
        guard let supabaseURL = URL(string: urlString) else { throw SupabaseConfigurationError.invalidURL }
        guard !anonKey.isEmpty else { throw SupabaseConfigurationError.missingAnonKey }

        return SupabaseClient(
            supabaseURL: supabaseURL,
            supabaseKey: anonKey
        )
    }

    private static func firstNonEmptyValue(_ candidates: String?...) -> String {
        for candidate in candidates {
            guard let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
                continue
            }
            return trimmed
        }
        return ""
    }
}

let supabase: SupabaseClient = {
    do {
        return try SupabaseConfiguration.makeClient()
    } catch {
        fatalError("Supabase configuration failed: \(error.localizedDescription)")
    }
}()
