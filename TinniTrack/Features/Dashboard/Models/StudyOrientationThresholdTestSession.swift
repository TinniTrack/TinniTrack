import Combine
import Foundation

@MainActor
struct StudyOrientationThresholdTestTiming {
    let preStimulusDelay: (StudyNo1OrientationThresholdConfiguration) -> TimeInterval
    let sleep: (TimeInterval) async throws -> Void

    static let live = StudyOrientationThresholdTestTiming(
        preStimulusDelay: { configuration in
            let range = max(
                0,
                configuration.maximumRandomPreStimulusDelay
                    - configuration.minimumPreStimulusDelay
            )
            let resolution = max(
                configuration.preStimulusDelayResolution,
                .leastNonzeroMagnitude
            )
            let stepCount = max(1, Int(floor(range / resolution)))
            let step = Int.random(in: 0..<stepCount)
            return configuration.minimumPreStimulusDelay
                + (Double(step) * resolution)
        },
        sleep: { duration in
            try await Task.sleep(
                nanoseconds: UInt64(max(0, duration) * 1_000_000_000)
            )
        }
    )
}

@MainActor
final class StudyOrientationThresholdTestSession: ObservableObject {
    enum Ear: String, Equatable {
        case right
        case left

        var channel: CalibratedTonePlaybackChannel {
            switch self {
            case .right:
                return .right
            case .left:
                return .left
            }
        }

        var displayName: String {
            rawValue.capitalized
        }
    }

    enum Stage: Equatable {
        case instructions(Ear)
        case testing(Ear)
        case completed
        case failed(ear: Ear, message: String)
    }

    typealias PlayTone = @MainActor (
        _ stimulus: StudyNo1OrientationThresholdStimulus,
        _ duration: TimeInterval
    ) async throws -> Void
    typealias StopTone = @MainActor () -> Void
    typealias OutputVolume = @MainActor () -> Double?

    @Published private(set) var stage: Stage = .instructions(.right)
    @Published private(set) var progress = 0.0
    @Published private(set) var responseCount = 0
    @Published private(set) var isPaused = false
    @Published private(set) var result: StudyNo1OrientationThresholdResult?

    private let configuration: StudyNo1OrientationThresholdConfiguration
    private let sequencerFactory: any StudyNo1OrientationThresholdSequencerBuilding
    private let playTone: PlayTone
    private let stopTone: StopTone
    private let outputVolume: OutputVolume
    private let timing: StudyOrientationThresholdTestTiming
    private let uptime: () -> TimeInterval

    private var sequencer: (any StudyNo1OrientationThresholdSequencing)?
    private var trialTask: Task<Void, Never>?
    private var trialGeneration: UInt64 = 0
    private var rightEarResult: StudyNo1OrientationThresholdEarResult?
    private var leftEarResult: StudyNo1OrientationThresholdEarResult?

    init(
        configuration: StudyNo1OrientationThresholdConfiguration = .studyNo1,
        sequencerFactory: (any StudyNo1OrientationThresholdSequencerBuilding)? = nil,
        playTone: @escaping PlayTone,
        stopTone: @escaping StopTone,
        outputVolume: @escaping OutputVolume,
        timing: StudyOrientationThresholdTestTiming? = nil,
        uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.configuration = configuration
        self.sequencerFactory = sequencerFactory
            ?? ResearchKitStudyNo1OrientationThresholdSequencerFactory()
        self.playTone = playTone
        self.stopTone = stopTone
        self.outputVolume = outputVolume
        self.timing = timing ?? .live
        self.uptime = uptime
    }

    var currentEar: Ear? {
        switch stage {
        case .instructions(let ear), .testing(let ear), .failed(let ear, _):
            return ear
        case .completed:
            return nil
        }
    }

    var isTesting: Bool {
        if case .testing = stage {
            return true
        }
        return false
    }

    func startCurrentEar() {
        let ear: Ear
        switch stage {
        case .instructions(let pendingEar), .failed(let pendingEar, _):
            ear = pendingEar
        case .testing, .completed:
            return
        }

        cancelTrial()
        let startedAt = uptime()

        do {
            sequencer = try sequencerFactory.makeSequencer(
                for: ear.channel,
                configuration: configuration,
                timestampProvider: { [uptime] in
                    max(0, uptime() - startedAt)
                }
            )
            responseCount = 0
            isPaused = false
            stage = .testing(ear)
            updateProgress()
            scheduleNextTrial()
        } catch {
            failCurrentEar(ear, message: error.localizedDescription)
        }
    }

    func heardTone() {
        guard case .testing(let ear) = stage,
              !isPaused,
              let sequencer
        else {
            return
        }

        cancelTrial()
        stopTone()
        sequencer.registerResponse(heard: true)
        responseCount += 1
        advanceAfterResponse(for: ear)
    }

    func pause() {
        guard isTesting, !isPaused else {
            return
        }

        isPaused = true
        cancelTrial()
        stopTone()
    }

    func resume() {
        guard isTesting, isPaused else {
            return
        }

        isPaused = false
        scheduleNextTrial()
    }

