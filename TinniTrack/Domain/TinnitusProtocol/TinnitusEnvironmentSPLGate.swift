import Foundation

/// Screening-policy values for Study No. 1. These values are not a physical
/// calibration claim and must be validated on supported iPhone hardware.
nonisolated struct TinnitusEnvironmentSPLGateConfiguration: Codable, Equatable, Sendable {
    let thresholdDBA: Double
    let recoveryThresholdDBA: Double
    let requiredContiguousSamples: Int
    let requiredLoudSamples: Int
    let requiredRecoverySamples: Int
    let samplingInterval: TimeInterval
    let maximumSamples: Int
    let warmUpDuration: TimeInterval
    let settlingDuration: TimeInterval
    let baselineChangeThresholdDB: Double
    let baselineAdaptationRate: Double
    let retainedMeasurementLimit: Int
    let sensitivityOffsetDB: Double?

    init(
        thresholdDBA: Double,
        recoveryThresholdDBA: Double = 43.0,
        requiredContiguousSamples: Int,
        requiredLoudSamples: Int = 2,
        requiredRecoverySamples: Int = 5,
        samplingInterval: TimeInterval,
        maximumSamples: Int,
        warmUpDuration: TimeInterval = 0.5,
        settlingDuration: TimeInterval = 0.35,
        baselineChangeThresholdDB: Double = 8.0,
        baselineAdaptationRate: Double = 0.05,
        retainedMeasurementLimit: Int = 120,
        sensitivityOffsetDB: Double?
    ) {
        self.thresholdDBA = thresholdDBA
        self.recoveryThresholdDBA = recoveryThresholdDBA
        self.requiredContiguousSamples = requiredContiguousSamples
        self.requiredLoudSamples = requiredLoudSamples
        self.requiredRecoverySamples = requiredRecoverySamples
        self.samplingInterval = samplingInterval
        self.maximumSamples = maximumSamples
        self.warmUpDuration = warmUpDuration
        self.settlingDuration = settlingDuration
        self.baselineChangeThresholdDB = baselineChangeThresholdDB
        self.baselineAdaptationRate = baselineAdaptationRate
        self.retainedMeasurementLimit = retainedMeasurementLimit
        self.sensitivityOffsetDB = sensitivityOffsetDB
    }

    /// `samplingInterval` is retained for payload compatibility. It now means
    /// the exact energy-window duration rather than a recorder polling period.
    var windowDuration: TimeInterval {
        samplingInterval
    }

    static let studyNo1 = TinnitusEnvironmentSPLGateConfiguration(
        thresholdDBA: 45.0,
        recoveryThresholdDBA: 43.0,
        requiredContiguousSamples: 5,
        requiredLoudSamples: 2,
        requiredRecoverySamples: 5,
        samplingInterval: 1.0,
        maximumSamples: 12,
        warmUpDuration: 0.5,
        settlingDuration: 0.35,
        baselineChangeThresholdDB: 8.0,
        baselineAdaptationRate: 0.05,
        retainedMeasurementLimit: 120,
        sensitivityOffsetDB: nil
    )
}

nonisolated enum TinnitusEnvironmentCalibrationStatus: String, Codable, Equatable, Sendable {
    case unavailable
    case provisional
    case physicallyValidated
}

nonisolated struct TinnitusEnvironmentCalibrationProfile: Codable, Equatable, Sendable {
    let identifier: String
    let status: TinnitusEnvironmentCalibrationStatus
    let estimatedDBAOffset: Double?
    let referenceSensitivityOffsetDB: Double?
    let provenance: String
    let uncertaintyDB: Double?

    static let legacyEstimate = TinnitusEnvironmentCalibrationProfile(
        identifier: "legacy-test-estimate",
        status: .provisional,
        estimatedDBAOffset: nil,
        referenceSensitivityOffsetDB: nil,
        provenance: "Legacy injected screening estimate",
        uncertaintyDB: nil
    )

    /// ResearchKit's generic iPhone sensitivity reference, applied with one
    /// consistent `dBFS - sensitivity + 94` formula. It is deliberately marked
    /// provisional because it is not per-model or per-unit calibration.
    static let provisionalBuiltInMicrophone = TinnitusEnvironmentCalibrationProfile(
        identifier: "researchkit-generic-iphone-built-in-mic-v1",
        status: .provisional,
        estimatedDBAOffset: 117.3,
        referenceSensitivityOffsetDB: -23.3,
        provenance: "ResearchKit generic iPhone sensitivity reference; unvalidated screening estimate",
        uncertaintyDB: nil
    )
}

