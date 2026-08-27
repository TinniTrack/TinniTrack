import AVFoundation
import Foundation
import UIKit

protocol StudyNo1RuntimeContextProviding {
    func deviceContext() -> StudyNo1DeviceContext
    func audioSessionContext() -> StudyNo1AudioSessionContext
    func airPodsContext(guardrailValidation: CalibratedAudioGuardrailValidation) -> StudyNo1AirPodsContext
}

struct SystemStudyNo1RuntimeContextProvider: StudyNo1RuntimeContextProviding {
    private let audioSession: AVAudioSession

    init(audioSession: AVAudioSession = .sharedInstance()) {
        self.audioSession = audioSession
    }

    func deviceContext() -> StudyNo1DeviceContext {
        StudyNo1DeviceContext(
            deviceModel: Self.hardwareModelIdentifier(),
            systemName: UIDevice.current.systemName,
            systemVersion: UIDevice.current.systemVersion
        )
    }

    func audioSessionContext() -> StudyNo1AudioSessionContext {
        StudyNo1AudioSessionContext(
            category: audioSession.category.rawValue,
            mode: audioSession.mode.rawValue,
            options: optionDescriptions(audioSession.categoryOptions),
            sampleRate: audioSession.sampleRate,
            bufferSize: audioSession.ioBufferDuration * max(audioSession.sampleRate, 1.0)
        )
    }

    func airPodsContext(guardrailValidation: CalibratedAudioGuardrailValidation) -> StudyNo1AirPodsContext {
        let identifier = guardrailValidation.metadata.supportedHeadphoneIdentifier
            ?? guardrailValidation.metadata.routeDetails?.outputs.first?.verifiedCalibratedHeadphoneIdentifier
        return StudyNo1AirPodsContext(
            modelIdentifier: identifier,
            firmwareVersion: nil,
            unavailableReason: "AirPods firmware is unavailable through public iOS route APIs."
        )
    }

    private func optionDescriptions(_ options: AVAudioSession.CategoryOptions) -> [String] {
        var values: [String] = []
        if options.contains(.mixWithOthers) { values.append("mixWithOthers") }
        if options.contains(.duckOthers) { values.append("duckOthers") }
        if options.contains(.allowBluetoothHFP) { values.append("allowBluetoothHFP") }
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
