import Foundation
import Testing
@testable import TinniTrack

struct LoudnessMatchResultBuilderTests {
    @Test
    func payloadIncludesAnalysisMetadataAndClampedNormalizedValues() {
        let enrollmentID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_750_000_000)
        let completedAt = startedAt.addingTimeInterval(42)
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
                matchedLevel: 1.4,
                currentRoute: AudioOutputRoute(name: "AirPods Pro 2", portType: "BluetoothA2DPOutput"),
                isSupportedRoute: true,
                ambientDB: 31,
                isAmbientQuiet: true,
                systemOutputVolumeAtStart: 0.5,
                systemOutputVolumeAtSubmit: 0.5,
                didSystemOutputVolumeChange: false,
                loudnessEvents: [
                    MeasurementTraceEvent(timestamp: startedAt, value: -0.5),
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

        #expect(submission.matchedLevel == 1)
        #expect(submission.rawPayload["matched_level"] == .number(1))
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

        guard case .array(let loudnessTrace)? = submission.rawPayload["loudness_trace"],
              case .object(let firstEvent)? = loudnessTrace.first else {
            Issue.record("Expected loudness trace in payload")
            return
        }
        #expect(firstEvent["value"] == .number(0))
        #expect(firstEvent["unit"] == .string("normalizedAmplitude"))

        guard case .object(let metadata)? = submission.rawPayload["measurement_metadata"] else {
            Issue.record("Expected measurement metadata in payload")
            return
        }
        #expect(metadata["protocol_version"] == .string("lm_v1"))
        #expect(metadata["calibration_profile_id"] == .string("study-no-1-unvalidated-normalized-output"))
        #expect(metadata["calibration_validation_status"] == .string("unvalidatedPrototype"))
        #expect(metadata["validity_notice"] == .string("Prototype payload is not yet calibrated to dB HL, dB SL, or verified dB SPL."))
    }
}
