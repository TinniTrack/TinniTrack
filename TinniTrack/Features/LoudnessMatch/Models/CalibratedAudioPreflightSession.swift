import Combine
import Foundation

@MainActor
protocol CalibratedAudioPreflightControlling: AnyObject {
    var objectWillChange: ObservableObjectPublisher { get }
    var headphoneRouteAssessment: HeadphoneRouteAssessment { get }
    var environmentGateResult: TinnitusEnvironmentSPLGateResult? { get }
    var environmentGateUpdate: TinnitusEnvironmentSPLGateUpdate? { get }
    var currentGuardrailValidation: CalibratedAudioGuardrailValidation { get }
    var isHeadphoneRouteMonitoring: Bool { get }
    var isAirPodsContinuityMonitoring: Bool { get }
    var isAirPodsRouteInterrupted: Bool { get }
    var isEnvironmentQuietnessInterrupted: Bool { get }
    var isAirPodsPlaybackRouteBlockedByAnotherApp: Bool { get }
    var isCurrentAirPodsPro2PlaybackRouteConfirmed: Bool { get }
    var isRunningEnvironmentGate: Bool { get }
    var isVolumeGateMonitoring: Bool { get }
    var message: LoudnessMatchTaskFlowViewModel.FlowMessage? { get }

    func validateAirPodsForCorrectEarStep() -> Bool
    func prepareEnvironmentGateForQuietRoomStep()
    func completeFitConfirmation()
    func acknowledgeSafetyAndStartTest() -> Bool
    func startHeadphoneRouteMonitoring()
    func stopHeadphoneRouteMonitoring()
    func startAirPodsContinuityMonitoring()
    func stopAirPodsContinuityMonitoring(clearInterruption: Bool)
    func startContinuousEnvironmentGate()
    func cancelEnvironmentGate()
    func startVolumeGateMonitoring()
    func stopVolumeGateMonitoring()
    func endAudioSessionWorkflow()
    func clearMessage()
}

@MainActor
final class CalibratedAudioPreflightSession: ObservableObject {
    enum Phase: Hashable {
        case airPods
        case quietRoom
        case fit
        case maximumVolume
        case postPreflight
        case activeTest
    }

    enum Interruption: Equatable {
        case airPods(routeUnconfirmed: Bool, blockedByAnotherApp: Bool)
        case quietRoom(levelRatio: Double?)
    }

    @Published private(set) var phase: Phase?
    @Published private(set) var requestedFallback: Phase?

    private let controller: CalibratedAudioPreflightControlling
    private var controllerObservation: AnyCancellable?
    private var hasStarted = false
    private var wasAirPodsRouteInterrupted: Bool

    init(controller: CalibratedAudioPreflightControlling) {
        self.controller = controller
        wasAirPodsRouteInterrupted = controller.isAirPodsRouteInterrupted
        controllerObservation = controller.objectWillChange.sink { [weak self] in
            Task { @MainActor in
                await Task.yield()
                self?.controllerDidChange()
            }
        }
    }

    var canCommitCurrentPhase: Bool {
        switch phase {
        case .airPods:
            return controller.isCurrentAirPodsPro2PlaybackRouteConfirmed
        case .quietRoom:
            return controller.environmentGateUpdate?.hasCurrentQuietDecision == true
        case .fit:
            return true
        case .maximumVolume:
            return controller.currentGuardrailValidation.state == .passed
        case .postPreflight, .activeTest:
            return true
        case nil:
            return false
        }
    }

    var interruption: Interruption? {
        guard let phase else {
            return nil
        }

        if controller.isAirPodsRouteInterrupted, phase != .airPods {
            return .airPods(
                routeUnconfirmed: isCurrentA2DPRouteUnconfirmed,
                blockedByAnotherApp: controller.isAirPodsPlaybackRouteBlockedByAnotherApp
            )
        }

        if controller.isEnvironmentQuietnessInterrupted,
           phase != .airPods,
           phase != .quietRoom {
            return .quietRoom(levelRatio: quietRoomInterruptionLevelRatio)
        }

        return nil
    }

    var participantMessage: String? {
        Self.participantMessage(for: controller.message)
    }

    func transition(to nextPhase: Phase?) {
        guard phase != nextPhase else {
            return
        }

        guard let nextPhase else {
            stop()
            return
        }

        hasStarted = true
        phase = nextPhase

        switch nextPhase {
        case .airPods:
            stopVolumeMonitoringIfNeeded()
            cancelEnvironmentGateIfNeeded()
            stopAirPodsContinuityIfNeeded()
            startHeadphoneRouteMonitoringIfNeeded()

        case .quietRoom, .fit:
            stopHeadphoneRouteMonitoringIfNeeded()
            stopVolumeMonitoringIfNeeded()
            startAirPodsContinuityIfNeeded()
            startEnvironmentGateIfNeeded()

        case .maximumVolume:
            stopHeadphoneRouteMonitoringIfNeeded()
            startAirPodsContinuityIfNeeded()
            startEnvironmentGateIfNeeded()
            startVolumeMonitoringIfNeeded()

        case .postPreflight, .activeTest:
            stopHeadphoneRouteMonitoringIfNeeded()
            stopVolumeMonitoringIfNeeded()
            startAirPodsContinuityIfNeeded()
            startEnvironmentGateIfNeeded()
        }
    }

    @discardableResult
    func commitCurrentPhase() -> Bool {
        switch phase {
        case .airPods:
            guard controller.validateAirPodsForCorrectEarStep() else {
                return false
            }
            controller.prepareEnvironmentGateForQuietRoomStep()
            return true

        case .quietRoom:
            return controller.environmentGateUpdate?.hasCurrentQuietDecision == true

        case .fit:
            controller.completeFitConfirmation()
            return true

        case .maximumVolume:
            return controller.acknowledgeSafetyAndStartTest()

        case .postPreflight, .activeTest:
            return true

        case nil:
            return false
        }
    }

