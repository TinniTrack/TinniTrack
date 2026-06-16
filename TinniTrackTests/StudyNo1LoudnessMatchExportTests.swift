import Foundation
import Testing
@testable import TinniTrack

struct StudyNo1LoudnessMatchExportTests {
    @Test
    func localExportProducesFlatCSVAndSnakeCaseJSONDataContract() throws {
        let submission = Self.makeSubmission()
        let record = StudyNo1LoudnessMatchExportBuilder.makeRecord(from: submission)
        let csv = StudyNo1LoudnessMatchExportBuilder.makeCSV(records: [record])
        let jsonData = try StudyNo1LoudnessMatchExportBuilder.makeJSONData(records: [record])
        let json = String(decoding: jsonData, as: UTF8.self)

        #expect(record.schemaVersion == "study-no-1-lm-payload-v2")
        #expect(record.validationStatus == "acceptedValid")
        #expect(record.qualityFlags == "routeNameCalibrationInferred")
        #expect(record.calibrationProfileID == "ork-airpods-pro-2-1khz-v1")
        #expect(record.calibrationSourceTableVersion?.contains("ResearchKit/ResearchKit commit") == true)
        #expect(record.audiogramThresholdDerivation == "exact_1000hz_no_interpolation")
        #expect(csv.contains("task_run_id,scheduled_task_id,enrollment_id,user_id,participant_id"))
        #expect(csv.contains("study-no-1-lm-payload-v2,acceptedValid,routeNameCalibrationInferred"))
        #expect(json.contains("\"schema_version\""))
        #expect(json.contains("\"calibration_profile_id\""))
    }

    @Test
    func dataDictionaryDocumentsValidityUnitsAndCalibrationColumns() {
        let columns = Set(StudyNo1LoudnessMatchExportBuilder.dataDictionary.map(\.column))

        #expect(columns.contains("validation_status"))
        #expect(columns.contains("estimated_db_spl"))
        #expect(columns.contains("estimated_db_hl"))
        #expect(columns.contains("estimated_db_sl_left"))
        #expect(columns.contains("calibration_profile_id"))
        #expect(columns.contains("calibration_source_table_version"))
        #expect(columns.contains("trial_standard_deviation"))
    }

    private static func makeSubmission() -> LoudnessMatchSubmission {
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

        return StudyNo1LoudnessMatchResultBuilder().makeSubmission(
            from: LoudnessMatchResultInput(
                scheduledTask: task,
                startedAt: startedAt,
                completedAt: startedAt.addingTimeInterval(30),
                matchedLevel: 0.5,
                currentRoute: AudioOutputRoute(name: "AirPods Pro 2", portType: "BluetoothA2DPOutput"),
                isSupportedRoute: true,
                ambientDB: 30,
                isAmbientQuiet: true,
                systemOutputVolumeAtStart: 0.5,
                systemOutputVolumeAtSubmit: 0.5,
                didSystemOutputVolumeChange: false,
                audiogramThreshold: AudiogramThresholdAtFrequency(
                    frequencyHz: 1_000,
                    leftDBHL: 10,
                    rightDBHL: 15,
                    sourceAudiogramID: UUID(),
                    measuredAt: startedAt.addingTimeInterval(-86_400),
                    derivation: "exact_1000hz_no_interpolation"
                ),
                loudnessEvents: [
                    MeasurementTraceEvent(timestamp: startedAt, value: 0.3),
                    MeasurementTraceEvent(timestamp: startedAt.addingTimeInterval(2), value: 0.5)
                ],
                ambientEvents: [
                    MeasurementTraceEvent(timestamp: startedAt, value: 30)
                ],
                systemOutputVolumeEvents: [
                    MeasurementTraceEvent(timestamp: startedAt, value: 0.5)
                ],
                deviceInfo: [:],
                outputDeviceInfo: [:],
                appVersion: "1.0"
            )
        )
    }
}
