import AVFoundation
import Foundation
import Testing
@testable import TinniTrack

@MainActor
struct AVAudioEnvironmentSPLMeterTests {
    @Test
    func permissionDenialProducesUnavailableWithoutConfiguringAudio() async throws {
        let coordinator = EnvironmentAudioSessionCoordinatorStub()
        let meter = AVAudioEnvironmentSPLMeter(
            audioSessionCoordinator: coordinator,
            permissionRequester: { false }
        )

        let events = try await collectEvents(
            from: meter.makeMonitor(configuration: .studyNo1, reason: .initial)
        )

        #expect(events.contains(.unavailable(.microphonePermissionDenied)))
        #expect(events.containsMeasurement == false)
        #expect(coordinator.configureForMeasurementCallCount == 0)
    }

    @Test
    func engineFactoryFailureProducesUnavailableWithoutAQuietOrLoudWindow() async throws {
        let coordinator = EnvironmentAudioSessionCoordinatorStub()
        let meter = AVAudioEnvironmentSPLMeter(
            audioSessionCoordinator: coordinator,
            engineFactory: { throw EnvironmentEngineFactoryFailure.expected },
            permissionRequester: { true }
        )

        let events = try await collectEvents(
            from: meter.makeMonitor(configuration: zeroDelayConfiguration, reason: .initial)
        )

        #expect(events.contains(.unavailable(.engineFailure)))
        #expect(events.containsMeasurement == false)
        #expect(coordinator.configureForMeasurementCallCount == 1)
    }

    @Test
    func builtInMicrophoneRouteMismatchIsIndeterminate() async throws {
        let coordinator = EnvironmentAudioSessionCoordinatorStub(
            configurationError: .actualInputRouteMismatch
        )
        let meter = AVAudioEnvironmentSPLMeter(
            audioSessionCoordinator: coordinator,
            permissionRequester: { true }
        )

        let events = try await collectEvents(
            from: meter.makeMonitor(configuration: zeroDelayConfiguration, reason: .initial)
        )

        #expect(events.contains(.unavailable(.routeMismatch)))
        #expect(events.containsMeasurement == false)
    }

    @Test
    func cancellationFinishesWithoutFabricatingAWindow() async throws {
        let coordinator = EnvironmentAudioSessionCoordinatorStub()
        let meter = AVAudioEnvironmentSPLMeter(
            audioSessionCoordinator: coordinator,
            permissionRequester: {
                await Task.yield()
                return true
            }
        )
        let monitor = meter.makeMonitor(configuration: .studyNo1, reason: .initial)

        await monitor.stop()
        let events = try await collectEvents(from: monitor)

        #expect(events.containsMeasurement == false)
        #expect(events.containsDecisionStatus == false)
    }

    private var zeroDelayConfiguration: TinnitusEnvironmentSPLGateConfiguration {
        TinnitusEnvironmentSPLGateConfiguration(
            thresholdDBA: 45,
            requiredContiguousSamples: 5,
            samplingInterval: 1,
            maximumSamples: 12,
            warmUpDuration: 0,
            settlingDuration: 0,
            sensitivityOffsetDB: nil
        )
    }

    private func collectEvents(
        from monitor: any EnvironmentSPLMonitorSession
    ) async throws -> [TinnitusEnvironmentSPLMonitorEvent] {
        var received: [TinnitusEnvironmentSPLMonitorEvent] = []
        for try await event in monitor.events {
            received.append(event)
            if case .unavailable = event {
                break
            }
        }
        await monitor.stop()
        return received
    }
}

@MainActor
private final class EnvironmentAudioSessionCoordinatorStub: StudyAudioSessionCoordinating {
    private(set) var isWorkflowActive = false
    private(set) var configureForMeasurementCallCount = 0
    private let configurationError: StudyAudioSessionCoordinatorError?

    init(configurationError: StudyAudioSessionCoordinatorError? = nil) {
        self.configurationError = configurationError
    }

    func beginWorkflow() {
        isWorkflowActive = true
    }

    func configureForMeasurement() throws -> TinnitusEnvironmentInputConfiguration {
        configureForMeasurementCallCount += 1
        if let configurationError {
            throw configurationError
        }
        isWorkflowActive = true
        return Self.input
    }

    func configureForPlayback(
        preferredSampleRate: Double,
        preferredBufferFrameCount: Int
    ) throws {
        isWorkflowActive = true
    }

    func verifiedCurrentMeasurementInput() -> TinnitusEnvironmentInputConfiguration? {
        Self.input
    }

    func endWorkflow() {
        isWorkflowActive = false
    }

    private static let input = TinnitusEnvironmentInputConfiguration(
        route: .builtInMicrophone,
        dataSourceOrientation: .bottom,
        sampleRate: 48_000,
        channelCount: 1,
        inputGain: 1,
        isInputGainSettable: false
    )
}

private enum EnvironmentEngineFactoryFailure: Error {
    case expected
}

private extension Array where Element == TinnitusEnvironmentSPLMonitorEvent {
    var containsMeasurement: Bool {
        contains {
            if case .measurement = $0 { return true }
            return false
        }
    }

    var containsDecisionStatus: Bool {
        contains {
            switch $0 {
            case .measurement:
                return true
            case .warmingUp, .ready, .invalidated, .unavailable:
                return false
            }
        }
    }
}
