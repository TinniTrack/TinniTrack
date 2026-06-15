import Foundation

struct StudyNo1LoudnessMatchExportRecord: Codable, Equatable {
    let taskRunID: UUID?
    let scheduledTaskID: UUID?
    let enrollmentID: UUID?
    let userID: UUID?
    let participantID: Int?
    let submittedAt: Date?
    let scheduledFor: Date?
    let dayIndex: Int?
    let slotIndex: Int?
    let schemaVersion: String
    let validationStatus: String
    let qualityFlags: String
    let taskKey: String
    let taskVersion: Int
    let startedAt: Date
    let completedAt: Date
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
}

struct StudyNo1DataDictionaryField: Equatable {
    let column: String
    let unit: String
    let description: String
}

enum StudyNo1LoudnessMatchExportBuilder {
    static let dataDictionary: [StudyNo1DataDictionaryField] = [
        StudyNo1DataDictionaryField(column: "task_run_id", unit: "uuid", description: "Backend task_runs row identifier."),
        StudyNo1DataDictionaryField(column: "participant_id", unit: "integer", description: "Research-facing participant identifier from profiles."),
        StudyNo1DataDictionaryField(column: "submitted_at", unit: "ISO-8601 timestamp", description: "Server submission timestamp."),
        StudyNo1DataDictionaryField(column: "scheduled_for", unit: "ISO-8601 timestamp", description: "Scheduled task slot timestamp."),
        StudyNo1DataDictionaryField(column: "day_index", unit: "integer", description: "Study No. 1 longitudinal day index."),
        StudyNo1DataDictionaryField(column: "slot_index", unit: "integer", description: "Within-day prompt slot index."),
        StudyNo1DataDictionaryField(column: "schema_version", unit: "identifier", description: "Study No. 1 loudness-match export schema version."),
        StudyNo1DataDictionaryField(column: "validation_status", unit: "enum", description: "acceptedValid only when route, calibration, ambient, volume, and audiogram gates passed."),
        StudyNo1DataDictionaryField(column: "quality_flags", unit: "pipe-delimited enum", description: "Quality and invalidation flags preserved from the app payload."),
        StudyNo1DataDictionaryField(column: "matched_normalized_amplitude", unit: "normalizedAmplitude", description: "Participant-selected peak-normalized sine amplitude after safe bounds."),
        StudyNo1DataDictionaryField(column: "peak_dbfs", unit: "dBFS", description: "20*log10(peak normalized amplitude)."),
        StudyNo1DataDictionaryField(column: "rms_dbfs", unit: "dBFS", description: "20*log10(peak normalized amplitude / sqrt(2)); used for estimated SPL."),
        StudyNo1DataDictionaryField(column: "estimated_db_spl", unit: "dB SPL", description: "RMS dBFS plus ORKAudiometry frequency and iOS volume calibration."),
        StudyNo1DataDictionaryField(column: "estimated_db_hl", unit: "dB HL", description: "Estimated dB SPL minus 1 kHz RETSPL."),
        StudyNo1DataDictionaryField(column: "estimated_db_sl_left", unit: "dB SL", description: "Estimated dB HL minus exact left-ear 1 kHz threshold when available."),
        StudyNo1DataDictionaryField(column: "estimated_db_sl_right", unit: "dB SL", description: "Estimated dB HL minus exact right-ear 1 kHz threshold when available."),
        StudyNo1DataDictionaryField(column: "calibration_profile_id", unit: "identifier", description: "Headphone calibration profile used to derive SPL/HL."),
        StudyNo1DataDictionaryField(column: "calibration_source_table_version", unit: "text", description: "Source table version/provenance for reproducibility."),
        StudyNo1DataDictionaryField(column: "trial_standard_deviation", unit: "normalizedAmplitude", description: "Variability of recorded adjustment events.")
    ]

    static func makeRecord(from submission: LoudnessMatchSubmission) -> StudyNo1LoudnessMatchExportRecord {
        let payload = submission.rawPayload
        let metadata = payload.object("measurement_metadata")
        let rawInputs = payload.object("raw_inputs")
        let derived = payload.object("derived_outputs")
        let quality = payload.object("quality")
        let gating = payload.object("gating")
        let headphoneGate = gating.object("headphone_gate")
        let ambient = gating.object("ambient")
        let profile = metadata.object("active_headphone_calibration_profile")
        let volumeLookup = derived.object("volume_curve_lookup")
        let threshold = rawInputs.object("audiogram_threshold")
        let trialSummary = payload.object("trial_summary")

        return StudyNo1LoudnessMatchExportRecord(
            taskRunID: nil,
            scheduledTaskID: nil,
            enrollmentID: nil,
            userID: nil,
            participantID: nil,
            submittedAt: nil,
            scheduledFor: nil,
            dayIndex: nil,
            slotIndex: nil,
            schemaVersion: metadata.string("schema_version") ?? "",
            validationStatus: quality.string("validation_status") ?? submission.validationStatus.rawValue,
            qualityFlags: quality.arrayStrings("quality_flags").joined(separator: "|"),
            taskKey: payload.string("task_key") ?? "",
            taskVersion: Int(payload.number("task_version") ?? 0),
            startedAt: submission.startedAt,
            completedAt: submission.completedAt,
            matchedNormalizedAmplitude: rawInputs.number("matched_level") ?? submission.matchedLevel,
            peakDBFS: derived.number("peak_dbfs"),
            rmsDBFS: derived.number("rms_dbfs"),
            estimatedDBSPL: derived.number("estimated_db_spl"),
            estimatedDBHL: derived.number("estimated_db_hl"),
            estimatedDBSLLeft: derived.number("estimated_db_sl_left"),
            estimatedDBSLRight: derived.number("estimated_db_sl_right"),
            estimatedDBSLBilateralMean: derived.number("estimated_db_sl_bilateral_mean"),
            calibrationProfileID: profile.string("profile_id"),
            calibrationProfileVersion: profile.string("profile_version"),
            calibrationSourceTableVersion: profile.string("source_table_version"),
            routeName: headphoneGate.string("route_name"),
            routePortType: headphoneGate.string("route_port_type"),
            systemOutputVolume: rawInputs.number("system_output_volume_at_submit"),
            volumeCurveOffsetDB: volumeLookup.number("offset_db"),
            audiogramThresholdLeftDBHL: threshold.number("left_db_hl"),
            audiogramThresholdRightDBHL: threshold.number("right_db_hl"),
            audiogramThresholdDerivation: threshold.string("derivation"),
            ambientDBAtSubmit: ambient.number("db_at_submit"),
            trialCount: Int(trialSummary.number("count") ?? 0),
            trialStandardDeviation: trialSummary.number("standard_deviation_normalized_amplitude")
        )
    }