    func consumeRequestedFallback() {
        requestedFallback = nil
    }

    func clearMessage() {
        controller.clearMessage()
    }

    func stop() {
        guard hasStarted || phase != nil else {
            return
        }

        stopHeadphoneRouteMonitoringIfNeeded()
        stopAirPodsContinuityIfNeeded()
        cancelEnvironmentGateIfNeeded()
        stopVolumeMonitoringIfNeeded()
        controller.endAudioSessionWorkflow()
        requestedFallback = nil
        phase = nil
        hasStarted = false
    }

    private func controllerDidChange() {
        objectWillChange.send()
        let didReconnectAirPods = wasAirPodsRouteInterrupted
            && !controller.isAirPodsRouteInterrupted
        wasAirPodsRouteInterrupted = controller.isAirPodsRouteInterrupted
        if didReconnectAirPods {
            resumePhaseAfterAirPodsReconnect()
        }

        guard let phase,
              phase.allowsAirPodsFallback,
              controller.headphoneRouteAssessment.isCompatibleBluetoothPlaybackRoute,
              !controller.isCurrentAirPodsPro2PlaybackRouteConfirmed,
              requestedFallback != .airPods
        else {
            return
        }

        transition(to: .airPods)
        requestedFallback = .airPods
    }

    private func resumePhaseAfterAirPodsReconnect() {
        guard !controller.isAirPodsRouteInterrupted else {
            return
        }

        switch phase {
        case .quietRoom, .fit:
            startEnvironmentGateIfNeeded()
        case .maximumVolume:
            startEnvironmentGateIfNeeded()
            startVolumeMonitoringIfNeeded()
        case .airPods, .postPreflight, .activeTest, nil:
            break
        }
    }

    private var isCurrentA2DPRouteUnconfirmed: Bool {
        controller.headphoneRouteAssessment.isCompatibleBluetoothPlaybackRoute
            && !controller.isCurrentAirPodsPro2PlaybackRouteConfirmed
    }

    private var quietRoomInterruptionLevelRatio: Double? {
        controller.environmentGateUpdate?.latestSampleDBA.map {
            $0 / TinnitusEnvironmentSPLGateConfiguration.studyNo1.thresholdDBA
        }
    }

    private func startHeadphoneRouteMonitoringIfNeeded() {
        guard !controller.isHeadphoneRouteMonitoring else {
            return
        }
        controller.startHeadphoneRouteMonitoring()
    }

    private func stopHeadphoneRouteMonitoringIfNeeded() {
        guard controller.isHeadphoneRouteMonitoring else {
            return
        }
        controller.stopHeadphoneRouteMonitoring()
    }

    private func startAirPodsContinuityIfNeeded() {
        guard !controller.isAirPodsContinuityMonitoring else {
            return
        }
        controller.startAirPodsContinuityMonitoring()
    }

    private func stopAirPodsContinuityIfNeeded() {
        guard controller.isAirPodsContinuityMonitoring else {
            return
        }
        controller.stopAirPodsContinuityMonitoring(clearInterruption: true)
    }

    private func startEnvironmentGateIfNeeded() {
        guard !controller.isAirPodsRouteInterrupted,
              !controller.isRunningEnvironmentGate,
              controller.environmentGateUpdate?.status != .quiet
        else {
            return
        }
        controller.startContinuousEnvironmentGate()
    }

    private func cancelEnvironmentGateIfNeeded() {
        guard controller.isRunningEnvironmentGate else {
            return
        }
        controller.cancelEnvironmentGate()
    }

    private func startVolumeMonitoringIfNeeded() {
        guard !controller.isAirPodsRouteInterrupted,
              !controller.isVolumeGateMonitoring
        else {
            return
        }
        controller.startVolumeGateMonitoring()
    }

    private func stopVolumeMonitoringIfNeeded() {
        guard controller.isVolumeGateMonitoring else {
            return
        }
        controller.stopVolumeGateMonitoring()
    }

    private static func participantMessage(
        for message: LoudnessMatchTaskFlowViewModel.FlowMessage?
    ) -> String? {
        switch message {
        case .playbackDisabled:
            return "Calibrated playback is still disabled for this participant workflow."
        case .environmentGateFailed:
            return "The quiet-room gate did not collect enough consecutive samples below the Study No. 1 threshold."
        case .airPodsNotInEar:
            return "Please place your AirPods in your ear."
        case .unsupportedHeadphones:
            return "We detected headphones that are not AirPods Pro 2. AirPods Pro 2 are the only headphones we can use for this study."
        case .airPodsPro2ConfirmationRequired:
            return "Confirm that the connected headphones are AirPods Pro 2 before continuing."
        case .calibratedPlaybackRouteUnavailable:
            return "AirPods Pro 2 are connected, but another app is using them for call audio. Close Phone, Zoom, or other apps that may be using the headphones, then try again."
        case .missingAudiogramThreshold(let message),
             .missingPreflight(let message),
             .incompletePayload(let message),
             .environmentGateUnavailable(let message),
             .playbackFailed(let message),
             .submissionFailed(let message):
            return message
        case .guardrailsUnavailable:
            return "Audio guardrails are missing, failed, or require restart."
        case nil:
            return nil
        }
    }
}

private extension CalibratedAudioPreflightSession.Phase {
    var allowsAirPodsFallback: Bool {
        switch self {
        case .quietRoom, .fit, .maximumVolume, .postPreflight:
            return true
        case .airPods, .activeTest:
            return false
        }
    }
}

extension LoudnessMatchTaskFlowViewModel: CalibratedAudioPreflightControlling {}
