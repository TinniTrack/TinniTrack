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
    let audiogramThreshold: AudiogramThresholdAtFrequency?
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
        let taskDefinition = protocolDefinition.tasks.first { task in
            task.key == input.scheduledTask.taskKey && task.version == input.scheduledTask.taskVersion
        }
        let calibrationProfile = CalibrationProfileCatalog.profile(for: input.currentRoute)
        let calibrationResult = LoudnessCalibrationCalculator.calibrate(
            LoudnessCalibrationInput(
                normalizedAmplitude: input.matchedLevel,
                systemOutputVolume: input.systemOutputVolumeAtSubmit,
                didSystemOutputVolumeChange: input.didSystemOutputVolumeChange,
                isSupportedRoute: input.isSupportedRoute,
                isAmbientQuiet: input.isAmbientQuiet,
                calibrationProfile: calibrationProfile,
                audiogramThreshold: input.audiogramThreshold
            )
        )
        let matchedLevel = calibrationResult.clampedNormalizedAmplitude

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
            ]),
            "calibration": .object([
                "profile_id": calibrationProfile.map { .string($0.identifier) } ?? .null,
                "profile_version": calibrationProfile.map { .string($0.version) } ?? .null,
                "support_status": calibrationProfile.map { .string($0.supportStatus.rawValue) } ?? .null,
                "is_available": .bool(calibrationProfile?.supportStatus == .supported)
            ]),
            "audiogram_threshold": .object([
                "frequency_hz": .number(StudyNo1Configuration.toneFrequencyHz),
                "has_exact_threshold": .bool(input.audiogramThreshold?.hasAnyThreshold == true),
                "derivation": input.audiogramThreshold.map { .string($0.derivation) } ?? .null
            ])
        ]

        let measurementMetadata: [String: JSONValue] = [
            "schema_version": .string(protocolDefinition.resultPayload.schemaVersion),
            "protocol_version": .string(protocolDefinition.resultPayload.protocolVersion),
            "calibration_profile_id": .string(protocolDefinition.calibrationProfile.identifier),
            "calibration_profile_version": .string(protocolDefinition.calibrationProfile.version),
            "calibration_validation_status": .string(protocolDefinition.calibrationProfile.validationStatus.rawValue),
            "active_headphone_calibration_profile": .object(Self.calibrationProfilePayload(calibrationProfile)),
            "dbfs_convention": .string(LoudnessCalibrationCalculator.dBFSConvention),
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

        let quality: [String: JSONValue] = [
            "validation_status": .string(calibrationResult.validationStatus.rawValue),
            "quality_flags": .array(calibrationResult.qualityFlags.map { .string($0.rawValue) }),
            "invalidation_reasons": .array(calibrationResult.invalidationReasons.map { .string($0) })
        ]

        let rawInputs: [String: JSONValue] = [
            "matched_level": .number(matchedLevel),
            "matched_level_raw": .number(input.matchedLevel),
            "matched_level_unit": .string(MeasurementUnit.normalizedAmplitude.rawValue),
            "safe_bounds": .object([
                "minimum_normalized_amplitude": .number(StudyNo1Configuration.minimumMatchedNormalizedAmplitude),
                "maximum_safe_normalized_amplitude": .number(StudyNo1Configuration.maximumSafeNormalizedAmplitude)
            ]),
            "system_output_volume_at_submit": input.systemOutputVolumeAtSubmit.map(JSONValue.number) ?? .null,
            "system_output_volume_at_start": input.systemOutputVolumeAtStart.map(JSONValue.number) ?? .null,
            "ambient_db_at_submit": input.ambientDB.map(JSONValue.number) ?? .null,
            "audiogram_threshold": .object(Self.audiogramThresholdPayload(input.audiogramThreshold))
        ]

        let derivedOutputs: [String: JSONValue] = [
            "peak_dbfs": Self.optionalNumber(calibrationResult.peakDBFS),
            "rms_dbfs": Self.optionalNumber(calibrationResult.rmsDBFS),
            "estimated_db_spl": Self.optionalNumber(calibrationResult.estimatedDBSPL),
            "estimated_db_hl": Self.optionalNumber(calibrationResult.estimatedDBHL),
            "estimated_db_sl_left": Self.optionalNumber(calibrationResult.estimatedDBSLLeft),
            "estimated_db_sl_right": Self.optionalNumber(calibrationResult.estimatedDBSLRight),
            "estimated_db_sl_bilateral_mean": Self.optionalNumber(calibrationResult.estimatedDBSLBilateralMean),
            "units": .object([
                "peak_dbfs": .string(MeasurementUnit.dBFS.rawValue),
                "rms_dbfs": .string(MeasurementUnit.dBFS.rawValue),
                "estimated_db_spl": .string(MeasurementUnit.dBSPL.rawValue),
                "estimated_db_hl": .string(MeasurementUnit.dBHL.rawValue),
                "estimated_db_sl_left": .string(MeasurementUnit.dBSL.rawValue),
                "estimated_db_sl_right": .string(MeasurementUnit.dBSL.rawValue),
                "estimated_db_sl_bilateral_mean": .string(MeasurementUnit.dBSL.rawValue)
            ]),
            "volume_curve_lookup": .object(Self.volumeCurvePayload(calibrationResult.volumeCurveLookup))
        ]

        let trialEvents = input.loudnessEvents.isEmpty
            ? [MeasurementTraceEvent(timestamp: input.completedAt, value: matchedLevel)]
            : input.loudnessEvents
        let trials = trialEvents.enumerated().map { index, event in
            JSONValue.object([
                "trial_index": .number(Double(index)),
                "offset_seconds": .number(event.timestamp.timeIntervalSince(baseTime)),
                "normalized_amplitude": .number(Self.clampedNormalizedLevel(event.value)),
                "unit": .string(MeasurementUnit.normalizedAmplitude.rawValue)
            ])
        }
        let trialSummary = Self.trialSummaryPayload(events: trialEvents, finalLevel: matchedLevel)

        let rawPayload: [String: JSONValue] = [
            "task_key": .string(input.scheduledTask.taskKey),
            "task_version": .number(Double(input.scheduledTask.taskVersion)),
            "stimulus": .object(stimulus),
            "raw_inputs": .object(rawInputs),
            "derived_outputs": .object(derivedOutputs),
            "trial_summary": .object(trialSummary),
            "trials": .array(trials),
            "matched_level": .number(matchedLevel),
            "matched_level_unit": .string(MeasurementUnit.normalizedAmplitude.rawValue),
            "loudness_trace": .array(loudnessTrace),
            "ambient_trace": .array(ambientTrace),
            "system_output_volume_trace": .array(systemOutputVolumeTrace),
            "gating": .object(gating),
            "quality": .object(quality),
            "device_info": .object(input.deviceInfo),
            "headphone_info": .object(input.outputDeviceInfo),
            "measurement_metadata": .object(measurementMetadata)
        ]

        return LoudnessMatchSubmission(
            startedAt: input.startedAt,
            completedAt: input.completedAt,
            matchedLevel: matchedLevel,
            validationStatus: calibrationResult.validationStatus,
            qualityFlags: calibrationResult.qualityFlags,
            gating: gating,
            rawPayload: rawPayload,
            deviceInfo: input.deviceInfo,
            headphoneInfo: input.outputDeviceInfo,
            appVersion: input.appVersion,
            calibrationVersion: calibrationProfile?.identifier ?? protocolDefinition.calibrationProfile.identifier
        )
    }

    private static func clampedNormalizedLevel(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private static func optionalNumber(_ value: Double?) -> JSONValue {
        value.map(JSONValue.number) ?? .null
    }

    private static func calibrationProfilePayload(_ profile: HeadphoneCalibrationProfile?) -> [String: JSONValue] {
        guard let profile else {
            return [
                "profile_id": .null,
                "profile_version": .null,
                "display_name": .null,
                "support_status": .null,
                "source_table_version": .null,
                "source_provenance": .null
            ]
        }
        let retsplDBFS = profile.frequencyCalibration?.retsplDBFS

        return [
            "profile_id": .string(profile.identifier),
            "profile_version": .string(profile.version),
            "display_name": .string(profile.displayName),
            "support_status": .string(profile.supportStatus.rawValue),
            "validation_status": .string(profile.validationStatus.rawValue),
            "researchkit_headphone_type_identifier": profile.outputDevice.researchKitHeadphoneTypeIdentifier.map(JSONValue.string) ?? .null,
            "source_table_version": .string(profile.sourceTableVersion),
            "source_provenance": .string(profile.sourceProvenance),
            "frequency_hz": profile.frequencyCalibration.map { .number($0.frequencyHz) } ?? .null,
            "frequency_db_spl": profile.frequencyCalibration.map { .number($0.frequencyDBSPL) } ?? .null,
            "retspl_db_spl": profile.frequencyCalibration.map { .number($0.retsplDBSPL) } ?? .null,
            "retspl_dbfs": retsplDBFS.map(JSONValue.number) ?? .null
        ]
    }

    private static func audiogramThresholdPayload(_ threshold: AudiogramThresholdAtFrequency?) -> [String: JSONValue] {
        guard let threshold else {
            return [
                "frequency_hz": .number(StudyNo1Configuration.toneFrequencyHz),
                "left_db_hl": .null,
                "right_db_hl": .null,
                "bilateral_mean_db_hl": .null,
                "source_audiogram_id": .null,
                "measured_at": .null,
                "derivation": .null
            ]
        }

        return [
            "frequency_hz": .number(threshold.frequencyHz),
            "left_db_hl": optionalNumber(threshold.leftDBHL),
            "right_db_hl": optionalNumber(threshold.rightDBHL),
            "bilateral_mean_db_hl": optionalNumber(threshold.bilateralMeanDBHL),
            "source_audiogram_id": threshold.sourceAudiogramID.map { .string($0.uuidString) } ?? .null,
            "measured_at": threshold.measuredAt.map { .string(Self.iso8601Formatter.string(from: $0)) } ?? .null,
            "derivation": .string(threshold.derivation)
        ]
    }

    private static func volumeCurvePayload(_ lookup: VolumeCurveLookup?) -> [String: JSONValue] {
        guard let lookup else {
            return [
                "raw_system_output_volume": .null,
                "quantized_system_output_volume": .null,
                "offset_db": .null
            ]
        }

        return [
            "raw_system_output_volume": .number(lookup.rawSystemOutputVolume),
            "quantized_system_output_volume": .number(lookup.quantizedSystemOutputVolume),
            "offset_db": .number(lookup.offsetDB)
        ]
    }

    private static func trialSummaryPayload(events: [MeasurementTraceEvent], finalLevel: Double) -> [String: JSONValue] {
        let values = events.map { clampedNormalizedLevel($0.value) }
        guard !values.isEmpty else {
            return [
                "count": .number(0),
                "final_normalized_amplitude": .number(finalLevel),
                "mean_normalized_amplitude": .null,
                "standard_deviation_normalized_amplitude": .null,
                "minimum_normalized_amplitude": .null,
                "maximum_normalized_amplitude": .null
            ]
        }

        let count = Double(values.count)
        let mean = values.reduce(0, +) / count
        let variance = values.reduce(0) { partial, value in
            partial + pow(value - mean, 2)
        } / count

        return [
            "count": .number(count),
            "final_normalized_amplitude": .number(finalLevel),
            "mean_normalized_amplitude": .number(mean),
            "standard_deviation_normalized_amplitude": .number(sqrt(variance)),
            "minimum_normalized_amplitude": .number(values.min() ?? finalLevel),
            "maximum_normalized_amplitude": .number(values.max() ?? finalLevel)
        ]
    }

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
