import Foundation
import Testing
@testable import TinniTrack

struct TinnitusProtocolEngineTests {
    private let timestamp = Date(timeIntervalSince1970: 1_800_010_000)

    @Test
    func studyNo1FixedFrequencyUsesBinauralPlaybackAndBuildsPlaybackPlan() throws {
        var engine = makeEngine()

        engine.selectLaterality(.left)
        engine.recordThreshold(levelDBHL: 10)

        #expect(engine.frequencyHz == 1_000)
        #expect(engine.currentCandidateLevelDBHL == 15)

        let attempt = engine.playCurrentTone(guardrailValidation: passedGuardrails())

        #expect(attempt.refusalReason == nil)
        #expect(attempt.request?.frequencyHz == 1_000)
        #expect(attempt.request?.levelDBHL == 15)
        #expect(attempt.request?.channel == .both)
        #expect(attempt.request?.stopsAfterDuration == false)
        #expect(attempt.plan?.metadata.requestedDBHL == 15)
        #expect(abs((attempt.plan?.metadata.targetDBSPL ?? 0) - 24.27) < 0.000_001)

        let planned = try #require(engine.events.last { $0.kind == .playbackPlanned })
        #expect(planned.presentedLevelDBHL == 15)
        #expect(planned.dbSL == 5)
        #expect(planned.guardrailMetadata?.validationState == .passed)
        #expect(planned.playbackMetadata?.channel == .both)
    }

