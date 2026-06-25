import Foundation

enum CalibratedAudioRoutePortKind: Equatable {
    case builtInSpeaker
    case builtInReceiver
    case wiredHeadphones
    case bluetoothA2DP
    case bluetoothHFP
    case bluetoothLE
    case airPlay
    case carAudio
    case hdmi
    case usbAudio
    case unknown(String)

    var isWirelessHeadphonePlaybackRoute: Bool {
        self == .bluetoothA2DP
    }
}

enum CalibratedHeadphoneVerificationSource: String, Equatable {
    case appCalibrationProfile
    case routeNameHeuristic
    case researchProtocol
    case externalDeviceRegistry
}

struct CalibratedAudioRouteOutput: Equatable {
    let portName: String
    let portType: CalibratedAudioRoutePortKind
    let portUID: String?
    let channelNames: [String]
    let verifiedCalibratedHeadphoneIdentifier: String?
    let verificationSource: CalibratedHeadphoneVerificationSource?

    init(
        portName: String,
        portType: CalibratedAudioRoutePortKind,
        portUID: String? = nil,
        channelNames: [String] = [],
        verifiedCalibratedHeadphoneIdentifier: String? = nil,
        verificationSource: CalibratedHeadphoneVerificationSource? = nil
    ) {
        self.portName = portName
        self.portType = portType
        self.portUID = portUID
        self.channelNames = channelNames
        self.verifiedCalibratedHeadphoneIdentifier = verifiedCalibratedHeadphoneIdentifier
        self.verificationSource = verificationSource
    }
}

struct CalibratedAudioRouteDetails: Equatable {
    let outputs: [CalibratedAudioRouteOutput]

    init(outputs: [CalibratedAudioRouteOutput]) {
        self.outputs = outputs
    }
}

struct CalibratedAudioVolumePolicy: Equatable {
    enum Kind: String, Equatable {
        case maximum
    }

    let kind: Kind
    let requiredVolume: Double
    let tolerance: Double

    static let maximum = CalibratedAudioVolumePolicy(
        kind: .maximum,
        requiredVolume: 1.0,
        tolerance: 0.000_1
    )

    var description: String {
        switch kind {
        case .maximum:
            return "Maximum AVAudioSession.outputVolume required; raw volume must be \(requiredVolume) within +/- \(tolerance)."
        }
    }

    func accepts(_ outputVolume: Double) -> Bool {
        outputVolume.isFinite
            && outputVolume >= 0.0
            && outputVolume <= 1.0
            && abs(outputVolume - requiredVolume) <= tolerance
    }
}

enum CalibratedAudioGuardrailState: Equatable {
    case notEvaluated
    case passed
    case failed
    case restartRequired
}

enum CalibratedAudioGuardrailError: Error, Equatable {
    case unsupportedRoute(route: CalibratedAudioRouteDetails, supportedPortTypes: [CalibratedAudioRoutePortKind])
    case unverifiedHeadphoneProfile(route: CalibratedAudioRouteDetails, requiredIdentifier: String)
    case invalidVolume(Double, policy: CalibratedAudioVolumePolicy)
    case routeChanged(previous: CalibratedAudioGuardrailMetadata, current: CalibratedAudioRouteDetails?)
    case volumeChanged(previous: CalibratedAudioGuardrailMetadata, currentVolume: Double?)
    case unavailableAudioSessionData(reason: String)
    case missingCalibrationProfile(String)
}

struct CalibratedAudioGuardrailMetadata: Equatable {
    let routeDetails: CalibratedAudioRouteDetails?
    let supportedHeadphoneIdentifier: String?
    let validationState: CalibratedAudioGuardrailState
    let rawOutputVolume: Double?
    let bucketedVolume: VolumeCurveBucket?
    let timestamp: Date
    let volumePolicyDescription: String
}

struct CalibratedAudioGuardrailValidation: Equatable {
    let state: CalibratedAudioGuardrailState
    let metadata: CalibratedAudioGuardrailMetadata
    let error: CalibratedAudioGuardrailError?
}

