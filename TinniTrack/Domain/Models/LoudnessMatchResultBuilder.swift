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
    let systemOutputVolumeAtStart: Double?
    let systemOutputVolumeAtSubmit: Double?
    let didSystemOutputVolumeChange: Bool
    let loudnessEvents: [MeasurementTraceEvent]
    let ambientEvents: [MeasurementTraceEvent]
    let systemOutputVolumeEvents: [MeasurementTraceEvent]
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
        let matchedLevel = Self.clampedNormalizedLevel(input.matchedLevel)
        let taskDefinition = protocolDefinition.tasks.first { task in
            task.key == input.scheduledTask.taskKey && task.version == input.scheduledTask.taskVersion
        }

        let loudnessTrace: [JSONValue] = input.loudnessEvents.map { event in
            .object([
                "offset_seconds": .number(event.timestamp.timeIntervalSince(baseTime)),
                "value": .number(Self.clampedNormalizedLevel(event.value)),
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

        let systemOutputVolumeTrace: [JSONValue] = input.systemOutputVolumeEvents.map { event in
            .object([
                "offset_seconds": .number(event.timestamp.timeIntervalSince(baseTime)),
                "value": .number(Self.clampedNormalizedLevel(event.value)),
                "unit": .string(MeasurementUnit.systemOutputVolume.rawValue)
            ])
        }

        let gating: [String: JSONValue] = [
            "headphone_gate": .object([
                "route_name": .string(input.currentRoute?.name ?? ""),
                "route_port_type": .string(input.currentRoute?.portType ?? ""),
                "is_supported": .bool(input.isSupportedRoute),
                "allowed_generations": .array([
                    .string("AirPods Pro 2"),
                    .string("AirPods Pro 3")
                ]),
                "gate_id": .string("study-no-1-airpods-pro-2-3-route-name-gate")
            ]),
            "ambient": .object([
                "threshold_db": .number(StudyNo1Configuration.ambientThresholdDB),
                "db_at_submit": .number(input.ambientDB ?? -1),
                "within_threshold": .bool(input.isAmbientQuiet),
                "unit": .string(MeasurementUnit.estimatedDBA.rawValue)
            ]),
            "system_output_volume": .object([
                "value_at_start": input.systemOutputVolumeAtStart.map(JSONValue.number) ?? .null,
                "value_at_submit": input.systemOutputVolumeAtSubmit.map(JSONValue.number) ?? .null,
                "changed_during_matching": .bool(input.didSystemOutputVolumeChange),
                "change_tolerance": .number(StudyNo1Configuration.outputVolumeChangeTolerance),
                "unit": .string(MeasurementUnit.systemOutputVolume.rawValue)
            ])
        ]

        let measurementMetadata: [String: JSONValue] = [
            "schema_version": .string(protocolDefinition.resultPayload.schemaVersion),
            "protocol_version": .string(protocolDefinition.resultPayload.protocolVersion),
            "calibration_profile_id": .string(protocolDefinition.calibrationProfile.identifier),
            "calibration_profile_version": .string(protocolDefinition.calibrationProfile.version),
            "calibration_validation_status": .string(protocolDefinition.calibrationProfile.validationStatus.rawValue),
            "result_units": .array(protocolDefinition.resultPayload.resultUnits.map { .string($0.rawValue) }),
            "validity_notice": .string(protocolDefinition.resultPayload.validityNotice)
        ]

        let stimulus: [String: JSONValue]
        if let stimulusDefinition = taskDefinition?.stimulus {
            stimulus = [
                "waveform": .string(stimulusDefinition.waveform),
                "frequency_hz": .number(stimulusDefinition.frequencyHz),
                "channel": .string(stimulusDefinition.channel)
            ]
        } else {
            stimulus = [
                "waveform": .string("sine"),
                "frequency_hz": .number(StudyNo1Configuration.toneFrequencyHz),
                "channel": .string("current output route")
            ]
        }

        let rawPayload: [String: JSONValue] = [
            "task_key": .string(input.scheduledTask.taskKey),
            "task_version": .number(Double(input.scheduledTask.taskVersion)),
            "stimulus": .object(stimulus),
            "matched_level": .number(matchedLevel),
            "matched_level_unit": .string(MeasurementUnit.normalizedAmplitude.rawValue),
            "loudness_trace": .array(loudnessTrace),
            "ambient_trace": .array(ambientTrace),
            "system_output_volume_trace": .array(systemOutputVolumeTrace),
            "gating": .object(gating),
            "device_info": .object(input.deviceInfo),
            "headphone_info": .object(input.outputDeviceInfo),
            "measurement_metadata": .object(measurementMetadata)
        ]

        return LoudnessMatchSubmission(
            startedAt: input.startedAt,
            completedAt: input.completedAt,
            matchedLevel: matchedLevel,
            gating: gating,
            rawPayload: rawPayload,
            deviceInfo: input.deviceInfo,
            headphoneInfo: input.outputDeviceInfo,
            appVersion: input.appVersion,
            calibrationVersion: protocolDefinition.calibrationProfile.identifier
        )
    }

    private static func clampedNormalizedLevel(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
