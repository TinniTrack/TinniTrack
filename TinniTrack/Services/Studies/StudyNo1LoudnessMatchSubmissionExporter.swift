import Foundation

enum StudyNo1LoudnessMatchSubmissionExportError: Error, Equatable {
    case missingCompletedAt
    case unsupportedTopLevelPayload
}

struct StudyNo1LoudnessMatchSubmissionExporter {
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let appVersion: String?

    init(
        appVersion: String? = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
        encoder: JSONEncoder? = nil,
        decoder: JSONDecoder? = nil
    ) {
        self.appVersion = appVersion
        self.encoder = encoder ?? Self.makeEncoder()
        self.decoder = decoder ?? JSONDecoder()
    }

    func makeSubmission(from payload: StudyNo1LoudnessMatchRunPayload) throws -> LoudnessMatchSubmission {
        try payload.validateCompletedStudyNo1()
        guard let completedAt = payload.lifecycle.completedAt else {
            throw StudyNo1LoudnessMatchSubmissionExportError.missingCompletedAt
        }

        return LoudnessMatchSubmission(
            startedAt: payload.lifecycle.startedAt,
            completedAt: completedAt,
            matchedLevel: payload.summary.medianMatchedDBHL,
            gating: gatingJSON(from: payload),
            rawPayload: try rawPayloadJSON(from: payload),
            deviceInfo: deviceJSON(from: payload),
            headphoneInfo: headphoneJSON(from: payload),
            appVersion: appVersion,
            calibrationVersion: payload.calibration.assetSourceVersion
        )
    }

    private func rawPayloadJSON(from payload: StudyNo1LoudnessMatchRunPayload) throws -> [String: JSONValue] {
        let data = try encoder.encode(payload)
        let jsonValue = try decoder.decode(JSONValue.self, from: data)
        guard case .object(let object) = jsonValue else {
            throw StudyNo1LoudnessMatchSubmissionExportError.unsupportedTopLevelPayload
        }
        return object
    }

    private func gatingJSON(from payload: StudyNo1LoudnessMatchRunPayload) -> [String: JSONValue] {
        [
            "environment": StudyNo1EnvironmentSubmissionEncoding.json(payload.environment),
            "fit_seal": .object([
                "status": .string(payload.fitSeal.status.rawValue),
                "limitations": .string(payload.fitSeal.limitations)
            ]),
            "safety": .object([
                "acknowledged": .bool(payload.safety.acknowledgedAt != nil),
                "stop_control_visible_before_playback": .bool(payload.safety.stopControlVisibleBeforePlayback),
                "maximum_level_dbhl": .number(payload.safety.maximumLevelDBHL),
                "limitation": .string(payload.safety.limitation)
            ]),
            "volume": .object([
                "output_volume": .number(payload.volume.outputVolume),
                "bucketed_output_volume": payload.volume.bucketedOutputVolume.map(JSONValue.number) ?? .null,
                "volume_curve_offset_db": payload.volume.volumeCurveOffsetDB.map(JSONValue.number) ?? .null,
                "policy": .string(payload.volume.policy)
            ])
        ]
    }

    private func deviceJSON(from payload: StudyNo1LoudnessMatchRunPayload) -> [String: JSONValue] {
        [
            "model": .string(payload.device.deviceModel),
            "system_name": .string(payload.device.systemName),
            "system_version": .string(payload.device.systemVersion),
            "audio_session": .object([
                "category": .string(payload.audioSession.category),
                "mode": .string(payload.audioSession.mode),
                "options": .array(payload.audioSession.options.map(JSONValue.string)),
                "sample_rate": .number(payload.audioSession.sampleRate),
                "buffer_size": .number(payload.audioSession.bufferSize)
            ])
        ]
    }