nonisolated enum TinnitusEnvironmentInputRoute: String, Codable, Equatable, Sendable {
    case builtInMicrophone
    case bluetoothHFP
    case wiredHeadset
    case usb
    case lineIn
    case unknown
}

nonisolated enum TinnitusEnvironmentDataSourceOrientation: String, Codable, Equatable, Sendable {
    case bottom
    case front
    case back
    case top
    case unknown
}

nonisolated struct TinnitusEnvironmentInputConfiguration: Codable, Equatable, Sendable {
    let route: TinnitusEnvironmentInputRoute
    let dataSourceOrientation: TinnitusEnvironmentDataSourceOrientation?
    let sampleRate: Double
    let channelCount: Int
    let inputGain: Float
    let isInputGainSettable: Bool
}

nonisolated enum TinnitusEnvironmentMeasurementFailureReason: String, Codable, Equatable, Sendable {
    case microphonePermissionDenied
    case builtInMicrophoneUnavailable
    case routeMismatch
    case routeChanged
    case dataSourceChanged
    case sampleFormatChanged
    case inputGainChanged
    case emptyInput
    case invalidPCM
    case clippedPCM
    case discontinuousSampleTime
    case incompleteWindow
    case audioSessionInterrupted
    case mediaServicesReset
    case engineFailure
    case missingCalibrationEstimate
    case cancelled
    case unavailable

    var invalidatesRoute: Bool {
        switch self {
        case .builtInMicrophoneUnavailable,
             .routeMismatch,
             .routeChanged,
             .dataSourceChanged,
             .sampleFormatChanged,
             .inputGainChanged,
             .mediaServicesReset:
            return true
        case .microphonePermissionDenied,
             .emptyInput,
             .invalidPCM,
             .clippedPCM,
             .discontinuousSampleTime,
             .incompleteWindow,
             .audioSessionInterrupted,
             .engineFailure,
             .missingCalibrationEstimate,
             .cancelled,
             .unavailable:
            return false
        }
    }
}

nonisolated enum TinnitusEnvironmentMeasurementValidity: Codable, Equatable, Sendable {
    case valid
    case invalid(TinnitusEnvironmentMeasurementFailureReason)
}

/// A provenance-bearing one-second energy measurement. Raw PCM is never part
/// of this value and must never be persisted by the capture service.
nonisolated struct TinnitusEnvironmentSPLMeasurement: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 2
    static let currentAlgorithmVersion = "a-weighted-pcm-energy-v1"

    let schemaVersion: Int
    let windowStartedAt: Date
    let windowEndedAt: Date
    let duration: TimeInterval
    let aWeightedDigitalLevelDBFS: Double?
    let provisionalEstimatedDBA: Double?
    let validity: TinnitusEnvironmentMeasurementValidity
    let input: TinnitusEnvironmentInputConfiguration
    let algorithmVersion: String
    let calibration: TinnitusEnvironmentCalibrationProfile

    var isValid: Bool {
        guard case .valid = validity,
              duration.isFinite,
              duration > 0,
              input.sampleRate.isFinite,
              input.sampleRate > 0,
              input.channelCount > 0,
              let aWeightedDigitalLevelDBFS,
              aWeightedDigitalLevelDBFS.isFinite
        else {
            return false
        }
        return true
    }

    var screeningLevelDBA: Double? {
        guard isValid,
              let provisionalEstimatedDBA,
              provisionalEstimatedDBA.isFinite
        else {
            return nil
        }
        return provisionalEstimatedDBA
    }
}

nonisolated enum TinnitusEnvironmentSPLSuspensionReason: String, Codable, Equatable, Sendable {
    case tonePlayback
    case responseTap
    case audioSessionHandoff
    case appInactive
}

nonisolated enum TinnitusEnvironmentSPLReacquisitionReason: String, Codable, Equatable, Sendable {
    case initial
    case postPlayback
    case postResponse
    case routeChange
    case dataSourceChange
    case sampleFormatChange
    case inputConfigurationChange
    case audioSessionInterruption
    case mediaServicesReset
    case manualRestart
}

