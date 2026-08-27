import Foundation
import Testing
@testable import TinniTrack

@MainActor
struct StudyOrientationThresholdTestSessionTests {
    @Test
    func heardResponsesCompleteRightThenLeftAndAggregateEarResults() throws {
        let factory = ThresholdSequencerFactoryFake()
        let playback = ThresholdPlaybackRecorder()
        let session = makeSession(factory: factory, playback: playback)

        session.startCurrentEar()
        let rightSequencer = try #require(factory.createdSequencers.first)
        session.heardTone()

        #expect(session.stage == .instructions(.left))
        #expect(rightSequencer.responses == [true])
        #expect(rightSequencer.channel == .right)

        session.startCurrentEar()
        let leftSequencer = try #require(factory.createdSequencers.last)
        session.heardTone()

        #expect(session.stage == .completed)
        #expect(session.progress == 1)
        #expect(leftSequencer.responses == [true])
        #expect(leftSequencer.channel == .left)
        #expect(factory.requestedChannels == [.right, .left])

        let result = try #require(session.result)
        #expect(result.isComplete)
        #expect(result.taskIdentifier == "study-no-1-orientation-threshold")
        #expect(result.rightEar?.channel == .right)
        #expect(result.rightEar?.thresholdDBHL == 15)
        #expect(result.leftEar?.channel == .left)
        #expect(result.leftEar?.thresholdDBHL == 20)
    }

    @Test
    func immediateTimingRegistersAnUnheardTimeoutAndAdvancesEar() async throws {
        let factory = ThresholdSequencerFactoryFake()
        let playback = ThresholdPlaybackRecorder()
        let timing = StudyOrientationThresholdTestTiming(
            preStimulusDelay: { _ in 0.3 },
            sleep: { _ in }
        )
        let session = makeSession(
            factory: factory,
            playback: playback,
            timing: timing
        )

        session.startCurrentEar()

        #expect(await waitUntil { session.stage == .instructions(.left) })
        let sequencer = try #require(factory.createdSequencers.first)
        #expect(sequencer.preStimulusDelays == [0.3])
        #expect(sequencer.stimulusPlaybackCount == 1)
        #expect(sequencer.responses == [false])
        #expect(playback.playedStimuli.map(\.channel) == [.right])
    }

    @Test
    func stopPreventsAStaleCancellationIgnoringSleeperFromMutatingState() async throws {
        let factory = ThresholdSequencerFactoryFake()
        let playback = ThresholdPlaybackRecorder()
        let sleeper = CancellationIgnoringThresholdSleeper()
        let timing = StudyOrientationThresholdTestTiming(
            preStimulusDelay: { _ in 0.4 },
            sleep: sleeper.sleep
        )
        let session = makeSession(
            factory: factory,
            playback: playback,
            timing: timing
        )

        session.startCurrentEar()
        #expect(await waitUntil { sleeper.pendingCount == 1 })
        let staleSequencer = try #require(factory.createdSequencers.first)

        session.stop()
        sleeper.resumeAll()
        for _ in 0..<5 {
            await Task.yield()
        }

        #expect(session.stage == .instructions(.right))
        #expect(session.result == nil)
        #expect(staleSequencer.stimulusPlaybackCount == 0)
        #expect(staleSequencer.responses.isEmpty)
        #expect(playback.playedStimuli.isEmpty)
    }

    @Test
    func rightEarRetryBuildsAFreshSequencerAndPlaysItsFirstTone() async throws {
        let factory = ThresholdSequencerFactoryFake()
        let playback = ThresholdPlaybackRecorder()
        let outputVolume = ThresholdOutputVolume(value: nil)
        let sleeper = CancellationIgnoringThresholdSleeper()
        let timing = StudyOrientationThresholdTestTiming(
            preStimulusDelay: { _ in 0.3 },
            sleep: sleeper.sleep
        )
        let session = makeSession(
            factory: factory,
            playback: playback,
            outputVolume: { outputVolume.value },
            timing: timing
        )

        session.startCurrentEar()
        session.heardTone()

        guard case .failed(let failedEar, let message) = session.stage else {
            Issue.record("Expected a retryable right-ear failure.")
            return
        }
        #expect(failedEar == .right)
        #expect(message.contains("output volume"))
        let failedSequencer = try #require(factory.createdSequencers.first)

        outputVolume.value = 0.8
        session.retryCurrentEar()
        let retrySequencer = try #require(factory.createdSequencers.last)
        #expect(await waitUntil { sleeper.pendingCount == 1 })
        sleeper.resumeAll()
        #expect(await waitUntil { playback.playedStimuli.count == 1 })
        #expect(playback.playedStimuli.last?.channel == .right)
        session.heardTone()

        #expect(factory.requestedChannels == [.right, .right])
        #expect(failedSequencer !== retrySequencer)
        #expect(session.stage == .instructions(.left))
        sleeper.resumeAll()
    }