struct CalibratedAudioGuardrailPolicy {
    let requiredHeadphoneIdentifier: String
    let supportedHeadphoneIdentifiers: Set<String>
    let volumePolicy: CalibratedAudioVolumePolicy
    private let converter: CalibratedAudioConverter

    init(
        requiredHeadphoneIdentifier: String = CalibratedHeadphoneIdentifier.airPodsPro2,
        supportedHeadphoneIdentifiers: Set<String> = [CalibratedHeadphoneIdentifier.airPodsPro2],
        volumePolicy: CalibratedAudioVolumePolicy = .maximum,
        converter: CalibratedAudioConverter = CalibratedAudioConverter()
    ) {
        self.requiredHeadphoneIdentifier = requiredHeadphoneIdentifier
        self.supportedHeadphoneIdentifiers = supportedHeadphoneIdentifiers
        self.volumePolicy = volumePolicy
        self.converter = converter
    }

    func validate(
        route: CalibratedAudioRouteDetails?,
        outputVolume: Double?,
        timestamp: Date = Date()
    ) -> CalibratedAudioGuardrailValidation {
        if !supportedHeadphoneIdentifiers.contains(requiredHeadphoneIdentifier) {
            return failure(
                .missingCalibrationProfile(requiredHeadphoneIdentifier),
                route: route,
                outputVolume: outputVolume,
                timestamp: timestamp
            )
        }

        guard let route, !route.outputs.isEmpty else {
            return failure(
                .unavailableAudioSessionData(reason: "No current audio route outputs were available."),
                route: route,
                outputVolume: outputVolume,
                timestamp: timestamp
            )
        }

        guard route.outputs.count == 1, let output = route.outputs.first else {
            return failure(
                .unsupportedRoute(route: route, supportedPortTypes: [.bluetoothA2DP]),
                route: route,
                outputVolume: outputVolume,
                timestamp: timestamp
            )
        }

        guard output.portType.isWirelessHeadphonePlaybackRoute else {
            return failure(
                .unsupportedRoute(route: route, supportedPortTypes: [.bluetoothA2DP]),
                route: route,
                outputVolume: outputVolume,
                timestamp: timestamp
            )
        }

        guard output.verifiedCalibratedHeadphoneIdentifier == requiredHeadphoneIdentifier,
              output.verificationSource != nil
        else {
            return failure(
                .unverifiedHeadphoneProfile(route: route, requiredIdentifier: requiredHeadphoneIdentifier),
                route: route,
                outputVolume: outputVolume,
                timestamp: timestamp
            )
        }

        guard let outputVolume else {
            return failure(
                .unavailableAudioSessionData(reason: "AVAudioSession.outputVolume was unavailable."),
                route: route,
                outputVolume: outputVolume,
                timestamp: timestamp
            )
        }

        guard outputVolume.isFinite, outputVolume >= 0.0, outputVolume <= 1.0 else {
            return failure(
                .invalidVolume(outputVolume, policy: volumePolicy),
                route: route,
                outputVolume: outputVolume,
                timestamp: timestamp
            )
        }

        guard volumePolicy.accepts(outputVolume) else {
            return failure(
                .invalidVolume(outputVolume, policy: volumePolicy),
                route: route,
                outputVolume: outputVolume,
                timestamp: timestamp
            )
        }

        return CalibratedAudioGuardrailValidation(
            state: .passed,
            metadata: metadata(
                state: .passed,
                route: route,
                outputVolume: outputVolume,
                timestamp: timestamp
            ),
            error: nil
        )
    }

    func hasVolumeChanged(from baseline: Double, to currentVolume: Double?) -> Bool {
        guard let currentVolume else {
            return true
        }
        return !currentVolume.isFinite || abs(currentVolume - baseline) > volumePolicy.tolerance
    }

    private func failure(
        _ error: CalibratedAudioGuardrailError,
        route: CalibratedAudioRouteDetails?,
        outputVolume: Double?,
        timestamp: Date
    ) -> CalibratedAudioGuardrailValidation {
        CalibratedAudioGuardrailValidation(
            state: .failed,
            metadata: metadata(
                state: .failed,
                route: route,
                outputVolume: outputVolume,
                timestamp: timestamp
            ),
            error: error
        )
    }

