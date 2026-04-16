//
//  SupabaseProfileService.swift
//  TinniTrack
//

import Foundation
import Supabase

final class SupabaseProfileService: ProfileServiceProtocol {
    private let client: SupabaseClient
    private let calendar = Calendar(identifier: .gregorian)

    init(client: SupabaseClient = supabase) {
        self.client = client
    }

    func fetchMyProfile() async throws -> Profile? {
        guard let userID = try await currentUserID() else {
            return nil
        }

        let rows: [ProfileRow] = try await client
            .from("profiles")
            .select("id,participant_id,first_name,last_name,date_of_birth,timezone,created_at,onboarding_completed_at")
            .eq("id", value: userID.uuidString)
            .limit(1)
            .execute()
            .value

        guard let row = rows.first else { return nil }
        return row.toDomain(calendar: calendar)
    }

    func completeOnboarding(firstName: String, lastName: String, dateOfBirth: Date) async throws {
        guard let userID = try await currentUserID() else {
            throw NSError(domain: "ProfileService", code: 401, userInfo: [NSLocalizedDescriptionKey: "No active session."])
        }

        let payload = OnboardingPayload(
            firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
            lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines),
            dateOfBirth: Self.dateOnlyFormatter.string(from: dateOfBirth),
            onboardingCompletedAt: Self.iso8601Formatter.string(from: Date())
        )

        try await client
            .from("profiles")
            .update(payload)
            .eq("id", value: userID.uuidString)
            .execute()
    }

    private func currentUserID() async throws -> UUID? {
        do {
            let session = try await client.auth.session
            return session.user.id
        } catch {
            return nil
        }
    }

    private static let dateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    fileprivate static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

private struct OnboardingPayload: Encodable {
    let firstName: String
    let lastName: String
    let dateOfBirth: String
    let onboardingCompletedAt: String

    enum CodingKeys: String, CodingKey {
        case firstName = "first_name"
        case lastName = "last_name"
        case dateOfBirth = "date_of_birth"
        case onboardingCompletedAt = "onboarding_completed_at"
    }
}

private struct ProfileRow: Decodable {
    let id: UUID
    let participantID: Int?
    let firstName: String?
    let lastName: String?
    let dateOfBirth: String?
    let timezone: String?
    let createdAt: String?
    let onboardingCompletedAt: String?

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

    func toDomain(calendar: Calendar) -> Profile {
        Profile(
            id: id,
            participantID: participantID,
            firstName: firstName,
            lastName: lastName,
            dateOfBirth: Self.parseDateOnly(dateOfBirth, calendar: calendar),
            timezone: timezone,
            createdAt: Self.parseTimestamp(createdAt),
            onboardingCompletedAt: Self.parseTimestamp(onboardingCompletedAt)
        )
    }

    private static func parseDateOnly(_ value: String?, calendar: Calendar) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        var components = DateComponents()
        let parts = value.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }
        components.year = year
        components.month = month
        components.day = day
        components.calendar = calendar
        components.timeZone = TimeZone(secondsFromGMT: 0)
        return components.date
    }

    private static func parseTimestamp(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        if let date = SupabaseProfileService.iso8601Formatter.date(from: value) {
            return date
        }
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        return fallback.date(from: value)
    }
}
