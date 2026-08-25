import Foundation

nonisolated enum StudyNo1OrientationThresholdPayloadValidationError: Error, Equatable {
    case missingRequiredFields([String])
    case incompleteThresholdRun(reason: String)
}

nonisolated struct StudyNo1OrientationThresholdRunPayload: Codable, Equatable {
    static let payloadVersion = "study-no-1-orientation-threshold-v1"
    static let protocolVersion = "orientation_threshold_v1"

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
    let rightEar: StudyNo1OrientationThresholdEarContext
    let leftEar: StudyNo1OrientationThresholdEarContext
    let limitations: [String]

    var matchedLevelForLegacyTaskRunColumn: Double {
        let values = [rightEar.thresholdDBHL, leftEar.thresholdDBHL].compactMap { $0 }
        guard !values.isEmpty else { return .nan }
        return values.sorted()[values.count / 2]
    }

    func validateCompletedOrientationThreshold() throws {
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
        if audioRoute.outputs.isEmpty {
            missing.append("audioRoute.outputs")
        }
        if volume.outputVolume < 0.0 || volume.outputVolume > 1.0 {
            missing.append("volume.outputVolume")
        }
        if environment.gateResult != .passed {
            missing.append("environment.gateResult")
        }
        if lifecycle.completedAt == nil {
            missing.append("lifecycle.completedAt")
        }
        if rightEar.thresholdDBHL == nil {
            missing.append("rightEar.thresholdDBHL")
        }
        if leftEar.thresholdDBHL == nil {
            missing.append("leftEar.thresholdDBHL")
        }

        guard missing.isEmpty else {
            throw StudyNo1OrientationThresholdPayloadValidationError.missingRequiredFields(missing)
        }

        guard payloadVersion == Self.payloadVersion else {
            throw StudyNo1OrientationThresholdPayloadValidationError.incompleteThresholdRun(
                reason: "Unexpected orientation threshold payload version."
            )
        }
        guard protocolKind == "studyNo1OrientationThresholdOneKilohertz" else {
            throw StudyNo1OrientationThresholdPayloadValidationError.incompleteThresholdRun(
                reason: "Payload is not the Study No. 1 orientation threshold protocol."
            )
        }
        guard rightEar.frequencyHz == 1_000, leftEar.frequencyHz == 1_000 else {
            throw StudyNo1OrientationThresholdPayloadValidationError.incompleteThresholdRun(
                reason: "Orientation threshold must measure 1000 Hz in both ears."
            )
        }
        guard rightEar.channel == .right, leftEar.channel == .left else {
            throw StudyNo1OrientationThresholdPayloadValidationError.incompleteThresholdRun(
                reason: "Orientation threshold ear channels are invalid."
            )
        }
    }
}

nonisolated struct StudyNo1OrientationThresholdEarContext: Codable, Equatable {
    let channel: CalibratedTonePlaybackChannel
    let frequencyHz: Double
    let thresholdDBHL: Double?
    let outputVolume: Double
    let headphoneType: String?
    let tonePlaybackDuration: TimeInterval
    let postStimulusDelay: TimeInterval
    let samples: [StudyNo1OrientationThresholdFrequencySampleContext]
}

nonisolated struct StudyNo1OrientationThresholdFrequencySampleContext: Codable, Equatable {
    let frequencyHz: Double
    let calculatedThresholdDBHL: Double?
    let channel: CalibratedTonePlaybackChannel
    let units: [StudyNo1OrientationThresholdUnitContext]
}

nonisolated struct StudyNo1OrientationThresholdUnitContext: Codable, Equatable {
    let levelDBHL: Double
    let startOfUnitTimeStamp: TimeInterval
    let preStimulusDelay: TimeInterval
    let userTapTimeStamp: TimeInterval?
    let timeoutTimeStamp: TimeInterval?
}

nonisolated struct StudyNo1OrientationThresholdPayloadBuilder {
    private let calibrationMetadata: CalibratedAudioCalibrationMetadata

    init(calibrationMetadata: CalibratedAudioCalibrationMetadata = CalibratedHeadphoneProfile.airPodsPro2.metadata) {
        self.calibrationMetadata = calibrationMetadata
    }

    func build(
        identifiers: StudyNo1IdentifierContext,
        startedAt: Date,
        completedAt: Date,
        submittedAt: Date?,
        guardrailValidation: CalibratedAudioGuardrailValidation,
        device: StudyNo1DeviceContext,
        airPods: StudyNo1AirPodsContext,
        audioSession: StudyNo1AudioSessionContext,
        environment: StudyNo1EnvironmentSPLContext,
        rightEar: StudyNo1OrientationThresholdEarContext,
        leftEar: StudyNo1OrientationThresholdEarContext
    ) throws -> StudyNo1OrientationThresholdRunPayload {
        let guardrailMetadata = guardrailValidation.metadata
        let payload = StudyNo1OrientationThresholdRunPayload(
            payloadVersion: StudyNo1OrientationThresholdRunPayload.payloadVersion,
            protocolKind: "studyNo1OrientationThresholdOneKilohertz",
            identifiers: identifiers,
            lifecycle: StudyNo1RunLifecycle(
                startedAt: startedAt,
                completedAt: completedAt,
                submittedAt: submittedAt,
                abortedAt: nil,
                interruptedAt: []
            ),
            device: device,
            airPods: airPods,
            calibration: StudyNo1ResearchKitCalibrationContext(metadata: calibrationMetadata),
            audioRoute: StudyNo1AudioRouteContext(
                outputs: guardrailMetadata.routeDetails?.outputs.map(StudyNo1RouteOutputContext.init) ?? []
            ),
            audioSession: audioSession,
            volume: StudyNo1VolumeContext(metadata: guardrailMetadata),
            environment: environment,
            rightEar: rightEar,
            leftEar: leftEar,
            limitations: [
                StudyNo1LoudnessMatchRunPayload.modelCalibratedOutputLimitation,
                "Orientation threshold is a validation record only; scheduled Study No. 1 loudness tasks use the imported HealthKit audiogram threshold for dB SL.",
                "No clinical or diagnostic claim is made by this payload."
            ]
        )

        try payload.validateCompletedOrientationThreshold()
        return payload
    }
}

nonisolated extension StudyNo1RouteOutputContext {
    init(_ output: CalibratedAudioRouteOutput) {
        portType = output.portType.description
        portName = output.portName
        portUID = output.portUID
        channelNames = output.channelNames
        verifiedCalibratedHeadphoneIdentifier = output.verifiedCalibratedHeadphoneIdentifier
        verificationSource = output.verificationSource?.rawValue
    }
}

nonisolated extension StudyNo1VolumeContext {
    init(metadata: CalibratedAudioGuardrailMetadata?) {
        outputVolume = metadata?.rawOutputVolume ?? -1.0
        bucketedOutputVolume = metadata?.bucketedVolume?.outputVolume
        volumeCurveOffsetDB = metadata?.bucketedVolume?.splOffsetDB
        policy = metadata?.volumePolicyDescription ?? ""
    }
}

nonisolated extension StudyNo1ResearchKitCalibrationContext {
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

nonisolated extension CalibratedAudioRoutePortKind {
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
