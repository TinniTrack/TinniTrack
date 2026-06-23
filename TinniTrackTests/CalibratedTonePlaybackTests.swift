import Foundation
import Testing
@testable import TinniTrack

struct CalibratedTonePlaybackTests {
    private let timestamp = Date(timeIntervalSince1970: 1_800_001_000)

    @Test
    func rendererMaintainsStablePhaseAcrossChunks() throws {
        let configuration = renderConfiguration(
            frequencyHz: 1_000,
            amplitude: 0.25,
            duration: 0.02,
            rampDuration: 0.0,
            sampleRate: 48_000
        )
        let full = try CalibratedToneRenderer.render(configuration)
        var chunkedRenderer = CalibratedToneRenderer()
        let firstChunk = try chunkedRenderer.renderNextFrames(137, configuration: configuration)
        let secondChunk = try chunkedRenderer.renderNextFrames(configuration.frameCount - 137, configuration: configuration)

        let chunkedLeft = firstChunk.left + secondChunk.left
        #expect(chunkedLeft.count == full.left.count)
        for index in full.left.indices {
            #expect(abs(Double(full.left[index] - chunkedLeft[index])) < 0.000_001)
        }
    }

    @Test
    func rendererProducesExpectedPeakAndRMSAtKnownAmplitude() throws {
        let amplitude = 0.25
        let configuration = renderConfiguration(
            frequencyHz: 1_000,
            amplitude: amplitude,
            duration: 0.048,
            rampDuration: 0.0,
            sampleRate: 48_000
        )

        let buffer = try CalibratedToneRenderer.render(configuration)

        #expect(abs(peak(buffer.left) - amplitude) < 0.000_001)
        #expect(abs(rms(buffer.left) - amplitude / sqrt(2.0)) < 0.000_001)
    }

    @Test
    func rendererAppliesRampBoundariesToPreventClicks() throws {
        let configuration = renderConfiguration(
            frequencyHz: 250,
            amplitude: 0.5,
            duration: 1.0,
            rampDuration: 0.2,
            sampleRate: 1_000
        )

        let buffer = try CalibratedToneRenderer.render(configuration)

        #expect(buffer.left.first == 0.0)
        #expect(buffer.left.last == 0.0)
        #expect(abs(Double(buffer.left[1])) < 0.003)
        #expect(peak(Array(buffer.left[configuration.rampFrameCount..<(configuration.frameCount - configuration.rampFrameCount)])) > 0.49)
    }

    @Test
    func rendererIsolatesRightChannel() throws {
        let configuration = renderConfiguration(
            channel: .right,
            amplitude: 0.4,
            duration: 0.02,
            rampDuration: 0.0,
            sampleRate: 48_000
        )

        let buffer = try CalibratedToneRenderer.render(configuration)

        #expect(buffer.left.allSatisfy { $0 == 0.0 })
        #expect(peak(buffer.right) > 0.39)
    }

    @Test
    func rendererFrameCountFollowsDurationAndSampleRate() throws {
        let configuration = renderConfiguration(
            duration: 0.123,
            rampDuration: 0.0,
            sampleRate: 1_000
        )

        let buffer = try CalibratedToneRenderer.render(configuration)

        #expect(configuration.frameCount == 123)
        #expect(buffer.frameCount == 123)
        #expect(buffer.right.count == 123)
    }

    @Test
    func rendererRefusesUnsafeAmplitude() {
        let configuration = renderConfiguration(amplitude: 1.0)

        let error = rendererError {
            try CalibratedToneRenderer.render(configuration)
        }

        #expect(error == .unsafeAmplitude(1.0))
    }

    @Test
    func plannerBuildsPlaybackRequestFromConversionAndGuardrailMetadata() throws {
        let validation = passedGuardrails()
        let planner = CalibratedTonePlaybackPlanner(
            sampleRate: 44_100,
            bufferFrameCount: 256,
            dateProvider: { timestamp }
        )
        let request = CalibratedTonePlaybackRequest(
            frequencyHz: 1_000,
            levelDBHL: 30,
            channel: .left,
            duration: 1.0,
            guardrailValidation: validation
        )

        let plan = try planner.makePlan(for: request)

        #expect(plan.conversion.headphoneIdentifier == "AIRPODSPROV2")
        #expect(plan.renderConfiguration.frequencyHz == 1_000)
        #expect(plan.renderConfiguration.amplitude == plan.conversion.linearAmplitude)
        #expect(plan.renderConfiguration.channel == .left)
        #expect(abs(plan.metadata.targetDBSPL - 39.27) < 0.000_001)
        #expect(abs(plan.metadata.attenuationDB - (-74.40)) < 0.000_001)
        #expect(abs(plan.metadata.linearAmplitude - 0.000_190_5) < 0.000_000_1)
        #expect(plan.metadata.routeGuardrailMetadata == validation.metadata)
        #expect(plan.metadata.sampleRate == 44_100)
        #expect(plan.metadata.bufferFrameCount == 256)
        #expect(plan.metadata.duration == 1.0)
        #expect(plan.metadata.rampDuration == 0.2)
        #expect(plan.metadata.requestedAt == timestamp)
        #expect(plan.metadata.startedAt == nil)
        #expect(plan.metadata.stoppedAt == nil)
        #expect(plan.metadata.calibrationMetadata.sourceFileNames.contains("frequency_dBSPL_AIRPODSPROV2.plist"))
        #expect(plan.metadata.mixerGainPolicy.contains("mainMixerNode.outputVolume"))
    }

