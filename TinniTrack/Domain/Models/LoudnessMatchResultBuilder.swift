import Foundation

struct MeasurementTraceEvent: Equatable {
    let timestamp: Date
    let value: Double
}

struct LoudnessMatchResultInput {
    let scheduledTask: ScheduledTask
    let startedAt: Date
    let completedAt: Date
    let matchedLevel: Double
    let currentRoute: AudioOutputRoute?
    let isSupportedRoute: Bool
    let ambientDB: Double?
    let isAmbientQuiet: Bool
    let loudnessEvents: [MeasurementTraceEvent]
    let ambientEvents: [MeasurementTraceEvent]
    let deviceInfo: [String: JSONValue]
    let outputDeviceInfo: [String: JSONValue]
    let appVersion: String?
}

protocol LoudnessMatchResultBuilding {
    func makeSubmission(from input: LoudnessMatchResultInput) -> LoudnessMatchSubmission
}

struct StudyNo1LoudnessMatchResultBuilder: LoudnessMatchResultBuilding {
    private let protocolDefinition: StudyProtocolDefinition

    init(protocolDefinition: StudyProtocolDefinition = StudyProtocolCatalog.studyNo1) {
        self.protocolDefinition = protocolDefinition
    }

    func makeSubmission(from input: LoudnessMatchResultInput) -> LoudnessMatchSubmission {
        let baseTime = input.startedAt

        let loudnessTrace: [JSONValue] = input.loudnessEvents.map { event in
            .object([
                "offset_seconds": .number(event.timestamp.timeIntervalSince(baseTime)),
                "value": .number(event.value),
                "unit": .string(MeasurementUnit.normalizedAmplitude.rawValue)
            ])
        }

        let ambientTrace: [JSONValue] = input.ambientEvents.map { event in
            .object([
                "offset_seconds": .number(event.timestamp.timeIntervalSince(baseTime)),
                "db": .number(event.value),
                "unit": .string(MeasurementUnit.estimatedDBA.rawValue)
            ])
        }

        let gating: [String: JSONValue] = [
            "headphone_gate": .object([
                "route_name": .string(input.currentRoute?.name ?? ""),
                "route_port_type": .string(input.currentRoute?.portType ?? ""),
                "is_supported": .bool(input.isSupportedRoute)
            ]),
            "ambient": .object([
                "threshold_db": .number(StudyNo1Configuration.ambientThresholdDB),
                "db_at_submit": .number(input.ambientDB ?? -1),
                "within_threshold": .bool(input.isAmbientQuiet),
                "unit": .string(MeasurementUnit.estimatedDBA.rawValue)
            ])
        ]

        let measurementMetadata: [String: JSONValue] = [
            "schema_version": .string(protocolDefinition.resultPayload.schemaVersion),
            "protocol_version": .string(protocolDefinition.resultPayload.protocolVersion),
            "calibration_profile_id": .string(protocolDefinition.calibrationProfile.identifier),
            "calibration_profile_version": .string(protocolDefinition.calibrationProfile.version),
            "calibration_validation_status": .string(protocolDefinition.calibrationProfile.validationStatus.rawValue),
            "validity_notice": .string(protocolDefinition.resultPayload.validityNotice)
        ]

        let rawPayload: [String: JSONValue] = [
            "task_key": .string(input.scheduledTask.taskKey),
            "task_version": .number(Double(input.scheduledTask.taskVersion)),
            "matched_level": .number(input.matchedLevel),
            "matched_level_unit": .string(MeasurementUnit.normalizedAmplitude.rawValue),
            "loudness_trace": .array(loudnessTrace),
            "ambient_trace": .array(ambientTrace),
            "measurement_metadata": .object(measurementMetadata)
        ]

        return LoudnessMatchSubmission(
            startedAt: input.startedAt,
            completedAt: input.completedAt,
            matchedLevel: input.matchedLevel,
            gating: gating,
            rawPayload: rawPayload,
            deviceInfo: input.deviceInfo,
            headphoneInfo: input.outputDeviceInfo,
            appVersion: input.appVersion,
            calibrationVersion: protocolDefinition.calibrationProfile.identifier
        )
    }
}
