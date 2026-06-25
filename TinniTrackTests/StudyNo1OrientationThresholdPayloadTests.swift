import Foundation
import Testing
@testable import TinniTrack

struct StudyNo1OrientationThresholdPayloadTests {
    private let timestamp = Date(timeIntervalSince1970: 1_800_060_000)

    @Test
    func orientationThresholdPayloadCapturesBothEarResearchKitTracesAndExports() throws {
        let payload = try makePayload()
        let exporter = StudyNo1OrientationThresholdSubmissionExporter(appVersion: "1.2.3")

        let submission = try exporter.makeSubmission(from: payload)

        #expect(payload.payloadVersion == "study-no-1-orientation-threshold-v1")
        #expect(payload.protocolKind == "studyNo1OrientationThresholdOneKilohertz")
        #expect(payload.rightEar.thresholdDBHL == 18)
        #expect(payload.leftEar.thresholdDBHL == 12)
        #expect(payload.rightEar.samples.first?.units.first?.levelDBHL == 20)
        #expect(payload.leftEar.samples.first?.units.first?.userTapTimeStamp == 0.8)
        #expect(submission.startedAt == timestamp)
        #expect(submission.completedAt == timestamp.addingTimeInterval(120))
        #expect(submission.appVersion == "1.2.3")
        #expect(submission.rawPayload["payloadVersion"] == .string("study-no-1-orientation-threshold-v1"))
        #expect(submission.gating["environment"] != nil)
        #expect(submission.deviceInfo["model"] == .string("iPhone17,2"))
        #expect(submission.headphoneInfo["model_identifier"] == .string("AIRPODSPROV2"))
    }

    @Test
    func orientationThresholdValidationRequiresBothEarsAtOneKilohertz() throws {
        let valid = try makePayload()
        let invalid = StudyNo1OrientationThresholdRunPayload(
            payloadVersion: valid.payloadVersion,
            protocolKind: valid.protocolKind,
            identifiers: valid.identifiers,
            lifecycle: valid.lifecycle,
            device: valid.device,
            airPods: valid.airPods,
            calibration: valid.calibration,
            audioRoute: valid.audioRoute,
            audioSession: valid.audioSession,
            volume: valid.volume,
            environment: valid.environment,
            rightEar: ear(channel: .right, frequencyHz: 2_000, threshold: 18),
            leftEar: valid.leftEar,
            limitations: valid.limitations
        )

        #expect(throws: StudyNo1OrientationThresholdPayloadValidationError.incompleteThresholdRun(
            reason: "Orientation threshold must measure 1000 Hz in both ears."
        )) {
            try invalid.validateCompletedOrientationThreshold()
        }
    }

    private func makePayload() throws -> StudyNo1OrientationThresholdRunPayload {
        try StudyNo1OrientationThresholdPayloadBuilder().build(
            identifiers: StudyNo1IdentifierContext(
                participantId: "participant-1",
                studySessionId: "session-1",
                enrollmentId: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!.uuidString,
                scheduledTaskId: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!.uuidString
            ),
            startedAt: timestamp,
            completedAt: timestamp.addingTimeInterval(120),
            submittedAt: timestamp.addingTimeInterval(150),
            guardrailValidation: passedGuardrails(),
            device: StudyNo1DeviceContext(
                deviceModel: "iPhone17,2",
                systemName: "iOS",
                systemVersion: "26.0"
            ),
            airPods: StudyNo1AirPodsContext(
                modelIdentifier: "AIRPODSPROV2",
                firmwareVersion: nil,
                unavailableReason: "Firmware unavailable through public APIs."
            ),
            audioSession: StudyNo1AudioSessionContext(
                category: "playback",
                mode: "default",
                options: [],
                sampleRate: 44_100,
                bufferSize: 512
            ),
            environment: StudyNo1EnvironmentSPLContext(
                thresholdDBA: 45,
                requiredContiguousSamples: 5,
                samplingInterval: 1,
                sensitivityOffsetDB: -23.3,
                samplesDBA: [32, 33, 34, 35, 36],
                gateResult: .passed
            ),
            rightEar: ear(channel: .right, threshold: 18),
            leftEar: ear(channel: .left, threshold: 12)
        )
    }

    private func ear(
        channel: CalibratedTonePlaybackChannel,
        frequencyHz: Double = 1_000,
        threshold: Double
    ) -> StudyNo1OrientationThresholdEarContext {
        StudyNo1OrientationThresholdEarContext(
            channel: channel,
            frequencyHz: frequencyHz,
            thresholdDBHL: threshold,
            outputVolume: 1.0,
            headphoneType: "airPodsProGen2",
            tonePlaybackDuration: 1.0,
            postStimulusDelay: 1.0,
            samples: [
                StudyNo1OrientationThresholdFrequencySampleContext(
                    frequencyHz: frequencyHz,
                    calculatedThresholdDBHL: threshold,
                    channel: channel,
                    units: [
                        StudyNo1OrientationThresholdUnitContext(
                            levelDBHL: threshold + 2,
                            startOfUnitTimeStamp: 0.5,
                            preStimulusDelay: 0.2,
                            userTapTimeStamp: channel == .left ? 0.8 : nil,
                            timeoutTimeStamp: channel == .right ? 1.2 : nil
                        )
                    ]
                )
            ]
        )
    }

    private func passedGuardrails() -> CalibratedAudioGuardrailValidation {
        CalibratedAudioGuardrailPolicy().validate(
            route: CalibratedAudioRouteDetails(outputs: [
                CalibratedAudioRouteOutput(
                    portName: "Verified AirPods Pro 2",
                    portType: .bluetoothA2DP,
                    portUID: "verified-airpods-pro-2",
                    channelNames: ["left", "right"],
                    verifiedCalibratedHeadphoneIdentifier: "AIRPODSPROV2",
                    verificationSource: .researchProtocol
                )
            ]),
            outputVolume: 1.0,
            timestamp: timestamp
        )
    }
}
