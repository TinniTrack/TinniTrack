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
        #expect(assessment.isCompatibleBluetoothPlaybackRoute == false)
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
    func airPodsProHeadsetProfileRetainsAdvisoryNameSignalDuringCalls() {
        let assessment = assessor.assess(
            outputs: [output(name: "AirPods Pro 2", portType: .bluetoothHFP)],
            outputVolume: 1.0
        )

        #expect(assessment.level == .likelyAirPodsProCommunicationRoute)
        #expect(assessment.primaryIssue == .bluetoothHeadsetProfile)
        #expect(assessment.looksLikeAirPodsProRoute)
        #expect(assessment.isCompatibleBluetoothPlaybackRoute == false)
        #expect(assessment.diagnosticReport.contains("Result: failed"))
        #expect(assessment.diagnosticReport.contains("AirPods name signal: looks like AirPods Pro"))
    }

    @Test
    func genericBluetoothHeadsetProfileFails() {
        let assessment = assessor.assess(
            outputs: [output(name: "Bluetooth Headset", portType: .bluetoothHFP)],
            outputVolume: 1.0
        )

        #expect(assessment.level == .failed)
        #expect(assessment.primaryIssue == .bluetoothHeadsetProfile)
        #expect(assessment.looksLikeAirPodsProRoute == false)
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
        "Basil’s AirPods Pro",
        "Air Pods Pro",
        "AirPods Pro (2nd generation)",
        "AirPods Pro second generation",
        "AirPods Pro Gen 2"
    ])
    func airPodsProLikeA2DPRouteIsCompatibleWithAdvisoryNameSignal(portName: String) {
        let assessment = assessor.assess(
            outputs: [output(name: portName, portType: .bluetoothA2DP)],
            outputVolume: 0.25
        )

        #expect(assessment.level == .likelyAirPodsProRoute)
        #expect(assessment.issues.isEmpty)
        #expect(assessment.looksLikeAirPodsProRoute)
        #expect(assessment.isCompatibleBluetoothPlaybackRoute)
        #expect(assessment.outputVolume == 0.25)
    }

    @Test(arguments: [
        "Bluetooth Speaker",
        "AirPods Max",
        "AirPods 3",
        "Beats Fit Pro 2",
        "Galaxy Buds Pro 2",
        "FakeAirPods Pro",
        "NotAirPods Pro",
        "AirPods Professional"
    ])
    func otherA2DPNamesRemainCompatibleWithoutAirPodsNameSignal(portName: String) {
        let assessment = assessor.assess(
            outputs: [output(name: portName, portType: .bluetoothA2DP)],
            outputVolume: 1.0
        )

        #expect(assessment.level == .compatibleBluetoothPlaybackRoute)
        #expect(assessment.issues.isEmpty)
        #expect(assessment.looksLikeAirPodsProRoute == false)
        #expect(assessment.isCompatibleBluetoothPlaybackRoute)
    }

    @Test
    func diagnosticReportIncludesRouteDecisionInputsWithoutRawUID() {
        let assessment = assessor.assess(
            outputs: [output(name: "Basil's AirPods Pro", portType: .bluetoothA2DP, uid: "private-route-id")],
            outputVolume: 0.9
        )

        #expect(assessment.diagnosticReport.contains("Result: compatible playback route"))
        #expect(assessment.diagnosticReport.contains("AirPods name signal: looks like AirPods Pro"))
        #expect(assessment.diagnosticReport.contains("Issue: none"))
        #expect(assessment.diagnosticReport.contains("Port name: Basil's AirPods Pro"))
        #expect(assessment.diagnosticReport.contains("Raw port type: BluetoothA2DPOutput"))
        #expect(assessment.diagnosticReport.contains("Route UID hash:"))
        #expect(assessment.diagnosticReport.contains("private-route-id") == false)
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
