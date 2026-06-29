import Foundation
import Testing
@testable import TinniTrack

struct StudyNo1LoudnessMatchPayloadTests {
    private let timestamp = Date(timeIntervalSince1970: 1_800_030_000)

    @Test
    func studyNo1PayloadCapturesRequiredContextAndEncodes() throws {
        let payload = try makeCompletedPayload()

        #expect(payload.payloadVersion == "study-no-1-loudness-match-v2")
        #expect(payload.protocolKind == "studyNo1FixedOneKilohertz")
        #expect(payload.identifiers.enrollmentId == enrollmentID.uuidString)
        #expect(payload.identifiers.scheduledTaskId == scheduledTaskID.uuidString)
        #expect(payload.device.deviceModel == "iPhone17,2")
        #expect(payload.airPods.modelIdentifier == "AIRPODSPROV2")
        #expect(payload.calibration.sourceFileNames.contains("retspl_AIRPODSPROV2.plist"))
        #expect(payload.audioRoute.outputs.first?.portType == "bluetoothA2DP")
        #expect(payload.audioRoute.outputs.first?.verifiedCalibratedHeadphoneIdentifier == "AIRPODSPROV2")
        #expect(payload.audioSession.sampleRate == 44_100)
        #expect(payload.volume.outputVolume == 1.0)
        #expect(payload.volume.bucketedOutputVolume == 1.0)
        #expect(payload.environment.gateResult == .passed)
        #expect(payload.environment.samplesDBA == [34.0, 35.0, 36.0, 37.0, 38.0])
        #expect(payload.fitSeal.status == .confirmedPassed)
        #expect(payload.safety.stopControlVisibleBeforePlayback)
        #expect(payload.stimulus.frequencyHz == 1_000)
        #expect(payload.stimulus.kind == "pureTone")
        #expect(payload.stimulus.channel == "both")
        #expect(payload.threshold.levelDBHL == 10)
        #expect(payload.threshold.source == .healthKitAudiogram)
        #expect(payload.trials.map(\.acceptedLevelDBHL) == [16, 14, 20])
        #expect(payload.summary.medianMatchedDBHL == 16)
        #expect(payload.summary.medianDBSL == 6)
        #expect(payload.protocolEvents.contains { $0.kind == "playbackPlanned" })
        #expect(payload.protocolEvents.contains { $0.guardrailState == "passed" && $0.guardrailOutputVolume == 1.0 })
        #expect(payload.playbackEvents.count == 6)
        #expect(payload.playbackEvents.allSatisfy { $0.channel == "both" })
        #expect(payload.refusals.contains { $0.reason == "stopRequested" })
        #expect(payload.limitations.contains(StudyNo1LoudnessMatchRunPayload.modelCalibratedOutputLimitation))

        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(StudyNo1LoudnessMatchRunPayload.self, from: data)
        #expect(decoded == payload)
    }

    @Test
    func missingRequiredPreflightMetadataRefusesCompletedPayload() throws {
        var payload = try makeCompletedPayload()
        payload = StudyNo1LoudnessMatchRunPayload(
            payloadVersion: payload.payloadVersion,
            protocolKind: payload.protocolKind,
            identifiers: payload.identifiers,
            lifecycle: payload.lifecycle,
            device: payload.device,
            airPods: payload.airPods,
            calibration: payload.calibration,
            audioRoute: payload.audioRoute,
            audioSession: payload.audioSession,
            volume: payload.volume,
            environment: StudyNo1EnvironmentSPLContext(
                thresholdDBA: 45,
                requiredContiguousSamples: 5,
                samplingInterval: 1.0,
                sensitivityOffsetDB: nil,
                samplesDBA: [],
                gateResult: .failed
            ),
            fitSeal: StudyNo1FitSealContext(
                status: .unavailable,
                confirmedAt: nil,
                limitations: "Participant did not confirm fit/seal."
            ),
            safety: StudyNo1SafetyContext(
                acknowledgedAt: nil,
                stopControlVisibleBeforePlayback: false,
                maximumLevelDBHL: 100,
                limitation: "Not acknowledged."
            ),
            stimulus: payload.stimulus,
            threshold: payload.threshold,
            trials: payload.trials,
            summary: payload.summary,
            protocolEvents: payload.protocolEvents,
            playbackEvents: payload.playbackEvents,
            refusals: payload.refusals,
            limitations: payload.limitations
        )

        do {
            try payload.validateCompletedStudyNo1()
            Issue.record("Expected missing preflight metadata to fail validation")
        } catch StudyNo1PayloadValidationError.missingRequiredFields(let fields) {
            #expect(fields.contains("environment.samplesDBA"))
            #expect(fields.contains("safety.acknowledgedAt"))
            #expect(fields.contains("safety.stopControlVisibleBeforePlayback"))
            #expect(fields.contains("fitSeal.status"))
        }
    }

