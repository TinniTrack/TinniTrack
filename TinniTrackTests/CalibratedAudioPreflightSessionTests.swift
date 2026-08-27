import Combine
import Foundation
import Testing
@testable import TinniTrack

@MainActor
struct CalibratedAudioPreflightSessionTests {
    @Test
    func phaseTransitionsOwnTheExpectedMonitorLifecycle() {
        let controller = makeController()
        let session = CalibratedAudioPreflightSession(controller: controller)

        session.transition(to: .airPods)

        #expect(session.phase == .airPods)
        #expect(controller.startHeadphoneRouteMonitoringCallCount == 1)
        #expect(controller.isHeadphoneRouteMonitoring)
        #expect(controller.startAirPodsContinuityMonitoringCallCount == 0)
        #expect(controller.startContinuousEnvironmentGateCallCount == 0)
        #expect(controller.startVolumeGateMonitoringCallCount == 0)

        session.transition(to: .quietRoom)

        #expect(controller.stopHeadphoneRouteMonitoringCallCount == 1)
        #expect(controller.startAirPodsContinuityMonitoringCallCount == 1)
        #expect(controller.startContinuousEnvironmentGateCallCount == 1)
        #expect(controller.isAirPodsContinuityMonitoring)
        #expect(controller.isRunningEnvironmentGate)

        session.transition(to: .fit)

        #expect(controller.startAirPodsContinuityMonitoringCallCount == 1)
        #expect(controller.startContinuousEnvironmentGateCallCount == 1)

        session.transition(to: .maximumVolume)

        #expect(controller.startVolumeGateMonitoringCallCount == 1)
        #expect(controller.isVolumeGateMonitoring)

        session.transition(to: .postPreflight)

        #expect(controller.stopVolumeGateMonitoringCallCount == 1)
        #expect(controller.isVolumeGateMonitoring == false)
        #expect(controller.isAirPodsContinuityMonitoring)
        #expect(controller.isRunningEnvironmentGate)

        session.transition(to: .activeTest)

        #expect(controller.startAirPodsContinuityMonitoringCallCount == 1)
        #expect(controller.startContinuousEnvironmentGateCallCount == 1)

        session.transition(to: nil)

        #expect(session.phase == nil)
        #expect(controller.stopAirPodsContinuityMonitoringCallCount == 1)
        #expect(controller.cancelEnvironmentGateCallCount == 1)
        #expect(controller.stopVolumeGateMonitoringCallCount == 1)
        #expect(controller.isAirPodsContinuityMonitoring == false)
        #expect(controller.isRunningEnvironmentGate == false)
    }

    @Test
    func backwardTransitionsTearDownOnlyTheMonitorsOwnedByThePoppedPhase() {
        let controller = makeController()
        let session = CalibratedAudioPreflightSession(controller: controller)

        session.transition(to: .maximumVolume)
        session.transition(to: .fit)

        #expect(controller.stopVolumeGateMonitoringCallCount == 1)
        #expect(controller.isVolumeGateMonitoring == false)
        #expect(controller.isAirPodsContinuityMonitoring)
        #expect(controller.isRunningEnvironmentGate)

        session.transition(to: .airPods)

        #expect(controller.stopAirPodsContinuityMonitoringCallCount == 1)
        #expect(controller.cancelEnvironmentGateCallCount == 1)
        #expect(controller.startHeadphoneRouteMonitoringCallCount == 1)
        #expect(controller.isHeadphoneRouteMonitoring)

        session.transition(to: nil)

        #expect(controller.stopHeadphoneRouteMonitoringCallCount == 1)
        #expect(controller.isHeadphoneRouteMonitoring == false)
    }

    @Test
    func stopIsIdempotentAndCleansUpEveryActiveMonitorOnce() {
        let controller = makeController()
        let session = CalibratedAudioPreflightSession(controller: controller)

        session.transition(to: .maximumVolume)
        session.stop()
        session.stop()

        #expect(session.phase == nil)
        #expect(session.requestedFallback == nil)
        #expect(controller.stopHeadphoneRouteMonitoringCallCount == 0)
        #expect(controller.stopAirPodsContinuityMonitoringCallCount == 1)
        #expect(controller.stopAirPodsContinuityArguments == [true])
        #expect(controller.cancelEnvironmentGateCallCount == 1)
        #expect(controller.stopVolumeGateMonitoringCallCount == 1)
    }

