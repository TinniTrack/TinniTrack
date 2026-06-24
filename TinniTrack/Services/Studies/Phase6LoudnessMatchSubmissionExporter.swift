import Foundation

enum Phase6LoudnessMatchSubmissionExportError: Error, Equatable {
    case missingCompletedAt
    case unsupportedTopLevelPayload
}

struct Phase6LoudnessMatchSubmissionExporter {
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

    func makeSubmission(from payload: Phase6LoudnessMatchRunPayload) throws -> LoudnessMatchSubmission {
        try payload.validateCompletedStudyNo1()
        guard let completedAt = payload.lifecycle.completedAt else {
            throw Phase6LoudnessMatchSubmissionExportError.missingCompletedAt
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

    private func rawPayloadJSON(from payload: Phase6LoudnessMatchRunPayload) throws -> [String: JSONValue] {
        let data = try encoder.encode(payload)
        let jsonValue = try decoder.decode(JSONValue.self, from: data)
        guard case .object(let object) = jsonValue else {
            throw Phase6LoudnessMatchSubmissionExportError.unsupportedTopLevelPayload
        }
        return object
    }

    private func gatingJSON(from payload: Phase6LoudnessMatchRunPayload) -> [String: JSONValue] {
        [
            "environment": .object([
                "threshold_dba": .number(payload.environment.thresholdDBA),
                "required_contiguous_samples": .number(Double(payload.environment.requiredContiguousSamples)),
                "sampling_interval": .number(payload.environment.samplingInterval),
                "sensitivity_offset_db": payload.environment.sensitivityOffsetDB.map(JSONValue.number) ?? .null,
                "samples_dba": .array(payload.environment.samplesDBA.map(JSONValue.number)),
                "gate_result": .string(payload.environment.gateResult.rawValue)
            ]),
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

    private func deviceJSON(from payload: Phase6LoudnessMatchRunPayload) -> [String: JSONValue] {
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

    private func headphoneJSON(from payload: Phase6LoudnessMatchRunPayload) -> [String: JSONValue] {
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
