import AVFoundation
import Foundation
import Testing
@testable import TinniTrack

struct CalibratedAudioSessionGuardrailMonitorTests {
    @Test
    func publicAudioRouteDataDoesNotVerifyAirPodsPro2FromRouteName() {
        let provider = MockAudioSessionRouteVolumeProvider(
            outputs: [
                AudioSessionRouteOutputSnapshot(
                    portName: "Vasyl's AirPods Pro 2",
                    portTypeRawValue: AVAudioSession.Port.bluetoothA2DP.rawValue,
                    portUID: "airpods-route",
                    channelNames: ["left", "right"]
                )
            ],
            outputVolume: 1.0
        )
        let monitor = CalibratedAudioSessionGuardrailMonitor(provider: provider)

        let validation = monitor.validateCurrentGuardrails()

        #expect(validation.state == .failed)
        guard case .unverifiedHeadphoneProfile(let route, let requiredIdentifier) = validation.error else {
            Issue.record("Expected unverifiedHeadphoneProfile, got \(String(describing: validation.error))")
            return
        }
        #expect(requiredIdentifier == "AIRPODSPROV2")
        #expect(route.outputs.first?.portName == "Vasyl's AirPods Pro 2")
        #expect(route.outputs.first?.verifiedCalibratedHeadphoneIdentifier == nil)
    }

    @Test
    func explicitProfileResolverAllowsSupportedAirPodsPro2RouteToPass() {
        let provider = MockAudioSessionRouteVolumeProvider(
            outputs: [bluetoothAirPodsOutput()],
            outputVolume: 1.0
        )
        let monitor = CalibratedAudioSessionGuardrailMonitor(
            provider: provider,
            profileResolver: StaticAirPodsPro2Resolver()
        )

        let validation = monitor.validateCurrentGuardrails()

        #expect(validation.state == .passed)
        #expect(validation.metadata.routeDetails?.outputs.first?.portType == .bluetoothA2DP)
        #expect(validation.metadata.supportedHeadphoneIdentifier == "AIRPODSPROV2")
        #expect(validation.metadata.rawOutputVolume == 1.0)
    }

    @Test
    func routeChangeObservationInvalidatesPassedGuardrails() {
        let provider = MockAudioSessionRouteVolumeProvider(
            outputs: [bluetoothAirPodsOutput()],
            outputVolume: 1.0
        )
        let monitor = CalibratedAudioSessionGuardrailMonitor(
            provider: provider,
            profileResolver: StaticAirPodsPro2Resolver()
        )
        var validations: [CalibratedAudioGuardrailValidation] = []
        monitor.startMonitoring { validations.append($0) }

        provider.outputs = [
            AudioSessionRouteOutputSnapshot(
                portName: "Speaker",
                portTypeRawValue: AVAudioSession.Port.builtInSpeaker.rawValue,
                portUID: "speaker",
                channelNames: []
            )
        ]
        provider.triggerRouteChange()

        #expect(validations.first?.state == .passed)
        #expect(validations.last?.state == .restartRequired)
        guard case .routeChanged(let previous, let current) = validations.last?.error else {
            Issue.record("Expected routeChanged, got \(String(describing: validations.last?.error))")
            return
        }
        #expect(previous.validationState == .passed)
        #expect(current?.outputs.first?.portType == .builtInSpeaker)
    }

    @Test
    func volumeObservationInvalidatesPassedGuardrails() {
        let provider = MockAudioSessionRouteVolumeProvider(
            outputs: [bluetoothAirPodsOutput()],
            outputVolume: 1.0
        )
        let monitor = CalibratedAudioSessionGuardrailMonitor(
            provider: provider,
            profileResolver: StaticAirPodsPro2Resolver()
        )
        var validations: [CalibratedAudioGuardrailValidation] = []
        monitor.startMonitoring { validations.append($0) }

        provider.outputVolume = 0.9375
        provider.triggerVolumeChange()

        #expect(validations.first?.state == .passed)
        #expect(validations.last?.state == .restartRequired)
        guard case .volumeChanged(let previous, let currentVolume) = validations.last?.error else {
            Issue.record("Expected volumeChanged, got \(String(describing: validations.last?.error))")
            return
        }
        #expect(previous.rawOutputVolume == 1.0)
        #expect(currentVolume == 0.9375)
    }

    @Test
    func stopMonitoringInvalidatesProviderObservations() {
        let provider = MockAudioSessionRouteVolumeProvider(
            outputs: [bluetoothAirPodsOutput()],
            outputVolume: 1.0
        )
        let monitor = CalibratedAudioSessionGuardrailMonitor(
            provider: provider,
            profileResolver: StaticAirPodsPro2Resolver()
        )

        monitor.startMonitoring { _ in }
        monitor.stopMonitoring()

        #expect(provider.routeObservation?.isInvalidated == true)
        #expect(provider.volumeObservation?.isInvalidated == true)
    }

    private func bluetoothAirPodsOutput() -> AudioSessionRouteOutputSnapshot {
        AudioSessionRouteOutputSnapshot(
            portName: "Verified AirPods Pro 2",
            portTypeRawValue: AVAudioSession.Port.bluetoothA2DP.rawValue,
            portUID: "verified-airpods",
            channelNames: ["left", "right"]
        )
    }
}

private struct StaticAirPodsPro2Resolver: CalibratedHeadphoneProfileResolving {
    func verification(for output: AudioSessionRouteOutputSnapshot) -> CalibratedHeadphoneVerification? {
        CalibratedHeadphoneVerification(
            identifier: "AIRPODSPROV2",
            source: .appCalibrationProfile
        )
    }
}

private final class MockAudioSessionRouteVolumeProvider: AudioSessionRouteVolumeProviding {
    var outputs: [AudioSessionRouteOutputSnapshot]
    var outputVolume: Double?
    private var routeHandler: (() -> Void)?
    private var volumeHandler: (() -> Void)?
    private(set) var routeObservation: MockAudioSessionObservation?
    private(set) var volumeObservation: MockAudioSessionObservation?

    init(outputs: [AudioSessionRouteOutputSnapshot], outputVolume: Double?) {
        self.outputs = outputs
        self.outputVolume = outputVolume
    }

    func currentRouteOutputs() -> [AudioSessionRouteOutputSnapshot] {
        outputs
    }

    func currentOutputVolume() -> Double? {
        outputVolume
    }

    func observeRouteChanges(_ handler: @escaping () -> Void) -> AudioSessionObservation {
        routeHandler = handler
        let observation = MockAudioSessionObservation()
        routeObservation = observation
        return observation
    }

    func observeOutputVolumeChanges(_ handler: @escaping () -> Void) -> AudioSessionObservation {
        volumeHandler = handler
        let observation = MockAudioSessionObservation()
        volumeObservation = observation
        return observation
    }

    func triggerRouteChange() {
        guard routeObservation?.isInvalidated != true else {
            return
        }
        routeHandler?()
    }

    func triggerVolumeChange() {
        guard volumeObservation?.isInvalidated != true else {
            return
        }
        volumeHandler?()
    }
}

private final class MockAudioSessionObservation: AudioSessionObservation {
    private(set) var isInvalidated = false

    func invalidate() {
        isInvalidated = true
    }
}
