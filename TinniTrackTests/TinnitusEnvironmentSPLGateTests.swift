import Foundation
import Testing
@testable import TinniTrack

struct TinnitusEnvironmentSPLGateTests {
    private let evaluator = TinnitusEnvironmentSPLGateEvaluator()

    @Test
    func fiveValidQuietWindowsPassInitialGate() {
        var machine = startedMachine()
        let generation = machine.generation

        for (index, level) in [40.0, 41, 42, 43, 44].enumerated() {
            _ = machine.handle(
                .measurement(measurement(level, index: index)),
                generation: generation
            )
        }

        #expect(machine.status == .quiet)
        #expect(machine.passedResult?.gateResult == .passed)
        #expect(machine.passedResult?.samplesDBA == [40, 41, 42, 43, 44])
        #expect(machine.currentUpdate.contiguousPassingSamples == 5)
    }

    @Test
    func invalidWindowCannotBridgeInitialQuietStreak() {
        var machine = startedMachine()
        let generation = machine.generation

        for (index, level) in [40.0, 41, 42, 43].enumerated() {
            _ = machine.handle(
                .measurement(measurement(level, index: index)),
                generation: generation
            )
        }
        _ = machine.handle(.invalidated(.invalidPCM), generation: generation)
        _ = machine.handle(
            .measurement(measurement(40, index: 5)),
            generation: generation
        )

        #expect(machine.passedResult == nil)
        #expect(machine.currentUpdate.contiguousPassingSamples == 1)
        #expect(machine.status == .measuringInitialQuietness)
    }

    @Test
    func intentionalSuspensionAndReacquisitionRetainPassWithoutInterruption() {
        var machine = passedMachine()

        let suspended = machine.suspend(reason: .tonePlayback)
        #expect(suspended.status == .suspended(.tonePlayback))
        #expect(suspended.passed)
        #expect(suspended.status.isGenuineLoudnessInterruption == false)

        let resumed = machine.beginMonitoring(reason: .postResponse)
        #expect(resumed.update.status == .reacquiring(.postResponse))
        #expect(resumed.update.passed)
        #expect(resumed.update.latestSampleDBA == nil)
        #expect(resumed.update.status.isGenuineLoudnessInterruption == false)

        _ = machine.handle(.ready, generation: resumed.generation)
        #expect(machine.status == .reacquiring(.postResponse))
        _ = machine.handle(
            .measurement(measurement(40, index: 10)),
            generation: resumed.generation
        )

        #expect(machine.status == .quiet)
        #expect(machine.passedResult?.passed == true)
    }

    @Test
    func oneLoudWindowIsOnlySuspected() {
        var machine = passedAndReacquiredMachine()
        let generation = machine.generation

        _ = machine.handle(
            .measurement(measurement(45, index: 10)),
            generation: generation
        )

        #expect(machine.status == .suspectedLoudness)
        #expect(machine.currentUpdate.consecutiveLoudSamples == 1)
        #expect(machine.status.isGenuineLoudnessInterruption == false)
        #expect(machine.passedResult?.passed == true)
    }

    @Test
    func twoConsecutiveLoudWindowsCreateGenuineInterruption() {
        var machine = passedAndReacquiredMachine()
        let generation = machine.generation

        _ = machine.handle(
            .measurement(measurement(45, index: 10)),
            generation: generation
        )
        _ = machine.handle(
            .measurement(measurement(46, index: 11)),
            generation: generation
        )

        #expect(machine.status == .interruptedByLoudness)
        #expect(machine.currentUpdate.consecutiveLoudSamples == 2)
        #expect(machine.status.isGenuineLoudnessInterruption)
    }

    @Test
    func quietWindowResetsLoudDebounce() {
        var machine = passedAndReacquiredMachine()
        let generation = machine.generation

        _ = machine.handle(
            .measurement(measurement(47, index: 10)),
            generation: generation
        )
        _ = machine.handle(
            .measurement(measurement(42, index: 11)),
            generation: generation
        )
        _ = machine.handle(
            .measurement(measurement(47, index: 12)),
            generation: generation
        )

        #expect(machine.status == .suspectedLoudness)
        #expect(machine.currentUpdate.consecutiveLoudSamples == 1)
    }

    @Test
    func fiveWindowsBelowRecoveryThresholdClearInterruption() {
        var machine = interruptedMachine()
        let generation = machine.generation

        for (index, level) in [42.0, 41, 40, 39].enumerated() {
            _ = machine.handle(
                .measurement(measurement(level, index: 20 + index)),
                generation: generation
            )
        }
        #expect(machine.status == .interruptedByLoudness)
        #expect(machine.currentUpdate.consecutiveRecoverySamples == 4)

        _ = machine.handle(
            .measurement(measurement(42, index: 24)),
            generation: generation
        )

        #expect(machine.status == .quiet)
        #expect(machine.currentUpdate.consecutiveRecoverySamples == 0)
        #expect(machine.passedResult?.passed == true)
    }

    @Test
    func recoveryRequiresLowerHysteresisThreshold() {
        var machine = interruptedMachine()
        let generation = machine.generation

        for index in 0..<4 {
            _ = machine.handle(
                .measurement(measurement(42, index: 20 + index)),
                generation: generation
            )
        }
        _ = machine.handle(
            .measurement(measurement(44, index: 24)),
            generation: generation
        )

        #expect(machine.status == .interruptedByLoudness)
        #expect(machine.currentUpdate.consecutiveRecoverySamples == 0)
    }

