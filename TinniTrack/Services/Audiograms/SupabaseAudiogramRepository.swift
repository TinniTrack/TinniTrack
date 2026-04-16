//
//  SupabaseAudiogramRepository.swift
//  TinniTrack
//

import Foundation
import Supabase

final class SupabaseAudiogramRepository: AudiogramRepositoryProtocol {
    private let client: SupabaseClient

    init(client: SupabaseClient = supabase) {
        self.client = client
    }

    func fetchLatestAudiogram() async throws -> AudiogramRecord? {
        guard let userID = try await currentUserID() else {
            return nil
        }

        let rows: [AudiogramRow] = try await client
            .from("audiograms")
            .select("id,measured_at,source,headphone_name,healthkit_sample_uuid")
            .eq("user_id", value: userID.uuidString)
            .order("measured_at", ascending: false)
            .limit(1)
            .execute()
            .value

        guard let row = rows.first else {
            return nil
        }

        return row.toDomain()
    }

    func saveHealthKitAudiograms(_ samples: [HealthKitAudiogramSample]) async throws -> Int {
        guard !samples.isEmpty else {
            return 0
        }

        guard let userID = try await currentUserID() else {
            throw NSError(
                domain: "AudiogramRepository",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "No active session."]
            )
        }

        var latestSampleByUUID: [UUID: HealthKitAudiogramSample] = [:]
        for sample in samples {
            if let existing = latestSampleByUUID[sample.sampleUUID] {
                if sample.measuredAt > existing.measuredAt {
                    latestSampleByUUID[sample.sampleUUID] = sample
                }
            } else {
                latestSampleByUUID[sample.sampleUUID] = sample
            }
        }

        let orderedSamples = latestSampleByUUID.values.sorted { $0.measuredAt < $1.measuredAt }

        var insertedCount = 0
        for sample in orderedSamples {
            let existingRows: [ExistingAudiogramRow] = try await client
                .from("audiograms")
                .select("id")
                .eq("user_id", value: userID.uuidString)
                .eq("healthkit_sample_uuid", value: sample.sampleUUID.uuidString)
                .limit(1)
                .execute()
                .value

            guard existingRows.isEmpty else {
                continue
            }

            let payload = NewAudiogramPayload(
                userID: userID,
                measuredAt: Self.iso8601Formatter.string(from: sample.measuredAt),
                source: "healthkit",
                headphoneName: sample.deviceName,
                healthKitSampleUUID: sample.sampleUUID,
                frequencyData: FrequencyDataPayload(
                    schemaVersion: 1,
                    points: sample.points
                )
            )

            try await client
                .from("audiograms")
                .insert(payload)
                .execute()

            insertedCount += 1
        }

        return insertedCount
    }

    private func currentUserID() async throws -> UUID? {
        do {
            let session = try await client.auth.session
            return session.user.id
        } catch {
            return nil
        }
    }

    fileprivate static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

private struct ExistingAudiogramRow: Decodable {
    let id: UUID
}

private struct AudiogramRow: Decodable {
    let id: UUID
    let measuredAt: String
    let source: String
    let headphoneName: String?
    let healthKitSampleUUID: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case measuredAt = "measured_at"
        case source
        case headphoneName = "headphone_name"
        case healthKitSampleUUID = "healthkit_sample_uuid"
    }

    func toDomain() -> AudiogramRecord {
        AudiogramRecord(
            id: id,
            measuredAt: Self.parseTimestamp(measuredAt) ?? Date.distantPast,
            source: source,
            headphoneName: headphoneName,
            healthKitSampleUUID: healthKitSampleUUID,
            points: []
        )
    }

    private static func parseTimestamp(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        if let date = SupabaseAudiogramRepository.iso8601Formatter.date(from: value) {
            return date
        }
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        return fallback.date(from: value)
    }
}

private struct FrequencyDataPayload: Encodable {
    let schemaVersion: Int
    let points: [AudiogramPoint]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case points
    }
}

private struct NewAudiogramPayload: Encodable {
    let userID: UUID
    let measuredAt: String
    let source: String
    let headphoneName: String?
    let healthKitSampleUUID: UUID
    let frequencyData: FrequencyDataPayload

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case measuredAt = "measured_at"
        case source
        case headphoneName = "headphone_name"
        case healthKitSampleUUID = "healthkit_sample_uuid"
        case frequencyData = "frequency_data"
    }
}
