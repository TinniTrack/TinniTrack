import Foundation
import Testing
@testable import TinniTrack

@MainActor
struct LoudnessMatchTaskFlowViewModelTests {
    private let timestamp = Date(timeIntervalSince1970: 1_800_020_000)

    @Test
    func defaultParticipantWorkflowKeepsPlaybackDisabled() {
        let player = MockCalibratedTonePlayer()
        let viewModel = LoudnessMatchTaskFlowViewModel(
            player: player,
            guardrailProvider: { passedGuardrails() },
            allowsCalibratedPlayback: false
        )
        viewModel.selectLaterality(.left)
        viewModel.thresholdLevelText = "10"
        viewModel.recordThresholdFromInput()

        viewModel.playTone()

        #expect(viewModel.message == .playbackDisabled)
        #expect(player.playedRequests.isEmpty)
        #expect(viewModel.isPlaying == false)
    }

    @Test
    func enabledTestHarnessBuildsPlaybackRequestThroughViewModelActions() throws {
        let player = MockCalibratedTonePlayer()
        let viewModel = LoudnessMatchTaskFlowViewModel(
            engine: makeEngine(),
            player: player,
            guardrailProvider: { passedGuardrails() },
            allowsCalibratedPlayback: true
        )

        viewModel.selectLaterality(.right)
        viewModel.thresholdLevelText = "10"
        viewModel.recordThresholdFromInput()
        viewModel.adjustLevel(.louder)
        viewModel.playTone()

        let request = try #require(player.playedRequests.first)
        #expect(request.frequencyHz == 1_000)
        #expect(request.levelDBHL == 16)
        #expect(request.channel == .right)
        #expect(viewModel.isPlaying)
        #expect(viewModel.events.contains { $0.kind == .playbackPlanned })

        viewModel.stopTone()

        #expect(player.stopCallCount == 1)
        #expect(viewModel.isPlaying == false)
        #expect(viewModel.events.last?.kind == .stopRequested)
    }

    @Test
    func viewModelCompletesThreeTrialsAndExposesSummary() {
        let viewModel = LoudnessMatchTaskFlowViewModel(
            engine: makeEngine(),
            guardrailProvider: { passedGuardrails() },
            allowsCalibratedPlayback: true
        )
        viewModel.selectLaterality(.left)
        viewModel.thresholdLevelText = "10"
        viewModel.recordThresholdFromInput()

        acceptCurrentTrial(viewModel, adjustment: .louder, confidence: .high)
        acceptCurrentTrial(viewModel, adjustment: .softer, confidence: .medium)
        acceptCurrentTrial(viewModel, adjustment: .muchLouder, confidence: .low)

        #expect(viewModel.isComplete)
        #expect(viewModel.completedSummary?.trials.map(\.acceptedLevelDBHL) == [16, 14, 20])
        #expect(viewModel.completedSummary?.medianMatchedDBHL == 16)
        #expect(viewModel.completedSummary?.qualityFlags.contains(.lowConfidence) == true)
    }

    @Test
    func invalidThresholdInputDoesNotAdvanceProtocol() {
        let viewModel = LoudnessMatchTaskFlowViewModel()
        viewModel.selectLaterality(.left)
        viewModel.thresholdLevelText = "abc"

        viewModel.recordThresholdFromInput()

        #expect(viewModel.message == .invalidThreshold)
        guard case .awaitingThreshold = viewModel.protocolState else {
            Issue.record("Expected threshold state")
            return
        }
    }

    @Test
    func failedGuardrailsRefusePlaybackAndRequireRestart() {
        let failed = CalibratedAudioGuardrailPolicy().validate(
            route: CalibratedAudioRouteDetails(outputs: []),
            outputVolume: 1.0,
            timestamp: timestamp
        )
        let viewModel = LoudnessMatchTaskFlowViewModel(
            engine: makeEngine(),
            player: MockCalibratedTonePlayer(),
            guardrailProvider: { failed },
            allowsCalibratedPlayback: true
        )
        viewModel.selectLaterality(.left)
        viewModel.thresholdLevelText = "10"
        viewModel.recordThresholdFromInput()

        viewModel.playTone()

        #expect(viewModel.message == .guardrailsUnavailable)
        guard case .restartRequired = viewModel.protocolState else {
            Issue.record("Expected restart-required state")
            return
        }
        #expect(viewModel.events.last?.kind == .playbackRefused)
    }

    @Test
    func thresholdUnavailablePathPreservesQualityFlags() {
        let viewModel = LoudnessMatchTaskFlowViewModel(engine: makeEngine())
        viewModel.selectLaterality(.unclear)
        viewModel.markThresholdUnavailable()

        acceptCurrentTrial(viewModel, adjustment: .louder, confidence: .high)
        acceptCurrentTrial(viewModel, adjustment: .louder, confidence: .high)
        acceptCurrentTrial(viewModel, adjustment: .louder, confidence: .high)

        #expect(viewModel.completedSummary?.medianDBSL == nil)
        #expect(viewModel.completedSummary?.qualityFlags.contains(.thresholdUnavailable) == true)
        #expect(viewModel.completedSummary?.qualityFlags.contains(.dbSLInvalid) == true)
        #expect(viewModel.completedSummary?.qualityFlags.contains(.ambiguousLaterality) == true)
    }

    private func acceptCurrentTrial(
        _ viewModel: LoudnessMatchTaskFlowViewModel,
        adjustment: TinnitusLoudnessAdjustment,
        confidence: TinnitusConfidenceRating
    ) {
        viewModel.adjustLevel(adjustment)
        viewModel.acceptCurrentLevel()
        viewModel.recordConfidence(confidence)
    }

    private func makeEngine() -> TinnitusProtocolEngine {
        TinnitusProtocolEngine(
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
}

@MainActor
private final class MockCalibratedTonePlayer: CalibratedTonePlaying {
    var playedRequests: [CalibratedTonePlaybackRequest] = []
    var stopCallCount = 0

    func play(_ request: CalibratedTonePlaybackRequest) throws -> CalibratedTonePlaybackMetadata {
        playedRequests.append(request)
        return try CalibratedTonePlaybackPlanner(dateProvider: {
            Date(timeIntervalSince1970: 1_800_020_000)
        })
        .makePlan(for: request)
        .metadata
        .started(at: Date(timeIntervalSince1970: 1_800_020_001))
    }

    func stop() -> CalibratedTonePlaybackMetadata? {
        stopCallCount += 1
        guard let request = playedRequests.last else {
            return nil
        }
        return try? CalibratedTonePlaybackPlanner(dateProvider: {
            Date(timeIntervalSince1970: 1_800_020_000)
        })
        .makePlan(for: request)
        .metadata
        .started(at: Date(timeIntervalSince1970: 1_800_020_001))
        .stopped(at: Date(timeIntervalSince1970: 1_800_020_002))
    }
}
