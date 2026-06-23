import Foundation
import Testing
@testable import TinniTrack

struct AcousticValidationTests {
    private let protocolDefinition = AcousticValidationProtocol.airPodsPro2MaxVolume
    private let evaluator = AcousticValidationEvaluator()
    private let timestamp = Date(timeIntervalSince1970: 1_800_020_000)

    @Test
    func airPodsPro2ValidationMatrixCoversRequiredFrequenciesAndChannels() throws {
        let matrix = try protocolDefinition.makeMatrix()

        #expect(matrix.count == 16)
        #expect(Set(matrix.map(\.frequencyHz)) == Set([250, 500, 1_000, 2_000, 3_000, 4_000, 6_000, 8_000]))
        #expect(Set(matrix.map(\.channel)) == Set([.left, .right]))

        let oneKilohertzLeft = try #require(matrix.first { $0.frequencyHz == 1_000 && $0.channel == .left })
        #expect(oneKilohertzLeft.requestedDBHL == 30)
        #expect(abs(oneKilohertzLeft.expectedDBSPL - 39.27) < 0.000_001)
        #expect(oneKilohertzLeft.outputVolume == 1.0)
        #expect(oneKilohertzLeft.calibrationMetadata.sourceFileNames.contains("retspl_AIRPODSPROV2.plist"))
    }

    @Test
    func completeExternalMeasurementsCanPassValidation() throws {
        let record = try validationRecord()

        let evaluation = try evaluator.evaluate(record)

        #expect(evaluation.status == .pass)
        #expect(evaluation.canMarkCalibrationValidated)
        #expect(evaluation.pointResults.count == 16)
        #expect(evaluation.maximumAbsoluteErrorDB == 1.0)
        #expect(evaluation.meanAbsoluteErrorDB == 1.0)
        #expect(evaluation.minimumChannelSeparationDB > 40.0)
        #expect(evaluation.pointResults.allSatisfy { $0.status == .pass })
    }

    @Test
    func reviewToleranceProducesNeedsReviewWithoutFailingEveryPoint() throws {
        let record = try validationRecord(measurementOffsetDB: 4.0)

        let evaluation = try evaluator.evaluate(record)

        #expect(evaluation.status == .needsReview)
        #expect(!evaluation.canMarkCalibrationValidated)
        #expect(evaluation.maximumAbsoluteErrorDB == 4.0)
        #expect(evaluation.pointResults.allSatisfy { $0.status == .needsReview })
    }

    @Test
    func outOfToleranceMeasurementsFailValidation() throws {
        let record = try validationRecord(measurementOffsetDB: 6.0)

        let evaluation = try evaluator.evaluate(record)

        #expect(evaluation.status == .fail)
        #expect(!evaluation.canMarkCalibrationValidated)
        #expect(evaluation.pointResults.allSatisfy { $0.status == .fail })
    }

    @Test
    func insufficientChannelSeparationFailsValidation() throws {
        let record = try validationRecord(
            measurementOffsetDB: 0.0,
            inactiveChannelOffsetFromExpectedDB: -10.0
        )

        let evaluation = try evaluator.evaluate(record)

        #expect(evaluation.status == .fail)
        #expect(evaluation.pointResults.allSatisfy { $0.channelSeparationDB == 10.0 })
    }

    @Test
    func maxVolumePolicyIsRequired() throws {
        var record = try validationRecord()
        record = AcousticValidationRunRecord(
            runIdentifier: record.runIdentifier,
            runVersion: record.runVersion,
            validationProtocol: record.validationProtocol,
            deviceContext: deviceContext(outputVolume: 0.9375),
            environmentContext: record.environmentContext,
            measurementChain: record.measurementChain,
            clinicalAudiometerPilot: record.clinicalAudiometerPilot,
            measurements: record.measurements,
            deviations: record.deviations,
            createdAt: record.createdAt
        )

        let error = validationError {
            try evaluator.evaluate(record)
        }

        #expect(error == .unsupportedVolume(actual: 0.9375, required: 1.0, tolerance: 0.000_1))
    }

    @Test
    func noiseControlPolicyRequiresOffModeForThisProtocol() throws {
        var record = try validationRecord()
        record = AcousticValidationRunRecord(
            runIdentifier: record.runIdentifier,
            runVersion: record.runVersion,
            validationProtocol: record.validationProtocol,
            deviceContext: deviceContext(noiseControlMode: .transparency),
            environmentContext: record.environmentContext,
            measurementChain: record.measurementChain,
            clinicalAudiometerPilot: record.clinicalAudiometerPilot,
            measurements: record.measurements,
            deviations: record.deviations,
            createdAt: record.createdAt
        )

        let error = validationError {
            try evaluator.evaluate(record)
        }

        #expect(error == .unsupportedNoiseControlMode(actual: .transparency, required: .off))
    }

