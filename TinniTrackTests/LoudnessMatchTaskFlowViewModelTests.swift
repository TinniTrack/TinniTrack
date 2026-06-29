import AVFoundation
import Foundation
import Testing
@testable import TinniTrack

@MainActor
struct LoudnessMatchTaskFlowViewModelTests {
    private let timestamp = Date(timeIntervalSince1970: 1_800_020_000)

    @Test
    func defaultParticipantWorkflowBuildsPlaybackRequestAfterMeasuredPreflightAndThreshold() async throws {
        let player = MockCalibratedTonePlayer()
        let viewModel = LoudnessMatchTaskFlowViewModel(
            engine: makeEngine(),
            player: player,
            guardrailProvider: { passedGuardrails() },
            environmentMeter: MockEnvironmentSPLMeter(samplesDBA: [31, 32, 33, 34, 35]),
            audiogramRepository: MockAudiogramRepository(
                audiogram: sampleAudiogram(leftThreshold: 10, rightThreshold: 10)
            )
        )

        await completePreflight(viewModel)
        await completeAudiogramThreshold(viewModel, laterality: .right)
        viewModel.adjustLevel(.louder)
        viewModel.playTone()

        let request = try #require(player.playedRequests.last)
        #expect(request.frequencyHz == 1_000)
        #expect(request.levelDBHL == 46)
        #expect(request.channel == .both)
        #expect(request.duration == 2.0)
        #expect(request.stopsAfterDuration == false)
        #expect(viewModel.isPlaying)
        #expect(viewModel.events.contains { $0.kind == .playbackPlanned })

        let stopCountBeforeLoudnessStop = player.stopCallCount
        viewModel.stopTone()

        #expect(player.stopCallCount == stopCountBeforeLoudnessStop + 1)
        #expect(viewModel.isPlaying == false)
        #expect(viewModel.events.last?.kind == .stopRequested)
    }

    @Test
    func tonePlaybackStartsOnceAndStaysOnUntilStopped() async throws {
        let player = MockCalibratedTonePlayer()
        let viewModel = LoudnessMatchTaskFlowViewModel(
            engine: makeEngine(),
            player: player,
            guardrailProvider: { passedGuardrails() },
            environmentMeter: MockEnvironmentSPLMeter(samplesDBA: [31, 32, 33, 34, 35]),
            audiogramRepository: MockAudiogramRepository(
                audiogram: sampleAudiogram(leftThreshold: 10, rightThreshold: 20)
            )
        )

        await completePreflight(viewModel)
        await completeAudiogramThreshold(viewModel, laterality: .left)
        viewModel.playTone()

        let request = try #require(player.playedRequests.last)
        #expect(request.channel == .both)
        #expect(request.levelDBHL == 45)
        #expect(player.playedRequests.count == 1)
        #expect(viewModel.isPlaying)

        try await Task.sleep(nanoseconds: 1_200_000_000)
        #expect(player.playedRequests.count == 1)
        #expect(viewModel.isPlaying)

        viewModel.stopTone()
        #expect(viewModel.isPlaying == false)
    }

    @Test
    func adjustingLevelWhilePlayingRefreshesCalibratedPlaybackLevel() async throws {
        let player = MockCalibratedTonePlayer()
        let viewModel = LoudnessMatchTaskFlowViewModel(
            engine: makeEngine(),
            player: player,
            guardrailProvider: { passedGuardrails() },
            environmentMeter: MockEnvironmentSPLMeter(samplesDBA: [31, 32, 33, 34, 35]),
            audiogramRepository: MockAudiogramRepository(
                audiogram: sampleAudiogram(leftThreshold: 10, rightThreshold: 20)
            )
        )

        await completePreflight(viewModel)
        await completeAudiogramThreshold(viewModel, laterality: .left)
        viewModel.playTone()
        #expect(player.playedRequests.map(\.levelDBHL) == [45])

        viewModel.adjustLevel(.louder)

        #expect(player.playedRequests.map(\.levelDBHL) == [45, 46])
        #expect(player.playedRequests.allSatisfy { $0.channel == .both })
        #expect(player.playedRequests.allSatisfy { $0.stopsAfterDuration == false })
        #expect(viewModel.currentCandidateLevelDBHL == 46)
        #expect(viewModel.isPlaying)

        viewModel.stopTone()
    }

