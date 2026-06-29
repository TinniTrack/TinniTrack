import Foundation
import Testing
@testable import TinniTrack

struct CalibratedAudioGuardrailPolicyTests {
    private let policy = CalibratedAudioGuardrailPolicy()
    private let timestamp = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func supportedAirPodsPro2RouteAtMaximumVolumePassesWithMetadata() {
        let validation = policy.validate(
            route: supportedRoute(),
            outputVolume: 1.0,
            timestamp: timestamp
        )

        #expect(validation.state == .passed)
        #expect(validation.error == nil)
        #expect(validation.metadata.supportedHeadphoneIdentifier == "AIRPODSPROV2")
        #expect(validation.metadata.rawOutputVolume == 1.0)
        #expect(validation.metadata.bucketedVolume == VolumeCurveBucket(outputVolume: 1.0, splOffsetDB: 0.0))
        #expect(validation.metadata.timestamp == timestamp)
        #expect(validation.metadata.volumePolicyDescription.contains("Maximum"))
    }

    @Test(arguments: [
        CalibratedAudioRoutePortKind.builtInSpeaker,
        .builtInReceiver,
        .wiredHeadphones,
        .bluetoothHFP,
        .bluetoothLE,
        .airPlay,
        .carAudio,
        .hdmi,
        .usbAudio,
        .unknown("mystery")
    ])
    func unsupportedRoutesFailWithStructuredError(portType: CalibratedAudioRoutePortKind) {
        let route = CalibratedAudioRouteDetails(outputs: [
            CalibratedAudioRouteOutput(
                portName: "Unsupported",
                portType: portType,
                verifiedCalibratedHeadphoneIdentifier: "AIRPODSPROV2",
                verificationSource: .appCalibrationProfile
            )
        ])

        let validation = policy.validate(route: route, outputVolume: 1.0, timestamp: timestamp)

        #expect(validation.state == .failed)
        #expect(validation.error == .unsupportedRoute(route: route, supportedPortTypes: [.bluetoothA2DP]))
    }

    @Test
    func genericBluetoothRouteDoesNotValidateWithoutProfileProof() {
        let route = CalibratedAudioRouteDetails(outputs: [
            CalibratedAudioRouteOutput(
                portName: "Bluetooth Headphones",
                portType: .bluetoothA2DP
            )
        ])

        let validation = policy.validate(route: route, outputVolume: 1.0, timestamp: timestamp)

        #expect(validation.state == .failed)
        #expect(validation.error == .unverifiedHeadphoneProfile(route: route, requiredIdentifier: "AIRPODSPROV2"))
    }

    @Test
    func broadAirPodsRouteNameMatchingAloneDoesNotValidateAirPodsPro2Support() {
        let route = CalibratedAudioRouteDetails(outputs: [
            CalibratedAudioRouteOutput(
                portName: "Vasyl's AirPods Pro 2",
                portType: .bluetoothA2DP
            )
        ])

        let validation = policy.validate(route: route, outputVolume: 1.0, timestamp: timestamp)

        #expect(validation.state == .failed)
        #expect(validation.error == .unverifiedHeadphoneProfile(route: route, requiredIdentifier: "AIRPODSPROV2"))
        #expect(validation.metadata.supportedHeadphoneIdentifier == nil)
    }

    @Test
    func unknownRouteDataReturnsUnavailableAudioSessionData() {
        let noRouteValidation = policy.validate(route: nil, outputVolume: 1.0, timestamp: timestamp)
        let emptyRouteValidation = policy.validate(
            route: CalibratedAudioRouteDetails(outputs: []),
            outputVolume: 1.0,
            timestamp: timestamp
        )

        #expect(noRouteValidation.state == .failed)
        #expect(noRouteValidation.error == .unavailableAudioSessionData(reason: "No current audio route outputs were available."))
        #expect(emptyRouteValidation.state == .failed)
        #expect(emptyRouteValidation.error == .unavailableAudioSessionData(reason: "No current audio route outputs were available."))
    }

    @Test
    func missingCalibrationProfileReturnsStructuredError() {
        let policy = CalibratedAudioGuardrailPolicy(supportedHeadphoneIdentifiers: [])
        let validation = policy.validate(route: supportedRoute(), outputVolume: 1.0, timestamp: timestamp)

        #expect(validation.state == .failed)
        #expect(validation.error == .missingCalibrationProfile("AIRPODSPROV2"))
    }

