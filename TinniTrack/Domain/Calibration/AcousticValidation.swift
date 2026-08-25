import Foundation

nonisolated enum AcousticValidationStatus: String, Codable, Equatable {
    case pass
    case fail
    case needsReview
}

nonisolated enum AcousticValidationNoiseControlMode: String, Codable, CaseIterable, Equatable {
    case activeNoiseCancellation
    case transparency
    case off
    case adaptive
    case unknown
}

nonisolated enum AcousticValidationClinicalPilotStatus: String, Codable, Equatable {
    case completed
    case notRun
}

nonisolated enum AcousticValidationError: Error, Equatable {
    case unsupportedFrequencyCoverage(missing: [Double])
    case unsupportedChannelCoverage(missing: [CalibratedTonePlaybackChannel])
    case unsupportedVolume(actual: Double, required: Double, tolerance: Double)
    case unsupportedNoiseControlMode(actual: AcousticValidationNoiseControlMode, required: AcousticValidationNoiseControlMode)
    case environmentGateFailed
    case missingMetadata([String])
    case missingMatrixMeasurements([String])
    case duplicateMeasurements([String])
}

nonisolated extension CalibratedTonePlaybackChannel: Codable {}

nonisolated struct AcousticValidationTolerancePolicy: Codable, Equatable {
    let passToleranceDB: Double
    let reviewToleranceDB: Double
    let minimumChannelSeparationDB: Double

    static let airPodsPro2 = AcousticValidationTolerancePolicy(
        passToleranceDB: 3.0,
        reviewToleranceDB: 5.0,
        minimumChannelSeparationDB: 40.0
    )
}

nonisolated struct AcousticValidationVolumePolicy: Codable, Equatable {
    let requiredOutputVolume: Double
    let tolerance: Double

    static let maximum = AcousticValidationVolumePolicy(
        requiredOutputVolume: 1.0,
        tolerance: CalibratedAudioVolumePolicy.maximum.tolerance
    )

    func accepts(_ outputVolume: Double) -> Bool {
        outputVolume.isFinite
            && outputVolume >= 0.0
            && outputVolume <= 1.0
            && abs(outputVolume - requiredOutputVolume) <= tolerance
    }
}

nonisolated struct AcousticValidationProtocol: Codable, Equatable {
    let identifier: String
    let version: String
    let headphoneIdentifier: String
    let requiredFrequenciesHz: [Double]
    let requiredChannels: [CalibratedTonePlaybackChannel]
    let validationLevelDBHL: Double
    let volumePolicy: AcousticValidationVolumePolicy
    let requiredNoiseControlMode: AcousticValidationNoiseControlMode
    let tolerancePolicy: AcousticValidationTolerancePolicy

    static let airPodsPro2MaxVolume = AcousticValidationProtocol(
        identifier: "airpods-pro-2-acoustic-validation",
        version: "airpods-pro-2-acoustic-validation-v1",
        headphoneIdentifier: CalibratedHeadphoneIdentifier.airPodsPro2,
        requiredFrequenciesHz: [250, 500, 1_000, 2_000, 3_000, 4_000, 6_000, 8_000],
        requiredChannels: [.left, .right],
        validationLevelDBHL: 30.0,
        volumePolicy: .maximum,
        requiredNoiseControlMode: .off,
        tolerancePolicy: .airPodsPro2
    )

    func makeMatrix(
        converter: CalibratedAudioConverter = CalibratedAudioConverter()
    ) throws -> [AcousticValidationMatrixPoint] {
        try requiredFrequenciesHz.flatMap { frequency in
            try requiredChannels.map { channel in
                let conversion = try converter.conversion(
                    headphoneIdentifier: headphoneIdentifier,
                    frequencyHz: frequency,
                    levelDBHL: validationLevelDBHL,
                    outputVolume: volumePolicy.requiredOutputVolume
                )

                return AcousticValidationMatrixPoint(
                    frequencyHz: frequency,
                    channel: channel,
                    requestedDBHL: validationLevelDBHL,
                    expectedDBSPL: conversion.targetDBSPL,
                    expectedAttenuationDB: conversion.attenuationDB,
                    expectedLinearAmplitude: conversion.linearAmplitude,
                    outputVolume: volumePolicy.requiredOutputVolume,
                    calibrationMetadata: conversion.calibrationMetadata
                )
            }
        }
    }
}