    func retryCurrentEar() {
        guard case .failed(let ear, _) = stage else {
            return
        }

        stage = .instructions(ear)
        startCurrentEar()
    }

    func stop() {
        cancelTrial()
        stopTone()
        sequencer = nil
        rightEarResult = nil
        leftEarResult = nil
        result = nil
        responseCount = 0
        progress = 0
        isPaused = false
        stage = .instructions(.right)
    }

    private func scheduleNextTrial() {
        guard case .testing(let ear) = stage,
              !isPaused,
              let sequencer,
              !sequencer.isComplete,
              sequencer.nextStimulus != nil
        else {
            if case .testing(let ear) = stage, sequencer?.isComplete == true {
                finishEar(ear)
            }
            return
        }

        trialGeneration &+= 1
        let generation = trialGeneration
        trialTask = Task { @MainActor [weak self] in
            await self?.runTrial(ear: ear, generation: generation)
        }
    }

    private func runTrial(ear: Ear, generation: UInt64) async {
        guard isCurrentTrial(generation),
              let sequencer,
              let stimulus = sequencer.nextStimulus
        else {
            return
        }

        let preStimulusDelay = timing.preStimulusDelay(configuration)
        sequencer.registerPreStimulusDelay(preStimulusDelay)

        do {
            try await timing.sleep(preStimulusDelay)
            guard isCurrentTrial(generation), !isPaused else {
                return
            }

            sequencer.registerStimulusPlayback()
            try await playTone(stimulus, configuration.toneDuration)

            try await timing.sleep(
                configuration.toneDuration + configuration.postStimulusDelay
            )
            guard isCurrentTrial(generation), !isPaused else {
                return
            }

            stopTone()
            sequencer.registerResponse(heard: false)
            responseCount += 1
            trialTask = nil
            advanceAfterResponse(for: ear)
        } catch is CancellationError {
            return
        } catch let error as CalibrationConversionError {
            handlePlaybackError(error, for: ear, generation: generation)
        } catch let error as CalibratedTonePlaybackError {
            handlePlaybackError(error, for: ear, generation: generation)
        } catch {
            guard isCurrentTrial(generation) else {
                return
            }
            stopTone()
            trialTask = nil
            failCurrentEar(ear, message: error.localizedDescription)
        }
    }

    private func handlePlaybackError(
        _ error: Error,
        for ear: Ear,
        generation: UInt64
    ) {
        guard isCurrentTrial(generation), let sequencer else {
            return
        }

        stopTone()
        trialTask = nil

        if error.isThresholdSignalClipping {
            sequencer.signalClipped()
            responseCount += 1
            advanceAfterResponse(for: ear)
        } else {
            failCurrentEar(ear, message: error.localizedDescription)
        }
    }

    private func advanceAfterResponse(for ear: Ear) {
        guard let sequencer else {
            return
        }

        updateProgress()
        if sequencer.isComplete {
            finishEar(ear)
        } else {
            scheduleNextTrial()
        }
    }

    private func finishEar(_ ear: Ear) {
        guard let sequencer else {
            return
        }

        cancelTrial()
        stopTone()

        guard let outputVolume = outputVolume() else {
            failCurrentEar(
                ear,
                message: "The output volume could not be verified. Return to the volume step and try again."
            )
            return
        }

        let earResult = sequencer.makeEarResult(outputVolume: outputVolume)
        guard earResult.thresholdDBHL != nil else {
            failCurrentEar(
                ear,
                message: "We could not establish a reliable threshold for your \(ear.rawValue) ear. Try that ear again."
            )
            return
        }

        self.sequencer = nil
        responseCount = 0

        switch ear {
        case .right:
            rightEarResult = earResult
            progress = 0.5
            stage = .instructions(.left)

        case .left:
            leftEarResult = earResult
            let completedResult = StudyNo1OrientationThresholdResult(
                taskIdentifier: "study-no-1-orientation-threshold",
                rightEar: rightEarResult,
                leftEar: leftEarResult,
                environment: nil
            )
            result = completedResult
            progress = 1
            stage = .completed
        }
    }

    private func failCurrentEar(_ ear: Ear, message: String) {
        cancelTrial()
        stopTone()
        sequencer = nil
        isPaused = false
        stage = .failed(ear: ear, message: message)
    }

    private func updateProgress() {
        let completedEars = rightEarResult == nil ? 0.0 : 1.0
        let currentEarProgress = min(max(sequencer?.progress ?? 0, 0), 0.95)
        progress = (completedEars + currentEarProgress) / 2.0
    }

    private func cancelTrial() {
        trialGeneration &+= 1
        trialTask?.cancel()
        trialTask = nil
    }

    private func isCurrentTrial(_ generation: UInt64) -> Bool {
        generation == trialGeneration && !Task.isCancelled
    }
}

private extension Error {
    var isThresholdSignalClipping: Bool {
        if let conversionError = self as? CalibrationConversionError,
           case .clippingOrUnsafeAmplitude = conversionError {
            return true
        }
        if let playbackError = self as? CalibratedTonePlaybackError,
           case .unsafeAmplitude = playbackError {
            return true
        }
        return false
    }
}