    @Test
    func builderRefusesUnavailableThresholdForStudyNo1Completion() {
        var engine = makeEngine()
        engine.selectLaterality(.left)
        engine.markThresholdUnavailable(reason: "Manual threshold not collected.")
        acceptCurrentTrial(&engine, adjustment: .louder, confidence: .high)
        acceptCurrentTrial(&engine, adjustment: .louder, confidence: .high)
        acceptCurrentTrial(&engine, adjustment: .louder, confidence: .high)

        guard case .completed(let summary) = engine.state else {
            Issue.record("Expected completed protocol fixture")
            return
        }

        do {
            _ = try StudyNo1LoudnessMatchPayloadBuilder().buildStudyNo1Payload(
                summary: summary,
                events: engine.events,
                preflight: preflightContext()
            )
            Issue.record("Expected Study No. 1 loudness-match builder to reject threshold-unavailable completion")
        } catch StudyNo1PayloadValidationError.incompleteStudyNo1(let reason) {
            #expect(reason.contains("threshold"))
        } catch {
            Issue.record("Unexpected error \(error)")
        }
    }

    @Test
    func completedStudyNo1ValidationRefusesManualThresholdSource() throws {
        let valid = try makeCompletedPayload()
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
            environment: valid.environment,
            fitSeal: valid.fitSeal,
            safety: valid.safety,
            stimulus: valid.stimulus,
            threshold: StudyNo1ThresholdContext(
                frequencyHz: valid.threshold.frequencyHz,
                levelDBHL: valid.threshold.levelDBHL,
                source: .measured,
                recordedAt: valid.threshold.recordedAt,
                limitation: "Legacy fixture."
            ),
            trials: valid.trials,
            summary: valid.summary,
            protocolEvents: valid.protocolEvents,
            playbackEvents: valid.playbackEvents,
            refusals: valid.refusals,
            limitations: valid.limitations
        )