    @Test
    func plannerRefusesMissingFailedAndRestartRequiredGuardrails() {
        let planner = CalibratedTonePlaybackPlanner(dateProvider: { timestamp })

        let notEvaluatedError = playbackError {
            try planner.makePlan(for: request(guardrails: CalibratedAudioGuardrailSession().validation))
        }
        let failedValidation = CalibratedAudioGuardrailPolicy().validate(
            route: CalibratedAudioRouteDetails(outputs: []),
            outputVolume: 1.0,
            timestamp: timestamp
        )
        let failedError = playbackError {
            try planner.makePlan(for: request(guardrails: failedValidation))
        }
        var session = CalibratedAudioGuardrailSession()
        _ = session.evaluate(route: supportedRoute(), outputVolume: 1.0, timestamp: timestamp)
        let restartRequired = session.routeDidChange(
            to: CalibratedAudioRouteDetails(outputs: [
                CalibratedAudioRouteOutput(portName: "Speaker", portType: .builtInSpeaker)
            ]),
            timestamp: timestamp.addingTimeInterval(1)
        )
        let restartError = playbackError {
            try planner.makePlan(for: request(guardrails: restartRequired))
        }

        #expect(notEvaluatedError == .guardrailsNotEvaluated)
        guard case .guardrailsFailed = failedError else {
            Issue.record("Expected failed guardrail refusal, got \(String(describing: failedError))")
            return
        }
        guard case .guardrailsRestartRequired = restartError else {
            Issue.record("Expected restart-required refusal, got \(String(describing: restartError))")
            return
        }
    }

    @Test
    func plannerRefusesUnsafeClippingConversion() {
        let planner = CalibratedTonePlaybackPlanner(dateProvider: { timestamp })

        let error = calibrationError {
            try planner.makePlan(
                for: CalibratedTonePlaybackRequest(
                    frequencyHz: 1_000,
                    levelDBHL: 105,
                    channel: .left,
                    duration: 1.0,
                    guardrailValidation: passedGuardrails()
                )
            )
        }

        guard case .clippingOrUnsafeAmplitude(
            let linearAmplitude,
            let attenuationDB,
            let targetDBSPL,
            let maximumSafeLinearAmplitude
        ) = error else {
            Issue.record("Expected clippingOrUnsafeAmplitude, got \(String(describing: error))")
            return
        }

        #expect(linearAmplitude > maximumSafeLinearAmplitude)
        #expect(attenuationDB >= -1.0)
        #expect(targetDBSPL == 114.27)
    }

    private func renderConfiguration(
        frequencyHz: Double = 1_000,
        channel: CalibratedTonePlaybackChannel = .left,
        amplitude: Double = 0.25,
        duration: TimeInterval = 0.02,
        rampDuration: TimeInterval = 0.0,
        sampleRate: Double = 48_000
    ) -> CalibratedToneRenderConfiguration {
        CalibratedToneRenderConfiguration(
            frequencyHz: frequencyHz,
            amplitude: amplitude,
            channel: channel,
            duration: duration,
            rampDuration: rampDuration,
            sampleRate: sampleRate
        )
    }

    private func request(
        guardrails: CalibratedAudioGuardrailValidation
    ) -> CalibratedTonePlaybackRequest {
        CalibratedTonePlaybackRequest(
            frequencyHz: 1_000,
            levelDBHL: 30,
            channel: .left,
            duration: 1.0,
            guardrailValidation: guardrails
        )
    }

    private func passedGuardrails() -> CalibratedAudioGuardrailValidation {
        CalibratedAudioGuardrailPolicy().validate(
            route: supportedRoute(),
            outputVolume: 1.0,
            timestamp: timestamp
        )
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

    private func peak(_ samples: [Float]) -> Double {
        samples.reduce(0.0) { max($0, abs(Double($1))) }
    }

    private func rms(_ samples: [Float]) -> Double {
        sqrt(samples.reduce(0.0) { $0 + Double($1 * $1) } / Double(samples.count))
    }

    private func rendererError<T>(from work: () throws -> T) -> CalibratedToneRendererError? {
        do {
            _ = try work()
            return nil
        } catch let error as CalibratedToneRendererError {
            return error
        } catch {
            return nil
        }
    }

    private func playbackError<T>(from work: () throws -> T) -> CalibratedTonePlaybackError? {
        do {
            _ = try work()
            return nil
        } catch let error as CalibratedTonePlaybackError {
            return error
        } catch {
            return nil
        }
    }

    private func calibrationError<T>(from work: () throws -> T) -> CalibrationConversionError? {
        do {
            _ = try work()
            return nil
        } catch let error as CalibrationConversionError {
            return error
        } catch {
            return nil
        }
    }
}