nonisolated enum TinnitusEnvironmentSPLGateStatus: Equatable, Sendable {
    case idle
    case warmingUp(TinnitusEnvironmentSPLReacquisitionReason)
    case measuringInitialQuietness
    case quiet
    case suspended(TinnitusEnvironmentSPLSuspensionReason)
    case reacquiring(TinnitusEnvironmentSPLReacquisitionReason)
    case suspectedLoudness
    case interruptedByLoudness
    case routeInvalid(TinnitusEnvironmentMeasurementFailureReason)
    case unavailable(TinnitusEnvironmentMeasurementFailureReason)

    var isGenuineLoudnessInterruption: Bool {
        self == .interruptedByLoudness
    }

    var permitsScreenedPlayback: Bool {
        self == .quiet
    }
}

nonisolated struct TinnitusEnvironmentSPLGateResult: Equatable, Sendable {
    let configuration: TinnitusEnvironmentSPLGateConfiguration
    let measurements: [TinnitusEnvironmentSPLMeasurement]
    let gateResult: StudyNo1GateResult

    /// Legacy provisional screening estimates. These are never raw digital
    /// dBFS values and remain only for backward-compatible payload fields.
    var samplesDBA: [Double] {
        measurements.compactMap(\.screeningLevelDBA)
    }

    var passed: Bool {
        gateResult == .passed
    }

    var studyNo1Context: StudyNo1EnvironmentSPLContext {
        StudyNo1EnvironmentSPLContext(
            thresholdDBA: configuration.thresholdDBA,
            requiredContiguousSamples: configuration.requiredContiguousSamples,
            samplingInterval: configuration.samplingInterval,
            sensitivityOffsetDB: measurements.last?.calibration.referenceSensitivityOffsetDB
                ?? configuration.sensitivityOffsetDB,
            samplesDBA: samplesDBA,
            gateResult: gateResult,
            measurementSchemaVersion: TinnitusEnvironmentSPLMeasurement.currentSchemaVersion,
            levelSemantics: "provisional_estimated_dba_screening",
            measurements: measurements
        )
    }
}

nonisolated struct TinnitusEnvironmentSPLGateUpdate: Equatable, Sendable {
    let generation: UInt64
    let status: TinnitusEnvironmentSPLGateStatus
    let measurements: [TinnitusEnvironmentSPLMeasurement]
    let latestMeasurement: TinnitusEnvironmentSPLMeasurement?
    let contiguousPassingSamples: Int
    let consecutiveLoudSamples: Int
    let consecutiveRecoverySamples: Int
    let localBaselineDBA: Double?
    let result: TinnitusEnvironmentSPLGateResult?

    var samplesDBA: [Double] {
        measurements.compactMap(\.screeningLevelDBA)
    }

    var latestSampleDBA: Double? {
        latestMeasurement?.screeningLevelDBA
    }

    var passed: Bool {
        result?.passed == true
    }

    var hasCurrentQuietDecision: Bool {
        passed && status.permitsScreenedPlayback
    }
}

nonisolated enum TinnitusEnvironmentSPLMonitorEvent: Equatable, Sendable {
    case warmingUp(TinnitusEnvironmentSPLReacquisitionReason)
    case ready
    case measurement(TinnitusEnvironmentSPLMeasurement)
    case invalidated(TinnitusEnvironmentMeasurementFailureReason)
    case unavailable(TinnitusEnvironmentMeasurementFailureReason)
}

