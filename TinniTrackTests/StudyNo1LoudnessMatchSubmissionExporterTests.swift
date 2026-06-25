import Foundation
import Testing
@testable import TinniTrack

struct StudyNo1LoudnessMatchSubmissionExporterTests {
    private let timestamp = Date(timeIntervalSince1970: 1_800_040_000)

    @Test
    func exporterMapsStudyNo1PayloadIntoExistingSubmissionShape() throws {
        let payload = makePayload()
        let exporter = StudyNo1LoudnessMatchSubmissionExporter(appVersion: "1.2.3")

        let submission = try exporter.makeSubmission(from: payload)

        #expect(submission.startedAt == timestamp)
        #expect(submission.completedAt == timestamp.addingTimeInterval(90))
        #expect(submission.matchedLevel == 16)
        #expect(submission.appVersion == "1.2.3")
        #expect(submission.calibrationVersion?.contains("retspl_AIRPODSPROV2.plist") == true)
        #expect(submission.deviceInfo["model"] == .string("iPhone17,2"))
        #expect(submission.deviceInfo["system_version"] == .string("26.0"))
        #expect(submission.headphoneInfo["model_identifier"] == .string("AIRPODSPROV2"))
        #expect(submission.gating["environment"] != nil)
        #expect(submission.gating["fit_seal"] != nil)
        #expect(submission.gating["safety"] != nil)
        #expect(submission.rawPayload["payloadVersion"] == .string("study-no-1-loudness-match-v2"))
        #expect(submission.rawPayload["protocolKind"] == .string("studyNo1FixedOneKilohertz"))

        guard case .object(let summary)? = submission.rawPayload["summary"] else {
            Issue.record("Expected summary object in raw payload")
            return
        }
        #expect(summary["medianMatchedDBHL"] == .number(16))
        #expect(summary["medianDBSL"] == .number(6))
    }

    @Test
    func exporterRefusesPayloadMissingRequiredPreflightData() {
        let valid = makePayload()
        let invalid = StudyNo1LoudnessMatchRunPayload(
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
            environment: StudyNo1EnvironmentSPLContext(
                thresholdDBA: 45,
                requiredContiguousSamples: 5,
                samplingInterval: 1,
                sensitivityOffsetDB: nil,
                samplesDBA: [],
                gateResult: .failed
            ),
            fitSeal: valid.fitSeal,
            safety: valid.safety,
            stimulus: valid.stimulus,
            threshold: valid.threshold,
            trials: valid.trials,
            summary: valid.summary,
            protocolEvents: valid.protocolEvents,
            playbackEvents: valid.playbackEvents,
            refusals: valid.refusals,
            limitations: valid.limitations
        )

        do {
            _ = try StudyNo1LoudnessMatchSubmissionExporter(appVersion: "1.2.3")
                .makeSubmission(from: invalid)
            Issue.record("Expected exporter to validate and reject incomplete preflight data")
        } catch StudyNo1PayloadValidationError.missingRequiredFields(let fields) {
            #expect(fields.contains("environment.samplesDBA"))
        } catch {
            Issue.record("Unexpected error \(error)")
        }
    }

