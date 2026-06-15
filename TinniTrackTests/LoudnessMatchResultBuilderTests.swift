import Foundation
import Testing
@testable import TinniTrack

struct LoudnessMatchResultBuilderTests {
    @Test
    func payloadIncludesCalibratedDerivedValuesAndProvenance() {
        let enrollmentID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_750_000_000)
        let completedAt = startedAt.addingTimeInterval(42)
        let audiogramID = UUID()
        let task = ScheduledTask(
            id: UUID(),
            enrollmentID: enrollmentID,
            taskKey: "lm_1khz_v1",
            taskVersion: 1,
            scheduledFor: startedAt,
            windowStart: startedAt.addingTimeInterval(-60),
            windowEnd: startedAt.addingTimeInterval(3_600),
            status: .scheduled,
            dayIndex: 0,
            slotIndex: 0,
            completedAt: nil
        )

        let submission = StudyNo1LoudnessMatchResultBuilder().makeSubmission(
            from: LoudnessMatchResultInput(
                scheduledTask: task,
                startedAt: startedAt,
                completedAt: completedAt,
                matchedLevel: 0.5,
                currentRoute: AudioOutputRoute(name: "AirPods Pro 2", portType: "BluetoothA2DPOutput"),
                isSupportedRoute: true,
                ambientDB: 31,
                isAmbientQuiet: true,
                systemOutputVolumeAtStart: 0.5,
                systemOutputVolumeAtSubmit: 0.5,
                didSystemOutputVolumeChange: false,
                audiogramThreshold: AudiogramThresholdAtFrequency(
                    frequencyHz: 1_000,
                    leftDBHL: 10,
                    rightDBHL: 15,
                    sourceAudiogramID: audiogramID,
                    measuredAt: startedAt.addingTimeInterval(-86_400),
                    derivation: "exact_1000hz_no_interpolation"
                ),
                loudnessEvents: [
                    MeasurementTraceEvent(timestamp: startedAt, value: 0.3),
                    MeasurementTraceEvent(timestamp: startedAt.addingTimeInterval(2), value: 0.72)
                ],
                ambientEvents: [
                    MeasurementTraceEvent(timestamp: startedAt.addingTimeInterval(1), value: 31)
                ],
                systemOutputVolumeEvents: [
                    MeasurementTraceEvent(timestamp: startedAt, value: 0.5)
                ],
                deviceInfo: ["model": .string("iPhone")],
                outputDeviceInfo: ["route_name": .string("AirPods Pro 2")],
                appVersion: "1.0"
            )
        )

