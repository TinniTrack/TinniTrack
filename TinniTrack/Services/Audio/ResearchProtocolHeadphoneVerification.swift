import AVFoundation
import Foundation

final class ResearchProtocolCalibratedHeadphoneResolver: CalibratedHeadphoneProfileResolving {
    var airPodsPro2Verified = false

    func verification(for output: AudioSessionRouteOutputSnapshot) -> CalibratedHeadphoneVerification? {
        guard airPodsPro2Verified,
              output.portTypeRawValue == AVAudioSession.Port.bluetoothA2DP.rawValue
        else {
            return nil
        }

        return CalibratedHeadphoneVerification(
            identifier: CalibratedHeadphoneIdentifier.airPodsPro2,
            source: .researchProtocol
        )
    }
}