    @Test
    func committingEachPhasePerformsOnlyItsConsequentialAction() {
        let controller = makeController()
        controller.isCurrentAirPodsPro2PlaybackRouteConfirmed = true
        controller.validateAirPodsResult = true
        controller.environmentGateResult = passingEnvironmentResult()
        controller.environmentGateUpdate = passingEnvironmentUpdate()
        controller.acknowledgeSafetyResult = true
        let session = CalibratedAudioPreflightSession(controller: controller)

        session.transition(to: .airPods)
        #expect(session.canCommitCurrentPhase)
        #expect(session.commitCurrentPhase())
        #expect(controller.validateAirPodsCallCount == 1)
        #expect(controller.prepareEnvironmentGateCallCount == 1)

        session.transition(to: .quietRoom)
        #expect(session.canCommitCurrentPhase)
        #expect(session.commitCurrentPhase())

        session.transition(to: .fit)
        #expect(session.canCommitCurrentPhase)
        #expect(session.commitCurrentPhase())
        #expect(controller.completeFitConfirmationCallCount == 1)

        session.transition(to: .maximumVolume)
        #expect(session.canCommitCurrentPhase)
        #expect(session.commitCurrentPhase())
        #expect(controller.acknowledgeSafetyCallCount == 1)

        session.transition(to: .postPreflight)
        #expect(session.commitCurrentPhase())
        session.transition(to: .activeTest)
        #expect(session.commitCurrentPhase())

        session.stop()
        #expect(session.canCommitCurrentPhase == false)
        #expect(session.commitCurrentPhase() == false)
        #expect(controller.validateAirPodsCallCount == 1)
        #expect(controller.prepareEnvironmentGateCallCount == 1)
        #expect(controller.completeFitConfirmationCallCount == 1)
        #expect(controller.acknowledgeSafetyCallCount == 1)
    }

    @Test
    func failedAirPodsCommitDoesNotPrepareQuietRoomGate() {
        let controller = makeController()
        controller.isCurrentAirPodsPro2PlaybackRouteConfirmed = true
        controller.validateAirPodsResult = false
        let session = CalibratedAudioPreflightSession(controller: controller)

        session.transition(to: .airPods)

        #expect(session.canCommitCurrentPhase)
        #expect(session.commitCurrentPhase() == false)
        #expect(controller.validateAirPodsCallCount == 1)
        #expect(controller.prepareEnvironmentGateCallCount == 0)
    }

