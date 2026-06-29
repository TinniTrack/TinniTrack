import AVFoundation
import Foundation

struct AudioSessionRouteOutputSnapshot: Equatable {
    let portName: String
    let portTypeRawValue: String
    let portUID: String?
    let channelNames: [String]
}

struct CalibratedHeadphoneVerification: Equatable {
    let identifier: String
    let source: CalibratedHeadphoneVerificationSource
}

protocol CalibratedHeadphoneProfileResolving {
    func verification(for output: AudioSessionRouteOutputSnapshot) -> CalibratedHeadphoneVerification?
}

struct PublicAudioRouteCalibratedHeadphoneResolver: CalibratedHeadphoneProfileResolving {
    func verification(for output: AudioSessionRouteOutputSnapshot) -> CalibratedHeadphoneVerification? {
        nil
    }
}

protocol AudioSessionObservation: AnyObject {
    func invalidate()
}

protocol AudioSessionRouteVolumeProviding: AnyObject {
    func refreshRouteAndVolume()
    func currentRouteOutputs() -> [AudioSessionRouteOutputSnapshot]
    func currentOutputVolume() -> Double?
    func observeRouteChanges(_ handler: @escaping () -> Void) -> AudioSessionObservation
    func observeOutputVolumeChanges(_ handler: @escaping () -> Void) -> AudioSessionObservation
}

final class CalibratedAudioSessionGuardrailMonitor {
    private let provider: AudioSessionRouteVolumeProviding
    private let profileResolver: CalibratedHeadphoneProfileResolving
    private let dateProvider: () -> Date
    private var session: CalibratedAudioGuardrailSession
    private var observations: [AudioSessionObservation] = []

    init(
        provider: AudioSessionRouteVolumeProviding = AVAudioSessionRouteVolumeProvider(),
        profileResolver: CalibratedHeadphoneProfileResolving = PublicAudioRouteCalibratedHeadphoneResolver(),
        policy: CalibratedAudioGuardrailPolicy = CalibratedAudioGuardrailPolicy(),
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.provider = provider
        self.profileResolver = profileResolver
        self.dateProvider = dateProvider
        session = CalibratedAudioGuardrailSession(policy: policy)
    }

    func currentRouteDetails() -> CalibratedAudioRouteDetails {
        CalibratedAudioRouteDetails(
            outputs: provider.currentRouteOutputs().map { output in
                let verification = profileResolver.verification(for: output)
                return CalibratedAudioRouteOutput(
                    portName: output.portName,
                    portType: Self.portKind(for: output.portTypeRawValue),
                    portUID: output.portUID,
                    channelNames: output.channelNames,
                    verifiedCalibratedHeadphoneIdentifier: verification?.identifier,
                    verificationSource: verification?.source
                )
            }
        )
    }

    @discardableResult
    func validateCurrentGuardrails() -> CalibratedAudioGuardrailValidation {
        provider.refreshRouteAndVolume()
        return session.evaluate(
            route: currentRouteDetails(),
            outputVolume: provider.currentOutputVolume(),
            timestamp: dateProvider()
        )
    }

    func startMonitoring(
        onValidationChange: @escaping (CalibratedAudioGuardrailValidation) -> Void
    ) {
        stopMonitoring()
        onValidationChange(validateCurrentGuardrails())

        let routeObservation = provider.observeRouteChanges { [weak self] in
            guard let self else { return }
            let validation = self.session.routeDidChange(
                to: self.currentRouteDetails(),
                timestamp: self.dateProvider()
            )
            onValidationChange(validation)
        }

        let volumeObservation = provider.observeOutputVolumeChanges { [weak self] in
            guard let self else { return }
            let validation = self.session.volumeDidChange(
                to: self.provider.currentOutputVolume(),
                timestamp: self.dateProvider()
            )
            onValidationChange(validation)
        }

        observations = [routeObservation, volumeObservation]
    }

    func stopMonitoring() {
        observations.forEach { $0.invalidate() }
        observations = []
    }

    deinit {
        stopMonitoring()
    }

    static func portKind(for rawValue: String) -> CalibratedAudioRoutePortKind {
        switch rawValue {
        case AVAudioSession.Port.builtInSpeaker.rawValue:
            return .builtInSpeaker
        case AVAudioSession.Port.builtInReceiver.rawValue:
            return .builtInReceiver
        case AVAudioSession.Port.headphones.rawValue:
            return .wiredHeadphones
        case AVAudioSession.Port.bluetoothA2DP.rawValue:
            return .bluetoothA2DP
        case AVAudioSession.Port.bluetoothHFP.rawValue:
            return .bluetoothHFP
        case AVAudioSession.Port.bluetoothLE.rawValue:
            return .bluetoothLE
        case AVAudioSession.Port.airPlay.rawValue:
            return .airPlay
        case AVAudioSession.Port.carAudio.rawValue:
            return .carAudio
        case AVAudioSession.Port.HDMI.rawValue:
            return .hdmi
        case AVAudioSession.Port.usbAudio.rawValue:
            return .usbAudio
        default:
            return .unknown(rawValue)
        }
    }
}

final class AVAudioSessionRouteVolumeProvider: AudioSessionRouteVolumeProviding {
    private let audioSession: AVAudioSession
    private let notificationCenter: NotificationCenter

    init(
        audioSession: AVAudioSession = .sharedInstance(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.audioSession = audioSession
        self.notificationCenter = notificationCenter
    }

    func refreshRouteAndVolume() {
        do {
            if audioSession.category != .playAndRecord {
                try audioSession.setCategory(.playback, mode: .default, options: [])
            }
            try audioSession.setActive(true)
        } catch {
            // Guardrail validation will fail safely if route or volume remains unavailable.
        }
    }

    func currentRouteOutputs() -> [AudioSessionRouteOutputSnapshot] {
        audioSession.currentRoute.outputs.map { output in
            AudioSessionRouteOutputSnapshot(
                portName: output.portName,
                portTypeRawValue: output.portType.rawValue,
                portUID: output.uid,
                channelNames: output.channels?.map(\.channelName) ?? []
            )
        }
    }

    func currentOutputVolume() -> Double? {
        Double(audioSession.outputVolume)
    }

    func observeRouteChanges(_ handler: @escaping () -> Void) -> AudioSessionObservation {
        NotificationAudioSessionObservation(
            notificationCenter.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: audioSession,
                queue: .main
            ) { _ in
                handler()
            },
            notificationCenter: notificationCenter
        )
    }

    func observeOutputVolumeChanges(_ handler: @escaping () -> Void) -> AudioSessionObservation {
        KeyValueAudioSessionObservation(
            audioSession.observe(\.outputVolume, options: [.new]) { _, _ in
                handler()
            }
        )
    }
}

private final class NotificationAudioSessionObservation: AudioSessionObservation {
    private var observer: NSObjectProtocol?
    private let notificationCenter: NotificationCenter

    init(_ observer: NSObjectProtocol, notificationCenter: NotificationCenter) {
        self.observer = observer
        self.notificationCenter = notificationCenter
    }

    func invalidate() {
        guard let observer else {
            return
        }
        notificationCenter.removeObserver(observer)
        self.observer = nil
    }

    deinit {
        invalidate()
    }
}

private final class KeyValueAudioSessionObservation: AudioSessionObservation {
    private var observation: NSKeyValueObservation?

    init(_ observation: NSKeyValueObservation) {
        self.observation = observation
    }

    func invalidate() {
        observation?.invalidate()
        observation = nil
    }

    deinit {
        invalidate()
    }
}
