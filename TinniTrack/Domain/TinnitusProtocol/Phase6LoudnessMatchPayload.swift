import Foundation

enum Phase6PayloadValidationError: Error, Equatable {
    case missingRequiredFields([String])
    case incompleteStudyA(reason: String)
}

enum Phase6GateResult: String, Codable, Equatable {
    case passed
    case failed
    case recordedOnly
}

enum Phase6FitSealStatus: String, Codable, Equatable {
    case confirmedPassed
    case confirmedNotPassed
    case unavailable
}

enum Phase6ThresholdSource: String, Codable, Equatable {
    case measured
    case manualScaffold
}

struct Phase6IdentifierContext: Codable, Equatable {
    let participantId: String?
    let studySessionId: String?
    let enrollmentId: String?
    let scheduledTaskId: String?
}

struct Phase6RunLifecycle: Codable, Equatable {
    let startedAt: Date
    let completedAt: Date?
    let submittedAt: Date?
    let abortedAt: Date?
    let interruptedAt: [Date]
}

struct Phase6DeviceContext: Codable, Equatable {
    let deviceModel: String
    let systemName: String
    let systemVersion: String
}

struct Phase6AirPodsContext: Codable, Equatable {
    let modelIdentifier: String?
    let firmwareVersion: String?
    let unavailableReason: String?
}

struct Phase6ResearchKitCalibrationContext: Codable, Equatable {
    let sourceRepositoryURL: String
    let vendoredResearchKitCommit: String
    let designDocumentResearchKitCommit: String
    let assetSourceVersion: String
    let sourceFileNames: [String]
    let validationStatus: String
    let limitation: String
}

struct Phase6RouteOutputContext: Codable, Equatable {
    let portType: String
    let portName: String
    let portUID: String?
    let channelNames: [String]
    let verifiedCalibratedHeadphoneIdentifier: String?
    let verificationSource: String?
}

struct Phase6AudioRouteContext: Codable, Equatable {
    let outputs: [Phase6RouteOutputContext]
}

struct Phase6AudioSessionContext: Codable, Equatable {
    let category: String
    let mode: String
    let options: [String]
    let sampleRate: Double
    let bufferSize: Double
}

struct Phase6VolumeContext: Codable, Equatable {
    let outputVolume: Double
    let bucketedOutputVolume: Double?
    let volumeCurveOffsetDB: Double?
    let policy: String
}

struct Phase6EnvironmentSPLContext: Codable, Equatable {
    let thresholdDBA: Double
    let requiredContiguousSamples: Int
    let samplingInterval: TimeInterval
    let sensitivityOffsetDB: Double?
    let samplesDBA: [Double]
    let gateResult: Phase6GateResult
}

struct Phase6FitSealContext: Codable, Equatable {
    let status: Phase6FitSealStatus
    let confirmedAt: Date?
    let limitations: String
}

struct Phase6SafetyContext: Codable, Equatable {
    let acknowledgedAt: Date?
    let stopControlVisibleBeforePlayback: Bool
    let maximumLevelDBHL: Double
    let limitation: String
}

struct Phase6StimulusContext: Codable, Equatable {
    let kind: String
    let frequencyHz: Double
    let channel: String
    let tinnitusLaterality: String
    let toneDuration: TimeInterval
    let rampDuration: TimeInterval
}

struct Phase6ThresholdContext: Codable, Equatable {
    let frequencyHz: Double
    let levelDBHL: Double
    let source: Phase6ThresholdSource
    let recordedAt: Date?
    let limitation: String?
}

struct Phase6LoudnessTrialContext: Codable, Equatable {
    let trialIndex: Int
    let acceptedLevelDBHL: Double
    let estimatedDBSPL: Double
    let dbSL: Double
    let confidence: String
    let acceptedAt: Date
}

struct Phase6LoudnessSummaryContext: Codable, Equatable {
    let medianMatchedDBHL: Double
    let medianEstimatedDBSPL: Double
    let medianDBSL: Double
    let withinSessionSpreadDB: Double
    let qualityFlags: [String]
    let completedAt: Date
}

struct Phase6ProtocolEventContext: Codable, Equatable {
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
    let guardrailRouteOutputs: [Phase6RouteOutputContext]
}

struct Phase6PlaybackEventContext: Codable, Equatable {
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

struct Phase6RefusalContext: Codable, Equatable {
    let timestamp: Date
    let reason: String
    let presentedLevelDBHL: Double?
    let guardrailState: String?
}

struct Phase6LoudnessMatchRunPayload: Codable, Equatable {
    static let payloadVersion = "phase-6-study-a-v1"
    static let modelCalibratedOutputLimitation = "Estimated model-calibrated output from ResearchKit AirPods Pro 2 tables, route, and system output volume. This is not exact patient-specific in-ear SPL."

