import Foundation

nonisolated enum StudyNo1PayloadValidationError: Error, Equatable {
    case missingRequiredFields([String])
    case incompleteStudyNo1(reason: String)
}

nonisolated enum StudyNo1GateResult: String, Codable, Equatable {
    case passed
    case failed
    case recordedOnly
}

nonisolated enum StudyNo1FitSealStatus: String, Codable, Equatable {
    case confirmedPassed
    case confirmedNotPassed
    case unavailable
}

nonisolated enum StudyNo1ThresholdSource: String, Codable, Equatable {
    case measured
    case manualScaffold
    case healthKitAudiogram
}

nonisolated struct StudyNo1IdentifierContext: Codable, Equatable {
    let participantId: String?
    let studySessionId: String?
    let enrollmentId: String?
    let scheduledTaskId: String?
}

nonisolated struct StudyNo1RunLifecycle: Codable, Equatable {
    let startedAt: Date
    let completedAt: Date?
    let submittedAt: Date?
    let abortedAt: Date?
    let interruptedAt: [Date]
}

nonisolated struct StudyNo1DeviceContext: Codable, Equatable {
    let deviceModel: String
    let systemName: String
    let systemVersion: String
}

nonisolated struct StudyNo1AirPodsContext: Codable, Equatable {
    let modelIdentifier: String?
    let firmwareVersion: String?
    let unavailableReason: String?
}

nonisolated struct StudyNo1ResearchKitCalibrationContext: Codable, Equatable {
    let sourceRepositoryURL: String
    let vendoredResearchKitCommit: String
    let designDocumentResearchKitCommit: String
    let assetSourceVersion: String
    let sourceFileNames: [String]
    let validationStatus: String
    let limitation: String
}

nonisolated struct StudyNo1RouteOutputContext: Codable, Equatable {
    let portType: String
    let portName: String
    let portUID: String?
    let channelNames: [String]
    let verifiedCalibratedHeadphoneIdentifier: String?
    let verificationSource: String?
}

nonisolated struct StudyNo1AudioRouteContext: Codable, Equatable {
    let outputs: [StudyNo1RouteOutputContext]
}

nonisolated struct StudyNo1AudioSessionContext: Codable, Equatable {
    let category: String
    let mode: String
    let options: [String]
    let sampleRate: Double
    let bufferSize: Double
}

nonisolated struct StudyNo1VolumeContext: Codable, Equatable {
    let outputVolume: Double
    let bucketedOutputVolume: Double?
    let volumeCurveOffsetDB: Double?
    let policy: String
}

/// A persistence-specific view of one accepted environment window.
///
/// The field names carry their units so future DSP changes cannot silently
/// reinterpret a stored value. This type deliberately does not store raw PCM or
/// accessory names/identifiers.
nonisolated struct StudyNo1EnvironmentSPLMeasurementContext: Codable, Equatable {
    let schemaVersion: Int
    let windowStartedAt: Date
    let windowEndedAt: Date
    let durationSeconds: TimeInterval
    let aWeightedDigitalLevelDBFS: Double?
    let provisionalEstimatedDBA: Double?
    let validity: String
    let failureReason: String?
    let sampleRateHz: Double
    let channelCount: Int
    let inputRoute: String
    let dataSourceOrientation: String?
    let inputGain: Double
    let isInputGainSettable: Bool
    let algorithmVersion: String
    let calibrationProfileIdentifier: String
    let calibrationStatus: String
    let calibrationEstimatedDBAOffset: Double?
    let calibrationReferenceSensitivityOffsetDB: Double?
    let calibrationProvenance: String
    let calibrationUncertaintyDB: Double?

    init(_ measurement: TinnitusEnvironmentSPLMeasurement) {
        schemaVersion = measurement.schemaVersion
        windowStartedAt = measurement.windowStartedAt
        windowEndedAt = measurement.windowEndedAt
        durationSeconds = measurement.duration
        aWeightedDigitalLevelDBFS = measurement.aWeightedDigitalLevelDBFS
        provisionalEstimatedDBA = measurement.provisionalEstimatedDBA

        switch measurement.validity {
        case .valid:
            validity = "valid"
            failureReason = nil
        case .invalid(let reason):
            validity = "invalid"
            failureReason = reason.rawValue
        }

        sampleRateHz = measurement.input.sampleRate
        channelCount = measurement.input.channelCount
        inputRoute = measurement.input.route.rawValue
        dataSourceOrientation = measurement.input.dataSourceOrientation?.rawValue
        inputGain = Double(measurement.input.inputGain)
        isInputGainSettable = measurement.input.isInputGainSettable
        algorithmVersion = measurement.algorithmVersion
        calibrationProfileIdentifier = measurement.calibration.identifier
        calibrationStatus = measurement.calibration.status.rawValue
        calibrationEstimatedDBAOffset = measurement.calibration.estimatedDBAOffset
        calibrationReferenceSensitivityOffsetDB = measurement.calibration.referenceSensitivityOffsetDB
        calibrationProvenance = measurement.calibration.provenance
        calibrationUncertaintyDB = measurement.calibration.uncertaintyDB
    }
}