nonisolated struct AcousticValidationMatrixPoint: Codable, Equatable {
    let frequencyHz: Double
    let channel: CalibratedTonePlaybackChannel
    let requestedDBHL: Double
    let expectedDBSPL: Double
    let expectedAttenuationDB: Double
    let expectedLinearAmplitude: Double
    let outputVolume: Double
    let calibrationMetadata: CalibratedAudioCalibrationMetadata

    var key: String {
        Self.key(frequencyHz: frequencyHz, channel: channel)
    }

    static func key(frequencyHz: Double, channel: CalibratedTonePlaybackChannel) -> String {
        "\(Int(frequencyHz.rounded()))Hz-\(channel.rawValue)"
    }
}

nonisolated struct AcousticValidationRouteContext: Codable, Equatable {
    let portName: String
    let portType: String
    let portUID: String?
    let channelNames: [String]
    let verifiedHeadphoneIdentifier: String
}

nonisolated struct AcousticValidationAirPodsFirmwareContext: Codable, Equatable {
    let version: String?
    let unavailableReason: String?

    var isResolved: Bool {
        !(version?.isEmpty ?? true) || !(unavailableReason?.isEmpty ?? true)
    }
}

nonisolated struct AcousticValidationDeviceContext: Codable, Equatable {
    let deviceModel: String
    let osVersion: String
    let airPodsModelIdentifier: String
    let airPodsFirmware: AcousticValidationAirPodsFirmwareContext
    let route: AcousticValidationRouteContext
    let outputVolume: Double
    let noiseControlMode: AcousticValidationNoiseControlMode
}

nonisolated struct AcousticValidationEnvironmentContext: Codable, Equatable {
    let thresholdDBA: Double
    let requiredContiguousSamples: Int
    let samplingInterval: TimeInterval
    let sensitivityOffsetDB: Double
    let recordedSamplesDBA: [Double]

    var passedGate: Bool {
        guard requiredContiguousSamples > 0 else {
            return false
        }

        var contiguous = 0
        for sample in recordedSamplesDBA {
            if sample < thresholdDBA {
                contiguous += 1
                if contiguous >= requiredContiguousSamples {
                    return true
                }
            } else {
                contiguous = 0
            }
        }
        return false
    }
}

nonisolated struct AcousticValidationMeasurementChain: Codable, Equatable {
    let labName: String
    let operatorName: String
    let couplerOrEarSimulator: String
    let microphone: String
    let acousticCalibrator: String
    let analyzerSoftware: String
    let measurementDate: Date
    let calibrationDate: Date
}

nonisolated struct AcousticValidationClinicalAudiometerPilot: Codable, Equatable {
    let status: AcousticValidationClinicalPilotStatus
    let audiometerModel: String?
    let transducer: String?
    let calibrationDate: Date?
    let pilotSampleSize: Int?
    let notes: String
}

nonisolated struct AcousticValidationMeasurement: Codable, Equatable {
    let frequencyHz: Double
    let channel: CalibratedTonePlaybackChannel
    let measuredDBSPL: Double?
    let inactiveChannelMeasuredDBSPL: Double?
    let notes: String?

    var key: String {
        AcousticValidationMatrixPoint.key(frequencyHz: frequencyHz, channel: channel)
    }
}

nonisolated struct AcousticValidationRunRecord: Codable, Equatable {
    let runIdentifier: String
    let runVersion: String
    let validationProtocol: AcousticValidationProtocol
    let deviceContext: AcousticValidationDeviceContext
    let environmentContext: AcousticValidationEnvironmentContext
    let measurementChain: AcousticValidationMeasurementChain
    let clinicalAudiometerPilot: AcousticValidationClinicalAudiometerPilot
    let measurements: [AcousticValidationMeasurement]
    let deviations: [String]
    let createdAt: Date
}

nonisolated struct AcousticValidationPointResult: Codable, Equatable {
    let point: AcousticValidationMatrixPoint
    let measuredDBSPL: Double
    let inactiveChannelMeasuredDBSPL: Double
    let errorDB: Double
    let absoluteErrorDB: Double
    let channelSeparationDB: Double
    let status: AcousticValidationStatus
}

nonisolated struct AcousticValidationEvaluation: Codable, Equatable {
    let runIdentifier: String
    let runVersion: String
    let status: AcousticValidationStatus
    let pointResults: [AcousticValidationPointResult]
    let maximumAbsoluteErrorDB: Double
    let meanAbsoluteErrorDB: Double
    let minimumChannelSeparationDB: Double
    let deviations: [String]

    var canMarkCalibrationValidated: Bool {
        status == .pass
    }
}