    @Test
    func maximumVolumePolicyAcceptsToleranceAndRejectsLowerVolume() {
        let withinTolerance = policy.validate(
            route: supportedRoute(),
            outputVolume: 0.999_95,
            timestamp: timestamp
        )
        let outsideTolerance = policy.validate(
            route: supportedRoute(),
            outputVolume: 0.999_8,
            timestamp: timestamp
        )

        #expect(withinTolerance.state == .passed)
        #expect(outsideTolerance.state == .failed)
        #expect(outsideTolerance.error == .invalidVolume(0.999_8, policy: .maximum))
    }

    @Test(arguments: [-0.01, 1.01, Double.infinity])
    func invalidVolumeValuesFailWithStructuredError(outputVolume: Double) {
        let validation = policy.validate(
            route: supportedRoute(),
            outputVolume: outputVolume,
            timestamp: timestamp
        )

        #expect(validation.state == .failed)
        guard case .invalidVolume(let value, let policy) = validation.error else {
            Issue.record("Expected invalidVolume, got \(String(describing: validation.error))")
            return
        }
        #expect(value == outputVolume)
        #expect(policy == .maximum)
    }

    @Test
    func allSixteenVolumeBucketsAreRecordedThroughGuardrailMetadata() throws {
        let expectedOffsets: [Double] = [
            -65.5,
            -58.5,
            -52.5,
            -47.0,
            -42.0,
            -37.5,
            -33.0,
            -29.0,
            -25.0,
            -21.0,
            -17.0,
            -13.5,
            -10.0,
            -6.5,
            -3.0,
            0.0
        ]

        for index in 1...16 {
            let volume = Double(index) / 16.0
            let validation = policy.validate(
                route: supportedRoute(),
                outputVolume: volume,
                timestamp: timestamp
            )

            #expect(validation.metadata.rawOutputVolume == volume)
            #expect(validation.metadata.bucketedVolume == VolumeCurveBucket(
                outputVolume: volume,
                splOffsetDB: expectedOffsets[index - 1]
            ))
        }
    }

    @Test
    func routeChangeAfterPassRequiresRestart() {
        var session = CalibratedAudioGuardrailSession(policy: policy)
        let pass = session.evaluate(route: supportedRoute(), outputVolume: 1.0, timestamp: timestamp)
        let changedRoute = CalibratedAudioRouteDetails(outputs: [
            CalibratedAudioRouteOutput(portName: "Speaker", portType: .builtInSpeaker)
        ])

        let invalidated = session.routeDidChange(
            to: changedRoute,
            timestamp: timestamp.addingTimeInterval(10)
        )

        #expect(pass.state == .passed)
        #expect(invalidated.state == .restartRequired)
        guard case .routeChanged(let previous, let current) = invalidated.error else {
            Issue.record("Expected routeChanged, got \(String(describing: invalidated.error))")
            return
        }
        #expect(previous.validationState == .passed)
        #expect(current == changedRoute)
    }

    @Test
    func volumeChangeAfterPassRequiresRestart() {
        var session = CalibratedAudioGuardrailSession(policy: policy)
        let pass = session.evaluate(route: supportedRoute(), outputVolume: 1.0, timestamp: timestamp)

        let invalidated = session.volumeDidChange(
            to: 0.9375,
            timestamp: timestamp.addingTimeInterval(10)
        )

        #expect(pass.state == .passed)
        #expect(invalidated.state == .restartRequired)
        guard case .volumeChanged(let previous, let currentVolume) = invalidated.error else {
            Issue.record("Expected volumeChanged, got \(String(describing: invalidated.error))")
            return
        }
        #expect(previous.rawOutputVolume == 1.0)
        #expect(currentVolume == 0.9375)
    }

    @Test
    func sameVolumeWithinToleranceDoesNotInvalidatePassedSession() {
        var session = CalibratedAudioGuardrailSession(policy: policy)
        let pass = session.evaluate(route: supportedRoute(), outputVolume: 1.0, timestamp: timestamp)

        let stillPassed = session.volumeDidChange(
            to: 0.999_95,
            timestamp: timestamp.addingTimeInterval(10)
        )

        #expect(pass.state == .passed)
        #expect(stillPassed.state == .passed)
        #expect(stillPassed.error == nil)
    }

    private func supportedRoute() -> CalibratedAudioRouteDetails {
        CalibratedAudioRouteDetails(outputs: [
            CalibratedAudioRouteOutput(
                portName: "Verified AirPods Pro 2",
                portType: .bluetoothA2DP,
                portUID: "verified-airpods-pro-2",
                channelNames: ["left", "right"],
                verifiedCalibratedHeadphoneIdentifier: "AIRPODSPROV2",
                verificationSource: .appCalibrationProfile
            )
        ])
    }
}