    static func makeJSONData(records: [StudyNo1LoudnessMatchExportRecord]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(records)
    }

    static func makeCSV(records: [StudyNo1LoudnessMatchExportRecord]) -> String {
        let header = [
            "task_run_id",
            "scheduled_task_id",
            "enrollment_id",
            "user_id",
            "participant_id",
            "submitted_at",
            "scheduled_for",
            "day_index",
            "slot_index",
            "schema_version",
            "validation_status",
            "quality_flags",
            "task_key",
            "task_version",
            "started_at",
            "completed_at",
            "matched_normalized_amplitude",
            "peak_dbfs",
            "rms_dbfs",
            "estimated_db_spl",
            "estimated_db_hl",
            "estimated_db_sl_left",
            "estimated_db_sl_right",
            "estimated_db_sl_bilateral_mean",
            "calibration_profile_id",
            "calibration_profile_version",
            "calibration_source_table_version",
            "route_name",
            "route_port_type",
            "system_output_volume",
            "volume_curve_offset_db",
            "audiogram_threshold_left_db_hl",
            "audiogram_threshold_right_db_hl",
            "audiogram_threshold_derivation",
            "ambient_db_at_submit",
            "trial_count",
            "trial_standard_deviation"
        ]

        let rows = records.map { csvRow(for: $0) }

        return ([header.joined(separator: ",")] + rows).joined(separator: "\n")
    }

    private static func csvRow(for record: StudyNo1LoudnessMatchExportRecord) -> String {
        let fields: [String] = [
            record.taskRunID?.uuidString ?? "",
            record.scheduledTaskID?.uuidString ?? "",
            record.enrollmentID?.uuidString ?? "",
            record.userID?.uuidString ?? "",
            record.participantID.map { String($0) } ?? "",
            record.submittedAt.map { iso8601Formatter.string(from: $0) } ?? "",
            record.scheduledFor.map { iso8601Formatter.string(from: $0) } ?? "",
            record.dayIndex.map { String($0) } ?? "",
            record.slotIndex.map { String($0) } ?? "",
            record.schemaVersion,
            record.validationStatus,
            record.qualityFlags,
            record.taskKey,
            String(record.taskVersion),
            iso8601Formatter.string(from: record.startedAt),
            iso8601Formatter.string(from: record.completedAt),
            format(record.matchedNormalizedAmplitude),
            format(record.peakDBFS),
            format(record.rmsDBFS),
            format(record.estimatedDBSPL),
            format(record.estimatedDBHL),
            format(record.estimatedDBSLLeft),
            format(record.estimatedDBSLRight),
            format(record.estimatedDBSLBilateralMean),
            record.calibrationProfileID ?? "",
            record.calibrationProfileVersion ?? "",
            record.calibrationSourceTableVersion ?? "",
            record.routeName ?? "",
            record.routePortType ?? "",
            format(record.systemOutputVolume),
            format(record.volumeCurveOffsetDB),
            format(record.audiogramThresholdLeftDBHL),
            format(record.audiogramThresholdRightDBHL),
            record.audiogramThresholdDerivation ?? "",
            format(record.ambientDBAtSubmit),
            String(record.trialCount),
            format(record.trialStandardDeviation)
        ]

        return fields.map(escapeCSV).joined(separator: ",")
    }

    private static func format(_ value: Double?) -> String {
        guard let value else { return "" }
        return String(format: "%.6f", value)
    }

    private static func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

private extension JSONValue {
    func object(_ key: String) -> [String: JSONValue] {
        guard case .object(let object)? = self.objectValue?[key] else { return [:] }
        return object
    }

    var objectValue: [String: JSONValue]? {
        guard case .object(let object) = self else { return nil }
        return object
    }
}

private extension Dictionary where Key == String, Value == JSONValue {
    func object(_ key: String) -> [String: JSONValue] {
        guard case .object(let object)? = self[key] else { return [:] }
        return object
    }

    func string(_ key: String) -> String? {
        guard case .string(let value)? = self[key] else { return nil }
        return value
    }

    func number(_ key: String) -> Double? {
        guard case .number(let value)? = self[key] else { return nil }
        return value
    }

    func arrayStrings(_ key: String) -> [String] {
        guard case .array(let values)? = self[key] else { return [] }
        return values.compactMap { value in
            guard case .string(let string) = value else { return nil }
            return string
        }
    }
}