    let payloadVersion: String
    let protocolKind: String
    let identifiers: Phase6IdentifierContext
    let lifecycle: Phase6RunLifecycle
    let device: Phase6DeviceContext
    let airPods: Phase6AirPodsContext
    let calibration: Phase6ResearchKitCalibrationContext
    let audioRoute: Phase6AudioRouteContext
    let audioSession: Phase6AudioSessionContext
    let volume: Phase6VolumeContext
    let environment: Phase6EnvironmentSPLContext
    let fitSeal: Phase6FitSealContext
    let safety: Phase6SafetyContext
    let stimulus: Phase6StimulusContext
    let threshold: Phase6ThresholdContext
    let trials: [Phase6LoudnessTrialContext]
    let summary: Phase6LoudnessSummaryContext
    let protocolEvents: [Phase6ProtocolEventContext]
    let playbackEvents: [Phase6PlaybackEventContext]
    let refusals: [Phase6RefusalContext]
    let limitations: [String]

    func validateCompletedStudyA() throws {
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
            throw Phase6PayloadValidationError.missingRequiredFields(missing)
        }

        guard protocolKind == "studyAFixedOneKilohertz" else {
            throw Phase6PayloadValidationError.incompleteStudyA(reason: "Payload is not Study A.")
        }
        guard stimulus.kind == "pureTone", stimulus.frequencyHz == 1_000 else {
            throw Phase6PayloadValidationError.incompleteStudyA(reason: "Study A must use a fixed 1000 Hz pure tone.")
        }
        guard threshold.source == .measured else {
            throw Phase6PayloadValidationError.incompleteStudyA(reason: "Completed Study A requires a measured 1000 Hz threshold source.")
        }
        guard threshold.frequencyHz == 1_000 else {
            throw Phase6PayloadValidationError.incompleteStudyA(reason: "Study A threshold must be recorded at 1000 Hz.")
        }
        guard trials.count == 3 else {
            throw Phase6PayloadValidationError.incompleteStudyA(reason: "Study A requires three loudness-match trials.")
        }
        guard trials.allSatisfy({ $0.estimatedDBSPL.isFinite && $0.dbSL.isFinite }) else {
            throw Phase6PayloadValidationError.incompleteStudyA(reason: "Study A requires estimated dB SPL and dB SL for each trial.")
        }
        guard environment.gateResult == .passed else {
            throw Phase6PayloadValidationError.incompleteStudyA(reason: "Completed Study A requires a passed environment SPL gate.")
        }
    }
}

struct Phase6PreflightContext: Equatable {
    let identifiers: Phase6IdentifierContext
    let startedAt: Date
    let submittedAt: Date?
    let guardrailValidation: CalibratedAudioGuardrailValidation
    let device: Phase6DeviceContext
    let airPods: Phase6AirPodsContext
    let audioSession: Phase6AudioSessionContext
    let environment: Phase6EnvironmentSPLContext
    let fitSeal: Phase6FitSealContext
    let safety: Phase6SafetyContext
    let thresholdSource: Phase6ThresholdSource
}

struct Phase6LoudnessMatchPayloadBuilder {
    private let calibrationMetadata: CalibratedAudioCalibrationMetadata

    init(calibrationMetadata: CalibratedAudioCalibrationMetadata = CalibratedHeadphoneProfile.airPodsPro2.metadata) {
        self.calibrationMetadata = calibrationMetadata
    }

