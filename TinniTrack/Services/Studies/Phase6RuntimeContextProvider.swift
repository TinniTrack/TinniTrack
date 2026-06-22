import AVFoundation
import Foundation
import UIKit

protocol Phase6RuntimeContextProviding {
    func deviceContext() -> Phase6DeviceContext
    func audioSessionContext() -> Phase6AudioSessionContext
    func airPodsContext(guardrailValidation: CalibratedAudioGuardrailValidation) -> Phase6AirPodsContext
}

struct SystemPhase6RuntimeContextProvider: Phase6RuntimeContextProviding {
    private let audioSession: AVAudioSession

    init(audioSession: AVAudioSession = .sharedInstance()) {
        self.audioSession = audioSession
    }

    func deviceContext() -> Phase6DeviceContext {
        Phase6DeviceContext(
            deviceModel: Self.hardwareModelIdentifier(),
            systemName: UIDevice.current.systemName,
            systemVersion: UIDevice.current.systemVersion
        )
    }

    func audioSessionContext() -> Phase6AudioSessionContext {
        Phase6AudioSessionContext(
            category: audioSession.category.rawValue,
            mode: audioSession.mode.rawValue,
            options: optionDescriptions(audioSession.categoryOptions),
            sampleRate: audioSession.sampleRate,
            bufferSize: audioSession.ioBufferDuration * max(audioSession.sampleRate, 1.0)
        )
    }

    func airPodsContext(guardrailValidation: CalibratedAudioGuardrailValidation) -> Phase6AirPodsContext {
        let identifier = guardrailValidation.metadata.supportedHeadphoneIdentifier
            ?? guardrailValidation.metadata.routeDetails?.outputs.first?.verifiedCalibratedHeadphoneIdentifier
        return Phase6AirPodsContext(
            modelIdentifier: identifier,
            firmwareVersion: nil,
            unavailableReason: "AirPods firmware is unavailable through public iOS route APIs."
        )
    }

    private func optionDescriptions(_ options: AVAudioSession.CategoryOptions) -> [String] {
        var values: [String] = []
        if options.contains(.mixWithOthers) { values.append("mixWithOthers") }
        if options.contains(.duckOthers) { values.append("duckOthers") }
        if options.contains(.allowBluetooth) { values.append("allowBluetooth") }
        if options.contains(.defaultToSpeaker) { values.append("defaultToSpeaker") }
        if options.contains(.interruptSpokenAudioAndMixWithOthers) { values.append("interruptSpokenAudioAndMixWithOthers") }
        if options.contains(.allowBluetoothA2DP) { values.append("allowBluetoothA2DP") }
        if options.contains(.allowAirPlay) { values.append("allowAirPlay") }
        if options.contains(.overrideMutedMicrophoneInterruption) { values.append("overrideMutedMicrophoneInterruption") }
        return values
    }

    private static func hardwareModelIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        return mirror.children.reduce(into: "") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else {
                return
            }
            identifier.append(String(UnicodeScalar(UInt8(value))))
        }
    }
}