    @Test
    func routeChangeResetsStreaksAndBaselineButRetainsInitialPass() {
        var machine = passedAndReacquiredMachine()
        let generation = machine.generation
        _ = machine.handle(
            .measurement(measurement(47, index: 10)),
            generation: generation
        )

        _ = machine.handle(.invalidated(.routeChanged), generation: generation)

        #expect(machine.status == .routeInvalid(.routeChanged))
        #expect(machine.currentUpdate.consecutiveLoudSamples == 0)
        #expect(machine.currentUpdate.consecutiveRecoverySamples == 0)
        #expect(machine.currentUpdate.localBaselineDBA == nil)
        #expect(machine.passedResult?.passed == true)
        #expect(machine.status.isGenuineLoudnessInterruption == false)
    }

    @Test
    func staleGenerationCannotUpdateCurrentState() {
        var machine = TinnitusEnvironmentSPLGateStateMachine()
        let old = machine.beginMonitoring(reason: .initial).generation
        let current = machine.beginMonitoring(reason: .manualRestart).generation
        _ = machine.handle(.ready, generation: current)

        let staleUpdate = machine.handle(
            .measurement(measurement(60, index: 0)),
            generation: old
        )

        #expect(staleUpdate == nil)
        #expect(machine.status == .measuringInitialQuietness)
        #expect(machine.measurements.isEmpty)
    }

    @Test
    func stableNoisyFixtureCannotPassThroughBaselineAdaptation() {
        var machine = startedMachine()
        let generation = machine.generation

        for index in 0..<30 {
            _ = machine.handle(
                .measurement(measurement(50, index: index)),
                generation: generation
            )
        }

        #expect(machine.passedResult == nil)
        #expect(machine.status == .suspectedLoudness)
        #expect(machine.currentUpdate.localBaselineDBA == nil)
    }

    @Test
    func unsupportedInputNeverBecomesQuietOrLoud() {
        var machine = startedMachine()
        let generation = machine.generation
        var mismatched = measurement(20, index: 0)
        mismatched = TinnitusEnvironmentSPLMeasurement(
            schemaVersion: mismatched.schemaVersion,
            windowStartedAt: mismatched.windowStartedAt,
            windowEndedAt: mismatched.windowEndedAt,
            duration: mismatched.duration,
            aWeightedDigitalLevelDBFS: mismatched.aWeightedDigitalLevelDBFS,
            provisionalEstimatedDBA: mismatched.provisionalEstimatedDBA,
            validity: .valid,
            input: TinnitusEnvironmentInputConfiguration(
                route: .bluetoothHFP,
                dataSourceOrientation: nil,
                sampleRate: 48_000,
                channelCount: 1,
                inputGain: 1,
                isInputGainSettable: false
            ),
            algorithmVersion: mismatched.algorithmVersion,
            calibration: mismatched.calibration
        )

        _ = machine.handle(.measurement(mismatched), generation: generation)

        #expect(machine.status == .routeInvalid(.routeMismatch))
        #expect(machine.passedResult == nil)
    }

    @Test
    func compatibilityEvaluatorDoesNotBridgeAcrossNonFiniteValue() {
        let result = evaluator.evaluate(
            samplesDBA: [40, 41, 42, 43, .nan, 44],
            configuration: .studyNo1
        )

        #expect(result.passed == false)
        #expect(result.samplesDBA == [40, 41, 42, 43, 44])
    }

    private func startedMachine() -> TinnitusEnvironmentSPLGateStateMachine {
        var machine = TinnitusEnvironmentSPLGateStateMachine()
        let started = machine.beginMonitoring(reason: .initial)
        _ = machine.handle(.ready, generation: started.generation)
        return machine
    }

    private func passedMachine() -> TinnitusEnvironmentSPLGateStateMachine {
        var machine = startedMachine()
        let generation = machine.generation
        for (index, level) in [40.0, 41, 42, 43, 44].enumerated() {
            _ = machine.handle(
                .measurement(measurement(level, index: index)),
                generation: generation
            )
        }
        return machine
    }

    private func passedAndReacquiredMachine() -> TinnitusEnvironmentSPLGateStateMachine {
        var machine = passedMachine()
        _ = machine.suspend(reason: .tonePlayback)
        let resumed = machine.beginMonitoring(reason: .postPlayback)
        _ = machine.handle(.ready, generation: resumed.generation)
        _ = machine.handle(
            .measurement(measurement(40, index: 9)),
            generation: resumed.generation
        )
        return machine
    }

    private func interruptedMachine() -> TinnitusEnvironmentSPLGateStateMachine {
        var machine = passedAndReacquiredMachine()
        let generation = machine.generation
        _ = machine.handle(
            .measurement(measurement(50, index: 10)),
            generation: generation
        )
        _ = machine.handle(
            .measurement(measurement(51, index: 11)),
            generation: generation
        )
        return machine
    }

    private func measurement(_ levelDBA: Double, index: Int) -> TinnitusEnvironmentSPLMeasurement {
        evaluator.legacyMeasurement(levelDBA: levelDBA, index: index)
    }
}
