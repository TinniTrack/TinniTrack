import AVFoundation
import Foundation
import Testing
@testable import TinniTrack

struct ResearchProtocolHeadphoneVerificationTests {
    private let timestamp = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func unconfirmedRouteDoesNotResolveFromAirPodsLikeName() {
        let resolver = ResearchProtocolCalibratedHeadphoneResolver()

        let verification = resolver.verification(for: output(name: "AirPods Pro 2", uid: "route-a"))

        #expect(verification == nil)
    }

    @Test
    func participantConfirmedA2DPRouteResolvesWithResearchProtocolSource() {
        let resolver = ResearchProtocolCalibratedHeadphoneResolver()
        resolver.confirmation = confirmation(name: "Basil’s AirPods Pro", uid: "route-a")

        let verification = resolver.verification(for: output(name: "Basil’s AirPods Pro", uid: "route-a"))

        #expect(verification?.identifier == "AIRPODSPROV2")
        #expect(verification?.source == .researchProtocol)
    }

    @Test
    func confirmationIsBoundToA2DPRouteUID() {
        let resolver = ResearchProtocolCalibratedHeadphoneResolver()
        resolver.confirmation = confirmation(name: "Basil’s AirPods Pro", uid: "route-a")

        let differentRoute = resolver.verification(for: output(name: "Basil’s AirPods Pro", uid: "route-b"))
        let callRoute = resolver.verification(for: output(
            name: "Basil’s AirPods Pro",
            uid: "route-a",
            portType: .bluetoothHFP
        ))

        #expect(differentRoute == nil)
        #expect(callRoute == nil)
    }

    @Test
    func confirmationStillRequiresAirPodsProFamilyNameSignal() {
        let resolver = ResearchProtocolCalibratedHeadphoneResolver()
        resolver.confirmation = confirmation(name: "Basil’s AirPods Pro", uid: "route-a")

        let renamedRoute = resolver.verification(for: output(name: "Bluetooth Headphones", uid: "route-a"))

        #expect(renamedRoute == nil)
    }

    @Test
    func missingRouteUIDFallsBackToExactNameWithinCurrentAttempt() {
        let resolver = ResearchProtocolCalibratedHeadphoneResolver()
        resolver.confirmation = confirmation(name: "Basil’s AirPods Pro", uid: nil)

        let matching = resolver.verification(for: output(name: "Basil’s AirPods Pro", uid: nil))
        let renamed = resolver.verification(for: output(name: "Other AirPods Pro", uid: nil))

        #expect(matching?.identifier == "AIRPODSPROV2")
        #expect(renamed == nil)
    }

    private func confirmation(name: String, uid: String?) -> ResearchProtocolHeadphoneRouteConfirmation {
        ResearchProtocolHeadphoneRouteConfirmation(
            headphoneIdentifier: CalibratedHeadphoneIdentifier.airPodsPro2,
            portUID: uid,
            portName: name,
            confirmedAt: timestamp
        )
    }

    private func output(
        name: String,
        uid: String?,
        portType: AVAudioSession.Port = .bluetoothA2DP
    ) -> AudioSessionRouteOutputSnapshot {
        AudioSessionRouteOutputSnapshot(
            portName: name,
            portTypeRawValue: portType.rawValue,
            portUID: uid,
            channelNames: ["left", "right"]
        )
    }
}
