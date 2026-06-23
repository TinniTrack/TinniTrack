import AVFoundation
import Foundation
import Testing
@testable import TinniTrack

struct HeadphoneRouteAssessmentTests {
    private let assessor = HeadphoneRouteAssessor()

    @Test
    func noOutputFailsWithNoOutputIssue() {
        let assessment = assessor.assess(outputs: [], outputVolume: 1.0)

        #expect(assessment.level == .failed)
        #expect(assessment.primaryIssue == .noOutput)
        #expect(assessment.passesAirPodsPro2Heuristic == false)
    }

    @Test
    func multipleOutputsFailWithMultipleOutputsIssue() {
        let assessment = assessor.assess(
            outputs: [
                output(name: "AirPods Pro 2", portType: .bluetoothA2DP),
                output(name: "Speaker", portType: .builtInSpeaker)
            ],
            outputVolume: 1.0
        )

        #expect(assessment.level == .failed)
        #expect(assessment.primaryIssue == .multipleOutputs)
        #expect(assessment.outputCount == 2)
    }

    @Test(arguments: [
        AVAudioSession.Port.builtInSpeaker,
        .builtInReceiver
    ])
    func builtInOutputsFailWithBuiltInOutputIssue(portType: AVAudioSession.Port) {
        let assessment = assessor.assess(outputs: [output(name: "iPhone", portType: portType)], outputVolume: 1.0)

        #expect(assessment.level == .failed)
        #expect(assessment.primaryIssue == .builtInOutput)
    }

    @Test(arguments: [
        AVAudioSession.Port.headphones,
        .airPlay,
        .carAudio,
        .HDMI,
        .usbAudio
    ])
    func wiredAndExternalRoutesFailWithUnsupportedExternalIssue(portType: AVAudioSession.Port) {
        let assessment = assessor.assess(outputs: [output(name: "External Output", portType: portType)], outputVolume: 1.0)

        #expect(assessment.level == .failed)
        #expect(assessment.primaryIssue == .unsupportedWiredOrExternalRoute)
    }

    @Test
    func bluetoothHeadsetProfileFails() {
        let assessment = assessor.assess(
            outputs: [output(name: "AirPods Pro 2", portType: .bluetoothHFP)],
            outputVolume: 1.0
        )

        #expect(assessment.level == .failed)
        #expect(assessment.primaryIssue == .bluetoothHeadsetProfile)
    }

    @Test
    func bluetoothLowEnergyRouteFails() {
        let assessment = assessor.assess(
            outputs: [output(name: "AirPods Pro 2", portType: .bluetoothLE)],
            outputVolume: 1.0
        )

        #expect(assessment.level == .failed)
        #expect(assessment.primaryIssue == .bluetoothLowEnergyRoute)
    }

    @Test(arguments: [
        "Vasyl's AirPods Pro 2",
        "AirPods Pro (2nd generation)",
        "AirPods Pro second generation",
        "AirPods Pro Gen 2"
    ])
    func airPodsPro2LikeA2DPRoutePasses(portName: String) {
        let assessment = assessor.assess(
            outputs: [output(name: portName, portType: .bluetoothA2DP)],
            outputVolume: 0.25
        )

        #expect(assessment.level == .likelyAirPodsPro2Route)
        #expect(assessment.issues.isEmpty)
        #expect(assessment.passesAirPodsPro2Heuristic)
        #expect(assessment.outputVolume == 0.25)
    }

    @Test(arguments: [
        "Bluetooth Speaker",
        "AirPods Max",
        "AirPods Pro",
        "AirPods 3"
    ])
    func nonMatchingA2DPRouteFailsAirPodsPro2Heuristic(portName: String) {
        let assessment = assessor.assess(
            outputs: [output(name: portName, portType: .bluetoothA2DP)],
            outputVolume: 1.0
        )

        #expect(assessment.level == .compatibleBluetoothPlaybackRoute)
        #expect(assessment.primaryIssue == .unsupportedBluetoothPlaybackDevice)
        #expect(assessment.passesAirPodsPro2Heuristic == false)
    }

    @Test
    func diagnosticReportIncludesRouteDecisionInputsWithoutRawUID() {
        let assessment = assessor.assess(
            outputs: [output(name: "Basil's AirPods Pro", portType: .bluetoothA2DP, uid: "private-route-id")],
            outputVolume: 0.9
        )

        #expect(assessment.diagnosticReport.contains("Result: failed"))
        #expect(assessment.diagnosticReport.contains("Issue: unsupportedBluetoothPlaybackDevice"))
        #expect(assessment.diagnosticReport.contains("Port name: Basil's AirPods Pro"))
        #expect(assessment.diagnosticReport.contains("Raw port type: BluetoothA2DPOutput"))
        #expect(assessment.diagnosticReport.contains("Route UID hash:"))
        #expect(assessment.diagnosticReport.contains("private-route-id") == false)
    }

    @Test
    func routeNameHeuristicResolverMarksOnlyLikelyAirPodsPro2Routes() {
        let resolver = RouteNameHeuristicCalibratedHeadphoneResolver()

        let verified = resolver.verification(for: output(name: "Vasyl's AirPods Pro 2", portType: .bluetoothA2DP))
        let rejected = resolver.verification(for: output(name: "AirPods Max", portType: .bluetoothA2DP))

        #expect(verified?.identifier == "AIRPODSPROV2")
        #expect(verified?.source == .routeNameHeuristic)
        #expect(rejected == nil)
    }

    private func output(
        name: String,
        portType: AVAudioSession.Port,
        uid: String = "route-uid",
        channelNames: [String] = ["left", "right"]
    ) -> AudioSessionRouteOutputSnapshot {
        AudioSessionRouteOutputSnapshot(
            portName: name,
            portTypeRawValue: portType.rawValue,
            portUID: uid,
            channelNames: channelNames
        )
    }
}