    @Test
    func missingMetadataRefusesEvaluation() throws {
        let record = try validationRecord(
            deviceContext: deviceContext(
                airPodsFirmware: AcousticValidationAirPodsFirmwareContext(
                    version: nil,
                    unavailableReason: nil
                )
            )
        )

        let error = validationError {
            try evaluator.evaluate(record)
        }

        #expect(error == .missingMetadata(["deviceContext.airPodsFirmware"]))
    }

    @Test
    func environmentGateMustPassBeforeValidation() throws {
        let record = try validationRecord(
            environmentContext: AcousticValidationEnvironmentContext(
                thresholdDBA: 45,
                requiredContiguousSamples: 5,
                samplingInterval: 1,
                sensitivityOffsetDB: -23.3,
                recordedSamplesDBA: [46, 44, 44, 46, 44, 44]
            )
        )

        let error = validationError {
            try evaluator.evaluate(record)
        }

        #expect(error == .environmentGateFailed)
    }

    @Test
    func externalSPLMeasurementsAreRequiredBeforeCalibrationCanBeValidated() throws {
        var measurements = try measurementsForMatrix()
        measurements[0] = AcousticValidationMeasurement(
            frequencyHz: measurements[0].frequencyHz,
            channel: measurements[0].channel,
            measuredDBSPL: nil,
            inactiveChannelMeasuredDBSPL: measurements[0].inactiveChannelMeasuredDBSPL,
            notes: measurements[0].notes
        )
        let record = try validationRecord(measurements: measurements)

        let error = validationError {
            try evaluator.evaluate(record)
        }

        #expect(error == .missingMatrixMeasurements(["250Hz-left"]))
    }

    @Test
    func missingRequiredMatrixPointIsRefused() throws {
        let measurements = try Array(measurementsForMatrix().dropFirst())
        let record = try validationRecord(measurements: measurements)

        let error = validationError {
            try evaluator.evaluate(record)
        }

        #expect(error == .missingMatrixMeasurements(["250Hz-left"]))
    }

    @Test
    func clinicalPilotNotRunKeepsOverallStatusInNeedsReview() throws {
        let pilot = AcousticValidationClinicalAudiometerPilot(
            status: .notRun,
            audiometerModel: nil,
            transducer: nil,
            calibrationDate: nil,
            pilotSampleSize: nil,
            notes: "Clinical audiometer comparison is deferred until the pilot lab session."
        )
        let record = try validationRecord(clinicalAudiometerPilot: pilot)

        let evaluation = try evaluator.evaluate(record)

        #expect(evaluation.status == .needsReview)
        #expect(!evaluation.canMarkCalibrationValidated)
    }

    @Test
    func validationRecordExportsAndRoundTripsAsJSON() throws {
        let record = try validationRecord()
        let evaluation = try evaluator.evaluate(record)
        let exporter = AcousticValidationRecordExporter(dateProvider: { timestamp.addingTimeInterval(10) })

        let data = try exporter.exportData(record: record, evaluation: evaluation)
        let package = try exporter.decodePackage(from: data)
        let json = try exporter.exportJSONString(record: record, evaluation: evaluation)

        #expect(package.record.runIdentifier == record.runIdentifier)
        #expect(package.record.measurements.count == record.measurements.count)
        #expect(package.evaluation.runIdentifier == evaluation.runIdentifier)
        #expect(package.evaluation.status == evaluation.status)
        #expect(package.exportedAt == timestamp.addingTimeInterval(10))
        #expect(json.contains("\"runVersion\" : \"phase-5-v1\""))
        #expect(json.contains("\"canMarkCalibrationValidated\"") == false)
    }

    @Test
    func phaseFiveDoesNotLoosenExistingUnguardedPlaybackRefusal() {
        let planner = CalibratedTonePlaybackPlanner(dateProvider: { timestamp })

        let error = playbackError {
            try planner.makePlan(
                for: CalibratedTonePlaybackRequest(
                    frequencyHz: 1_000,
                    levelDBHL: 30,
                    channel: .left,
                    duration: 1.0,
                    guardrailValidation: CalibratedAudioGuardrailSession().validation
                )
            )
        }

        #expect(error == .guardrailsNotEvaluated)
    }