    @Test
    func lateralitySelectionResolvesHealthKitAudiogramThresholdAndStartsFirstTrial() async throws {
        let player = MockCalibratedTonePlayer()
        let viewModel = LoudnessMatchTaskFlowViewModel(
            engine: makeEngine(),
            player: player,
            guardrailProvider: { passedGuardrails() },
            environmentMeter: MockEnvironmentSPLMeter(samplesDBA: [31, 32, 33, 34, 35]),
            audiogramRepository: MockAudiogramRepository(
                audiogram: sampleAudiogram(leftThreshold: 12, rightThreshold: 22)
            )
        )

        await completePreflight(viewModel)
        await viewModel.selectLaterality(.left)

        guard case .readyForTrial(_, let candidateLevel) = viewModel.protocolState else {
            Issue.record("Expected loudness trial after HealthKit audiogram threshold")
            return
        }
        #expect(candidateLevel == 45)
        #expect(viewModel.completedSummary == nil)
        #expect(player.playedRequests.isEmpty)
        #expect(viewModel.events.contains {
            $0.kind == .thresholdRecorded
                && $0.presentedLevelDBHL == 17
                && $0.response == "healthkit_audiogram"
        })
        #expect(viewModel.events.contains { $0.kind == .thresholdPlaybackPlanned } == false)
    }

    @Test
    func startLoudnessMatchResolvesThresholdOnlyWhenParticipantStartsTest() async throws {
        let viewModel = LoudnessMatchTaskFlowViewModel(
            engine: makeEngine(),
            guardrailProvider: { passedGuardrails() },
            environmentMeter: MockEnvironmentSPLMeter(samplesDBA: [31, 32, 33, 34, 35]),
            audiogramRepository: MockAudiogramRepository(
                audiogram: sampleAudiogram(leftThreshold: 12, rightThreshold: 22)
            )
        )

        await completePreflight(viewModel)
        #expect(viewModel.selectedLaterality == nil)
        #expect(viewModel.events.contains { $0.kind == .lateralitySelected } == false)

        let didStart = await viewModel.startLoudnessMatch(laterality: .right)

        #expect(didStart)
        #expect(viewModel.selectedLaterality == .right)
        guard case .readyForTrial(_, let candidateLevel) = viewModel.protocolState else {
            Issue.record("Expected first loudness trial after pressing Start Test")
            return
        }
        #expect(candidateLevel == 45)
        #expect(viewModel.events.contains { $0.kind == .lateralitySelected && $0.laterality == .right })
        #expect(viewModel.events.contains { $0.kind == .thresholdRecorded && $0.response == "healthkit_audiogram" })
    }

    @Test
    func viewModelCompletesThreeTrialsAndExposesSummary() async {
        let viewModel = LoudnessMatchTaskFlowViewModel(
            engine: makeEngine(),
            guardrailProvider: { passedGuardrails() },
            environmentMeter: MockEnvironmentSPLMeter(samplesDBA: [31, 32, 33, 34, 35]),
            audiogramRepository: MockAudiogramRepository(
                audiogram: sampleAudiogram(leftThreshold: 10, rightThreshold: 20)
            )
        )
        await completePreflight(viewModel)
        await completeAudiogramThreshold(viewModel, laterality: .left)

        acceptCurrentTrial(viewModel, adjustment: .louder, confidence: .high)
        acceptCurrentTrial(viewModel, adjustment: .softer, confidence: .medium)
        acceptCurrentTrial(viewModel, adjustment: .muchLouder, confidence: .low)

        #expect(viewModel.isComplete)
        #expect(viewModel.completedSummary?.trials.map(\.acceptedLevelDBHL) == [46, 44, 50])
        #expect(viewModel.completedSummary?.medianMatchedDBHL == 46)
        #expect(viewModel.completedSummary?.qualityFlags.contains(.lowConfidence) == true)
    }

    @Test
    func failedGuardrailsRefusePlaybackAndKeepPreflightLocked() async {
        let failed = CalibratedAudioGuardrailPolicy().validate(
            route: CalibratedAudioRouteDetails(outputs: []),
            outputVolume: 1.0,
            timestamp: timestamp
        )
        let viewModel = LoudnessMatchTaskFlowViewModel(
            engine: makeEngine(),
            player: MockCalibratedTonePlayer(),
            guardrailProvider: { failed },
            environmentMeter: MockEnvironmentSPLMeter(samplesDBA: [31, 32, 33, 34, 35]),
            audiogramRepository: MockAudiogramRepository(
                audiogram: sampleAudiogram(leftThreshold: 10, rightThreshold: 20)
            )
        )
        await completePreflight(viewModel)
        await viewModel.selectLaterality(.left)

        viewModel.playTone()

        guard case .missingPreflight = viewModel.message else {
            Issue.record("Expected missing preflight because guardrails failed")
            return
        }
    }

    @Test
    func guardedPlaybackRequiresFullPreflight() async {
        let player = MockCalibratedTonePlayer()
        let viewModel = LoudnessMatchTaskFlowViewModel(
            engine: makeEngine(),
            player: player,
            guardrailProvider: { passedGuardrails() },
            environmentMeter: MockEnvironmentSPLMeter(samplesDBA: [31, 32, 33, 34, 35]),
            audiogramRepository: MockAudiogramRepository(
                audiogram: sampleAudiogram(leftThreshold: 10, rightThreshold: 20)
            )
        )
        await viewModel.selectLaterality(.left)

        viewModel.playTone()

        guard case .missingPreflight = viewModel.message else {
            Issue.record("Expected missing preflight message")
            return
        }
        #expect(player.playedRequests.isEmpty)
    }

    @Test
    func preflightUsesEnvironmentGateResult() async {
        let passing = LoudnessMatchTaskFlowViewModel(
            engine: makeEngine(),
            guardrailProvider: { passedGuardrails() },
            environmentMeter: MockEnvironmentSPLMeter(samplesDBA: [31, 32, 33, 34, 35])
        )
        await completePreflight(passing)
        #expect(passing.preflightReady)
        #expect(passing.environmentGateResult?.gateResult == .passed)

        let failing = LoudnessMatchTaskFlowViewModel(
            engine: makeEngine(),
            guardrailProvider: { passedGuardrails() },
            environmentMeter: MockEnvironmentSPLMeter(samplesDBA: [31, 46, 33, 47, 34])
        )
        failing.fitSealConfirmed = true
        failing.safetyAcknowledged = true
        failing.refreshGuardrails()
        await failing.runEnvironmentGate()

        #expect(failing.preflightReady == false)
        #expect(failing.message == .environmentGateFailed)
    }

    @Test
    func continuousEnvironmentGateStreamsTooLoudThenPasses() async throws {
        let viewModel = LoudnessMatchTaskFlowViewModel(
            engine: makeEngine(),
            guardrailProvider: { passedGuardrails() },
            environmentMeter: MockEnvironmentSPLMeter(samplesDBA: []),
            environmentGateMonitor: MockEnvironmentSPLGateMonitor(samplesByUpdate: [
                [44],
                [44, 46],
                [44, 46, 40, 41, 42, 43, 44]
            ])
        )

        viewModel.startContinuousEnvironmentGate()
        #expect(try await waitUntil {
            viewModel.isRunningEnvironmentGate == false
                && viewModel.environmentGateResult?.passed == true
        })

        #expect(viewModel.isRunningEnvironmentGate == false)
        #expect(viewModel.environmentGateUpdate?.status == .passed)
        #expect(viewModel.environmentGateResult?.passed == true)
        #expect(viewModel.environmentGateResult?.samplesDBA == [44, 46, 40, 41, 42, 43, 44])
        #expect(viewModel.hasPassedEnvironmentGate)
    }

    @Test
    func continuousEnvironmentGateKeepsRunningAfterPassingUpdate() async throws {
        let viewModel = LoudnessMatchTaskFlowViewModel(
            engine: makeEngine(),
            guardrailProvider: { passedGuardrails() },
            environmentMeter: MockEnvironmentSPLMeter(samplesDBA: []),
            environmentGateMonitor: MockEnvironmentSPLGateMonitor(
                samplesByUpdate: [[40, 41, 42, 43, 44]],
                finishAfterUpdates: false
            )
        )

        viewModel.startContinuousEnvironmentGate()
        #expect(try await waitUntil {
            viewModel.isRunningEnvironmentGate
                && viewModel.environmentGateResult?.passed == true
        })

        #expect(viewModel.isRunningEnvironmentGate)
        #expect(viewModel.environmentGateResult?.passed == true)
        #expect(viewModel.hasPassedEnvironmentGate)
        viewModel.cancelEnvironmentGate()
    }

    @Test
    func preparingQuietRoomStepClearsPreviousGatePassImmediately() async throws {
        let viewModel = LoudnessMatchTaskFlowViewModel(
            engine: makeEngine(),
            guardrailProvider: { passedGuardrails() },
            environmentMeter: MockEnvironmentSPLMeter(samplesDBA: []),
            environmentGateMonitor: MockEnvironmentSPLGateMonitor(
                samplesByUpdate: [[40, 41, 42, 43, 44]],
                finishAfterUpdates: false
            )
        )

        viewModel.startContinuousEnvironmentGate()
        #expect(try await waitUntil {
            viewModel.environmentGateResult?.passed == true
        })

        viewModel.prepareEnvironmentGateForQuietRoomStep()

        #expect(viewModel.environmentGateResult == nil)
        #expect(viewModel.environmentGateUpdate?.status == .measuring)
        #expect(viewModel.environmentGateUpdate?.contiguousPassingSamples == 0)
        #expect(viewModel.hasPassedEnvironmentGate == false)
        #expect(viewModel.isRunningEnvironmentGate == false)
    }

    @Test
    func continuousEnvironmentGateClearsCurrentPassWhenRoomGetsLoudAgain() async throws {
        let viewModel = LoudnessMatchTaskFlowViewModel(
            engine: makeEngine(),
            guardrailProvider: { passedGuardrails() },
            environmentMeter: MockEnvironmentSPLMeter(samplesDBA: []),
            environmentGateMonitor: MockEnvironmentSPLGateMonitor(
                samplesByUpdate: [
                    [40, 41, 42, 43, 44],
                    [40, 41, 42, 43, 44, 50]
                ],
                finishAfterUpdates: false
            )
        )

        viewModel.startContinuousEnvironmentGate()
        #expect(try await waitUntil {
            viewModel.environmentGateUpdate?.status == .tooLoud
                && viewModel.hasPassedEnvironmentGate
        })

        #expect(viewModel.hasPassedEnvironmentGate)
        #expect(viewModel.environmentGateUpdate?.status == .tooLoud)
        #expect(viewModel.environmentGateResult == nil)
        #expect(viewModel.isEnvironmentQuietnessInterrupted)
        viewModel.cancelEnvironmentGate()
    }

    @Test
    func continuousEnvironmentGateCancellationDoesNotSetResult() async throws {
        let viewModel = LoudnessMatchTaskFlowViewModel(
            engine: makeEngine(),
            guardrailProvider: { passedGuardrails() },
            environmentMeter: MockEnvironmentSPLMeter(samplesDBA: []),
            environmentGateMonitor: MockEnvironmentSPLGateMonitor(samplesByUpdate: [[44]], finishAfterUpdates: false)
        )

        viewModel.startContinuousEnvironmentGate()
        try await Task.sleep(nanoseconds: 10_000_000)
        viewModel.cancelEnvironmentGate()

        #expect(viewModel.isRunningEnvironmentGate == false)
        #expect(viewModel.environmentGateResult == nil)
    }

    @Test
    func continuousEnvironmentGateKeepsMonitoringDuringPlaybackAndInterruptsWhenRoomGetsLoud() async throws {
        let player = MockCalibratedTonePlayer()
        let environmentGateMonitor = ControllableEnvironmentSPLGateMonitor()
        let viewModel = LoudnessMatchTaskFlowViewModel(
            engine: makeEngine(),
            player: player,
            guardrailProvider: { passedGuardrails() },
            environmentMeter: MockEnvironmentSPLMeter(samplesDBA: []),
            environmentGateMonitor: environmentGateMonitor,
            audiogramRepository: MockAudiogramRepository(
                audiogram: sampleAudiogram(leftThreshold: 10, rightThreshold: 20)
            )
        )

        viewModel.startContinuousEnvironmentGate()
        environmentGateMonitor.yield(samplesDBA: [40, 41, 42, 43, 44])
        #expect(try await waitUntil {
            viewModel.isRunningEnvironmentGate
                && viewModel.environmentGateResult?.passed == true
        })

        viewModel.fitSealConfirmed = true
        viewModel.safetyAcknowledged = true
        viewModel.refreshGuardrails()
        await completeAudiogramThreshold(viewModel, laterality: .left)
        viewModel.playTone()

        #expect(player.playedRequests.count == 1)
        #expect(viewModel.isPlaying)
        #expect(viewModel.isRunningEnvironmentGate)
        #expect(viewModel.environmentGateResult?.passed == true)
        #expect(viewModel.preflightReady)

        environmentGateMonitor.yield(samplesDBA: [40, 41, 42, 43, 44, 50])
        #expect(try await waitUntil {
            viewModel.isEnvironmentQuietnessInterrupted
                && viewModel.isPlaying == false
        })

        #expect(player.stopCallCount == 1)
        #expect(viewModel.environmentGateResult == nil)
        #expect(viewModel.preflightReady == false)
        #expect(viewModel.canPlayTone == false)
        viewModel.cancelEnvironmentGate()
    }

    @Test
    func startTestRequiresPassedVolumeGuardrails() async {
        var validation = CalibratedAudioGuardrailPolicy().validate(
            route: supportedRoute(),
            outputVolume: 0.5,
            timestamp: timestamp
        )
        let viewModel = LoudnessMatchTaskFlowViewModel(
            engine: makeEngine(),
            guardrailProvider: { validation },
            environmentMeter: MockEnvironmentSPLMeter(samplesDBA: [31, 32, 33, 34, 35])
        )
        viewModel.completeFitConfirmation()
        await viewModel.runEnvironmentGate()

        #expect(viewModel.acknowledgeSafetyAndStartTest() == false)
        #expect(viewModel.preflightReady == false)

        validation = passedGuardrails()
        #expect(viewModel.acknowledgeSafetyAndStartTest())
        #expect(viewModel.preflightReady)
        #expect(viewModel.safetyAcknowledged)
    }

    @Test
    func correctEarGateShowsMissingAirPodsMessageWhenNoRouteIsAvailable() {
        let routeProvider = MockAudioSessionRouteVolumeProvider(outputs: [], outputVolume: 1.0)
        let viewModel = LoudnessMatchTaskFlowViewModel(
            engine: makeEngine(),
            guardrailProvider: { CalibratedAudioGuardrailSession().validation },
            headphoneRouteProvider: routeProvider,
            environmentMeter: MockEnvironmentSPLMeter(samplesDBA: [31, 32, 33, 34, 35])
        )

        #expect(viewModel.validateAirPodsForCorrectEarStep() == false)
        #expect(viewModel.message == .airPodsNotInEar)
        #expect(viewModel.headphoneRouteAssessment.primaryIssue == .noOutput)
    }

    @Test
    func correctEarGateShowsUnsupportedHeadphonesMessageForNonMatchingBluetoothPlaybackRoute() {
        let routeProvider = MockAudioSessionRouteVolumeProvider(
            outputs: [audioOutput(name: "Bluetooth Speaker", portType: .bluetoothA2DP)],
            outputVolume: 1.0
        )
        let viewModel = LoudnessMatchTaskFlowViewModel(
            engine: makeEngine(),
            guardrailProvider: { CalibratedAudioGuardrailSession().validation },
            headphoneRouteProvider: routeProvider,
            environmentMeter: MockEnvironmentSPLMeter(samplesDBA: [31, 32, 33, 34, 35])
        )

        #expect(viewModel.validateAirPodsForCorrectEarStep() == false)
        #expect(viewModel.message == .unsupportedHeadphones)
        #expect(viewModel.headphoneRouteAssessment.primaryIssue == .unsupportedBluetoothPlaybackDevice)
    }

    @Test
    func correctEarGatePassesForLikelyAirPodsPro2PlaybackRoute() {
        let routeProvider = MockAudioSessionRouteVolumeProvider(
            outputs: [audioOutput(name: "Vasyl's AirPods Pro 2", portType: .bluetoothA2DP)],
            outputVolume: 0.5
        )
        let viewModel = LoudnessMatchTaskFlowViewModel(
            engine: makeEngine(),
            guardrailProvider: { CalibratedAudioGuardrailSession().validation },
            headphoneRouteProvider: routeProvider,
            environmentMeter: MockEnvironmentSPLMeter(samplesDBA: [31, 32, 33, 34, 35])
        )

        #expect(viewModel.validateAirPodsForCorrectEarStep())
        #expect(viewModel.message == nil)
        #expect(viewModel.headphoneRouteAssessment.passesAirPodsPro2Heuristic)
    }

    @Test
    func correctEarGateBlocksAirPodsPro2HeadsetProfileDuringCall() {
        let routeProvider = MockAudioSessionRouteVolumeProvider(
            outputs: [audioOutput(name: "Vasyl's AirPods Pro 2", portType: .bluetoothHFP)],
            outputVolume: 1.0
        )
        let viewModel = LoudnessMatchTaskFlowViewModel(
            engine: makeEngine(),
            guardrailProvider: { CalibratedAudioGuardrailSession().validation },
            headphoneRouteProvider: routeProvider,
            environmentMeter: MockEnvironmentSPLMeter(samplesDBA: [31, 32, 33, 34, 35])
        )

        #expect(viewModel.validateAirPodsForCorrectEarStep() == false)
        #expect(viewModel.message == .calibratedPlaybackRouteUnavailable)
        #expect(viewModel.headphoneRouteAssessment.passesAirPodsPro2Heuristic)
        #expect(viewModel.headphoneRouteAssessment.passesAirPodsPro2PlaybackHeuristic == false)
    }

    @Test
    func headphoneRouteMonitoringUpdatesAssessmentAndStopsObservation() async {
        let routeProvider = MockAudioSessionRouteVolumeProvider(outputs: [], outputVolume: 1.0)
        let viewModel = LoudnessMatchTaskFlowViewModel(
            engine: makeEngine(),
            guardrailProvider: { CalibratedAudioGuardrailSession().validation },
            headphoneRouteProvider: routeProvider,
            environmentMeter: MockEnvironmentSPLMeter(samplesDBA: [31, 32, 33, 34, 35])
        )

        viewModel.startHeadphoneRouteMonitoring()
        #expect(viewModel.isHeadphoneRouteMonitoring)
        #expect(viewModel.headphoneRouteAssessment.primaryIssue == .noOutput)

        routeProvider.outputs = [audioOutput(name: "Vasyl's AirPods Pro 2", portType: .bluetoothA2DP)]
        routeProvider.triggerRouteChange()
        await Task.yield()
        #expect(viewModel.headphoneRouteAssessment.passesAirPodsPro2Heuristic)

        viewModel.stopHeadphoneRouteMonitoring()
        #expect(viewModel.isHeadphoneRouteMonitoring == false)
        #expect(routeProvider.routeObservation?.isInvalidated == true)
    }

    @Test
    func airPodsContinuityMonitoringPausesOnDisconnectAndClearsOnReconnect() async {
        let routeProvider = MockAudioSessionRouteVolumeProvider(
            outputs: [audioOutput(name: "Vasyl's AirPods Pro 2", portType: .bluetoothA2DP)],
            outputVolume: 1.0
        )
        let viewModel = LoudnessMatchTaskFlowViewModel(
            engine: makeEngine(),
            headphoneRouteProvider: routeProvider,
            environmentMeter: MockEnvironmentSPLMeter(samplesDBA: [31, 32, 33, 34, 35])
        )

        viewModel.startAirPodsContinuityMonitoring()
        #expect(viewModel.isAirPodsContinuityMonitoring)
        #expect(viewModel.isAirPodsRouteInterrupted == false)

        routeProvider.outputs = []
        routeProvider.triggerRouteChange()
        await Task.yield()
        #expect(viewModel.isAirPodsRouteInterrupted)
        #expect(viewModel.headphoneRouteAssessment.primaryIssue == .noOutput)

        routeProvider.outputs = [audioOutput(name: "Vasyl's AirPods Pro 2", portType: .bluetoothA2DP)]
        routeProvider.triggerRouteChange()
        await Task.yield()
        #expect(viewModel.isAirPodsRouteInterrupted == false)

        viewModel.stopAirPodsContinuityMonitoring()
        #expect(viewModel.isAirPodsContinuityMonitoring == false)
    }

    @Test
    func airPodsDisconnectDoesNotStopContinuousEnvironmentGate() async throws {
        let routeProvider = MockAudioSessionRouteVolumeProvider(
            outputs: [audioOutput(name: "Vasyl's AirPods Pro 2", portType: .bluetoothA2DP)],
            outputVolume: 1.0
        )
        let viewModel = LoudnessMatchTaskFlowViewModel(
            engine: makeEngine(),
            headphoneRouteProvider: routeProvider,
            environmentMeter: MockEnvironmentSPLMeter(samplesDBA: []),
            environmentGateMonitor: MockEnvironmentSPLGateMonitor(samplesByUpdate: [[34]], finishAfterUpdates: false)
        )

        viewModel.startAirPodsContinuityMonitoring()
        viewModel.startContinuousEnvironmentGate()
        #expect(try await waitUntil { viewModel.isRunningEnvironmentGate })

        routeProvider.outputs = []
        routeProvider.triggerRouteChange()
        await Task.yield()

        #expect(viewModel.isAirPodsRouteInterrupted)
        #expect(viewModel.isRunningEnvironmentGate)
        viewModel.cancelEnvironmentGate()
    }

    @Test
    func airPodsRouteChangeDuringQuietRoomGateDoesNotForcePlaybackRefreshLoop() async throws {
        let routeProvider = MockAudioSessionRouteVolumeProvider(
            outputs: [audioOutput(name: "Vasyl's AirPods Pro 2", portType: .bluetoothA2DP)],
            outputVolume: 1.0
        )
        let viewModel = LoudnessMatchTaskFlowViewModel(
            engine: makeEngine(),
            headphoneRouteProvider: routeProvider,
            environmentMeter: MockEnvironmentSPLMeter(samplesDBA: []),
            environmentGateMonitor: MockEnvironmentSPLGateMonitor(samplesByUpdate: [[34]], finishAfterUpdates: false)
        )

        viewModel.startAirPodsContinuityMonitoring()
        viewModel.startContinuousEnvironmentGate()
        #expect(try await waitUntil { viewModel.isRunningEnvironmentGate })
        let refreshCountBeforeRouteChange = routeProvider.refreshCallCount

        routeProvider.triggerRouteChange()
        await Task.yield()

        #expect(viewModel.isRunningEnvironmentGate)
        #expect(viewModel.isAirPodsRouteInterrupted == false)
        #expect(routeProvider.refreshCallCount == refreshCountBeforeRouteChange)
        viewModel.cancelEnvironmentGate()
    }

    @Test
    func airPodsHeadsetProfileDuringTaskPausesUntilPlaybackRouteReturns() async {
        let routeProvider = MockAudioSessionRouteVolumeProvider(
            outputs: [audioOutput(name: "Vasyl's AirPods Pro 2", portType: .bluetoothA2DP)],
            outputVolume: 1.0
        )
        let viewModel = LoudnessMatchTaskFlowViewModel(
            engine: makeEngine(),
            headphoneRouteProvider: routeProvider,
            environmentMeter: MockEnvironmentSPLMeter(samplesDBA: [31, 32, 33, 34, 35])
        )

        viewModel.startAirPodsContinuityMonitoring()
        #expect(viewModel.isAirPodsRouteInterrupted == false)

        routeProvider.outputs = [audioOutput(name: "Vasyl's AirPods Pro 2", portType: .bluetoothHFP)]
        routeProvider.triggerRouteChange()
        await Task.yield()

        #expect(viewModel.isAirPodsRouteInterrupted)
        #expect(viewModel.isAirPodsPlaybackRouteBlockedByAnotherApp)
        #expect(viewModel.headphoneRouteAssessment.passesAirPodsPro2Heuristic)
        #expect(viewModel.headphoneRouteAssessment.passesAirPodsPro2PlaybackHeuristic == false)

        routeProvider.outputs = [audioOutput(name: "Vasyl's AirPods Pro 2", portType: .bluetoothA2DP)]
        routeProvider.triggerRouteChange()
        await Task.yield()

        #expect(viewModel.isAirPodsRouteInterrupted == false)
        #expect(viewModel.isAirPodsPlaybackRouteBlockedByAnotherApp == false)
    }

    @Test
    func airPodsDisconnectDuringToneStopsPlaybackWithoutRestartingProtocol() async {
        let player = MockCalibratedTonePlayer()
        let routeProvider = MockAudioSessionRouteVolumeProvider(
            outputs: [audioOutput(name: "Vasyl's AirPods Pro 2", portType: .bluetoothA2DP)],
            outputVolume: 1.0
        )
        let viewModel = LoudnessMatchTaskFlowViewModel(
            engine: makeEngine(),
            player: player,
            headphoneRouteProvider: routeProvider,
            environmentMeter: MockEnvironmentSPLMeter(samplesDBA: [31, 32, 33, 34, 35]),
            audiogramRepository: MockAudiogramRepository(
                audiogram: sampleAudiogram(leftThreshold: 10, rightThreshold: 20)
            )
        )

        viewModel.startAirPodsContinuityMonitoring()
        await completePreflight(viewModel)
        await completeAudiogramThreshold(viewModel, laterality: .left)
        viewModel.playTone()
        #expect(viewModel.isPlaying)

        routeProvider.outputs = []
        routeProvider.triggerRouteChange()
        await Task.yield()

        #expect(viewModel.isAirPodsRouteInterrupted)
        #expect(viewModel.isPlaying == false)
        #expect(player.stopCallCount == 1)
        if case .restartRequired = viewModel.protocolState {
            Issue.record("AirPods route interruption should pause instead of requiring protocol restart.")
        }
    }

    @Test
    func completedStudyNo1BuildsPayloadWithHealthKitAudiogramThresholdAndPreflightMetadata() async throws {
        let viewModel = await completedViewModel()
        let payload = try viewModel.makeStudyNo1Payload(
            scheduledTask: scheduledTask(),
            enrollment: enrollment(),
            submittedAt: timestamp.addingTimeInterval(100)
        )

        #expect(payload.identifiers.enrollmentId == enrollment().id.uuidString)
        #expect(payload.identifiers.scheduledTaskId == scheduledTask().id.uuidString)
        #expect(payload.device.deviceModel == "iPhone17,2")
        #expect(payload.airPods.modelIdentifier == "AIRPODSPROV2")
        #expect(payload.environment.samplesDBA == [31, 32, 33, 34, 35])
        #expect(payload.environment.gateResult == .passed)
        #expect(payload.fitSeal.status == .confirmedPassed)
        #expect(payload.safety.acknowledgedAt != nil)
        #expect(payload.threshold.source == .healthKitAudiogram)
        #expect(payload.threshold.levelDBHL == 15)
        #expect(payload.summary.medianMatchedDBHL == 46)
    }

    @Test
    func submitCompletedRunUsesStudyServiceBoundary() async {
        let viewModel = await completedViewModel()
        let service = MockStudyService()
        let task = scheduledTask()
        let currentEnrollment = enrollment()

        await viewModel.submitCompletedRun(
            scheduledTask: task,
            enrollment: currentEnrollment,
            studyService: service
        )

        #expect(viewModel.hasSubmitted)
        #expect(service.submissions.count == 1)
        #expect(service.submissions.first?.scheduledTaskID == task.id)
        #expect(service.submissions.first?.enrollmentID == currentEnrollment.id)
        #expect(service.submissions.first?.submission.matchedLevel == 46)
        #expect(service.submissions.first?.submission.rawPayload["payloadVersion"] == .string("study-no-1-loudness-match-v2"))
    }

    @Test
    func missingAudiogramThresholdPreventsScheduledLoudnessTaskStart() async {
        let viewModel = LoudnessMatchTaskFlowViewModel(
            engine: makeEngine(),
            guardrailProvider: { passedGuardrails() },
            environmentMeter: MockEnvironmentSPLMeter(samplesDBA: [31, 32, 33, 34, 35]),
            audiogramRepository: MockAudiogramRepository(
                audiogram: sampleAudiogram(leftThreshold: nil, rightThreshold: 20)
            )
        )
        await completePreflight(viewModel)
        await viewModel.selectLaterality(.left)

        if case .missingAudiogramThreshold(let message) = viewModel.message {
            #expect(message.contains("both left and right ear thresholds"))
        } else {
            Issue.record("Expected missing audiogram threshold message")
        }
        #expect(viewModel.completedSummary == nil)
    }

    @Test
    func scheduledLoudnessTaskStartsFromAudiogramWithoutManualThresholdEvents() async throws {
        let viewModel = LoudnessMatchTaskFlowViewModel(
            engine: makeEngine(),
            guardrailProvider: { passedGuardrails() },
            environmentMeter: MockEnvironmentSPLMeter(samplesDBA: [31, 32, 33, 34, 35]),
            audiogramRepository: MockAudiogramRepository(
                audiogram: sampleAudiogram(leftThreshold: 10, rightThreshold: 20)
            )
        )

        await completePreflight(viewModel)
        await viewModel.selectLaterality(.right)

        guard case .readyForTrial(_, let candidateLevel) = viewModel.protocolState else {
            Issue.record("Expected scheduled loudness task to start trial after audiogram threshold resolution")
            return
        }

        #expect(candidateLevel == 45)
        #expect(viewModel.events.contains { $0.kind == .thresholdRecorded && $0.response == "healthkit_audiogram" })
        #expect(viewModel.events.contains { $0.kind == .thresholdToneRequested } == false)
        #expect(viewModel.events.contains { $0.kind == .thresholdPlaybackPlanned } == false)
    }

    @Test
    func orientationThresholdSubmissionUsesAppOwnedQuietRoomGate() async throws {
        let viewModel = LoudnessMatchTaskFlowViewModel(
            engine: makeEngine(),
            guardrailProvider: { passedGuardrails() },
            environmentMeter: MockEnvironmentSPLMeter(samplesDBA: [31, 32, 33, 34, 35]),
            runtimeContextProvider: MockStudyNo1RuntimeContextProvider(),
            orientationThresholdExporter: StudyNo1OrientationThresholdSubmissionExporter(appVersion: "1.2.3"),
            dateProvider: { timestamp }
        )
        await completePreflight(viewModel)

        let service = MockStudyService()
        let task = scheduledTask(dayIndex: -1, slotIndex: 0)
        let submitted = await viewModel.submitOrientationThreshold(
            result: orientationThresholdResult(),
            scheduledTask: task,
            enrollment: enrollment(),
            studyService: service
        )

        #expect(submitted)
        #expect(viewModel.hasSubmitted)
        #expect(service.orientationSubmissions.count == 1)
        #expect(service.orientationSubmissions.first?.scheduledTaskID == task.id)
        #expect(service.orientationSubmissions.first?.submission.gating["environment"] != nil)
        #expect(service.orientationSubmissions.first?.submission.rawPayload["environment"] != nil)
    }

    @Test
    func orientationThresholdSubmissionFailsWithoutAppQuietRoomGate() async {
        let viewModel = LoudnessMatchTaskFlowViewModel(
            engine: makeEngine(),
            guardrailProvider: { passedGuardrails() },
            environmentMeter: MockEnvironmentSPLMeter(samplesDBA: [31, 32, 33, 34, 35]),
            runtimeContextProvider: MockStudyNo1RuntimeContextProvider(),
            orientationThresholdExporter: StudyNo1OrientationThresholdSubmissionExporter(appVersion: "1.2.3"),
            dateProvider: { timestamp }
        )

        let service = MockStudyService()
        let submitted = await viewModel.submitOrientationThreshold(
            result: orientationThresholdResult(),
            scheduledTask: scheduledTask(dayIndex: -1, slotIndex: 0),
            enrollment: enrollment(),
            studyService: service
        )

        #expect(submitted == false)
        #expect(viewModel.hasSubmitted == false)
        #expect(service.orientationSubmissions.isEmpty)
        if case .incompletePayload(let message) = viewModel.message {
            #expect(message.contains("environment.samplesDBA"))
        } else {
            Issue.record("Expected missing app quiet-room gate payload error")
        }
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

    private func completePreflight(_ viewModel: LoudnessMatchTaskFlowViewModel) async {
        viewModel.fitSealConfirmed = true
        viewModel.safetyAcknowledged = true
        viewModel.refreshGuardrails()
        await viewModel.runEnvironmentGate()
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        condition: @escaping () -> Bool
    ) async throws -> Bool {
        let start = DispatchTime.now().uptimeNanoseconds
        while !condition() {
            if DispatchTime.now().uptimeNanoseconds - start >= timeoutNanoseconds {
                return false
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        return true
    }

    private func completeAudiogramThreshold(
        _ viewModel: LoudnessMatchTaskFlowViewModel,
        laterality: TinnitusLaterality
    ) async {
        await viewModel.selectLaterality(laterality)
    }

    private func completedViewModel() async -> LoudnessMatchTaskFlowViewModel {
        let viewModel = LoudnessMatchTaskFlowViewModel(
            engine: makeEngine(),
            guardrailProvider: { passedGuardrails() },
            environmentMeter: MockEnvironmentSPLMeter(samplesDBA: [31, 32, 33, 34, 35]),
            audiogramRepository: MockAudiogramRepository(
                audiogram: sampleAudiogram(leftThreshold: 10, rightThreshold: 20)
            ),
            runtimeContextProvider: MockStudyNo1RuntimeContextProvider(),
            submissionExporter: StudyNo1LoudnessMatchSubmissionExporter(appVersion: "1.2.3"),
            dateProvider: { timestamp }
        )
        await completePreflight(viewModel)
        await completeAudiogramThreshold(viewModel, laterality: .left)
        acceptCurrentTrial(viewModel, adjustment: .louder, confidence: .high)
        acceptCurrentTrial(viewModel, adjustment: .softer, confidence: .medium)
        acceptCurrentTrial(viewModel, adjustment: .muchLouder, confidence: .low)
        return viewModel
    }

    private func makeEngine(toneDuration: TimeInterval? = nil) -> TinnitusProtocolEngine {
        let configuration: TinnitusProtocolConfiguration
        if let toneDuration {
            configuration = TinnitusProtocolConfiguration(
                kind: .studyNo1FixedOneKilohertz,
                stimulusKind: .pureTone,
                frequencyHz: 1_000,
                requiredTrialCount: 3,
                toneDuration: toneDuration,
                rampDuration: CalibratedTonePlaybackDefaults.rampDuration,
                initialLoudnessMatchLevelDBHL: 45.0,
                minimumLevelDBHL: -10.0,
                maximumLevelDBHL: 100.0,
                highSpreadThresholdDB: 10.0,
                supportedPitchFrequenciesHz: CalibratedHeadphoneProfile.airPodsPro2.supportedFrequenciesHz
            )
        } else {
            configuration = .studyNo1FixedOneKilohertz
        }

        return TinnitusProtocolEngine(
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
                verificationSource: .researchProtocol
            )
        ])
    }

    private func audioOutput(
        name: String,
        portType: AVAudioSession.Port,
        uid: String = "route-uid"
    ) -> AudioSessionRouteOutputSnapshot {
        AudioSessionRouteOutputSnapshot(
            portName: name,
            portTypeRawValue: portType.rawValue,
            portUID: uid,
            channelNames: ["left", "right"]
        )
    }

    private func scheduledTask(dayIndex: Int = 0, slotIndex: Int = 0) -> ScheduledTask {
        ScheduledTask(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            enrollmentID: enrollment().id,
            taskKey: "lm_1khz_v2",
            taskVersion: 2,
            scheduledFor: timestamp,
            windowStart: timestamp.addingTimeInterval(-60),
            windowEnd: timestamp.addingTimeInterval(3_600),
            status: .scheduled,
            dayIndex: dayIndex,
            slotIndex: slotIndex,
            completedAt: nil
        )
    }

    private func orientationThresholdResult() -> StudyNo1OrientationThresholdResearchKitResult {
        StudyNo1OrientationThresholdResearchKitResult(
            taskIdentifier: "study-no-1-orientation-threshold",
            rightEar: orientationEar(channel: .right, threshold: 18),
            leftEar: orientationEar(channel: .left, threshold: 12),
            environment: nil
        )
    }

    private func orientationEar(
        channel: CalibratedTonePlaybackChannel,
        threshold: Double
    ) -> StudyNo1OrientationThresholdEarResult {
        StudyNo1OrientationThresholdEarResult(
            channel: channel,
            thresholdDBHL: threshold,
            outputVolume: 1.0,
            headphoneType: "airPodsProGen2",
            tonePlaybackDuration: 1.0,
            postStimulusDelay: 1.0,
            samples: [
                StudyNo1OrientationThresholdFrequencySample(
                    frequencyHz: 1_000,
                    calculatedThresholdDBHL: threshold,
                    channel: channel,
                    units: [
                        StudyNo1OrientationThresholdUnit(
                            levelDBHL: threshold,
                            startOfUnitTimeStamp: 0.1,
                            preStimulusDelay: 0.2,
                            userTapTimeStamp: 0.6,
                            timeoutTimeStamp: nil
                        )
                    ]
                )
            ]
        )
    }

    private func enrollment() -> StudyEnrollment {
        StudyEnrollment(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            userID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            studyID: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            status: .enrolled,
            enrolledAt: timestamp,
            createdAt: timestamp
        )
    }

    private func sampleAudiogram(leftThreshold: Double?, rightThreshold: Double?) -> AudiogramRecord {
        AudiogramRecord(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            measuredAt: timestamp.addingTimeInterval(-3_600),
            source: "healthkit",
            headphoneName: "AirPods Pro 2",
            healthKitSampleUUID: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
            points: [
                AudiogramPoint(
                    frequencyHz: 1_000,
                    leftEarDBHL: leftThreshold,
                    rightEarDBHL: rightThreshold,
                    tests: []
                )
            ]
        )
    }
}