    @Test
    func lateralitySelectionIsRecordedWithoutChangingPlaybackChannel() {
        for laterality in TinnitusLaterality.allCases {
            var engine = makeEngine()
            engine.selectLaterality(laterality)

            #expect(engine.channel == .both)
            #expect(engine.events.contains {
                $0.kind == .lateralitySelected
                    && $0.laterality == laterality
                    && $0.channel == .both
                    && $0.response == nil
            })
        }
    }

    @Test
    func repeatedTrialsComputeMedianSpreadDBSLAndConfidenceQuality() {
        var engine = makeEngine()
        engine.selectLaterality(.left)
        engine.recordThreshold(levelDBHL: 10)

        acceptCurrentTrial(&engine, adjustments: [.muchLouder], confidence: .high)
        acceptCurrentTrial(&engine, adjustments: [.louder, .louder], confidence: .low)
        acceptCurrentTrial(&engine, adjustments: [.softer], confidence: .medium)

        guard case .completed(let summary) = engine.state else {
            Issue.record("Expected completed state")
            return
        }

        #expect(summary.trials.map(\.acceptedLevelDBHL) == [20, 17, 14])
        #expect(summary.medianMatchedDBHL == 17)
        #expect(summary.medianEstimatedDBSPL == 26.27)
        #expect(summary.medianDBSL == 7)
        #expect(summary.withinSessionSpreadDB == 6)
        #expect(summary.qualityFlags.contains(.lowConfidence))
        #expect(!summary.qualityFlags.contains(.highWithinSessionSpread))
    }

    @Test
    func unavailableThresholdKeepsDBSLInvalidAndUsesDocumentedFallbackStart() {
        var engine = makeEngine()
        engine.selectLaterality(.left)
        engine.markThresholdUnavailable(reason: "No threshold estimator is enabled in this build.")

        #expect(engine.currentCandidateLevelDBHL == 10)

        acceptCurrentTrial(&engine, adjustments: [], confidence: .high)
        acceptCurrentTrial(&engine, adjustments: [], confidence: .high)
        acceptCurrentTrial(&engine, adjustments: [], confidence: .high)

        guard case .completed(let summary) = engine.state else {
            Issue.record("Expected completed state")
            return
        }

        #expect(summary.thresholdStatus == .unavailable(reason: "No threshold estimator is enabled in this build."))
        #expect(summary.medianDBSL == nil)
        #expect(summary.qualityFlags.contains(.thresholdUnavailable))
        #expect(summary.qualityFlags.contains(.dbSLInvalid))

        let event = engine.events.first { $0.kind == .thresholdUnavailable }
        #expect(event?.reason == "No threshold estimator is enabled in this build.")
    }

    @Test
    func highWithinSessionSpreadIsFlagged() {
        var engine = makeEngine()
        engine.selectLaterality(.left)
        engine.recordThreshold(levelDBHL: 10)

        acceptCurrentTrial(&engine, adjustments: [], confidence: .high)
        acceptCurrentTrial(&engine, adjustments: [.muchLouder, .muchLouder, .muchLouder], confidence: .high)
        acceptCurrentTrial(&engine, adjustments: [.muchSofter], confidence: .high)

        guard case .completed(let summary) = engine.state else {
            Issue.record("Expected completed state")
            return
        }

        #expect(summary.trials.map(\.acceptedLevelDBHL) == [15, 30, 10])
        #expect(summary.withinSessionSpreadDB == 20)
        #expect(summary.qualityFlags.contains(.highWithinSessionSpread))
    }

    @Test
    func playbackRefusesMissingFailedAndRestartRequiredGuardrails() {
        var notEvaluatedEngine = engineReadyForPlayback()
        let notEvaluated = notEvaluatedEngine.playCurrentTone(
            guardrailValidation: CalibratedAudioGuardrailSession().validation
        )
        #expect(notEvaluated.refusalReason == .guardrailNotEvaluated)
        #expect(notEvaluatedEngine.events.last?.kind == .playbackRefused)
        guard case .restartRequired(.guardrailNotEvaluated) = notEvaluatedEngine.state else {
            Issue.record("Expected restart-required state")
            return
        }

        var failedEngine = engineReadyForPlayback()
        let failedValidation = CalibratedAudioGuardrailPolicy().validate(
            route: CalibratedAudioRouteDetails(outputs: []),
            outputVolume: 1.0,
            timestamp: timestamp
        )
        let failed = failedEngine.playCurrentTone(guardrailValidation: failedValidation)
        guard case .guardrailFailed = failed.refusalReason else {
            Issue.record("Expected guardrail failed refusal")
            return
        }
        #expect(failedEngine.events.last?.qualityFlags.contains(.guardrailFailed) == true)

        var restartEngine = engineReadyForPlayback()
        var session = CalibratedAudioGuardrailSession()
        _ = session.evaluate(route: supportedRoute(), outputVolume: 1.0, timestamp: timestamp)
        let restartValidation = session.routeDidChange(
            to: CalibratedAudioRouteDetails(outputs: [
                CalibratedAudioRouteOutput(portName: "Speaker", portType: .builtInSpeaker)
            ]),
            timestamp: timestamp
        )
        let restart = restartEngine.playCurrentTone(guardrailValidation: restartValidation)
        guard case .restartRequired = restart.refusalReason else {
            Issue.record("Expected restart-required refusal")
            return
        }
    }

    @Test
    func safetyAndUnsupportedFrequencyRefusalsAreLogged() {
        var clippingEngine = makeEngine(configuration: clippingConfiguration())
        clippingEngine.selectLaterality(.left)
        clippingEngine.recordThreshold(levelDBHL: 100)
        clippingEngine.adjustLevel(.muchLouder)

        let clipping = clippingEngine.playCurrentTone(guardrailValidation: passedGuardrails())

        guard case .safetyRefusal = clipping.refusalReason else {
            Issue.record("Expected safety refusal")
            return
        }
        #expect(clippingEngine.events.last?.qualityFlags.contains(.safetyLimitRefused) == true)

        var unsupportedEngine = makeEngine(configuration: unsupportedFrequencyConfiguration())
        unsupportedEngine.selectLaterality(.left)
        unsupportedEngine.recordThreshold(levelDBHL: 10)

        let unsupported = unsupportedEngine.playCurrentTone(guardrailValidation: passedGuardrails())

        #expect(unsupported.refusalReason == .unsupportedFrequency(999))
        #expect(unsupportedEngine.events.last?.qualityFlags.contains(.unsupportedFrequency) == true)
    }

    @Test
    func applyingGuardrailChangeRequiresRestartAndLogsMetadata() {
        var engine = engineReadyForPlayback()
        var session = CalibratedAudioGuardrailSession()
        _ = session.evaluate(route: supportedRoute(), outputVolume: 1.0, timestamp: timestamp)
        let validation = session.volumeDidChange(to: 0.9375, timestamp: timestamp.addingTimeInterval(1))

        engine.applyGuardrailValidation(validation)

        guard case .restartRequired(.restartRequired) = engine.state else {
            Issue.record("Expected restart-required state")
            return
        }

        let event = engine.events.last
        #expect(event?.kind == .guardrailChanged)
        #expect(event?.guardrailMetadata?.validationState == .restartRequired)
    }

    private func acceptCurrentTrial(
        _ engine: inout TinnitusProtocolEngine,
        adjustments: [TinnitusLoudnessAdjustment],
        confidence: TinnitusConfidenceRating
    ) {
        adjustments.forEach { engine.adjustLevel($0) }
        engine.acceptCurrentLevel()
        engine.recordConfidence(confidence)
    }

    private func engineReadyForPlayback() -> TinnitusProtocolEngine {
        var engine = makeEngine()
        engine.selectLaterality(.left)
        engine.recordThreshold(levelDBHL: 10)
        return engine
    }

    private func makeEngine(
        configuration: TinnitusProtocolConfiguration = .studyNo1FixedOneKilohertz
    ) -> TinnitusProtocolEngine {
        TinnitusProtocolEngine(
            configuration: configuration,
            playbackPlanner: CalibratedTonePlaybackPlanner(dateProvider: { timestamp }),
            dateProvider: { timestamp }
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

    private func clippingConfiguration() -> TinnitusProtocolConfiguration {
        TinnitusProtocolConfiguration(
            kind: .studyNo1FixedOneKilohertz,
            stimulusKind: .pureTone,
            frequencyHz: 1_000,
            requiredTrialCount: 3,
            toneDuration: 1.0,
            rampDuration: CalibratedTonePlaybackDefaults.rampDuration,
            thresholdStartOffsetDBSL: 5.0,
            conservativeFallbackStartDBHL: 10.0,
            minimumLevelDBHL: -10.0,
            maximumLevelDBHL: 110.0,
            highSpreadThresholdDB: 10.0,
            supportedPitchFrequenciesHz: CalibratedHeadphoneProfile.airPodsPro2.supportedFrequenciesHz
        )
    }

    private func unsupportedFrequencyConfiguration() -> TinnitusProtocolConfiguration {
        TinnitusProtocolConfiguration(
            kind: .studyNo2TablePitchMatched,
            stimulusKind: .pureTone,
            frequencyHz: 999,
            requiredTrialCount: 3,
            toneDuration: 1.0,
            rampDuration: CalibratedTonePlaybackDefaults.rampDuration,
            thresholdStartOffsetDBSL: 5.0,
            conservativeFallbackStartDBHL: 10.0,
            minimumLevelDBHL: -10.0,
            maximumLevelDBHL: 100.0,
            highSpreadThresholdDB: 10.0,
            supportedPitchFrequenciesHz: CalibratedHeadphoneProfile.airPodsPro2.supportedFrequenciesHz
        )
    }
}
