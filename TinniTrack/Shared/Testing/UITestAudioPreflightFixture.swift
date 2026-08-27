#if DEBUG
import AVFoundation
import Foundation

enum UITestAudioPreflightFixture {
    static let readinessEnvironmentKey = "UITEST_MOCK_AUDIO_PREFLIGHT_READY"
    static let recurringTaskEnvironmentKey = "UITEST_MOCK_RECURRING_LOUDNESS_TASK"
    static let confirmationRequiredEnvironmentKey = "UITEST_MOCK_AIRPODS_CONFIRMATION_REQUIRED"
    static let waitingForAirPodsEnvironmentKey = "UITEST_MOCK_WAITING_FOR_AIRPODS"

    static func isEnabled(processInfo: ProcessInfo = .processInfo) -> Bool {
        processInfo.environment[readinessEnvironmentKey] == "1"
    }

    static func makeAudiogramCoordinator() -> AudiogramImportCoordinating {
        ReadyAudiogramImportCoordinator()
    }

    @MainActor
    static func makeLoudnessViewModel(
        processInfo: ProcessInfo = .processInfo
    ) -> LoudnessMatchTaskFlowViewModel {
        let isWaitingForAirPods = processInfo.environment[waitingForAirPodsEnvironmentKey] == "1"
        let requiresConfirmation = processInfo.environment[confirmationRequiredEnvironmentKey] == "1"
        let routeProvider: AudioSessionRouteVolumeProviding = isWaitingForAirPods
            ? WaitingAudioSessionRouteProvider()
            : ReadyAudioSessionRouteProvider()
        let guardrailValidation = if isWaitingForAirPods {
            makeWaitingForAirPodsGuardrailValidation()
        } else {
            makePassedGuardrailValidation(
                verificationSource: requiresConfirmation
                    ? .appCalibrationProfile
                    : .researchProtocol
            )
        }
        let viewModel = LoudnessMatchTaskFlowViewModel(
            guardrailProvider: { guardrailValidation },
            headphoneRouteProvider: routeProvider,
            environmentMeter: PassingEnvironmentSPLGate(),
            environmentGateMonitor: PassingEnvironmentSPLGate(),
            audiogramRepository: ReadyAudiogramRepository()
        )
        if !requiresConfirmation && !isWaitingForAirPods {
            viewModel.setAirPodsPro2ConfirmedForCurrentRoute(true)
        }
        viewModel.clearMessage()
        return viewModel
    }

    private static func makeWaitingForAirPodsGuardrailValidation()
        -> CalibratedAudioGuardrailValidation {
        CalibratedAudioGuardrailPolicy().validate(
            route: CalibratedAudioRouteDetails(outputs: []),
            outputVolume: 1.0,
            timestamp: fixtureDate
        )
    }

    private static func makePassedGuardrailValidation(
        verificationSource: CalibratedHeadphoneVerificationSource
    ) -> CalibratedAudioGuardrailValidation {
        CalibratedAudioGuardrailPolicy().validate(
            route: CalibratedAudioRouteDetails(
                outputs: [
                    CalibratedAudioRouteOutput(
                        portName: ReadyAudioSessionRouteProvider.portName,
                        portType: .bluetoothA2DP,
                        portUID: ReadyAudioSessionRouteProvider.portUID,
                        channelNames: ["Left", "Right"],
                        verifiedCalibratedHeadphoneIdentifier: CalibratedHeadphoneIdentifier.airPodsPro2,
                        verificationSource: verificationSource
                    )
                ]
            ),
            outputVolume: 1.0,
            timestamp: fixtureDate
        )
    }

    fileprivate static let fixtureDate = Date(timeIntervalSince1970: 1_725_000_000)
}

private struct ReadyAudiogramImportCoordinator: AudiogramImportCoordinating {
    func evaluatePrerequisite() async -> AudiogramPrerequisiteState {
        .met(latestMeasuredAt: UITestAudioPreflightFixture.fixtureDate)
    }

    func importFromHealthKit() async throws -> AudiogramImportResult {
        .noNewRecords(latestMeasuredAt: UITestAudioPreflightFixture.fixtureDate)
    }
}