/// Pure lifecycle and policy reducer. Capture services supply provenance-bearing
/// windows; feature code only sends intentional lifecycle signals.
nonisolated struct TinnitusEnvironmentSPLGateStateMachine: Sendable {
    typealias Generation = UInt64

    private(set) var configuration: TinnitusEnvironmentSPLGateConfiguration
    private(set) var generation: Generation = 0
    private(set) var status: TinnitusEnvironmentSPLGateStatus = .idle
    private(set) var passedResult: TinnitusEnvironmentSPLGateResult?
    private(set) var measurements: [TinnitusEnvironmentSPLMeasurement] = []
    private(set) var latestMeasurement: TinnitusEnvironmentSPLMeasurement?
    private(set) var contiguousPassingSamples = 0
    private(set) var consecutiveLoudSamples = 0
    private(set) var consecutiveRecoverySamples = 0
    private(set) var localBaselineDBA: Double?

    private var baselineSeedLevels: [Double] = []
    private var initialQuietMeasurements: [TinnitusEnvironmentSPLMeasurement] = []

    init(configuration: TinnitusEnvironmentSPLGateConfiguration = .studyNo1) {
        self.configuration = configuration
    }

    mutating func beginMonitoring(
        reason: TinnitusEnvironmentSPLReacquisitionReason
    ) -> (generation: Generation, update: TinnitusEnvironmentSPLGateUpdate) {
        generation &+= 1
        resetTransientPolicyState(resetBaseline: true)
        status = passedResult == nil ? .warmingUp(reason) : .reacquiring(reason)
        return (generation, currentUpdate)
    }

    mutating func suspend(
        reason: TinnitusEnvironmentSPLSuspensionReason
    ) -> TinnitusEnvironmentSPLGateUpdate {
        generation &+= 1
        resetTransientPolicyState(resetBaseline: true)
        latestMeasurement = nil
        status = .suspended(reason)
        return currentUpdate
    }

    mutating func reset() -> TinnitusEnvironmentSPLGateUpdate {
        generation &+= 1
        status = .idle
        passedResult = nil
        measurements = []
        latestMeasurement = nil
        resetTransientPolicyState(resetBaseline: true)
        initialQuietMeasurements = []
        return currentUpdate
    }

    mutating func handle(
        _ event: TinnitusEnvironmentSPLMonitorEvent,
        generation eventGeneration: Generation
    ) -> TinnitusEnvironmentSPLGateUpdate? {
        guard eventGeneration == generation else {
            return nil
        }

        switch event {
        case .warmingUp(let reason):
            resetTransientPolicyState(resetBaseline: true)
            latestMeasurement = nil
            status = passedResult == nil ? .warmingUp(reason) : .reacquiring(reason)

        case .ready:
            status = passedResult == nil ? .measuringInitialQuietness : reacquiringStatus

        case .measurement(let measurement):
            apply(measurement)

        case .invalidated(let reason):
            resetTransientPolicyState(resetBaseline: true)
            latestMeasurement = nil
            status = reason.invalidatesRoute
                ? .routeInvalid(reason)
                : (passedResult == nil ? .warmingUp(reacquisitionReason(for: reason)) : .reacquiring(reacquisitionReason(for: reason)))

        case .unavailable(let reason):
            resetTransientPolicyState(resetBaseline: true)
            latestMeasurement = nil
            status = reason.invalidatesRoute ? .routeInvalid(reason) : .unavailable(reason)
        }

        return currentUpdate
    }

    var currentUpdate: TinnitusEnvironmentSPLGateUpdate {
        TinnitusEnvironmentSPLGateUpdate(
            generation: generation,
            status: status,
            measurements: measurements,
            latestMeasurement: latestMeasurement,
            contiguousPassingSamples: contiguousPassingSamples,
            consecutiveLoudSamples: consecutiveLoudSamples,
            consecutiveRecoverySamples: consecutiveRecoverySamples,
            localBaselineDBA: localBaselineDBA,
            result: passedResult
        )
    }

    private var reacquiringStatus: TinnitusEnvironmentSPLGateStatus {
        switch status {
        case .reacquiring(let reason):
            return .reacquiring(reason)
        case .warmingUp(let reason):
            return .reacquiring(reason)
        default:
            return .reacquiring(.manualRestart)
        }
    }

    private mutating func apply(_ measurement: TinnitusEnvironmentSPLMeasurement) {
        latestMeasurement = measurement
        appendRetained(measurement)

        guard measurement.isValid else {
            let reason: TinnitusEnvironmentMeasurementFailureReason
            if case .invalid(let invalidReason) = measurement.validity {
                reason = invalidReason
            } else {
                reason = .invalidPCM
            }
            resetTransientPolicyState(resetBaseline: true)
            status = reason.invalidatesRoute
                ? .routeInvalid(reason)
                : (passedResult == nil ? .warmingUp(reacquisitionReason(for: reason)) : .reacquiring(reacquisitionReason(for: reason)))
            return
        }

        let frameTolerance = 1.0 / measurement.input.sampleRate
        guard abs(measurement.duration - configuration.windowDuration) <= frameTolerance else {
            resetTransientPolicyState(resetBaseline: true)
            status = passedResult == nil
                ? .warmingUp(.sampleFormatChange)
                : .reacquiring(.sampleFormatChange)
            return
        }

        guard measurement.input.route == .builtInMicrophone else {
            resetTransientPolicyState(resetBaseline: true)
            status = .routeInvalid(.routeMismatch)
            return
        }

        guard let levelDBA = measurement.screeningLevelDBA else {
            resetTransientPolicyState(resetBaseline: true)
            status = .unavailable(.missingCalibrationEstimate)
            return
        }

        if passedResult == nil {
            applyInitialMeasurement(measurement, levelDBA: levelDBA)
        } else {
            applyContinuousMeasurement(levelDBA: levelDBA)
        }
    }

    private mutating func applyInitialMeasurement(
        _ measurement: TinnitusEnvironmentSPLMeasurement,
        levelDBA: Double
    ) {
        consecutiveLoudSamples = 0
        consecutiveRecoverySamples = 0

        guard levelDBA < configuration.thresholdDBA else {
            contiguousPassingSamples = 0
            initialQuietMeasurements = []
            baselineSeedLevels = []
            localBaselineDBA = nil
            status = .suspectedLoudness
            return
        }

        contiguousPassingSamples += 1
        initialQuietMeasurements.append(measurement)
        baselineSeedLevels.append(levelDBA)
        status = .measuringInitialQuietness

        guard contiguousPassingSamples >= configuration.requiredContiguousSamples else {
            return
        }

        localBaselineDBA = mean(baselineSeedLevels)
        let passingMeasurements = Array(
            initialQuietMeasurements.suffix(configuration.requiredContiguousSamples)
        )
        passedResult = TinnitusEnvironmentSPLGateResult(
            configuration: configuration,
            measurements: passingMeasurements,
            gateResult: .passed
        )
        status = .quiet
    }

    private mutating func applyContinuousMeasurement(levelDBA: Double) {
        contiguousPassingSamples = 0

        if status == .interruptedByLoudness {
            consecutiveLoudSamples = 0
            if levelDBA < configuration.recoveryThresholdDBA {
                consecutiveRecoverySamples += 1
                baselineSeedLevels.append(levelDBA)
                if consecutiveRecoverySamples >= configuration.requiredRecoverySamples {
                    localBaselineDBA = mean(
                        Array(baselineSeedLevels.suffix(configuration.requiredRecoverySamples))
                    )
                    consecutiveRecoverySamples = 0
                    baselineSeedLevels = []
                    status = .quiet
                }
            } else {
                consecutiveRecoverySamples = 0
                baselineSeedLevels = []
            }
            return
        }

        consecutiveRecoverySamples = 0
        let exceedsAbsoluteThreshold = levelDBA >= configuration.thresholdDBA
        let exceedsBaselineChange = localBaselineDBA.map {
            levelDBA - $0 >= configuration.baselineChangeThresholdDB
        } ?? false

        if exceedsAbsoluteThreshold || exceedsBaselineChange {
            consecutiveLoudSamples += 1
            status = consecutiveLoudSamples >= configuration.requiredLoudSamples
                ? .interruptedByLoudness
                : .suspectedLoudness
            return
        }

        consecutiveLoudSamples = 0
        status = .quiet
        updateBaseline(with: levelDBA)
    }

    private mutating func appendRetained(_ measurement: TinnitusEnvironmentSPLMeasurement) {
        measurements.append(measurement)
        let overflow = measurements.count - configuration.retainedMeasurementLimit
        if overflow > 0 {
            measurements.removeFirst(overflow)
        }
    }

    private mutating func updateBaseline(with levelDBA: Double) {
        guard let localBaselineDBA else {
            baselineSeedLevels.append(levelDBA)
            if baselineSeedLevels.count >= configuration.requiredContiguousSamples {
                self.localBaselineDBA = mean(baselineSeedLevels)
                baselineSeedLevels = []
            }
            return
        }

        guard levelDBA < configuration.recoveryThresholdDBA else {
            return
        }
        let rate = min(max(configuration.baselineAdaptationRate, 0), 1)
        self.localBaselineDBA = localBaselineDBA + (rate * (levelDBA - localBaselineDBA))
    }

    private mutating func resetTransientPolicyState(resetBaseline: Bool) {
        contiguousPassingSamples = 0
        consecutiveLoudSamples = 0
        consecutiveRecoverySamples = 0
        initialQuietMeasurements = []
        baselineSeedLevels = []
        if resetBaseline {
            localBaselineDBA = nil
        }
    }

    private func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else {
            return nil
        }
        return values.reduce(0, +) / Double(values.count)
    }

    private func reacquisitionReason(
        for failure: TinnitusEnvironmentMeasurementFailureReason
    ) -> TinnitusEnvironmentSPLReacquisitionReason {
        switch failure {
        case .routeMismatch, .routeChanged, .builtInMicrophoneUnavailable:
            return .routeChange
        case .dataSourceChanged:
            return .dataSourceChange
        case .sampleFormatChanged,
             .emptyInput,
             .invalidPCM,
             .clippedPCM,
             .discontinuousSampleTime,
             .incompleteWindow:
            return .sampleFormatChange
        case .inputGainChanged:
            return .inputConfigurationChange
        case .audioSessionInterrupted:
            return .audioSessionInterruption
        case .mediaServicesReset:
            return .mediaServicesReset
        case .microphonePermissionDenied,
             .engineFailure,
             .missingCalibrationEstimate,
             .cancelled,
             .unavailable:
            return .manualRestart
        }
    }
}

