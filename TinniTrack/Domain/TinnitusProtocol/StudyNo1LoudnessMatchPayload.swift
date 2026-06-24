import Foundation

enum StudyNo1PayloadValidationError: Error, Equatable {
    case missingRequiredFields([String])
    case incompleteStudyNo1(reason: String)
}

enum StudyNo1GateResult: String, Codable, Equatable {
    case passed
    case failed
    case recordedOnly
}

enum StudyNo1FitSealStatus: String, Codable, Equatable {
    case confirmedPassed
    case confirmedNotPassed
    case unavailable
}

enum StudyNo1ThresholdSource: String, Codable, Equatable {
    case measured
    case manualScaffold
}

struct StudyNo1IdentifierContext: Codable, Equatable {
    let participantId: String?
    let studySessionId: String?
    let enrollmentId: String?
    let scheduledTaskId: String?
}

struct StudyNo1RunLifecycle: Codable, Equatable {
    let startedAt: Date
    let completedAt: Date?
    let submittedAt: Date?
    let abortedAt: Date?
    let interruptedAt: [Date]
}

struct StudyNo1DeviceContext: Codable, Equatable {
    let deviceModel: String
    let systemName: String
    let systemVersion: String
}

struct StudyNo1AirPodsContext: Codable, Equatable {
    let modelIdentifier: String?
    let firmwareVersion: String?
    let unavailableReason: String?
}

struct StudyNo1ResearchKitCalibrationContext: Codable, Equatable {
    let sourceRepositoryURL: String
    let vendoredResearchKitCommit: String
    let designDocumentResearchKitCommit: String
    let assetSourceVersion: String
    let sourceFileNames: [String]
    let validationStatus: String
    let limitation: String
}

struct StudyNo1RouteOutputContext: Codable, Equatable {
    let portType: String
    let portName: String
    let portUID: String?
    let channelNames: [String]
    let verifiedCalibratedHeadphoneIdentifier: String?
    let verificationSource: String?
}

struct StudyNo1AudioRouteContext: Codable, Equatable {
    let outputs: [StudyNo1RouteOutputContext]
}

struct StudyNo1AudioSessionContext: Codable, Equatable {
    let category: String
    let mode: String
    let options: [String]
    let sampleRate: Double
    let bufferSize: Double
}

struct StudyNo1VolumeContext: Codable, Equatable {
    let outputVolume: Double
    let bucketedOutputVolume: Double?
    let volumeCurveOffsetDB: Double?
    let policy: String
}

struct StudyNo1EnvironmentSPLContext: Codable, Equatable {
    let thresholdDBA: Double
    let requiredContiguousSamples: Int
    let samplingInterval: TimeInterval
    let sensitivityOffsetDB: Double?
    let samplesDBA: [Double]
    let gateResult: StudyNo1GateResult
}

struct StudyNo1FitSealContext: Codable, Equatable {
    let status: StudyNo1FitSealStatus
    let confirmedAt: Date?
    let limitations: String
}

struct StudyNo1SafetyContext: Codable, Equatable {
    let acknowledgedAt: Date?
    let stopControlVisibleBeforePlayback: Bool
    let maximumLevelDBHL: Double
    let limitation: String
}

struct StudyNo1StimulusContext: Codable, Equatable {
    let kind: String
    let frequencyHz: Double
    let channel: String
    let tinnitusLaterality: String
    let toneDuration: TimeInterval
    let rampDuration: TimeInterval
}

struct StudyNo1ThresholdContext: Codable, Equatable {
    let frequencyHz: Double
    let levelDBHL: Double
    let source: StudyNo1ThresholdSource
    let recordedAt: Date?
    let limitation: String?
}

struct StudyNo1LoudnessTrialContext: Codable, Equatable {
    let trialIndex: Int
    let acceptedLevelDBHL: Double
    let estimatedDBSPL: Double
    let dbSL: Double
    let confidence: String
    let acceptedAt: Date
}

struct StudyNo1LoudnessSummaryContext: Codable, Equatable {
    let medianMatchedDBHL: Double
    let medianEstimatedDBSPL: Double
    let medianDBSL: Double
    let withinSessionSpreadDB: Double
    let qualityFlags: [String]
    let completedAt: Date
}

struct StudyNo1ProtocolEventContext: Codable, Equatable {
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

struct StudyNo1PlaybackEventContext: Codable, Equatable {
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

struct StudyNo1RefusalContext: Codable, Equatable {
    let timestamp: Date
    let reason: String
    let presentedLevelDBHL: Double?
    let guardrailState: String?
}

struct StudyNo1LoudnessMatchRunPayload: Codable, Equatable {
    static let payloadVersion = "study-no-1-loudness-match-v1"
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
        guard threshold.source == .measured else {
            throw StudyNo1PayloadValidationError.incompleteStudyNo1(reason: "Completed Study No. 1 requires a measured 1000 Hz threshold source.")
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

struct StudyNo1PreflightContext: Equatable {
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

struct StudyNo1LoudnessMatchPayloadBuilder {
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
                toneDuration: events.compactMap { $0.playbackMetadata?.duration }.first ?? 1.0,
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
                "AirPods Pro 2 verification uses the recorded research-protocol route confirmation when public iOS APIs cannot expose Apple's private AirPods hearing-test verification.",
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

private extension StudyNo1RouteOutputContext {
    init(_ output: CalibratedAudioRouteOutput) {
        portType = output.portType.description
        portName = output.portName
        portUID = output.portUID
        channelNames = output.channelNames
        verifiedCalibratedHeadphoneIdentifier = output.verifiedCalibratedHeadphoneIdentifier
        verificationSource = output.verificationSource?.rawValue
    }
}

private extension StudyNo1VolumeContext {
    init(metadata: CalibratedAudioGuardrailMetadata?) {
        outputVolume = metadata?.rawOutputVolume ?? -1.0
        bucketedOutputVolume = metadata?.bucketedVolume?.outputVolume
        volumeCurveOffsetDB = metadata?.bucketedVolume?.splOffsetDB
        policy = metadata?.volumePolicyDescription ?? ""
    }
}

private extension StudyNo1ResearchKitCalibrationContext {
    init(metadata: CalibratedAudioCalibrationMetadata) {
        sourceRepositoryURL = metadata.sourceRepositoryURL
        vendoredResearchKitCommit = metadata.vendoredResearchKitCommit
        designDocumentResearchKitCommit = metadata.designDocumentResearchKitCommit
        assetSourceVersion = metadata.sourceFileNames.joined(separator: ",")
        sourceFileNames = metadata.sourceFileNames
        validationStatus = metadata.validationStatus.rawValue
        limitation = StudyNo1LoudnessMatchRunPayload.modelCalibratedOutputLimitation
    }
}

private extension StudyNo1LoudnessTrialContext {
    init(_ trial: TinnitusLoudnessMatchTrial) {
        trialIndex = trial.trialIndex
        acceptedLevelDBHL = trial.acceptedLevelDBHL
        estimatedDBSPL = trial.estimatedDBSPL ?? .nan
        dbSL = trial.dbSL ?? .nan
        confidence = trial.confidence.rawValue
        acceptedAt = trial.acceptedAt
    }
}

private extension StudyNo1ProtocolEventContext {
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

private extension StudyNo1PlaybackEventContext {
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

private extension StudyNo1RefusalContext {
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