    private func headphoneJSON(from payload: StudyNo1LoudnessMatchRunPayload) -> [String: JSONValue] {
        [
            "model_identifier": payload.airPods.modelIdentifier.map(JSONValue.string) ?? .null,
            "firmware_version": payload.airPods.firmwareVersion.map(JSONValue.string) ?? .null,
            "unavailable_reason": payload.airPods.unavailableReason.map(JSONValue.string) ?? .null,
            "route": .object([
                "outputs": .array(payload.audioRoute.outputs.map { output in
                    .object([
                        "port_type": .string(output.portType),
                        "port_name": .string(output.portName),
                        "port_uid": output.portUID.map(JSONValue.string) ?? .null,
                        "channel_names": .array(output.channelNames.map(JSONValue.string)),
                        "verified_calibrated_headphone_identifier": output.verifiedCalibratedHeadphoneIdentifier.map(JSONValue.string) ?? .null,
                        "verification_source": output.verificationSource.map(JSONValue.string) ?? .null
                    ])
                })
            ]),
            "calibration": .object([
                "source_repository_url": .string(payload.calibration.sourceRepositoryURL),
                "vendored_researchkit_commit": .string(payload.calibration.vendoredResearchKitCommit),
                "design_document_researchkit_commit": .string(payload.calibration.designDocumentResearchKitCommit),
                "asset_source_version": .string(payload.calibration.assetSourceVersion),
                "validation_status": .string(payload.calibration.validationStatus),
                "limitation": .string(payload.calibration.limitation)
            ])
        ]
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

/// Shared JSONB representation used by both Study No. 1 submission paths.
/// Legacy keys remain available for existing queries, while new window records
/// carry explicit units and their own schema version.
nonisolated enum StudyNo1EnvironmentSubmissionEncoding {
    static func json(_ environment: StudyNo1EnvironmentSPLContext) -> JSONValue {
        .object([
            // Legacy compatibility fields. `samples_dba` contains provisional
            // screening estimates only, never digital dBFS values.
            "threshold_dba": .number(environment.thresholdDBA),
            "required_contiguous_samples": .number(Double(environment.requiredContiguousSamples)),
            "sampling_interval": .number(environment.samplingInterval),
            "sensitivity_offset_db": environment.sensitivityOffsetDB.map(JSONValue.number) ?? .null,
            "samples_dba": .array(environment.samplesDBA.map(JSONValue.number)),
            "gate_result": .string(environment.gateResult.rawValue),

            // Unit-explicit current policy and measurement fields.
            "screening_threshold_estimated_dba": .number(environment.thresholdDBA),
            "window_duration_seconds": .number(environment.samplingInterval),
            "legacy_samples_dba_semantics": environment.levelSemantics.map(JSONValue.string) ?? .null,
            "measurement_schema_version": environment.measurementSchemaVersion
                .map { .number(Double($0)) } ?? .null,
            "level_semantics": environment.levelSemantics.map(JSONValue.string) ?? .null,
            "measurements": .array((environment.measurements ?? []).map(measurementJSON))
        ])
    }

    private static func measurementJSON(
        _ measurement: StudyNo1EnvironmentSPLMeasurementContext
    ) -> JSONValue {
        .object([
            "schema_version": .number(Double(measurement.schemaVersion)),
            "window_started_at": .string(iso8601String(measurement.windowStartedAt)),
            "window_ended_at": .string(iso8601String(measurement.windowEndedAt)),
            "duration_seconds": .number(measurement.durationSeconds),
            "a_weighted_digital_level_dbfs": measurement.aWeightedDigitalLevelDBFS
                .map(JSONValue.number) ?? .null,
            "provisional_estimated_dba": measurement.provisionalEstimatedDBA
                .map(JSONValue.number) ?? .null,
            "validity": .string(measurement.validity),
            "failure_reason": measurement.failureReason.map(JSONValue.string) ?? .null,
            "input": .object([
                "route": .string(measurement.inputRoute),
                "data_source_orientation": measurement.dataSourceOrientation
                    .map(JSONValue.string) ?? .null,
                "sample_rate_hz": .number(measurement.sampleRateHz),
                "channel_count": .number(Double(measurement.channelCount)),
                "input_gain": .number(measurement.inputGain),
                "is_input_gain_settable": .bool(measurement.isInputGainSettable)
            ]),
            "algorithm_version": .string(measurement.algorithmVersion),
            "calibration": .object([
                "profile_identifier": .string(measurement.calibrationProfileIdentifier),
                "status": .string(measurement.calibrationStatus),
                "estimated_dba_offset": measurement.calibrationEstimatedDBAOffset
                    .map(JSONValue.number) ?? .null,
                "reference_sensitivity_offset_db": measurement.calibrationReferenceSensitivityOffsetDB
                    .map(JSONValue.number) ?? .null,
                "provenance": .string(measurement.calibrationProvenance),
                "uncertainty_db": measurement.calibrationUncertaintyDB
                    .map(JSONValue.number) ?? .null
            ])
        ])
    }

    private static func iso8601String(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