    private func validationRecord(
        measurementOffsetDB: Double = 1.0,
        inactiveChannelOffsetFromExpectedDB: Double = -55.0,
        deviceContext: AcousticValidationDeviceContext? = nil,
        environmentContext: AcousticValidationEnvironmentContext? = nil,
        clinicalAudiometerPilot: AcousticValidationClinicalAudiometerPilot? = nil,
        measurements: [AcousticValidationMeasurement]? = nil
    ) throws -> AcousticValidationRunRecord {
        AcousticValidationRunRecord(
            runIdentifier: "run-001",
            runVersion: "phase-5-v1",
            validationProtocol: protocolDefinition,
            deviceContext: deviceContext ?? self.deviceContext(),
            environmentContext: environmentContext ?? self.environmentContext(),
            measurementChain: measurementChain(),
            clinicalAudiometerPilot: clinicalAudiometerPilot ?? self.clinicalAudiometerPilot(),
            measurements: try measurements ?? measurementsForMatrix(
                measurementOffsetDB: measurementOffsetDB,
                inactiveChannelOffsetFromExpectedDB: inactiveChannelOffsetFromExpectedDB
            ),
            deviations: [],
            createdAt: timestamp
        )
    }

    private func measurementsForMatrix(
        measurementOffsetDB: Double = 1.0,
        inactiveChannelOffsetFromExpectedDB: Double = -55.0
    ) throws -> [AcousticValidationMeasurement] {
        try protocolDefinition.makeMatrix().map { point in
            AcousticValidationMeasurement(
                frequencyHz: point.frequencyHz,
                channel: point.channel,
                measuredDBSPL: point.expectedDBSPL + measurementOffsetDB,
                inactiveChannelMeasuredDBSPL: point.expectedDBSPL + inactiveChannelOffsetFromExpectedDB,
                notes: "Measured with external coupler fixture."
            )
        }
    }

    private func deviceContext(
        outputVolume: Double = 1.0,
        noiseControlMode: AcousticValidationNoiseControlMode = .off,
        airPodsFirmware: AcousticValidationAirPodsFirmwareContext = AcousticValidationAirPodsFirmwareContext(
            version: "7A302",
            unavailableReason: nil
        )
    ) -> AcousticValidationDeviceContext {
        AcousticValidationDeviceContext(
            deviceModel: "iPhone17,1",
            osVersion: "iOS 26.0",
            airPodsModelIdentifier: "AIRPODSPROV2",
            airPodsFirmware: airPodsFirmware,
            route: AcousticValidationRouteContext(
                portName: "Verified AirPods Pro 2",
                portType: "BluetoothA2DPOutput",
                portUID: "airpods-pro-2-lab",
                channelNames: ["left", "right"],
                verifiedHeadphoneIdentifier: "AIRPODSPROV2"
            ),
            outputVolume: outputVolume,
            noiseControlMode: noiseControlMode
        )
    }

    private func environmentContext() -> AcousticValidationEnvironmentContext {
        AcousticValidationEnvironmentContext(
            thresholdDBA: 45,
            requiredContiguousSamples: 5,
            samplingInterval: 1,
            sensitivityOffsetDB: -23.3,
            recordedSamplesDBA: [42.5, 41.8, 43.0, 42.1, 41.9]
        )
    }

    private func measurementChain() -> AcousticValidationMeasurementChain {
        AcousticValidationMeasurementChain(
            labName: "TinniTrack Acoustic Lab",
            operatorName: "Researcher",
            couplerOrEarSimulator: "IEC 60318-4 ear simulator",
            microphone: "Class 1 measurement microphone",
            acousticCalibrator: "94 dB SPL pistonphone",
            analyzerSoftware: "Lab analyzer 1.0",
            measurementDate: timestamp,
            calibrationDate: timestamp.addingTimeInterval(-86_400)
        )
    }

    private func clinicalAudiometerPilot() -> AcousticValidationClinicalAudiometerPilot {
        AcousticValidationClinicalAudiometerPilot(
            status: .completed,
            audiometerModel: "Clinical audiometer reference",
            transducer: "Insert earphones",
            calibrationDate: timestamp.addingTimeInterval(-86_400),
            pilotSampleSize: 3,
            notes: "Pilot comparison metadata recorded; clinical claims remain deferred."
        )
    }

    private func validationError<T>(from work: () throws -> T) -> AcousticValidationError? {
        do {
            _ = try work()
            return nil
        } catch let error as AcousticValidationError {
            return error
        } catch {
            return nil
        }
    }

    private func playbackError<T>(from work: () throws -> T) -> CalibratedTonePlaybackError? {
        do {
            _ = try work()
            return nil
        } catch let error as CalibratedTonePlaybackError {
            return error
        } catch {
            return nil
        }
    }
}