private struct ReadyAudiogramRepository: AudiogramRepositoryProtocol {
    func fetchLatestAudiogram() async throws -> AudiogramRecord? {
        AudiogramRecord(
            id: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!,
            measuredAt: UITestAudioPreflightFixture.fixtureDate,
            source: "uitest",
            headphoneName: ReadyAudioSessionRouteProvider.portName,
            healthKitSampleUUID: nil,
            points: [
                AudiogramPoint(
                    frequencyHz: 1_000,
                    leftEarDBHL: 10,
                    rightEarDBHL: 15,
                    tests: []
                )
            ]
        )
    }

    func saveHealthKitAudiograms(_ samples: [HealthKitAudiogramSample]) async throws -> Int {
        samples.count
    }
}

private struct PassingEnvironmentSPLGate: EnvironmentSPLMeasuring, EnvironmentSPLGateMonitoring {
    private let samplesDBA = [30.0, 31.0, 32.0, 33.0, 34.0]

    func runGate(
        configuration: TinnitusEnvironmentSPLGateConfiguration
    ) async throws -> TinnitusEnvironmentSPLGateResult {
        TinnitusEnvironmentSPLGateEvaluator().evaluate(
            samplesDBA: samplesDBA,
            configuration: configuration
        )
    }

    func makeMonitor(
        configuration: TinnitusEnvironmentSPLGateConfiguration,
        reason: TinnitusEnvironmentSPLReacquisitionReason
    ) -> any EnvironmentSPLMonitorSession {
        let result = TinnitusEnvironmentSPLGateEvaluator().evaluate(
            samplesDBA: samplesDBA,
            configuration: configuration
        )
        return PassingEnvironmentSPLMonitorSession(
            reason: reason,
            measurements: result.measurements
        )
    }
}

@MainActor
private final class PassingEnvironmentSPLMonitorSession: EnvironmentSPLMonitorSession {
    let events: AsyncThrowingStream<TinnitusEnvironmentSPLMonitorEvent, Error>
    private let continuation: AsyncThrowingStream<TinnitusEnvironmentSPLMonitorEvent, Error>.Continuation

    init(
        reason: TinnitusEnvironmentSPLReacquisitionReason,
        measurements: [TinnitusEnvironmentSPLMeasurement]
    ) {
        var captured: AsyncThrowingStream<TinnitusEnvironmentSPLMonitorEvent, Error>.Continuation!
        events = AsyncThrowingStream { captured = $0 }
        continuation = captured
        continuation.yield(.warmingUp(reason))
        continuation.yield(.ready)
        measurements.forEach { continuation.yield(.measurement($0)) }
    }

    func stop() async {
        continuation.finish()
    }
}

private final class ReadyAudioSessionRouteProvider: AudioSessionRouteVolumeProviding {
    static let portName = "UI Test AirPods Pro 2"
    static let portUID = "uitest-airpods-pro-2"

    func refreshRouteAndVolume() {}

    func currentRouteOutputs() -> [AudioSessionRouteOutputSnapshot] {
        [
            AudioSessionRouteOutputSnapshot(
                portName: Self.portName,
                portTypeRawValue: AVAudioSession.Port.bluetoothA2DP.rawValue,
                portUID: Self.portUID,
                channelNames: ["Left", "Right"]
            )
        ]
    }

    func currentOutputVolume() -> Double? {
        1.0
    }

    func observeRouteChanges(_ handler: @escaping () -> Void) -> AudioSessionObservation {
        FixtureAudioSessionObservation()
    }

    func observeOutputVolumeChanges(_ handler: @escaping () -> Void) -> AudioSessionObservation {
        FixtureAudioSessionObservation()
    }
}

private final class WaitingAudioSessionRouteProvider: AudioSessionRouteVolumeProviding {
    func refreshRouteAndVolume() {}

    func currentRouteOutputs() -> [AudioSessionRouteOutputSnapshot] {
        []
    }

    func currentOutputVolume() -> Double? {
        1.0
    }

    func observeRouteChanges(_ handler: @escaping () -> Void) -> AudioSessionObservation {
        FixtureAudioSessionObservation()
    }

    func observeOutputVolumeChanges(_ handler: @escaping () -> Void) -> AudioSessionObservation {
        FixtureAudioSessionObservation()
    }
}

private final class FixtureAudioSessionObservation: AudioSessionObservation {
    func invalidate() {}
}
#endif