    @Test
    func compatibleUnconfirmedRouteRequestsOneFallbackUntilConsumed() async throws {
        let controller = makeController()
        controller.headphoneRouteAssessment = compatibleAirPodsAssessment()
        controller.isCurrentAirPodsPro2PlaybackRouteConfirmed = true
        let session = CalibratedAudioPreflightSession(controller: controller)
        session.transition(to: .maximumVolume)

        controller.isCurrentAirPodsPro2PlaybackRouteConfirmed = false
        controller.publishChange()

        #expect(try await waitUntil {
            session.phase == .airPods && session.requestedFallback == .airPods
        })
        let firstRouteStartCount = controller.startHeadphoneRouteMonitoringCallCount

        controller.publishChange()
        for _ in 0..<3 {
            await Task.yield()
        }

        #expect(session.requestedFallback == .airPods)
        #expect(controller.startHeadphoneRouteMonitoringCallCount == firstRouteStartCount)

        session.consumeRequestedFallback()

        #expect(session.requestedFallback == nil)
        #expect(session.phase == .airPods)

        session.transition(to: .maximumVolume)
        controller.publishChange()

        #expect(try await waitUntil {
            session.phase == .airPods && session.requestedFallback == .airPods
        })
        #expect(controller.startHeadphoneRouteMonitoringCallCount == firstRouteStartCount + 1)
    }

    @Test
    func reconnectResumesMonitorsForCurrentMaximumVolumePhase() async throws {
        let controller = makeController()
        controller.isCurrentAirPodsPro2PlaybackRouteConfirmed = true
        controller.isAirPodsRouteInterrupted = true
        let session = CalibratedAudioPreflightSession(controller: controller)

        session.transition(to: .maximumVolume)

        #expect(controller.startAirPodsContinuityMonitoringCallCount == 1)
        #expect(controller.startContinuousEnvironmentGateCallCount == 0)
        #expect(controller.startVolumeGateMonitoringCallCount == 0)

        controller.isAirPodsRouteInterrupted = false
        controller.publishChange()

        #expect(try await waitUntil {
            controller.startContinuousEnvironmentGateCallCount == 1
                && controller.startVolumeGateMonitoringCallCount == 1
        })
        #expect(session.phase == .maximumVolume)
    }

    @Test
    func unrelatedControllerChangesDoNotRestartAStoppedEnvironmentMonitor() async {
        let controller = makeController()
        controller.isCurrentAirPodsPro2PlaybackRouteConfirmed = true
        let session = CalibratedAudioPreflightSession(controller: controller)
        session.transition(to: .maximumVolume)

        #expect(controller.startContinuousEnvironmentGateCallCount == 1)
        #expect(controller.startVolumeGateMonitoringCallCount == 1)

        controller.isRunningEnvironmentGate = false
        controller.environmentGateResult = nil
        controller.publishChange()
        for _ in 0..<3 {
            await Task.yield()
        }

        #expect(controller.startContinuousEnvironmentGateCallCount == 1)
        #expect(controller.startVolumeGateMonitoringCallCount == 1)
        #expect(session.phase == .maximumVolume)
    }

    @Test
    func interruptionStateMapsAirPodsAndQuietRoomContext() {
        let controller = makeController()
        let session = CalibratedAudioPreflightSession(controller: controller)
        session.transition(to: .activeTest)

        controller.headphoneRouteAssessment = compatibleAirPodsAssessment()
        controller.isCurrentAirPodsPro2PlaybackRouteConfirmed = false
        controller.isAirPodsRouteInterrupted = true
        controller.isAirPodsPlaybackRouteBlockedByAnotherApp = true

        #expect(
            session.interruption
                == .airPods(routeUnconfirmed: true, blockedByAnotherApp: true)
        )

        controller.isAirPodsRouteInterrupted = false
        controller.isEnvironmentQuietnessInterrupted = true
        controller.environmentGateUpdate = interruptedEnvironmentUpdate()

        #expect(session.interruption == .quietRoom(levelRatio: 1.2))

        session.transition(to: .quietRoom)
        #expect(session.interruption == nil)
    }

    @Test
    func participantMessagesAreMappedAndClearForwardsToController() {
        let controller = makeController()
        let session = CalibratedAudioPreflightSession(controller: controller)
        let cases: [(LoudnessMatchTaskFlowViewModel.FlowMessage, String)] = [
            (.airPodsNotInEar, "Please place your AirPods in your ear."),
            (
                .unsupportedHeadphones,
                "We detected headphones that are not AirPods Pro 2. AirPods Pro 2 are the only headphones we can use for this study."
            ),
            (
                .guardrailsUnavailable,
                "Audio guardrails are missing, failed, or require restart."
            ),
            (.missingPreflight("Finish setup first."), "Finish setup first."),
            (.submissionFailed("Please retry."), "Please retry.")
        ]

        for (message, expectedText) in cases {
            controller.message = message
            #expect(session.participantMessage == expectedText)
        }

        session.clearMessage()

        #expect(controller.clearMessageCallCount == 1)
        #expect(controller.message == nil)
        #expect(session.participantMessage == nil)
    }

    private func makeController() -> CalibratedAudioPreflightControllerSpy {
        CalibratedAudioPreflightControllerSpy(
            currentGuardrailValidation: passedGuardrails()
        )
    }

    private func passingEnvironmentResult() -> TinnitusEnvironmentSPLGateResult {
        TinnitusEnvironmentSPLGateEvaluator().evaluate(
            samplesDBA: [40, 41, 42, 43, 44],
            configuration: .studyNo1
        )
    }

    private func passingEnvironmentUpdate() -> TinnitusEnvironmentSPLGateUpdate {
        TinnitusEnvironmentSPLGateEvaluator().update(
            samplesDBA: [40, 41, 42, 43, 44],
            configuration: .studyNo1
        )
    }

    private func interruptedEnvironmentUpdate() -> TinnitusEnvironmentSPLGateUpdate {
        var machine = TinnitusEnvironmentSPLGateStateMachine()
        let initial = machine.beginMonitoring(reason: .initial)
        _ = machine.handle(.ready, generation: initial.generation)
        let evaluator = TinnitusEnvironmentSPLGateEvaluator()
        for (index, level) in [40.0, 41, 42, 43, 44].enumerated() {
            _ = machine.handle(
                .measurement(evaluator.legacyMeasurement(levelDBA: level, index: index)),
                generation: initial.generation
            )
        }
        let resumed = machine.beginMonitoring(reason: .postPlayback)
        _ = machine.handle(.ready, generation: resumed.generation)
        _ = machine.handle(
            .measurement(evaluator.legacyMeasurement(levelDBA: 54, index: 5)),
            generation: resumed.generation
        )
        _ = machine.handle(
            .measurement(evaluator.legacyMeasurement(levelDBA: 54, index: 6)),
            generation: resumed.generation
        )
        return machine.currentUpdate
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
            outputVolume: 1,
            timestamp: Date(timeIntervalSince1970: 1_710_000_000)
        )
    }

    private func compatibleAirPodsAssessment() -> HeadphoneRouteAssessment {
        HeadphoneRouteAssessment(
            level: .likelyAirPodsProRoute,
            outputCount: 1,
            portName: "AirPods Pro",
            portType: .bluetoothA2DP,
            portTypeRawValue: "BluetoothA2DPOutput",
            routeUID: "airpods-route",
            channelNames: ["left", "right"],
            outputVolume: 1,
            issues: []
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 1,
        condition: @escaping @MainActor () -> Bool
    ) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        return condition()
    }
}

