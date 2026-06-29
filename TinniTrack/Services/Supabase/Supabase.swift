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

struct SupabaseEnvironmentDescriptor: Equatable {
    let url: URL
    let name: String
    let isProduction: Bool

    var hostDescription: String {
        url.host ?? url.absoluteString
    }

    var badgeText: String {
        "\(name.uppercased()) SUPABASE"
    }
}

enum SupabaseConfiguration {
    static func makeClient(bundle: Bundle = .main, processInfo: ProcessInfo = .processInfo) throws -> SupabaseClient {
        let resolved = try resolve(bundle: bundle, processInfo: processInfo)

        return SupabaseClient(
            supabaseURL: resolved.environment.url,
            supabaseKey: resolved.anonKey,
            options: SupabaseClientOptions(
                auth: .init(emitLocalSessionAsInitialSession: true)
            )
        )
    }

    static func currentEnvironment(bundle: Bundle = .main, processInfo: ProcessInfo = .processInfo) -> SupabaseEnvironmentDescriptor {
        do {
            return try resolve(bundle: bundle, processInfo: processInfo).environment
        } catch {
            return SupabaseEnvironmentDescriptor(
                url: URL(string: "about:blank")!,
                name: "Unconfigured",
                isProduction: false
            )
        }
    }

    static func currentEnvironment(bundleInfo: [String: Any], processEnvironment: [String: String]) -> SupabaseEnvironmentDescriptor {
        do {
            return try resolve(bundleInfo: bundleInfo, processEnvironment: processEnvironment).environment
        } catch {
            return SupabaseEnvironmentDescriptor(
                url: URL(string: "about:blank")!,
                name: "Unconfigured",
                isProduction: false
            )
        }
    }

    private static func resolve(bundle: Bundle, processInfo: ProcessInfo) throws -> ResolvedConfiguration {
        try resolve(bundleInfo: bundle.infoDictionary ?? [:], processEnvironment: processInfo.environment)
    }

    private static func resolve(bundleInfo: [String: Any], processEnvironment env: [String: String]) throws -> ResolvedConfiguration {
        let bundledURLString = bundleInfo["SUPABASE_URL"] as? String
        let urlString = firstNonEmptyValue(env["SUPABASE_URL"], bundledURLString)
        let anonKey = firstNonEmptyValue(
            env["SUPABASE_ANON_KEY"],
            bundleInfo["SUPABASE_ANON_KEY"] as? String
        )

        guard !urlString.isEmpty else { throw SupabaseConfigurationError.missingURL }
        guard let supabaseURL = URL(string: urlString) else { throw SupabaseConfigurationError.invalidURL }
        guard !anonKey.isEmpty else { throw SupabaseConfigurationError.missingAnonKey }

        let explicitEnvironment = firstNonEmptyValue(
            env["SUPABASE_ENVIRONMENT"],
            bundleInfo["SUPABASE_ENVIRONMENT"] as? String
        )
        let name = environmentName(explicitEnvironment, supabaseURL: supabaseURL, bundledURLString: bundledURLString)
        let isProduction = name.caseInsensitiveCompare("Production") == .orderedSame

        return ResolvedConfiguration(
            environment: SupabaseEnvironmentDescriptor(
                url: supabaseURL,
                name: name,
                isProduction: isProduction
            ),
            anonKey: anonKey
        )
    }

    private static func environmentName(_ explicitEnvironment: String, supabaseURL: URL, bundledURLString: String?) -> String {
        if !explicitEnvironment.isEmpty {
            return explicitEnvironment
        }

        let bundled = bundledURLString?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let bundled, !bundled.isEmpty, bundled != supabaseURL.absoluteString {
            return "Development"
        }

        return "Production"
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

    private struct ResolvedConfiguration {
        let environment: SupabaseEnvironmentDescriptor
        let anonKey: String
    }
}

let supabase: SupabaseClient = {
    do {
        return try SupabaseConfiguration.makeClient()
    } catch {
        fatalError("Supabase configuration failed: \(error.localizedDescription)")
    }
}()

let supabaseEnvironment = SupabaseConfiguration.currentEnvironment()