    private func metadata(
        state: CalibratedAudioGuardrailState,
        route: CalibratedAudioRouteDetails?,
        outputVolume: Double?,
        timestamp: Date
    ) -> CalibratedAudioGuardrailMetadata {
        CalibratedAudioGuardrailMetadata(
            routeDetails: route,
            supportedHeadphoneIdentifier: state == .passed ? requiredHeadphoneIdentifier : nil,
            validationState: state,
            rawOutputVolume: outputVolume,
            bucketedVolume: bucket(outputVolume),
            timestamp: timestamp,
            volumePolicyDescription: volumePolicy.description
        )
    }

    private func bucket(_ outputVolume: Double?) -> VolumeCurveBucket? {
        guard let outputVolume else {
            return nil
        }
        return try? converter.volumeBucket(
            headphoneIdentifier: requiredHeadphoneIdentifier,
            outputVolume: outputVolume
        )
    }
}

struct CalibratedAudioGuardrailSession {
    private let policy: CalibratedAudioGuardrailPolicy
    private(set) var validation: CalibratedAudioGuardrailValidation

    init(policy: CalibratedAudioGuardrailPolicy = CalibratedAudioGuardrailPolicy()) {
        self.policy = policy
        validation = CalibratedAudioGuardrailValidation(
            state: .notEvaluated,
            metadata: CalibratedAudioGuardrailMetadata(
                routeDetails: nil,
                supportedHeadphoneIdentifier: nil,
                validationState: .notEvaluated,
                rawOutputVolume: nil,
                bucketedVolume: nil,
                timestamp: Date.distantPast,
                volumePolicyDescription: policy.volumePolicy.description
            ),
            error: nil
        )
    }

    mutating func evaluate(
        route: CalibratedAudioRouteDetails?,
        outputVolume: Double?,
        timestamp: Date = Date()
    ) -> CalibratedAudioGuardrailValidation {
        validation = policy.validate(
            route: route,
            outputVolume: outputVolume,
            timestamp: timestamp
        )
        return validation
    }

    mutating func routeDidChange(
        to route: CalibratedAudioRouteDetails?,
        timestamp: Date = Date()
    ) -> CalibratedAudioGuardrailValidation {
        guard validation.state == .passed else {
            validation = policy.validate(
                route: route,
                outputVolume: validation.metadata.rawOutputVolume,
                timestamp: timestamp
            )
            return validation
        }

        validation = restartRequired(
            .routeChanged(previous: validation.metadata, current: route),
            route: route,
            outputVolume: validation.metadata.rawOutputVolume,
            timestamp: timestamp
        )
        return validation
    }

    mutating func volumeDidChange(
        to outputVolume: Double?,
        timestamp: Date = Date()
    ) -> CalibratedAudioGuardrailValidation {
        guard validation.state == .passed else {
            validation = policy.validate(
                route: validation.metadata.routeDetails,
                outputVolume: outputVolume,
                timestamp: timestamp
            )
            return validation
        }

        guard let baseline = validation.metadata.rawOutputVolume,
              policy.hasVolumeChanged(from: baseline, to: outputVolume)
        else {
            return validation
        }

        validation = restartRequired(
            .volumeChanged(previous: validation.metadata, currentVolume: outputVolume),
            route: validation.metadata.routeDetails,
            outputVolume: outputVolume,
            timestamp: timestamp
        )
        return validation
    }

    private func restartRequired(
        _ error: CalibratedAudioGuardrailError,
        route: CalibratedAudioRouteDetails?,
        outputVolume: Double?,
        timestamp: Date
    ) -> CalibratedAudioGuardrailValidation {
        CalibratedAudioGuardrailValidation(
            state: .restartRequired,
            metadata: CalibratedAudioGuardrailMetadata(
                routeDetails: route,
                supportedHeadphoneIdentifier: validation.metadata.supportedHeadphoneIdentifier,
                validationState: .restartRequired,
                rawOutputVolume: outputVolume,
                bucketedVolume: validation.metadata.bucketedVolume,
                timestamp: timestamp,
                volumePolicyDescription: policy.volumePolicy.description
            ),
            error: error
        )
    }
}