/// Compatibility helper for deterministic fixtures that already provide
/// provisional estimated dBA values. Production PCM never enters this API.
nonisolated struct TinnitusEnvironmentSPLGateEvaluator {
    func evaluate(
        samplesDBA: [Double],
        configuration: TinnitusEnvironmentSPLGateConfiguration = .studyNo1
    ) -> TinnitusEnvironmentSPLGateResult {
        var machine = TinnitusEnvironmentSPLGateStateMachine(configuration: configuration)
        let started = machine.beginMonitoring(reason: .initial)
        _ = machine.handle(.ready, generation: started.generation)
        for (index, sample) in samplesDBA.enumerated() {
            guard sample.isFinite else {
                _ = machine.handle(.invalidated(.invalidPCM), generation: started.generation)
                continue
            }
            _ = machine.handle(
                .measurement(legacyMeasurement(levelDBA: sample, index: index, configuration: configuration)),
                generation: started.generation
            )
        }

        return machine.passedResult ?? TinnitusEnvironmentSPLGateResult(
            configuration: configuration,
            measurements: machine.measurements,
            gateResult: .failed
        )
    }

    func update(
        samplesDBA: [Double],
        configuration: TinnitusEnvironmentSPLGateConfiguration = .studyNo1
    ) -> TinnitusEnvironmentSPLGateUpdate {
        var machine = TinnitusEnvironmentSPLGateStateMachine(configuration: configuration)
        let started = machine.beginMonitoring(reason: .initial)
        _ = machine.handle(.ready, generation: started.generation)
        for (index, sample) in samplesDBA.enumerated() {
            guard sample.isFinite else {
                _ = machine.handle(.invalidated(.invalidPCM), generation: started.generation)
                continue
            }
            _ = machine.handle(
                .measurement(legacyMeasurement(levelDBA: sample, index: index, configuration: configuration)),
                generation: started.generation
            )
        }
        return machine.currentUpdate
    }

    func legacyMeasurement(
        levelDBA: Double,
        index: Int = 0,
        configuration: TinnitusEnvironmentSPLGateConfiguration = .studyNo1
    ) -> TinnitusEnvironmentSPLMeasurement {
        let start = Date(timeIntervalSince1970: Double(index) * configuration.windowDuration)
        let input = TinnitusEnvironmentInputConfiguration(
            route: .builtInMicrophone,
            dataSourceOrientation: .bottom,
            sampleRate: 48_000,
            channelCount: 1,
            inputGain: 1,
            isInputGainSettable: false
        )
        return TinnitusEnvironmentSPLMeasurement(
            schemaVersion: TinnitusEnvironmentSPLMeasurement.currentSchemaVersion,
            windowStartedAt: start,
            windowEndedAt: start.addingTimeInterval(configuration.windowDuration),
            duration: configuration.windowDuration,
            aWeightedDigitalLevelDBFS: levelDBA - 100,
            provisionalEstimatedDBA: levelDBA,
            validity: .valid,
            input: input,
            algorithmVersion: "legacy-injected-estimate-v1",
            calibration: .legacyEstimate
        )
    }
}