        #expect(submission.validationStatus == .acceptedValid)
        #expect(submission.qualityFlags == [.routeNameCalibrationInferred])
        #expect(submission.matchedLevel == 0.5)
        #expect(submission.rawPayload["matched_level"] == .number(0.5))
        #expect(submission.rawPayload["matched_level_unit"] == .string("normalizedAmplitude"))
        #expect(submission.rawPayload["stimulus"] == .object([
            "waveform": .string("sine"),
            "frequency_hz": .number(1_000),
            "channel": .string("current output route")
        ]))
        #expect(submission.rawPayload["gating"] == .object(submission.gating))
        #expect(submission.gating["headphone_gate"] == .object([
            "route_name": .string("AirPods Pro 2"),
            "route_port_type": .string("BluetoothA2DPOutput"),
            "is_supported": .bool(true),
            "allowed_generations": .array([
                .string("AirPods Pro 2"),
                .string("AirPods Pro 3")
            ]),
            "gate_id": .string("study-no-1-airpods-pro-2-3-route-name-gate")
        ]))
        #expect(submission.gating["system_output_volume"] == .object([
            "value_at_start": .number(0.5),
            "value_at_submit": .number(0.5),
            "changed_during_matching": .bool(false),
            "change_tolerance": .number(StudyNo1Configuration.outputVolumeChangeTolerance),
            "unit": .string("systemOutputVolume")
        ]))

        guard case .object(let rawInputs)? = submission.rawPayload["raw_inputs"] else {
            Issue.record("Expected raw inputs")
            return
        }
        #expect(rawInputs["matched_level"] == .number(0.5))

        guard case .object(let derivedOutputs)? = submission.rawPayload["derived_outputs"] else {
            Issue.record("Expected derived outputs")
            return
        }
        #expect(derivedOutputs["peak_dbfs"] == .number(-6.020599913279624))
        if case .number(let estimatedDBSPL)? = derivedOutputs["estimated_db_spl"] {
            #expect(abs(estimatedDBSPL - 45.63910008672037) < 0.000001)
        } else {
            Issue.record("Expected estimated dB SPL")
        }
        if case .number(let estimatedDBHL)? = derivedOutputs["estimated_db_hl"] {
            #expect(abs(estimatedDBHL - 36.36910008672037) < 0.000001)
        } else {
            Issue.record("Expected estimated dB HL")
        }
        if case .number(let estimatedDBSL)? = derivedOutputs["estimated_db_sl_bilateral_mean"] {
            #expect(abs(estimatedDBSL - 23.86910008672037) < 0.000001)
        } else {
            Issue.record("Expected estimated dB SL")
        }

        guard case .array(let loudnessTrace)? = submission.rawPayload["loudness_trace"],
              case .object(let firstEvent)? = loudnessTrace.first else {
            Issue.record("Expected loudness trace in payload")
            return
        }
        #expect(firstEvent["value"] == .number(0.3))
        #expect(firstEvent["unit"] == .string("normalizedAmplitude"))

        guard case .object(let metadata)? = submission.rawPayload["measurement_metadata"] else {
            Issue.record("Expected measurement metadata in payload")
            return
        }
        #expect(metadata["protocol_version"] == .string("lm_v1"))
        #expect(metadata["calibration_profile_id"] == .string("study-no-1-ork-airpods-pro-2-1khz"))
        #expect(metadata["calibration_validation_status"] == .string("researchKitReferenceAvailable"))

        guard case .object(let profile)? = metadata["active_headphone_calibration_profile"] else {
            Issue.record("Expected active headphone calibration profile")
            return
        }
        #expect(profile["profile_id"] == .string("ork-airpods-pro-2-1khz-v1"))
        #expect(profile["retspl_db_spl"] == .number(9.27))
        #expect(profile["source_table_version"] == .string("ResearchKit/ResearchKit main commit daba8c9f103477bd0279cc52a924a85b480df601, verified 2026-06-15"))
    }

    @Test
    func missingAudiogramThresholdMarksSubmissionInvalidAndPreservesTrace() {
        let startedAt = Date(timeIntervalSince1970: 1_750_000_000)
        let task = ScheduledTask(
            id: UUID(),
            enrollmentID: UUID(),
            taskKey: "lm_1khz_v1",
            taskVersion: 1,
            scheduledFor: startedAt,
            windowStart: startedAt.addingTimeInterval(-60),
            windowEnd: startedAt.addingTimeInterval(3_600),
            status: .scheduled,
            dayIndex: 0,
            slotIndex: 0,
            completedAt: nil
        )

        let submission = StudyNo1LoudnessMatchResultBuilder().makeSubmission(
            from: LoudnessMatchResultInput(
                scheduledTask: task,
                startedAt: startedAt,
                completedAt: startedAt.addingTimeInterval(30),
                matchedLevel: 0.4,
                currentRoute: AudioOutputRoute(name: "AirPods Pro 2", portType: "BluetoothA2DPOutput"),
                isSupportedRoute: true,
                ambientDB: 30,
                isAmbientQuiet: true,
                systemOutputVolumeAtStart: 0.5,
                systemOutputVolumeAtSubmit: 0.5,
                didSystemOutputVolumeChange: false,
                audiogramThreshold: nil,
                loudnessEvents: [
                    MeasurementTraceEvent(timestamp: startedAt, value: 0.4)
                ],
                ambientEvents: [],
                systemOutputVolumeEvents: [],
                deviceInfo: [:],
                outputDeviceInfo: [:],
                appVersion: nil
            )
        )

        #expect(submission.validationStatus == .invalid)
        #expect(submission.qualityFlags.contains(.missingAudiogramThreshold))
        guard case .object(let quality)? = submission.rawPayload["quality"] else {
            Issue.record("Expected quality object")
            return
        }
        #expect(quality["validation_status"] == .string("invalid"))
        guard case .array(let loudnessTrace)? = submission.rawPayload["loudness_trace"] else {
            Issue.record("Expected loudness trace preservation")
            return
        }
        #expect(loudnessTrace.count == 1)
    }
}