@MainActor
private final class CalibratedAudioPreflightControllerSpy: CalibratedAudioPreflightControlling {
    let objectWillChange = ObservableObjectPublisher()

    var headphoneRouteAssessment: HeadphoneRouteAssessment = .notEvaluated
    var environmentGateResult: TinnitusEnvironmentSPLGateResult?
    var environmentGateUpdate: TinnitusEnvironmentSPLGateUpdate?
    var currentGuardrailValidation: CalibratedAudioGuardrailValidation
    var isHeadphoneRouteMonitoring = false
    var isAirPodsContinuityMonitoring = false
    var isAirPodsRouteInterrupted = false
    var isEnvironmentQuietnessInterrupted = false
    var isAirPodsPlaybackRouteBlockedByAnotherApp = false
    var isCurrentAirPodsPro2PlaybackRouteConfirmed = false
    var isRunningEnvironmentGate = false
    var isVolumeGateMonitoring = false
    var message: LoudnessMatchTaskFlowViewModel.FlowMessage?

    var validateAirPodsResult = true
    var acknowledgeSafetyResult = true

    private(set) var validateAirPodsCallCount = 0
    private(set) var prepareEnvironmentGateCallCount = 0
    private(set) var completeFitConfirmationCallCount = 0
    private(set) var acknowledgeSafetyCallCount = 0
    private(set) var startHeadphoneRouteMonitoringCallCount = 0
    private(set) var stopHeadphoneRouteMonitoringCallCount = 0
    private(set) var startAirPodsContinuityMonitoringCallCount = 0
    private(set) var stopAirPodsContinuityMonitoringCallCount = 0
    private(set) var stopAirPodsContinuityArguments: [Bool] = []
    private(set) var startContinuousEnvironmentGateCallCount = 0
    private(set) var cancelEnvironmentGateCallCount = 0
    private(set) var startVolumeGateMonitoringCallCount = 0
    private(set) var stopVolumeGateMonitoringCallCount = 0
    private(set) var endAudioSessionWorkflowCallCount = 0
    private(set) var clearMessageCallCount = 0

    init(currentGuardrailValidation: CalibratedAudioGuardrailValidation) {
        self.currentGuardrailValidation = currentGuardrailValidation
    }

    func publishChange() {
        objectWillChange.send()
    }

    func validateAirPodsForCorrectEarStep() -> Bool {
        validateAirPodsCallCount += 1
        return validateAirPodsResult
    }

    func prepareEnvironmentGateForQuietRoomStep() {
        prepareEnvironmentGateCallCount += 1
    }

    func completeFitConfirmation() {
        completeFitConfirmationCallCount += 1
    }

    func acknowledgeSafetyAndStartTest() -> Bool {
        acknowledgeSafetyCallCount += 1
        return acknowledgeSafetyResult
    }

    func startHeadphoneRouteMonitoring() {
        startHeadphoneRouteMonitoringCallCount += 1
        isHeadphoneRouteMonitoring = true
    }

    func stopHeadphoneRouteMonitoring() {
        stopHeadphoneRouteMonitoringCallCount += 1
        isHeadphoneRouteMonitoring = false
    }

    func startAirPodsContinuityMonitoring() {
        startAirPodsContinuityMonitoringCallCount += 1
        isAirPodsContinuityMonitoring = true
    }

    func stopAirPodsContinuityMonitoring(clearInterruption: Bool) {
        stopAirPodsContinuityMonitoringCallCount += 1
        stopAirPodsContinuityArguments.append(clearInterruption)
        isAirPodsContinuityMonitoring = false
        if clearInterruption {
            isAirPodsRouteInterrupted = false
        }
    }

    func startContinuousEnvironmentGate() {
        startContinuousEnvironmentGateCallCount += 1
        isRunningEnvironmentGate = true
    }

    func cancelEnvironmentGate() {
        cancelEnvironmentGateCallCount += 1
        isRunningEnvironmentGate = false
    }

    func startVolumeGateMonitoring() {
        startVolumeGateMonitoringCallCount += 1
        isVolumeGateMonitoring = true
    }

    func stopVolumeGateMonitoring() {
        stopVolumeGateMonitoringCallCount += 1
        isVolumeGateMonitoring = false
    }

    func endAudioSessionWorkflow() {
        endAudioSessionWorkflowCallCount += 1
    }

    func clearMessage() {
        clearMessageCallCount += 1
        message = nil
    }
}