    @Test
    func leftEarRetryBuildsAFreshSequencerAndPlaysItsFirstTone() async throws {
        let factory = ThresholdSequencerFactoryFake()
        let playback = ThresholdPlaybackRecorder()
        let outputVolume = ThresholdOutputVolume(value: 0.8)
        let sleeper = CancellationIgnoringThresholdSleeper()
        let timing = StudyOrientationThresholdTestTiming(
            preStimulusDelay: { _ in 0.3 },
            sleep: sleeper.sleep
        )
        let session = makeSession(
            factory: factory,
            playback: playback,
            outputVolume: { outputVolume.value },
            timing: timing
        )

        session.startCurrentEar()
        session.heardTone()
        #expect(session.stage == .instructions(.left))

        outputVolume.value = nil
        session.startCurrentEar()
        session.heardTone()

        guard case .failed(let failedEar, let message) = session.stage else {
            Issue.record("Expected a retryable left-ear failure.")
            return
        }
        #expect(failedEar == .left)
        #expect(message.contains("output volume"))
        let failedSequencer = try #require(factory.createdSequencers.last)

        outputVolume.value = 0.8
        session.retryCurrentEar()
        let retrySequencer = try #require(factory.createdSequencers.last)
        #expect(await waitUntil { sleeper.pendingCount == 1 })
        sleeper.resumeAll()
        #expect(await waitUntil { playback.playedStimuli.count == 1 })
        #expect(playback.playedStimuli.last?.channel == .left)
        session.heardTone()

        #expect(factory.requestedChannels == [.right, .left, .left])
        #expect(failedSequencer !== retrySequencer)
        #expect(session.stage == .completed)
        sleeper.resumeAll()
    }

    @Test
    func playbackFailureEntersRetryableFailedStageWithoutRecordingAResponse() async throws {
        let factory = ThresholdSequencerFactoryFake()
        let playback = ThresholdPlaybackRecorder()
        playback.error = .playbackFailed
        let timing = StudyOrientationThresholdTestTiming(
            preStimulusDelay: { _ in 0 },
            sleep: { _ in }
        )
        let session = makeSession(
            factory: factory,
            playback: playback,
            timing: timing
        )

        session.startCurrentEar()

        #expect(await waitUntil {
            if case .failed = session.stage { return true }
            return false
        })
        let sequencer = try #require(factory.createdSequencers.first)
        #expect(sequencer.stimulusPlaybackCount == 1)
        #expect(sequencer.responses.isEmpty)
        guard case .failed(let ear, let message) = session.stage else {
            Issue.record("Expected playback failure state.")
            return
        }
        #expect(ear == .right)
        #expect(message == "Playback failed.")
    }

    private func makeSession(
        factory: ThresholdSequencerFactoryFake,
        playback: ThresholdPlaybackRecorder,
        outputVolume: @escaping StudyOrientationThresholdTestSession.OutputVolume = { 0.8 },
        timing: StudyOrientationThresholdTestTiming = StudyOrientationThresholdTestTiming(
            preStimulusDelay: { _ in 0.3 },
            sleep: { _ in }
        )
    ) -> StudyOrientationThresholdTestSession {
        StudyOrientationThresholdTestSession(
            sequencerFactory: factory,
            playTone: { stimulus, duration in
                try await playback.play(stimulus, duration: duration)
            },
            stopTone: {
                playback.stop()
            },
            outputVolume: outputVolume,
            timing: timing,
            uptime: { 100 }
        )
    }

    private func waitUntil(
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        for _ in 0..<200 {
            if condition() {
                return true
            }
            await Task.yield()
        }
        return condition()
    }
}

