import AVFoundation
import Foundation

enum HeadphoneRouteVerificationLevel: String, Equatable, Codable {
    case failed
    case compatibleBluetoothPlaybackRoute
    case likelyAirPodsProRoute
    case likelyAirPodsProCommunicationRoute
}

enum HeadphoneRouteIssue: String, Equatable, Codable {
    case noOutput
    case multipleOutputs
    case builtInOutput
    case unsupportedWiredOrExternalRoute
    case bluetoothHeadsetProfile
    case bluetoothLowEnergyRoute
    case unknownRoute
    case outputVolumeUnavailable
}

struct HeadphoneRouteAssessment: Equatable {
    let level: HeadphoneRouteVerificationLevel
    let outputCount: Int
    let portName: String?
    let portType: CalibratedAudioRoutePortKind?
    let portTypeRawValue: String?
    let routeUID: String?
    let channelNames: [String]
    let outputVolume: Double?
    let issues: [HeadphoneRouteIssue]

    static let notEvaluated = HeadphoneRouteAssessment(
        level: .failed,
        outputCount: 0,
        portName: nil,
        portType: nil,
        portTypeRawValue: nil,
        routeUID: nil,
        channelNames: [],
        outputVolume: nil,
        issues: [.noOutput]
    )

    var looksLikeAirPodsProRoute: Bool {
        switch level {
        case .likelyAirPodsProRoute, .likelyAirPodsProCommunicationRoute:
            return true
        case .failed, .compatibleBluetoothPlaybackRoute:
            return false
        }
    }

    var isCompatibleBluetoothPlaybackRoute: Bool {
        outputCount == 1 && portType == .bluetoothA2DP
    }

    var isAirPodsProPlaybackRouteCandidate: Bool {
        isCompatibleBluetoothPlaybackRoute && looksLikeAirPodsProRoute
    }

    var isBluetoothHeadsetProfile: Bool {
        portType == .bluetoothHFP
    }

    var primaryIssue: HeadphoneRouteIssue? {
        issues.first
    }

    var routeUIDFingerprint: String? {
        routeUID.map(Self.stableFingerprint)
    }

    var diagnosticItems: [HeadphoneRouteDiagnosticItem] {
        [
            HeadphoneRouteDiagnosticItem(title: "Result", value: isCompatibleBluetoothPlaybackRoute ? "compatible playback route" : "failed"),
            HeadphoneRouteDiagnosticItem(title: "AirPods name signal", value: looksLikeAirPodsProRoute ? "looks like AirPods Pro" : "not recognized"),
            HeadphoneRouteDiagnosticItem(title: "Level", value: level.rawValue),
            HeadphoneRouteDiagnosticItem(title: "Issue", value: issues.map(\.rawValue).joined(separator: ", ").nilIfEmpty ?? "none"),
            HeadphoneRouteDiagnosticItem(title: "Output count", value: "\(outputCount)"),
            HeadphoneRouteDiagnosticItem(title: "Port name", value: portName ?? "none"),
            HeadphoneRouteDiagnosticItem(title: "Port type", value: portType.map { String(describing: $0) } ?? "none"),
            HeadphoneRouteDiagnosticItem(title: "Raw port type", value: portTypeRawValue ?? "none"),
            HeadphoneRouteDiagnosticItem(title: "Route UID hash", value: routeUIDFingerprint ?? "none"),
            HeadphoneRouteDiagnosticItem(title: "Channels", value: channelNames.joined(separator: ", ").nilIfEmpty ?? "none"),
            HeadphoneRouteDiagnosticItem(title: "Output volume", value: outputVolume.map { String(format: "%.3f", $0) } ?? "none")
        ]
    }

    var diagnosticReport: String {
        diagnosticItems
            .map { "\($0.title): \($0.value)" }
            .joined(separator: "\n")
    }

    nonisolated private static func stableFingerprint(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }
}

struct HeadphoneRouteDiagnosticItem: Equatable, Identifiable {
    let title: String
    let value: String

    var id: String {
        title
    }
}

struct HeadphoneRouteAssessor {
    func assess(
        outputs: [AudioSessionRouteOutputSnapshot],
        outputVolume: Double?
    ) -> HeadphoneRouteAssessment {
        guard !outputs.isEmpty else {
            return HeadphoneRouteAssessment(
                level: .failed,
                outputCount: 0,
                portName: nil,
                portType: nil,
                portTypeRawValue: nil,
                routeUID: nil,
                channelNames: [],
                outputVolume: outputVolume,
                issues: [.noOutput]
            )
        }

        guard outputs.count == 1, let output = outputs.first else {
            return HeadphoneRouteAssessment(
                level: .failed,
                outputCount: outputs.count,
                portName: outputs.first?.portName,
                portType: outputs.first.map { CalibratedAudioSessionGuardrailMonitor.portKind(for: $0.portTypeRawValue) },
                portTypeRawValue: outputs.first?.portTypeRawValue,
                routeUID: outputs.first?.portUID,
                channelNames: outputs.first?.channelNames ?? [],
                outputVolume: outputVolume,
                issues: [.multipleOutputs]
            )
        }

        let portType = CalibratedAudioSessionGuardrailMonitor.portKind(for: output.portTypeRawValue)
        let issue = issue(for: portType)
        let level = verificationLevel(for: portType, portName: output.portName)

        return HeadphoneRouteAssessment(
            level: level,
            outputCount: 1,
            portName: output.portName,
            portType: portType,
            portTypeRawValue: output.portTypeRawValue,
            routeUID: output.portUID,
            channelNames: output.channelNames,
            outputVolume: outputVolume,
            issues: issue.map { [$0] } ?? []
        )
    }

    private func verificationLevel(
        for portType: CalibratedAudioRoutePortKind,
        portName: String
    ) -> HeadphoneRouteVerificationLevel {
        if portType == .bluetoothA2DP {
            return Self.looksLikeAirPodsPro(portName)
                ? .likelyAirPodsProRoute
                : .compatibleBluetoothPlaybackRoute
        }

        if portType == .bluetoothHFP, Self.looksLikeAirPodsPro(portName) {
            return .likelyAirPodsProCommunicationRoute
        }

        return .failed
    }

    private func issue(for portType: CalibratedAudioRoutePortKind) -> HeadphoneRouteIssue? {
        switch portType {
        case .bluetoothA2DP:
            return nil
        case .bluetoothHFP:
            return .bluetoothHeadsetProfile
        case .bluetoothLE:
            return .bluetoothLowEnergyRoute
        case .builtInSpeaker, .builtInReceiver:
            return .builtInOutput
        case .wiredHeadphones, .airPlay, .carAudio, .hdmi, .usbAudio:
            return .unsupportedWiredOrExternalRoute
        case .unknown:
            return .unknownRoute
        }
    }

    static func looksLikeAirPodsPro(_ portName: String) -> Bool {
        let normalized = portName
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "-", with: " ")

        let tokenString = normalized
            .split { !$0.isLetter && !$0.isNumber }
            .joined(separator: " ")
        let paddedTokenString = " \(tokenString) "

        return paddedTokenString.contains(" airpods pro ")
            || paddedTokenString.contains(" air pods pro ")
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
