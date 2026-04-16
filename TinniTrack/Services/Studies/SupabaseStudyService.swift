//
//  SupabaseStudyService.swift
//  TinniTrack
//

import Foundation
import Supabase

final class SupabaseStudyService: StudyServiceProtocol {
    private let client: SupabaseClient

    init(client: SupabaseClient = supabase) {
        self.client = client
    }

    func fetchStudies() async throws -> [Study] {
        let rows: [StudyRow] = try await client
            .from("studies")
            .select("id,slug,title,description,status,created_at")
            .order("created_at", ascending: false)
            .execute()
            .value

        return rows.map { $0.toDomain() }
    }

    func fetchMyEnrollments() async throws -> [StudyEnrollment] {
        guard let userID = try await currentUserID() else {
            return []
        }

        let rows: [StudyEnrollmentRow] = try await client
            .from("study_enrollments")
            .select("id,user_id,study_id,status,enrolled_at,created_at")
            .eq("user_id", value: userID.uuidString)
            .execute()
            .value

        return rows.map { $0.toDomain() }
    }

    func enroll(studyID: UUID) async throws {
        guard let userID = try await currentUserID() else {
            throw NSError(
                domain: "StudyService",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "No active session."]
            )
        }

        let existing: [EnrollmentLookupRow] = try await client
            .from("study_enrollments")
            .select("id")
            .eq("user_id", value: userID.uuidString)
            .eq("study_id", value: studyID.uuidString)
            .limit(1)
            .execute()
            .value

        if let enrollmentID = existing.first?.id {
            try await client
                .from("study_enrollments")
                .update(EnrollmentStatusPayload(
                    status: "enrolled",
                    enrolledAt: Self.iso8601Formatter.string(from: Date())
                ))
                .eq("id", value: enrollmentID.uuidString)
                .execute()
        } else {
            try await client
                .from("study_enrollments")
                .insert(NewEnrollmentPayload(
                    userID: userID,
                    studyID: studyID,
                    status: "enrolled",
                    enrolledAt: Self.iso8601Formatter.string(from: Date())
                ))
                .execute()
        }
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

private struct StudyRow: Decodable {
    let id: UUID
    let slug: String
    let title: String
    let description: String
    let status: String
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case slug
        case title
        case description
        case status
        case createdAt = "created_at"
    }

    func toDomain() -> Study {
        Study(
            id: id,
            slug: slug,
            title: title,
            description: description,
            status: StudyRecruitmentStatus(rawValue: status),
            createdAt: Self.parseTimestamp(createdAt)
        )
    }

    private static func parseTimestamp(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        if let date = SupabaseStudyService.iso8601Formatter.date(from: value) {
            return date
        }
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        return fallback.date(from: value)
    }
}

private struct StudyEnrollmentRow: Decodable {
    let id: UUID
    let userID: UUID
    let studyID: UUID
    let status: String
    let enrolledAt: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case studyID = "study_id"
        case status
        case enrolledAt = "enrolled_at"
        case createdAt = "created_at"
    }

    func toDomain() -> StudyEnrollment {
        StudyEnrollment(
            id: id,
            userID: userID,
            studyID: studyID,
            status: StudyEnrollmentStatus(rawValue: status),
            enrolledAt: Self.parseTimestamp(enrolledAt),
            createdAt: Self.parseTimestamp(createdAt)
        )
    }

    private static func parseTimestamp(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        if let date = SupabaseStudyService.iso8601Formatter.date(from: value) {
            return date
        }
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        return fallback.date(from: value)
    }
}

private struct EnrollmentLookupRow: Decodable {
    let id: UUID
}

private struct EnrollmentStatusPayload: Encodable {
    let status: String
    let enrolledAt: String

    enum CodingKeys: String, CodingKey {
        case status
        case enrolledAt = "enrolled_at"
    }
}

private struct NewEnrollmentPayload: Encodable {
    let userID: UUID
    let studyID: UUID
    let status: String
    let enrolledAt: String

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case studyID = "study_id"
        case status
        case enrolledAt = "enrolled_at"
    }
}
