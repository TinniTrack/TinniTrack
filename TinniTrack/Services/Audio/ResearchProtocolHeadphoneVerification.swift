import AVFoundation
import Foundation

struct ResearchProtocolHeadphoneRouteConfirmation: Equatable {
    let headphoneIdentifier: String
    let portUID: String?
    let portName: String
    let confirmedAt: Date

    func matches(_ output: AudioSessionRouteOutputSnapshot) -> Bool {
        guard output.portTypeRawValue == AVAudioSession.Port.bluetoothA2DP.rawValue else {
            return false
        }

        if let portUID {
            return output.portUID == portUID
        }

        return output.portUID == nil && output.portName == portName
    }
}

final class ResearchProtocolCalibratedHeadphoneResolver: CalibratedHeadphoneProfileResolving {
    var confirmation: ResearchProtocolHeadphoneRouteConfirmation?

    func verification(for output: AudioSessionRouteOutputSnapshot) -> CalibratedHeadphoneVerification? {
        guard let confirmation,
              confirmation.headphoneIdentifier == CalibratedHeadphoneIdentifier.airPodsPro2,
              HeadphoneRouteAssessor.looksLikeAirPodsPro(output.portName),
              confirmation.matches(output)
        else {
            return nil
        }

        return CalibratedHeadphoneVerification(
            identifier: confirmation.headphoneIdentifier,
            source: .researchProtocol
        )
    }
}