nonisolated struct StudyNo1EnvironmentSPLContext: Codable, Equatable {
    static let currentLevelSemantics = "provisional_estimated_dba_screening"

    let thresholdDBA: Double
    let requiredContiguousSamples: Int
    let samplingInterval: TimeInterval
    let sensitivityOffsetDB: Double?
    /// Legacy screening estimates retained for payload compatibility. This field
    /// must never contain A-weighted digital dBFS values.
    let samplesDBA: [Double]
    let gateResult: StudyNo1GateResult
    let measurementSchemaVersion: Int?
    let levelSemantics: String?
    let measurements: [StudyNo1EnvironmentSPLMeasurementContext]?

    init(
        thresholdDBA: Double,
        requiredContiguousSamples: Int,
        samplingInterval: TimeInterval,
        sensitivityOffsetDB: Double?,
        samplesDBA: [Double],
        gateResult: StudyNo1GateResult,
        measurementSchemaVersion: Int? = nil,
        levelSemantics: String? = nil,
        measurements: [TinnitusEnvironmentSPLMeasurement]? = nil
    ) {
        let provisionalEstimates = measurements?.compactMap(\.screeningLevelDBA) ?? []

        self.thresholdDBA = thresholdDBA
        self.requiredContiguousSamples = requiredContiguousSamples
        self.samplingInterval = samplingInterval
        self.sensitivityOffsetDB = sensitivityOffsetDB
        self.samplesDBA = measurements == nil ? samplesDBA : provisionalEstimates
        self.gateResult = gateResult
        self.measurementSchemaVersion = measurementSchemaVersion
            ?? measurements?.map(\.schemaVersion).max()
        self.levelSemantics = levelSemantics
            ?? (measurements == nil ? nil : Self.currentLevelSemantics)
        self.measurements = measurements?.map(StudyNo1EnvironmentSPLMeasurementContext.init)
    }

    private enum CodingKeys: String, CodingKey {
        case thresholdDBA
        case requiredContiguousSamples
        case samplingInterval
        case sensitivityOffsetDB
        case samplesDBA
        case gateResult
        case measurementSchemaVersion
        case levelSemantics
        case measurements
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        thresholdDBA = try container.decode(Double.self, forKey: .thresholdDBA)
        requiredContiguousSamples = try container.decode(Int.self, forKey: .requiredContiguousSamples)
        samplingInterval = try container.decode(TimeInterval.self, forKey: .samplingInterval)
        sensitivityOffsetDB = try container.decodeIfPresent(Double.self, forKey: .sensitivityOffsetDB)
        samplesDBA = try container.decode([Double].self, forKey: .samplesDBA)
        gateResult = try container.decode(StudyNo1GateResult.self, forKey: .gateResult)
        measurementSchemaVersion = try container.decodeIfPresent(Int.self, forKey: .measurementSchemaVersion)
        levelSemantics = try container.decodeIfPresent(String.self, forKey: .levelSemantics)
        measurements = try container.decodeIfPresent(
            [StudyNo1EnvironmentSPLMeasurementContext].self,
            forKey: .measurements
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(thresholdDBA, forKey: .thresholdDBA)
        try container.encode(requiredContiguousSamples, forKey: .requiredContiguousSamples)
        try container.encode(samplingInterval, forKey: .samplingInterval)
        try container.encodeIfPresent(sensitivityOffsetDB, forKey: .sensitivityOffsetDB)
        try container.encode(samplesDBA, forKey: .samplesDBA)
        try container.encode(gateResult, forKey: .gateResult)
        try container.encodeIfPresent(measurementSchemaVersion, forKey: .measurementSchemaVersion)
        try container.encodeIfPresent(levelSemantics, forKey: .levelSemantics)
        try container.encodeIfPresent(measurements, forKey: .measurements)
    }
}

nonisolated struct StudyNo1FitSealContext: Codable, Equatable {
    let status: StudyNo1FitSealStatus
    let confirmedAt: Date?
    let limitations: String
}

nonisolated struct StudyNo1SafetyContext: Codable, Equatable {
    let acknowledgedAt: Date?
    let stopControlVisibleBeforePlayback: Bool
    let maximumLevelDBHL: Double
    let limitation: String
}

nonisolated struct StudyNo1StimulusContext: Codable, Equatable {
    let kind: String
    let frequencyHz: Double
    let channel: String
    let tinnitusLaterality: String
    let toneDuration: TimeInterval
    let rampDuration: TimeInterval
}

nonisolated struct StudyNo1ThresholdContext: Codable, Equatable {
    let frequencyHz: Double
    let levelDBHL: Double
    let source: StudyNo1ThresholdSource
    let recordedAt: Date?
    let limitation: String?
}

nonisolated struct StudyNo1LoudnessTrialContext: Codable, Equatable {
    let trialIndex: Int
    let acceptedLevelDBHL: Double
    let estimatedDBSPL: Double
    let dbSL: Double
    let confidence: String
    let acceptedAt: Date
}

nonisolated struct StudyNo1LoudnessSummaryContext: Codable, Equatable {
    let medianMatchedDBHL: Double
    let medianEstimatedDBSPL: Double
    let medianDBSL: Double
    let withinSessionSpreadDB: Double
    let qualityFlags: [String]
    let completedAt: Date
}

nonisolated struct StudyNo1ProtocolEventContext: Codable, Equatable {
    let timestamp: Date
    let kind: String
    let frequencyHz: Double?
    let presentedLevelDBHL: Double?
    let estimatedDBSPL: Double?
    let dbSL: Double?
    let channel: String?
    let laterality: String?
    let confidence: String?
    let response: String?
    let reason: String?
    let qualityFlags: [String]
    let guardrailState: String?
    let guardrailOutputVolume: Double?
    let guardrailRouteOutputs: [StudyNo1RouteOutputContext]
}

nonisolated struct StudyNo1PlaybackEventContext: Codable, Equatable {
    let timestamp: Date
    let frequencyHz: Double
    let channel: String
    let requestedDBHL: Double
    let targetDBSPL: Double
    let attenuationDB: Double
    let linearAmplitude: Double
    let duration: TimeInterval
    let rampDuration: TimeInterval
    let sampleRate: Double
    let bufferFrameCount: Int
    let startedAt: Date?
    let stoppedAt: Date?
}

nonisolated struct StudyNo1RefusalContext: Codable, Equatable {
    let timestamp: Date
    let reason: String
    let presentedLevelDBHL: Double?
    let guardrailState: String?
}

nonisolated struct StudyNo1LoudnessMatchRunPayload: Codable, Equatable {
    static let payloadVersion = "study-no-1-loudness-match-v3"
    static let legacyPayloadVersion = "study-no-1-loudness-match-v2"
    static let modelCalibratedOutputLimitation = "Estimated model-calibrated output from ResearchKit AirPods Pro 2 tables, route, and system output volume. This is not exact patient-specific in-ear SPL."

    let payloadVersion: String
    let protocolKind: String
    let identifiers: StudyNo1IdentifierContext
    let lifecycle: StudyNo1RunLifecycle
    let device: StudyNo1DeviceContext
    let airPods: StudyNo1AirPodsContext
    let calibration: StudyNo1ResearchKitCalibrationContext
    let audioRoute: StudyNo1AudioRouteContext
    let audioSession: StudyNo1AudioSessionContext
    let volume: StudyNo1VolumeContext
    let environment: StudyNo1EnvironmentSPLContext
    let fitSeal: StudyNo1FitSealContext
    let safety: StudyNo1SafetyContext
    let stimulus: StudyNo1StimulusContext
    let threshold: StudyNo1ThresholdContext
    let trials: [StudyNo1LoudnessTrialContext]
    let summary: StudyNo1LoudnessSummaryContext
    let protocolEvents: [StudyNo1ProtocolEventContext]
    let playbackEvents: [StudyNo1PlaybackEventContext]
    let refusals: [StudyNo1RefusalContext]
    let limitations: [String]

    func validateCompletedStudyNo1() throws {
        var missing: [String] = []

        if identifiers.enrollmentId?.isEmpty ?? true {
            missing.append("identifiers.enrollmentId")
        }
        if identifiers.scheduledTaskId?.isEmpty ?? true {
            missing.append("identifiers.scheduledTaskId")
        }
        if device.deviceModel.isEmpty {
            missing.append("device.deviceModel")
        }
        if device.systemVersion.isEmpty {
            missing.append("device.systemVersion")
        }
        if (airPods.modelIdentifier?.isEmpty ?? true) && (airPods.unavailableReason?.isEmpty ?? true) {
            missing.append("airPods.modelIdentifierOrUnavailableReason")
        }
        if audioRoute.outputs.isEmpty {
            missing.append("audioRoute.outputs")
        }
        if volume.outputVolume < 0.0 || volume.outputVolume > 1.0 {
            missing.append("volume.outputVolume")
        }
        if environment.samplesDBA.isEmpty {
            missing.append("environment.samplesDBA")
        }
        if payloadVersion == Self.payloadVersion {
            if environment.measurementSchemaVersion == nil {
                missing.append("environment.measurementSchemaVersion")
            }
            if environment.levelSemantics != StudyNo1EnvironmentSPLContext.currentLevelSemantics {
                missing.append("environment.levelSemantics")
            }
            if environment.measurements?.isEmpty != false {
                missing.append("environment.measurements")
            }
        }
        if safety.acknowledgedAt == nil {
            missing.append("safety.acknowledgedAt")
        }
        if !safety.stopControlVisibleBeforePlayback {
            missing.append("safety.stopControlVisibleBeforePlayback")
        }
        if fitSeal.status != .confirmedPassed {
            missing.append("fitSeal.status")
        }
        if lifecycle.completedAt == nil {
            missing.append("lifecycle.completedAt")
        }

        guard missing.isEmpty else {
            throw StudyNo1PayloadValidationError.missingRequiredFields(missing)
        }

        guard protocolKind == "studyNo1FixedOneKilohertz" else {
            throw StudyNo1PayloadValidationError.incompleteStudyNo1(reason: "Payload is not Study No. 1.")
        }
        guard stimulus.kind == "pureTone", stimulus.frequencyHz == 1_000 else {
            throw StudyNo1PayloadValidationError.incompleteStudyNo1(reason: "Study No. 1 must use a fixed 1000 Hz pure tone.")
        }
        guard threshold.source == .healthKitAudiogram else {
            throw StudyNo1PayloadValidationError.incompleteStudyNo1(reason: "Completed Study No. 1 requires a HealthKit audiogram 1000 Hz threshold source.")
        }
        guard threshold.frequencyHz == 1_000 else {
            throw StudyNo1PayloadValidationError.incompleteStudyNo1(reason: "Study No. 1 threshold must be recorded at 1000 Hz.")
        }
        guard trials.count == 3 else {
            throw StudyNo1PayloadValidationError.incompleteStudyNo1(reason: "Study No. 1 requires three loudness-match trials.")
        }
        guard trials.allSatisfy({ $0.estimatedDBSPL.isFinite && $0.dbSL.isFinite }) else {
            throw StudyNo1PayloadValidationError.incompleteStudyNo1(reason: "Study No. 1 requires estimated dB SPL and dB SL for each trial.")
        }
        guard environment.gateResult == .passed else {
            throw StudyNo1PayloadValidationError.incompleteStudyNo1(reason: "Completed Study No. 1 requires a passed environment SPL gate.")
        }
    }
}

nonisolated struct StudyNo1PreflightContext: Equatable {
    let identifiers: StudyNo1IdentifierContext
    let startedAt: Date
    let submittedAt: Date?
    let guardrailValidation: CalibratedAudioGuardrailValidation
    let device: StudyNo1DeviceContext
    let airPods: StudyNo1AirPodsContext
    let audioSession: StudyNo1AudioSessionContext
    let environment: StudyNo1EnvironmentSPLContext
    let fitSeal: StudyNo1FitSealContext
    let safety: StudyNo1SafetyContext
    let thresholdSource: StudyNo1ThresholdSource
}

nonisolated struct StudyNo1LoudnessMatchPayloadBuilder {
    private let calibrationMetadata: CalibratedAudioCalibrationMetadata

    init(calibrationMetadata: CalibratedAudioCalibrationMetadata = CalibratedHeadphoneProfile.airPodsPro2.metadata) {
        self.calibrationMetadata = calibrationMetadata
    }

    func buildStudyNo1Payload(
        summary: TinnitusLoudnessMatchSummary,
        events: [TinnitusProtocolEvent],
        preflight: StudyNo1PreflightContext
    ) throws -> StudyNo1LoudnessMatchRunPayload {
        guard summary.frequencyHz == 1_000 else {
            throw StudyNo1PayloadValidationError.incompleteStudyNo1(reason: "Study No. 1 summary must be fixed at 1000 Hz.")
        }
        guard case .measured(let thresholdDBHL) = summary.thresholdStatus else {
            throw StudyNo1PayloadValidationError.incompleteStudyNo1(reason: "Study No. 1 cannot complete without a recorded threshold.")
        }
        guard let medianEstimatedDBSPL = summary.medianEstimatedDBSPL,
              let medianDBSL = summary.medianDBSL
        else {
            throw StudyNo1PayloadValidationError.incompleteStudyNo1(reason: "Study No. 1 requires estimated dB SPL and dB SL medians.")
        }

        let guardrailMetadata = latestGuardrailMetadata(from: events) ?? preflight.guardrailValidation.metadata
        let route = StudyNo1AudioRouteContext(
            outputs: guardrailMetadata.routeDetails?.outputs.map(StudyNo1RouteOutputContext.init) ?? []
        )
        let thresholdRecordedAt = events.last { $0.kind == .thresholdRecorded }?.timestamp
        let threshold = StudyNo1ThresholdContext(
            frequencyHz: summary.frequencyHz,
            levelDBHL: thresholdDBHL,
            source: preflight.thresholdSource,
            recordedAt: thresholdRecordedAt,
            limitation: nil
        )
        let payload = StudyNo1LoudnessMatchRunPayload(
            payloadVersion: StudyNo1LoudnessMatchRunPayload.payloadVersion,
            protocolKind: "studyNo1FixedOneKilohertz",
            identifiers: preflight.identifiers,
            lifecycle: StudyNo1RunLifecycle(
                startedAt: preflight.startedAt,
                completedAt: summary.completedAt,
                submittedAt: preflight.submittedAt,
                abortedAt: nil,
                interruptedAt: events.compactMap { event in
                    event.kind == .guardrailChanged ? event.timestamp : nil
                }
            ),
            device: preflight.device,
            airPods: preflight.airPods,
            calibration: StudyNo1ResearchKitCalibrationContext(metadata: calibrationMetadata),
            audioRoute: route,
            audioSession: preflight.audioSession,
            volume: StudyNo1VolumeContext(metadata: guardrailMetadata),
            environment: preflight.environment,
            fitSeal: preflight.fitSeal,
            safety: preflight.safety,
            stimulus: StudyNo1StimulusContext(
                kind: "pureTone",
                frequencyHz: summary.frequencyHz,
                channel: summary.channel.rawValue,
                tinnitusLaterality: events.first { $0.kind == .lateralitySelected }?.laterality?.rawValue ?? "unknown",
                toneDuration: events.compactMap { $0.playbackMetadata?.duration }.first ?? 2.0,
                rampDuration: events.compactMap { $0.playbackMetadata?.rampDuration }.first ?? CalibratedTonePlaybackDefaults.rampDuration
            ),
            threshold: threshold,
            trials: summary.trials.map(StudyNo1LoudnessTrialContext.init),
            summary: StudyNo1LoudnessSummaryContext(
                medianMatchedDBHL: summary.medianMatchedDBHL,
                medianEstimatedDBSPL: medianEstimatedDBSPL,
                medianDBSL: medianDBSL,
                withinSessionSpreadDB: summary.withinSessionSpreadDB,
                qualityFlags: summary.qualityFlags.map(\.rawValue),
                completedAt: summary.completedAt
            ),
            protocolEvents: events.map(StudyNo1ProtocolEventContext.init),
            playbackEvents: events.compactMap(StudyNo1PlaybackEventContext.init),
            refusals: events.compactMap(StudyNo1RefusalContext.init),
            limitations: [
                StudyNo1LoudnessMatchRunPayload.modelCalibratedOutputLimitation,
                "Any headphone identifier and verification provenance in this payload come from guardrail metadata; public iOS APIs do not provide AirPods Pro 2 hardware attestation.",
                "No clinical or diagnostic claim is made by this payload."
            ]
        )

        try payload.validateCompletedStudyNo1()
        return payload
    }

    private func latestGuardrailMetadata(from events: [TinnitusProtocolEvent]) -> CalibratedAudioGuardrailMetadata? {
        events.compactMap(\.guardrailMetadata).last
    }
}

nonisolated private extension StudyNo1LoudnessTrialContext {
    init(_ trial: TinnitusLoudnessMatchTrial) {
        trialIndex = trial.trialIndex
        acceptedLevelDBHL = trial.acceptedLevelDBHL
        estimatedDBSPL = trial.estimatedDBSPL ?? .nan
        dbSL = trial.dbSL ?? .nan
        confidence = trial.confidence.rawValue
        acceptedAt = trial.acceptedAt
    }
}

nonisolated private extension StudyNo1ProtocolEventContext {
    init(_ event: TinnitusProtocolEvent) {
        timestamp = event.timestamp
        kind = event.kind.rawValue
        frequencyHz = event.frequencyHz
        presentedLevelDBHL = event.presentedLevelDBHL
        estimatedDBSPL = event.estimatedDBSPL
        dbSL = event.dbSL
        channel = event.channel?.rawValue
        laterality = event.laterality?.rawValue
        confidence = event.confidence?.rawValue
        response = event.response
        reason = event.reason
        qualityFlags = event.qualityFlags.map(\.rawValue)
        guardrailState = event.guardrailMetadata.map { "\($0.validationState)" }
        guardrailOutputVolume = event.guardrailMetadata?.rawOutputVolume
        guardrailRouteOutputs = event.guardrailMetadata?.routeDetails?.outputs.map(StudyNo1RouteOutputContext.init) ?? []
    }
}

nonisolated private extension StudyNo1PlaybackEventContext {
    init?(_ event: TinnitusProtocolEvent) {
        guard let metadata = event.playbackMetadata else {
            return nil
        }

        timestamp = event.timestamp
        frequencyHz = metadata.frequencyHz
        channel = metadata.channel.rawValue
        requestedDBHL = metadata.requestedDBHL
        targetDBSPL = metadata.targetDBSPL
        attenuationDB = metadata.attenuationDB
        linearAmplitude = metadata.linearAmplitude
        duration = metadata.duration
        rampDuration = metadata.rampDuration
        sampleRate = metadata.sampleRate
        bufferFrameCount = metadata.bufferFrameCount
        startedAt = metadata.startedAt
        stoppedAt = metadata.stoppedAt
    }
}

nonisolated private extension StudyNo1RefusalContext {
    init?(_ event: TinnitusProtocolEvent) {
        guard event.kind == .playbackRefused || event.kind == .stopRequested || event.kind == .abortRecorded else {
            return nil
        }

        timestamp = event.timestamp
        reason = event.reason ?? event.kind.rawValue
        presentedLevelDBHL = event.presentedLevelDBHL
        guardrailState = event.guardrailMetadata.map { "\($0.validationState)" }
    }
}