        do {
            try invalid.validateCompletedStudyNo1()
            Issue.record("Expected completed Study No. 1 validation to reject manual thresholds")
        } catch StudyNo1PayloadValidationError.incompleteStudyNo1(let reason) {
            #expect(reason.contains("HealthKit audiogram"))
        }
    }

    @Test
    func builderRefusesNonStudyNo1Frequency() {
        var summary = TinnitusLoudnessMatchSummary(
            frequencyHz: 2_000,
            channel: .both,
            thresholdStatus: .measured(levelDBHL: 10),
            trials: [
                TinnitusLoudnessMatchTrial(
                    trialIndex: 1,
                    acceptedLevelDBHL: 15,
                    estimatedDBSPL: 29.11,
                    dbSL: 5,
                    confidence: .high,
                    acceptedAt: timestamp
                ),
                TinnitusLoudnessMatchTrial(
                    trialIndex: 2,
                    acceptedLevelDBHL: 16,
                    estimatedDBSPL: 30.11,
                    dbSL: 6,
                    confidence: .high,
                    acceptedAt: timestamp
                ),
                TinnitusLoudnessMatchTrial(
                    trialIndex: 3,
                    acceptedLevelDBHL: 17,
                    estimatedDBSPL: 31.11,
                    dbSL: 7,
                    confidence: .high,
                    acceptedAt: timestamp
                )
            ],
            medianMatchedDBHL: 16,
            medianEstimatedDBSPL: 30.11,
            medianDBSL: 6,
            withinSessionSpreadDB: 2,
            qualityFlags: [],
            completedAt: timestamp
        )
        _ = summary

        do {
            _ = try StudyNo1LoudnessMatchPayloadBuilder().buildStudyNo1Payload(
                summary: summary,
                events: [],
                preflight: preflightContext()
            )
            Issue.record("Expected non-1000 Hz summary to be rejected")
        } catch StudyNo1PayloadValidationError.incompleteStudyNo1(let reason) {
            #expect(reason.contains("1000"))
        } catch {
            Issue.record("Unexpected error \(error)")
        }
    }

    private func makeCompletedPayload() throws -> StudyNo1LoudnessMatchRunPayload {
        var engine = makeEngine()
        engine.selectLaterality(.left)
        engine.recordThreshold(levelDBHL: 10)

        playAndStop(&engine)
        acceptCurrentTrial(&engine, adjustment: .louder, confidence: .high)
        playAndStop(&engine)
        acceptCurrentTrial(&engine, adjustment: .softer, confidence: .medium)
        playAndStop(&engine)
        acceptCurrentTrial(&engine, adjustment: .muchLouder, confidence: .low)

        guard case .completed(let summary) = engine.state else {
            throw StudyNo1PayloadValidationError.incompleteStudyNo1(reason: "Expected completed test fixture.")
        }

        return try StudyNo1LoudnessMatchPayloadBuilder().buildStudyNo1Payload(
            summary: summary,
            events: engine.events,
            preflight: preflightContext()
        )
    }

    private func playAndStop(_ engine: inout TinnitusProtocolEngine) {
        let attempt = engine.playCurrentTone(guardrailValidation: passedGuardrails())
        engine.recordStop(playbackMetadata: attempt.plan?.metadata.started(at: timestamp).stopped(at: timestamp.addingTimeInterval(1)))
    }

    private func acceptCurrentTrial(
        _ engine: inout TinnitusProtocolEngine,
        adjustment: TinnitusLoudnessAdjustment,
        confidence: TinnitusConfidenceRating
    ) {
        engine.adjustLevel(adjustment)
        engine.acceptCurrentLevel()
        engine.recordConfidence(confidence)
    }

    private func makeEngine() -> TinnitusProtocolEngine {
        TinnitusProtocolEngine(
            playbackPlanner: CalibratedTonePlaybackPlanner(dateProvider: { timestamp }),
            dateProvider: { timestamp }
        )
    }

    private func preflightContext() -> StudyNo1PreflightContext {
        StudyNo1PreflightContext(
            identifiers: StudyNo1IdentifierContext(
                participantId: participantID.uuidString,
                studySessionId: "study-session-1",
                enrollmentId: enrollmentID.uuidString,
                scheduledTaskId: scheduledTaskID.uuidString
            ),
            startedAt: timestamp,
            submittedAt: timestamp.addingTimeInterval(60),
            guardrailValidation: passedGuardrails(),
            device: StudyNo1DeviceContext(
                deviceModel: "iPhone17,2",
                systemName: "iOS",
                systemVersion: "26.0"
            ),
            airPods: StudyNo1AirPodsContext(
                modelIdentifier: "AIRPODSPROV2",
                firmwareVersion: nil,
                unavailableReason: "Firmware unavailable through public iOS route APIs."
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
                samplingInterval: 1.0,
                sensitivityOffsetDB: -23.3,
                samplesDBA: [34.0, 35.0, 36.0, 37.0, 38.0],
                gateResult: .passed
            ),
            fitSeal: StudyNo1FitSealContext(
                status: .confirmedPassed,
                confirmedAt: timestamp,
                limitations: "Participant confirmed fit/seal; public API does not expose Apple Ear Tip Fit Test result."
            ),
            safety: StudyNo1SafetyContext(
                acknowledgedAt: timestamp,
                stopControlVisibleBeforePlayback: true,
                maximumLevelDBHL: 100,
                limitation: "Immediate stop is available; no diagnostic claim."
            ),
            thresholdSource: .healthKitAudiogram
        )
    }

    private func passedGuardrails() -> CalibratedAudioGuardrailValidation {
        CalibratedAudioGuardrailPolicy().validate(
            route: supportedRoute(),
            outputVolume: 1.0,
            timestamp: timestamp
        )
    }

    private func supportedRoute() -> CalibratedAudioRouteDetails {
        CalibratedAudioRouteDetails(outputs: [
            CalibratedAudioRouteOutput(
                portName: "Verified AirPods Pro 2",
                portType: .bluetoothA2DP,
                portUID: "verified-airpods-pro-2",
                channelNames: ["left", "right"],
                verifiedCalibratedHeadphoneIdentifier: "AIRPODSPROV2",
                verificationSource: .appCalibrationProfile
            )
        ])
    }

    private let participantID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let enrollmentID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private let scheduledTaskID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
}