    func buildStudyAPayload(
        summary: TinnitusLoudnessMatchSummary,
        events: [TinnitusProtocolEvent],
        preflight: Phase6PreflightContext
    ) throws -> Phase6LoudnessMatchRunPayload {
        guard summary.frequencyHz == 1_000 else {
            throw Phase6PayloadValidationError.incompleteStudyA(reason: "Study A summary must be fixed at 1000 Hz.")
        }
        guard case .measured(let thresholdDBHL) = summary.thresholdStatus else {
            throw Phase6PayloadValidationError.incompleteStudyA(reason: "Study A cannot complete Phase 6 without a recorded threshold.")
        }
        guard let medianEstimatedDBSPL = summary.medianEstimatedDBSPL,
              let medianDBSL = summary.medianDBSL
        else {
            throw Phase6PayloadValidationError.incompleteStudyA(reason: "Study A requires estimated dB SPL and dB SL medians.")
        }

        let guardrailMetadata = latestGuardrailMetadata(from: events) ?? preflight.guardrailValidation.metadata
        let route = Phase6AudioRouteContext(
            outputs: guardrailMetadata.routeDetails?.outputs.map(Phase6RouteOutputContext.init) ?? []
        )
        let thresholdRecordedAt = events.last { $0.kind == .thresholdRecorded }?.timestamp
        let threshold = Phase6ThresholdContext(
            frequencyHz: summary.frequencyHz,
            levelDBHL: thresholdDBHL,
            source: preflight.thresholdSource,
            recordedAt: thresholdRecordedAt,
            limitation: nil
        )
        let payload = Phase6LoudnessMatchRunPayload(
            payloadVersion: Phase6LoudnessMatchRunPayload.payloadVersion,
            protocolKind: "studyAFixedOneKilohertz",
            identifiers: preflight.identifiers,
            lifecycle: Phase6RunLifecycle(
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
            calibration: Phase6ResearchKitCalibrationContext(metadata: calibrationMetadata),
            audioRoute: route,
            audioSession: preflight.audioSession,
            volume: Phase6VolumeContext(metadata: guardrailMetadata),
            environment: preflight.environment,
            fitSeal: preflight.fitSeal,
            safety: preflight.safety,
            stimulus: Phase6StimulusContext(
                kind: "pureTone",
                frequencyHz: summary.frequencyHz,
                channel: summary.channel.rawValue,
                tinnitusLaterality: events.first { $0.kind == .lateralitySelected }?.laterality?.rawValue ?? "unknown",
                toneDuration: events.compactMap { $0.playbackMetadata?.duration }.first ?? 1.0,
                rampDuration: events.compactMap { $0.playbackMetadata?.rampDuration }.first ?? CalibratedTonePlaybackDefaults.rampDuration
            ),
            threshold: threshold,
            trials: summary.trials.map(Phase6LoudnessTrialContext.init),
            summary: Phase6LoudnessSummaryContext(
                medianMatchedDBHL: summary.medianMatchedDBHL,
                medianEstimatedDBSPL: medianEstimatedDBSPL,
                medianDBSL: medianDBSL,
                withinSessionSpreadDB: summary.withinSessionSpreadDB,
                qualityFlags: summary.qualityFlags.map(\.rawValue),
                completedAt: summary.completedAt
            ),
            protocolEvents: events.map(Phase6ProtocolEventContext.init),
            playbackEvents: events.compactMap(Phase6PlaybackEventContext.init),
            refusals: events.compactMap(Phase6RefusalContext.init),
            limitations: [
                Phase6LoudnessMatchRunPayload.modelCalibratedOutputLimitation,
                "AirPods Pro 2 verification uses the recorded research-protocol route confirmation when public iOS APIs cannot expose Apple's private AirPods hearing-test verification.",
                "No clinical or diagnostic claim is made by this payload."
            ]
        )

        try payload.validateCompletedStudyA()
        return payload
    }

    private func latestGuardrailMetadata(from events: [TinnitusProtocolEvent]) -> CalibratedAudioGuardrailMetadata? {
        events.compactMap(\.guardrailMetadata).last
    }
}

private extension Phase6RouteOutputContext {
    init(_ output: CalibratedAudioRouteOutput) {
        portType = output.portType.description
        portName = output.portName
        portUID = output.portUID
        channelNames = output.channelNames
        verifiedCalibratedHeadphoneIdentifier = output.verifiedCalibratedHeadphoneIdentifier
        verificationSource = output.verificationSource?.rawValue
    }
}

private extension Phase6VolumeContext {
    init(metadata: CalibratedAudioGuardrailMetadata?) {
        outputVolume = metadata?.rawOutputVolume ?? -1.0
        bucketedOutputVolume = metadata?.bucketedVolume?.outputVolume
        volumeCurveOffsetDB = metadata?.bucketedVolume?.splOffsetDB
        policy = metadata?.volumePolicyDescription ?? ""
    }
}

private extension Phase6ResearchKitCalibrationContext {
    init(metadata: CalibratedAudioCalibrationMetadata) {
        sourceRepositoryURL = metadata.sourceRepositoryURL
        vendoredResearchKitCommit = metadata.vendoredResearchKitCommit
        designDocumentResearchKitCommit = metadata.designDocumentResearchKitCommit
        assetSourceVersion = metadata.sourceFileNames.joined(separator: ",")
        sourceFileNames = metadata.sourceFileNames
        validationStatus = metadata.validationStatus.rawValue
        limitation = Phase6LoudnessMatchRunPayload.modelCalibratedOutputLimitation
    }
}

private extension Phase6LoudnessTrialContext {
    init(_ trial: TinnitusLoudnessMatchTrial) {
        trialIndex = trial.trialIndex
        acceptedLevelDBHL = trial.acceptedLevelDBHL
        estimatedDBSPL = trial.estimatedDBSPL ?? .nan
        dbSL = trial.dbSL ?? .nan
        confidence = trial.confidence.rawValue
        acceptedAt = trial.acceptedAt
    }
}

private extension Phase6ProtocolEventContext {
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
        guardrailRouteOutputs = event.guardrailMetadata?.routeDetails?.outputs.map(Phase6RouteOutputContext.init) ?? []
    }
}

private extension Phase6PlaybackEventContext {
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

private extension Phase6RefusalContext {
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

private extension CalibratedAudioRoutePortKind {
    var description: String {
        switch self {
        case .builtInSpeaker:
            return "builtInSpeaker"
        case .builtInReceiver:
            return "builtInReceiver"
        case .wiredHeadphones:
            return "wiredHeadphones"
        case .bluetoothA2DP:
            return "bluetoothA2DP"
        case .bluetoothHFP:
            return "bluetoothHFP"
        case .bluetoothLE:
            return "bluetoothLE"
        case .airPlay:
            return "airPlay"
        case .carAudio:
            return "carAudio"
        case .hdmi:
            return "hdmi"
        case .usbAudio:
            return "usbAudio"
        case .unknown(let value):
            return value
        }
    }
}
