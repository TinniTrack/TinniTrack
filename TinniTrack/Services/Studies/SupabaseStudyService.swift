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
            .select("id,user_id,study_id,status,enrolled_at,created_at,onboarding_completed_at")
            .eq("user_id", value: userID.uuidString)
            .execute()
            .value

        return rows.map { $0.toDomain() }
    }

    func fetchScheduledTasks(enrollmentID: UUID) async throws -> [ScheduledTask] {
        let rows: [ScheduledTaskRow] = try await client
            .from("scheduled_tasks")
            .select("id,enrollment_id,task_key,task_version,scheduled_for,window_start,window_end,status,day_index,slot_index,completed_at")
            .eq("enrollment_id", value: enrollmentID.uuidString)
            .order("scheduled_for", ascending: true)
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

    func completeStudyNo1Onboarding(enrollmentID: UUID, timezone: String) async throws {
        let params: [String: String] = [
            "p_enrollment_id": enrollmentID.uuidString,
            "p_timezone": timezone
        ]

        try await client
            .rpc(
                "complete_study_no_1_onboarding",
                params: params
            )
            .execute()
    }

    func submitLoudnessMatch(
        scheduledTaskID: UUID,
        enrollmentID: UUID,
        submission: LoudnessMatchSubmission
    ) async throws {
        guard submission.validationStatus == .acceptedValid else {
            throw NSError(
                domain: "StudyService",
                code: 422,
                userInfo: [NSLocalizedDescriptionKey: "Loudness-match submission is invalid and was not sent."]
            )
        }

        let params: [String: JSONValue] = [
            "p_scheduled_task_id": .string(scheduledTaskID.uuidString),
            "p_enrollment_id": .string(enrollmentID.uuidString),
            "p_started_at": .string(Self.iso8601Formatter.string(from: submission.startedAt)),
            "p_completed_at": .string(Self.iso8601Formatter.string(from: submission.completedAt)),
            "p_matched_level": .number(submission.matchedLevel),
            "p_gating": .object(submission.gating),
            "p_raw_payload": .object(submission.rawPayload),
            "p_device_info": .object(submission.deviceInfo),
            "p_headphone_info": .object(submission.headphoneInfo),
            "p_app_version": submission.appVersion.map(JSONValue.string) ?? .null,
            "p_calibration_version": submission.calibrationVersion.map(JSONValue.string) ?? .null
        ]

        try await client
            .rpc(
                "submit_study_no_1_loudness_match",
                params: params
            )
            .execute()
    }

    func fetchStudyNo1LoudnessMatchExports() async throws -> [StudyNo1LoudnessMatchExportRecord] {
        let rows: [StudyNo1LoudnessMatchExportRow] = try await client
            .rpc("export_study_no_1_loudness_matches")
            .execute()
            .value

        return rows.map { $0.toDomain() }
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
    let onboardingCompletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case studyID = "study_id"
        case status
        case enrolledAt = "enrolled_at"
        case createdAt = "created_at"
        case onboardingCompletedAt = "onboarding_completed_at"
    }

    func toDomain() -> StudyEnrollment {
        StudyEnrollment(
            id: id,
            userID: userID,
            studyID: studyID,
            status: StudyEnrollmentStatus(rawValue: status),
            enrolledAt: Self.parseTimestamp(enrolledAt),
            createdAt: Self.parseTimestamp(createdAt),
            onboardingCompletedAt: Self.parseTimestamp(onboardingCompletedAt)
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

private struct ScheduledTaskRow: Decodable {
    let id: UUID
    let enrollmentID: UUID
    let taskKey: String
    let taskVersion: Int
    let scheduledFor: String
    let windowStart: String
    let windowEnd: String
    let status: String
    let dayIndex: Int
    let slotIndex: Int
    let completedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case enrollmentID = "enrollment_id"
        case taskKey = "task_key"
        case taskVersion = "task_version"
        case scheduledFor = "scheduled_for"
        case windowStart = "window_start"
        case windowEnd = "window_end"
        case status
        case dayIndex = "day_index"
        case slotIndex = "slot_index"
        case completedAt = "completed_at"
    }

    func toDomain() -> ScheduledTask {
        ScheduledTask(
            id: id,
            enrollmentID: enrollmentID,
            taskKey: taskKey,
            taskVersion: taskVersion,
            scheduledFor: Self.parseTimestamp(scheduledFor) ?? Date.distantPast,
            windowStart: Self.parseTimestamp(windowStart) ?? Date.distantPast,
            windowEnd: Self.parseTimestamp(windowEnd) ?? Date.distantFuture,
            status: ScheduledTaskStatus(rawValue: status),
            dayIndex: dayIndex,
            slotIndex: slotIndex,
            completedAt: Self.parseTimestamp(completedAt)
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

private struct StudyNo1LoudnessMatchExportRow: Decodable {
    let taskRunID: UUID?
    let scheduledTaskID: UUID?
    let enrollmentID: UUID?
    let userID: UUID?
    let participantID: Int?
    let submittedAt: String?
    let scheduledFor: String?
    let dayIndex: Int?
    let slotIndex: Int?
    let startedAt: String?
    let completedAt: String?
    let schemaVersion: String
    let validationStatus: String
    let qualityFlags: String
    let taskKey: String
    let taskVersion: Int
    let matchedNormalizedAmplitude: Double
    let peakDBFS: Double?
    let rmsDBFS: Double?
    let estimatedDBSPL: Double?
    let estimatedDBHL: Double?
    let estimatedDBSLLeft: Double?
    let estimatedDBSLRight: Double?
    let estimatedDBSLBilateralMean: Double?
    let calibrationProfileID: String?
    let calibrationProfileVersion: String?
    let calibrationSourceTableVersion: String?
    let routeName: String?
    let routePortType: String?
    let systemOutputVolume: Double?
    let volumeCurveOffsetDB: Double?
    let audiogramThresholdLeftDBHL: Double?
    let audiogramThresholdRightDBHL: Double?
    let audiogramThresholdDerivation: String?
    let ambientDBAtSubmit: Double?
    let trialCount: Int
    let trialStandardDeviation: Double?

    enum CodingKeys: String, CodingKey {
        case taskRunID = "task_run_id"
        case scheduledTaskID = "scheduled_task_id"
        case enrollmentID = "enrollment_id"
        case userID = "user_id"
        case participantID = "participant_id"
        case submittedAt = "submitted_at"
        case scheduledFor = "scheduled_for"
        case dayIndex = "day_index"
        case slotIndex = "slot_index"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case schemaVersion = "schema_version"
        case validationStatus = "validation_status"
        case qualityFlags = "quality_flags"
        case taskKey = "task_key"
        case taskVersion = "task_version"
        case matchedNormalizedAmplitude = "matched_normalized_amplitude"
        case peakDBFS = "peak_dbfs"
        case rmsDBFS = "rms_dbfs"
        case estimatedDBSPL = "estimated_db_spl"
        case estimatedDBHL = "estimated_db_hl"
        case estimatedDBSLLeft = "estimated_db_sl_left"
        case estimatedDBSLRight = "estimated_db_sl_right"
        case estimatedDBSLBilateralMean = "estimated_db_sl_bilateral_mean"
        case calibrationProfileID = "calibration_profile_id"
        case calibrationProfileVersion = "calibration_profile_version"
        case calibrationSourceTableVersion = "calibration_source_table_version"
        case routeName = "route_name"
        case routePortType = "route_port_type"
        case systemOutputVolume = "system_output_volume"
        case volumeCurveOffsetDB = "volume_curve_offset_db"
        case audiogramThresholdLeftDBHL = "audiogram_threshold_left_db_hl"
        case audiogramThresholdRightDBHL = "audiogram_threshold_right_db_hl"
        case audiogramThresholdDerivation = "audiogram_threshold_derivation"
        case ambientDBAtSubmit = "ambient_db_at_submit"
        case trialCount = "trial_count"
        case trialStandardDeviation = "trial_standard_deviation"
    }

    func toDomain() -> StudyNo1LoudnessMatchExportRecord {
        StudyNo1LoudnessMatchExportRecord(
            taskRunID: taskRunID,
            scheduledTaskID: scheduledTaskID,
            enrollmentID: enrollmentID,
            userID: userID,
            participantID: participantID,
            submittedAt: Self.parseTimestamp(submittedAt),
            scheduledFor: Self.parseTimestamp(scheduledFor),
            dayIndex: dayIndex,
            slotIndex: slotIndex,
            schemaVersion: schemaVersion,
            validationStatus: validationStatus,
            qualityFlags: qualityFlags,
            taskKey: taskKey,
            taskVersion: taskVersion,
            startedAt: Self.parseTimestamp(startedAt) ?? Date(timeIntervalSince1970: 0),
            completedAt: Self.parseTimestamp(completedAt) ?? Date(timeIntervalSince1970: 0),
            matchedNormalizedAmplitude: matchedNormalizedAmplitude,
            peakDBFS: peakDBFS,
            rmsDBFS: rmsDBFS,
            estimatedDBSPL: estimatedDBSPL,
            estimatedDBHL: estimatedDBHL,
            estimatedDBSLLeft: estimatedDBSLLeft,
            estimatedDBSLRight: estimatedDBSLRight,
            estimatedDBSLBilateralMean: estimatedDBSLBilateralMean,
            calibrationProfileID: calibrationProfileID,
            calibrationProfileVersion: calibrationProfileVersion,
            calibrationSourceTableVersion: calibrationSourceTableVersion,
            routeName: routeName,
            routePortType: routePortType,
            systemOutputVolume: systemOutputVolume,
            volumeCurveOffsetDB: volumeCurveOffsetDB,
            audiogramThresholdLeftDBHL: audiogramThresholdLeftDBHL,
            audiogramThresholdRightDBHL: audiogramThresholdRightDBHL,
            audiogramThresholdDerivation: audiogramThresholdDerivation,
            ambientDBAtSubmit: ambientDBAtSubmit,
            trialCount: trialCount,
            trialStandardDeviation: trialStandardDeviation
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