private struct MockAudiogramRepository: AudiogramRepositoryProtocol {
    let audiogram: AudiogramRecord?

    func fetchLatestAudiogram() async throws -> AudiogramRecord? {
        audiogram
    }

    func saveHealthKitAudiograms(_ samples: [HealthKitAudiogramSample]) async throws -> Int {
        samples.count
    }
}

private struct MockEnvironmentSPLMeter: EnvironmentSPLMeasuring {
    let samplesDBA: [Double]

    func runGate(configuration: TinnitusEnvironmentSPLGateConfiguration) async throws -> TinnitusEnvironmentSPLGateResult {
        TinnitusEnvironmentSPLGateEvaluator().evaluate(samplesDBA: samplesDBA, configuration: configuration)
    }
}

private struct MockEnvironmentSPLGateMonitor: EnvironmentSPLGateMonitoring {
    let samplesByUpdate: [[Double]]
    var finishAfterUpdates = true

    func monitorGate(
        configuration: TinnitusEnvironmentSPLGateConfiguration
    ) -> AsyncThrowingStream<TinnitusEnvironmentSPLGateUpdate, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                for samples in samplesByUpdate {
                    continuation.yield(
                        TinnitusEnvironmentSPLGateEvaluator().update(
                            samplesDBA: samples,
                            configuration: configuration
                        )
                    )
                    await Task.yield()
                }