nonisolated struct AcousticValidationEvaluator {
    private let converter: CalibratedAudioConverter

    init(converter: CalibratedAudioConverter = CalibratedAudioConverter()) {
        self.converter = converter
    }

    func evaluate(_ record: AcousticValidationRunRecord) throws -> AcousticValidationEvaluation {
        try validateMetadata(record)
        let matrix = try record.validationProtocol.makeMatrix(converter: converter)
        let measurements = try indexedMeasurements(record.measurements, matrix: matrix)

        let pointResults = try matrix.map { point in
            let measurement = try requiredMeasurement(for: point, in: measurements)
            let errorDB = measurement.measuredDBSPL - point.expectedDBSPL
            let absoluteErrorDB = abs(errorDB)
            let channelSeparationDB = measurement.measuredDBSPL - measurement.inactiveChannelMeasuredDBSPL

            return AcousticValidationPointResult(
                point: point,
                measuredDBSPL: measurement.measuredDBSPL,
                inactiveChannelMeasuredDBSPL: measurement.inactiveChannelMeasuredDBSPL,
                errorDB: errorDB,
                absoluteErrorDB: absoluteErrorDB,
                channelSeparationDB: channelSeparationDB,
                status: status(
                    absoluteErrorDB: absoluteErrorDB,
                    channelSeparationDB: channelSeparationDB,
                    tolerancePolicy: record.validationProtocol.tolerancePolicy
                )
            )
        }

        let maximumAbsoluteError = pointResults.map(\.absoluteErrorDB).max() ?? 0.0
        let meanAbsoluteError = pointResults.isEmpty
            ? 0.0
            : pointResults.map(\.absoluteErrorDB).reduce(0.0, +) / Double(pointResults.count)
        let minimumSeparation = pointResults.map(\.channelSeparationDB).min() ?? 0.0

        return AcousticValidationEvaluation(
            runIdentifier: record.runIdentifier,
            runVersion: record.runVersion,
            status: overallStatus(
                pointResults: pointResults,
                pilot: record.clinicalAudiometerPilot,
                deviations: record.deviations
            ),
            pointResults: pointResults,
            maximumAbsoluteErrorDB: maximumAbsoluteError,
            meanAbsoluteErrorDB: meanAbsoluteError,
            minimumChannelSeparationDB: minimumSeparation,
            deviations: record.deviations
        )
    }

    private func validateMetadata(_ record: AcousticValidationRunRecord) throws {
        var missing: [String] = []

        if record.runIdentifier.isEmpty {
            missing.append("runIdentifier")
        }
        if record.runVersion.isEmpty {
            missing.append("runVersion")
        }
        if record.deviceContext.deviceModel.isEmpty {
            missing.append("deviceContext.deviceModel")
        }
        if record.deviceContext.osVersion.isEmpty {
            missing.append("deviceContext.osVersion")
        }
        if record.deviceContext.airPodsModelIdentifier.isEmpty {
            missing.append("deviceContext.airPodsModelIdentifier")
        }
        if !record.deviceContext.airPodsFirmware.isResolved {
            missing.append("deviceContext.airPodsFirmware")
        }
        if record.deviceContext.route.portName.isEmpty {
            missing.append("deviceContext.route.portName")
        }
        if record.deviceContext.route.portType.isEmpty {
            missing.append("deviceContext.route.portType")
        }
        if record.deviceContext.route.verifiedHeadphoneIdentifier.isEmpty {
            missing.append("deviceContext.route.verifiedHeadphoneIdentifier")
        }
        if record.environmentContext.recordedSamplesDBA.isEmpty {
            missing.append("environmentContext.recordedSamplesDBA")
        }
        if record.measurementChain.labName.isEmpty {
            missing.append("measurementChain.labName")
        }
        if record.measurementChain.operatorName.isEmpty {
            missing.append("measurementChain.operatorName")
        }
        if record.measurementChain.couplerOrEarSimulator.isEmpty {
            missing.append("measurementChain.couplerOrEarSimulator")
        }
        if record.measurementChain.microphone.isEmpty {
            missing.append("measurementChain.microphone")
        }
        if record.measurementChain.acousticCalibrator.isEmpty {
            missing.append("measurementChain.acousticCalibrator")
        }
        if record.measurementChain.analyzerSoftware.isEmpty {
            missing.append("measurementChain.analyzerSoftware")
        }
        if record.clinicalAudiometerPilot.notes.isEmpty {
            missing.append("clinicalAudiometerPilot.notes")
        }

        guard missing.isEmpty else {
            throw AcousticValidationError.missingMetadata(missing)
        }

        guard record.validationProtocol.volumePolicy.accepts(record.deviceContext.outputVolume) else {
            throw AcousticValidationError.unsupportedVolume(
                actual: record.deviceContext.outputVolume,
                required: record.validationProtocol.volumePolicy.requiredOutputVolume,
                tolerance: record.validationProtocol.volumePolicy.tolerance
            )
        }

        guard record.deviceContext.noiseControlMode == record.validationProtocol.requiredNoiseControlMode else {
            throw AcousticValidationError.unsupportedNoiseControlMode(
                actual: record.deviceContext.noiseControlMode,
                required: record.validationProtocol.requiredNoiseControlMode
            )
        }

        guard record.environmentContext.passedGate else {
            throw AcousticValidationError.environmentGateFailed
        }
    }

    private func indexedMeasurements(
        _ measurements: [AcousticValidationMeasurement],
        matrix: [AcousticValidationMatrixPoint]
    ) throws -> [String: AcousticValidationResolvedMeasurement] {
        let requiredKeys = Set(matrix.map(\.key))
        let providedKeys = measurements.map(\.key)
        let missingKeys = requiredKeys.subtracting(providedKeys).sorted()
        guard missingKeys.isEmpty else {
            throw AcousticValidationError.missingMatrixMeasurements(missingKeys)
        }

        let duplicateKeys = Dictionary(grouping: providedKeys, by: { $0 })
            .filter { $0.value.count > 1 }
            .map(\.key)
            .sorted()
        guard duplicateKeys.isEmpty else {
            throw AcousticValidationError.duplicateMeasurements(duplicateKeys)
        }

        var resolved: [String: AcousticValidationResolvedMeasurement] = [:]
        var missingExternalMeasurements: [String] = []

        for measurement in measurements where requiredKeys.contains(measurement.key) {
            guard let measuredDBSPL = measurement.measuredDBSPL,
                  let inactiveChannelMeasuredDBSPL = measurement.inactiveChannelMeasuredDBSPL
            else {
                missingExternalMeasurements.append(measurement.key)
                continue
            }

            resolved[measurement.key] = AcousticValidationResolvedMeasurement(
                measuredDBSPL: measuredDBSPL,
                inactiveChannelMeasuredDBSPL: inactiveChannelMeasuredDBSPL
            )
        }

        guard missingExternalMeasurements.isEmpty else {
            throw AcousticValidationError.missingMatrixMeasurements(missingExternalMeasurements.sorted())
        }

        return resolved
    }

    private func requiredMeasurement(
        for point: AcousticValidationMatrixPoint,
        in measurements: [String: AcousticValidationResolvedMeasurement]
    ) throws -> AcousticValidationResolvedMeasurement {
        guard let measurement = measurements[point.key] else {
            throw AcousticValidationError.missingMatrixMeasurements([point.key])
        }
        return measurement
    }

    private func status(
        absoluteErrorDB: Double,
        channelSeparationDB: Double,
        tolerancePolicy: AcousticValidationTolerancePolicy
    ) -> AcousticValidationStatus {
        guard channelSeparationDB >= tolerancePolicy.minimumChannelSeparationDB else {
            return .fail
        }

        if absoluteErrorDB <= tolerancePolicy.passToleranceDB {
            return .pass
        }
        if absoluteErrorDB <= tolerancePolicy.reviewToleranceDB {
            return .needsReview
        }
        return .fail
    }

    private func overallStatus(
        pointResults: [AcousticValidationPointResult],
        pilot: AcousticValidationClinicalAudiometerPilot,
        deviations: [String]
    ) -> AcousticValidationStatus {
        if pointResults.contains(where: { $0.status == .fail }) {
            return .fail
        }
        if pilot.status != .completed || !deviations.isEmpty || pointResults.contains(where: { $0.status == .needsReview }) {
            return .needsReview
        }
        return .pass
    }
}

nonisolated private struct AcousticValidationResolvedMeasurement: Equatable {
    let measuredDBSPL: Double
    let inactiveChannelMeasuredDBSPL: Double
}