    private func makePayload() -> StudyNo1LoudnessMatchRunPayload {
        StudyNo1LoudnessMatchRunPayload(
            payloadVersion: StudyNo1LoudnessMatchRunPayload.payloadVersion,
            protocolKind: "studyNo1FixedOneKilohertz",
            identifiers: StudyNo1IdentifierContext(
                participantId: "participant-1",
                studySessionId: "session-1",
                enrollmentId: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!.uuidString,
                scheduledTaskId: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!.uuidString
            ),
            lifecycle: StudyNo1RunLifecycle(
                startedAt: timestamp,
                completedAt: timestamp.addingTimeInterval(90),
                submittedAt: timestamp.addingTimeInterval(120),
                abortedAt: nil,
                interruptedAt: []
            ),
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
            calibration: StudyNo1ResearchKitCalibrationContext(
                sourceRepositoryURL: CalibratedHeadphoneProfile.airPodsPro2.metadata.sourceRepositoryURL,
                vendoredResearchKitCommit: CalibratedHeadphoneProfile.airPodsPro2.metadata.vendoredResearchKitCommit,
                designDocumentResearchKitCommit: CalibratedHeadphoneProfile.airPodsPro2.metadata.designDocumentResearchKitCommit,
                assetSourceVersion: CalibratedHeadphoneProfile.airPodsPro2.metadata.sourceFileNames.joined(separator: ","),
                sourceFileNames: CalibratedHeadphoneProfile.airPodsPro2.metadata.sourceFileNames,
                validationStatus: CalibratedHeadphoneProfile.airPodsPro2.metadata.validationStatus.rawValue,
                limitation: StudyNo1LoudnessMatchRunPayload.modelCalibratedOutputLimitation
            ),
            audioRoute: StudyNo1AudioRouteContext(outputs: [
                StudyNo1RouteOutputContext(
                    portType: "bluetoothA2DP",
                    portName: "Verified AirPods Pro 2",
                    portUID: "route-1",
                    channelNames: ["left", "right"],
                    verifiedCalibratedHeadphoneIdentifier: "AIRPODSPROV2",
                    verificationSource: "appCalibrationProfile"
                )
            ]),
            audioSession: StudyNo1AudioSessionContext(
                category: "playback",
                mode: "default",
                options: [],
                sampleRate: 44_100,
                bufferSize: 512
            ),
            volume: StudyNo1VolumeContext(
                outputVolume: 1.0,
                bucketedOutputVolume: 1.0,
                volumeCurveOffsetDB: 0,
                policy: CalibratedAudioVolumePolicy.maximum.description
            ),
            environment: StudyNo1EnvironmentSPLContext(
                thresholdDBA: 45,
                requiredContiguousSamples: 5,
                samplingInterval: 1,
                sensitivityOffsetDB: -23.3,
                samplesDBA: [32, 33, 34, 35, 36],
                gateResult: .passed
            ),
            fitSeal: StudyNo1FitSealContext(
                status: .confirmedPassed,
                confirmedAt: timestamp,
                limitations: "Participant confirmation only."
            ),
            safety: StudyNo1SafetyContext(
                acknowledgedAt: timestamp,
                stopControlVisibleBeforePlayback: true,
                maximumLevelDBHL: 100,
                limitation: "Immediate stop visible before playback."
            ),
            stimulus: StudyNo1StimulusContext(
                kind: "pureTone",
                frequencyHz: 1_000,
                channel: "left",
                tinnitusLaterality: "left",
                toneDuration: 1,
                rampDuration: 0.2
            ),
            threshold: StudyNo1ThresholdContext(
                frequencyHz: 1_000,
                levelDBHL: 10,
                source: .healthKitAudiogram,
                recordedAt: timestamp,
                limitation: nil
            ),
            trials: [
                StudyNo1LoudnessTrialContext(trialIndex: 1, acceptedLevelDBHL: 15, estimatedDBSPL: 24.27, dbSL: 5, confidence: "high", acceptedAt: timestamp),
                StudyNo1LoudnessTrialContext(trialIndex: 2, acceptedLevelDBHL: 16, estimatedDBSPL: 25.27, dbSL: 6, confidence: "medium", acceptedAt: timestamp),
                StudyNo1LoudnessTrialContext(trialIndex: 3, acceptedLevelDBHL: 17, estimatedDBSPL: 26.27, dbSL: 7, confidence: "high", acceptedAt: timestamp)
            ],
            summary: StudyNo1LoudnessSummaryContext(
                medianMatchedDBHL: 16,
                medianEstimatedDBSPL: 25.27,
                medianDBSL: 6,
                withinSessionSpreadDB: 2,
                qualityFlags: [],
                completedAt: timestamp.addingTimeInterval(90)
            ),
            protocolEvents: [
                StudyNo1ProtocolEventContext(
                    timestamp: timestamp,
                    kind: "sessionStarted",
                    frequencyHz: nil,
                    presentedLevelDBHL: nil,
                    estimatedDBSPL: nil,
                    dbSL: nil,
                    channel: nil,
                    laterality: nil,
                    confidence: nil,
                    response: nil,
                    reason: nil,
                    qualityFlags: [],
                    guardrailState: nil,
                    guardrailOutputVolume: nil,
                    guardrailRouteOutputs: []
                )
            ],
            playbackEvents: [
                StudyNo1PlaybackEventContext(
                    timestamp: timestamp,
                    frequencyHz: 1_000,
                    channel: "left",
                    requestedDBHL: 15,
                    targetDBSPL: 24.27,
                    attenuationDB: -89.4,
                    linearAmplitude: 0.00003,
                    duration: 1,
                    rampDuration: 0.2,
                    sampleRate: 44_100,
                    bufferFrameCount: 512,
                    startedAt: timestamp,
                    stoppedAt: timestamp.addingTimeInterval(1)
                )
            ],
            refusals: [],
            limitations: [
                StudyNo1LoudnessMatchRunPayload.modelCalibratedOutputLimitation,
                "No clinical or diagnostic claim is made by this payload."
            ]
        )
    }
}