@MainActor
private final class ThresholdSequencerFactoryFake:
    StudyNo1OrientationThresholdSequencerBuilding
{
    private(set) var requestedChannels: [CalibratedTonePlaybackChannel] = []
    private(set) var createdSequencers: [ThresholdSequencerFake] = []

    func makeSequencer(
        for channel: CalibratedTonePlaybackChannel,
        configuration: StudyNo1OrientationThresholdConfiguration,
        timestampProvider: @escaping () -> TimeInterval
    ) throws -> any StudyNo1OrientationThresholdSequencing {
        requestedChannels.append(channel)
        let sequencer = ThresholdSequencerFake(
            channel: channel,
            configuration: configuration,
            thresholdDBHL: channel == .right ? 15 : 20
        )
        createdSequencers.append(sequencer)
        return sequencer
    }
}

@MainActor
private final class ThresholdSequencerFake: StudyNo1OrientationThresholdSequencing {
    let channel: CalibratedTonePlaybackChannel
    let configuration: StudyNo1OrientationThresholdConfiguration
    let thresholdDBHL: Double

    private(set) var responses: [Bool] = []
    private(set) var preStimulusDelays: [TimeInterval] = []
    private(set) var stimulusPlaybackCount = 0
    private(set) var clippingCount = 0

    init(
        channel: CalibratedTonePlaybackChannel,
        configuration: StudyNo1OrientationThresholdConfiguration,
        thresholdDBHL: Double
    ) {
        self.channel = channel
        self.configuration = configuration
        self.thresholdDBHL = thresholdDBHL
    }

    var nextStimulus: StudyNo1OrientationThresholdStimulus? {
        guard !isComplete else { return nil }
        return StudyNo1OrientationThresholdStimulus(
            frequencyHz: 1_000,
            levelDBHL: 30,
            channel: channel
        )
    }

    var progress: Double {
        isComplete ? 1 : 0
    }

    var isComplete: Bool {
        !responses.isEmpty || clippingCount > 0
    }

    func registerPreStimulusDelay(_ delay: TimeInterval) {
        preStimulusDelays.append(delay)
    }

    func registerStimulusPlayback() {
        stimulusPlaybackCount += 1
    }

    func registerResponse(heard: Bool) {
        responses.append(heard)
    }

    func signalClipped() {
        clippingCount += 1
    }

    func makeEarResult(outputVolume: Double) -> StudyNo1OrientationThresholdEarResult {
        let unit = StudyNo1OrientationThresholdUnit(
            levelDBHL: thresholdDBHL,
            startOfUnitTimeStamp: 0,
            preStimulusDelay: preStimulusDelays.first ?? 0,
            userTapTimeStamp: responses.last == true ? 1 : nil,
            timeoutTimeStamp: responses.last == false ? 1 : nil
        )
        let sample = StudyNo1OrientationThresholdFrequencySample(
            frequencyHz: 1_000,
            calculatedThresholdDBHL: thresholdDBHL,
            channel: channel,
            units: [unit]
        )
        return StudyNo1OrientationThresholdEarResult(
            channel: channel,
            thresholdDBHL: thresholdDBHL,
            outputVolume: outputVolume,
            headphoneType: configuration.headphoneTypeIdentifier,
            tonePlaybackDuration: configuration.toneDuration,
            postStimulusDelay: configuration.postStimulusDelay,
            samples: [sample]
        )
    }
}

@MainActor
private final class ThresholdPlaybackRecorder {
    private(set) var playedStimuli: [StudyNo1OrientationThresholdStimulus] = []
    private(set) var stopCount = 0
    var error: ThresholdSessionTestError?

    func play(
        _ stimulus: StudyNo1OrientationThresholdStimulus,
        duration: TimeInterval
    ) async throws {
        playedStimuli.append(stimulus)
        if let error {
            throw error
        }
    }

    func stop() {
        stopCount += 1
    }
}

@MainActor
private final class ThresholdOutputVolume {
    var value: Double?

    init(value: Double?) {
        self.value = value
    }
}

@MainActor
private final class CancellationIgnoringThresholdSleeper {
    private var continuations: [CheckedContinuation<Void, Never>] = []

    var pendingCount: Int {
        continuations.count
    }

    func sleep(_ duration: TimeInterval) async throws {
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func resumeAll() {
        let pending = continuations
        continuations.removeAll()
        pending.forEach { $0.resume() }
    }
}

private enum ThresholdSessionTestError: LocalizedError {
    case playbackFailed

    var errorDescription: String? {
        "Playback failed."
    }
}