                if finishAfterUpdates {
                    continuation.finish()
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

private final class ControllableEnvironmentSPLGateMonitor: EnvironmentSPLGateMonitoring {
    private var continuation: AsyncThrowingStream<TinnitusEnvironmentSPLGateUpdate, Error>.Continuation?
    private var configuration: TinnitusEnvironmentSPLGateConfiguration = .studyNo1

    func monitorGate(
        configuration: TinnitusEnvironmentSPLGateConfiguration
    ) -> AsyncThrowingStream<TinnitusEnvironmentSPLGateUpdate, Error> {
        self.configuration = configuration
        return AsyncThrowingStream { continuation in
            self.continuation = continuation
        }
    }

    func yield(samplesDBA: [Double]) {
        continuation?.yield(
            TinnitusEnvironmentSPLGateEvaluator().update(
                samplesDBA: samplesDBA,
                configuration: configuration
            )
        )
    }

    func finish() {
        continuation?.finish()
    }
}

private final class MockAudioSessionRouteVolumeProvider: AudioSessionRouteVolumeProviding {
    var outputs: [AudioSessionRouteOutputSnapshot]
    var outputVolume: Double?
    private(set) var refreshCallCount = 0
    private var routeHandlers: [UUID: () -> Void] = [:]
    private(set) var routeObservation: MockAudioSessionObservation?

    init(outputs: [AudioSessionRouteOutputSnapshot], outputVolume: Double?) {
        self.outputs = outputs
        self.outputVolume = outputVolume
    }

    func refreshRouteAndVolume() {
        refreshCallCount += 1
    }

    func currentRouteOutputs() -> [AudioSessionRouteOutputSnapshot] {
        outputs
    }

    func currentOutputVolume() -> Double? {
        outputVolume
    }

    func observeRouteChanges(_ handler: @escaping () -> Void) -> AudioSessionObservation {
        let id = UUID()
        routeHandlers[id] = handler
        let observation = MockAudioSessionObservation { [weak self] in
            self?.routeHandlers[id] = nil
        }
        routeObservation = observation
        return observation
    }

    func observeOutputVolumeChanges(_ handler: @escaping () -> Void) -> AudioSessionObservation {
        MockAudioSessionObservation()
    }

    func triggerRouteChange() {
        let currentHandlers = routeHandlers
        for (id, handler) in currentHandlers {
            guard routeHandlers[id] != nil else {
                continue
            }
            handler()
        }
    }
}

private final class MockAudioSessionObservation: AudioSessionObservation {
    private let onInvalidate: () -> Void
    private(set) var isInvalidated = false

    init(onInvalidate: @escaping () -> Void = {}) {
        self.onInvalidate = onInvalidate
    }

    func invalidate() {
        guard !isInvalidated else {
            return
        }
        isInvalidated = true
        onInvalidate()
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

private struct MockStudyNo1RuntimeContextProvider: StudyNo1RuntimeContextProviding {
    func deviceContext() -> StudyNo1DeviceContext {
        StudyNo1DeviceContext(
            deviceModel: "iPhone17,2",
            systemName: "iOS",
            systemVersion: "26.0"
        )
    }

    func audioSessionContext() -> StudyNo1AudioSessionContext {
        StudyNo1AudioSessionContext(
            category: "playback",
            mode: "default",
            options: [],
            sampleRate: 44_100,
            bufferSize: 512
        )
    }

    func airPodsContext(guardrailValidation: CalibratedAudioGuardrailValidation) -> StudyNo1AirPodsContext {
        StudyNo1AirPodsContext(
            modelIdentifier: guardrailValidation.metadata.supportedHeadphoneIdentifier,
            firmwareVersion: nil,
            unavailableReason: "Firmware unavailable in test fixture."
        )
    }
}

private final class MockStudyService: StudyServiceProtocol {
    struct Submission {
        let scheduledTaskID: UUID
        let enrollmentID: UUID
        let submission: LoudnessMatchSubmission
    }

    struct OrientationSubmission {
        let scheduledTaskID: UUID
        let enrollmentID: UUID
        let submission: StudyNo1OrientationThresholdSubmission
    }

    var submissions: [Submission] = []
    var orientationSubmissions: [OrientationSubmission] = []

    func fetchStudies() async throws -> [Study] { [] }
    func fetchMyEnrollments() async throws -> [StudyEnrollment] { [] }
    func fetchScheduledTasks(enrollmentID: UUID) async throws -> [ScheduledTask] { [] }
    func enroll(studyID: UUID) async throws {}
    func completeStudyNo1Onboarding(enrollmentID: UUID, timezone: String) async throws {}

    func beginStudyNo1OrientationThresholdTask(enrollmentID: UUID) async throws -> ScheduledTask {
        throw NSError(
            domain: "MockStudyService",
            code: 404,
            userInfo: [NSLocalizedDescriptionKey: "No orientation threshold task configured."]
        )
    }

    func submitLoudnessMatch(
        scheduledTaskID: UUID,
        enrollmentID: UUID,
        submission: LoudnessMatchSubmission
    ) async throws {
        submissions.append(Submission(
            scheduledTaskID: scheduledTaskID,
            enrollmentID: enrollmentID,
            submission: submission
        ))
    }

    func submitStudyNo1OrientationThreshold(
        scheduledTaskID: UUID,
        enrollmentID: UUID,
        submission: StudyNo1OrientationThresholdSubmission
    ) async throws {
        orientationSubmissions.append(OrientationSubmission(
            scheduledTaskID: scheduledTaskID,
            enrollmentID: enrollmentID,
            submission: submission
        ))
    }
}
