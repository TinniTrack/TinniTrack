import AudioToolbox
import AVFoundation
import Foundation

@MainActor
protocol CalibratedTonePlaying: AnyObject {
    @discardableResult
    func play(_ request: CalibratedTonePlaybackRequest) throws -> CalibratedTonePlaybackMetadata

    @discardableResult
    func stop() -> CalibratedTonePlaybackMetadata?

    @discardableResult
    func stopAndWaitForSilence() async -> CalibratedTonePlaybackMetadata?

    func waitForSilenceAfterStop() async
}

extension CalibratedTonePlaying {
    @discardableResult
    func stopAndWaitForSilence() async -> CalibratedTonePlaybackMetadata? {
        let metadata = stop()
        await waitForSilenceAfterStop()
        return metadata
    }

    func waitForSilenceAfterStop() async {
    }
}

@MainActor
final class CalibratedToneScheduledStopCoordinator {
    typealias Scheduler = @MainActor (
        _ delay: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> Void

    private let scheduler: Scheduler
    private var playbackGeneration: UInt64 = 0

    init(
        scheduler: @escaping Scheduler = { delay, action in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
        }
    ) {
        self.scheduler = scheduler
    }

    func beginPlayback() {
        playbackGeneration &+= 1
    }

    func invalidatePlayback() {
        playbackGeneration &+= 1
    }

    func scheduleStop(
        after delay: TimeInterval,
        action: @escaping @MainActor @Sendable () -> Void
    ) {
        let scheduledGeneration = playbackGeneration
        scheduler(delay) { [weak self] in
            guard let self, self.playbackGeneration == scheduledGeneration else {
                return
            }
            action()
        }
    }
}

@MainActor
final class CalibratedToneAudioPlayer: CalibratedTonePlaying {
    private let audioSession: AVAudioSession
    private let audioSessionCoordinator: StudyAudioSessionCoordinating
    private let guardrailMonitor: CalibratedAudioSessionGuardrailMonitor?
    private let converter: CalibratedAudioConverter
    private let dateProvider: () -> Date
    private let preferredSampleRate: Double
    private let preferredBufferFrameCount: Int
    private let scheduledStopCoordinator: CalibratedToneScheduledStopCoordinator
    private var engine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    private var renderState: CalibratedToneAudioRenderState?
    private(set) var currentMetadata: CalibratedTonePlaybackMetadata?
    private(set) var lastMetadata: CalibratedTonePlaybackMetadata?

    init(
        audioSession: AVAudioSession = .sharedInstance(),
        audioSessionCoordinator: StudyAudioSessionCoordinating? = nil,
        guardrailMonitor: CalibratedAudioSessionGuardrailMonitor? = nil,
        converter: CalibratedAudioConverter? = nil,
        preferredSampleRate: Double? = nil,
        preferredBufferFrameCount: Int? = nil,
        scheduledStopCoordinator: CalibratedToneScheduledStopCoordinator? = nil,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.audioSession = audioSession
        self.audioSessionCoordinator = audioSessionCoordinator ?? StudyAudioSessionCoordinator.shared
        self.guardrailMonitor = guardrailMonitor
        self.converter = converter ?? CalibratedAudioConverter()
        self.preferredSampleRate = preferredSampleRate
            ?? CalibratedTonePlaybackDefaults.sampleRate
        self.preferredBufferFrameCount = preferredBufferFrameCount
            ?? CalibratedTonePlaybackDefaults.renderBufferFrameCount
        self.scheduledStopCoordinator = scheduledStopCoordinator
            ?? CalibratedToneScheduledStopCoordinator()
        self.dateProvider = dateProvider
    }

    @discardableResult
    func play(_ request: CalibratedTonePlaybackRequest) throws -> CalibratedTonePlaybackMetadata {
        if let renderState, engine != nil {
            let playbackTiming = currentPlaybackTiming()
            let planner = makePlaybackPlanner(
                sampleRate: playbackTiming.sampleRate,
                bufferFrameCount: playbackTiming.bufferFrameCount
            )
            let plan = try planner.makePlan(for: request)
            scheduledStopCoordinator.beginPlayback()
            renderState.transition(
                to: plan.renderConfiguration,
                duration: CalibratedTonePlaybackDefaults.levelAdjustmentRampDuration
            )
            let metadata = plan.metadata.started(at: dateProvider())
            currentMetadata = metadata
            lastMetadata = metadata
            startGuardrailMonitoring()
            if plan.renderConfiguration.stopsAfterDuration {
                scheduleNaturalStop(after: plan.renderConfiguration.duration)
            }
            return metadata
        }

        try configureAudioSession()

        let playbackTiming = currentPlaybackTiming()
        let planner = makePlaybackPlanner(
            sampleRate: playbackTiming.sampleRate,
            bufferFrameCount: playbackTiming.bufferFrameCount
        )
        let plan = try planner.makePlan(for: request)

        stopImmediately()
        let playbackEngine = AVAudioEngine()
        let state = CalibratedToneAudioRenderState(configuration: plan.renderConfiguration)
        let source = AVAudioSourceNode { _, _, frameCount, audioBufferList in
            state.render(frameCount: Int(frameCount), into: audioBufferList)
            return noErr
        }
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: playbackTiming.sampleRate,
            channels: 2,
            interleaved: false
        )

        playbackEngine.attach(source)
        playbackEngine.connect(source, to: playbackEngine.mainMixerNode, format: format)
        playbackEngine.mainMixerNode.outputVolume = 1.0
        playbackEngine.prepare()
        try playbackEngine.start()

        engine = playbackEngine
        sourceNode = source
        renderState = state
        scheduledStopCoordinator.beginPlayback()

        let metadata = plan.metadata.started(at: dateProvider())
        currentMetadata = metadata
        lastMetadata = metadata

        startGuardrailMonitoring()
        if plan.renderConfiguration.stopsAfterDuration {
            scheduleNaturalStop(after: plan.renderConfiguration.duration)
        }

        return metadata
    }

    private func currentPlaybackTiming() -> (sampleRate: Double, bufferFrameCount: Int) {
        let activeSampleRate = audioSession.sampleRate > 0.0 ? audioSession.sampleRate : preferredSampleRate
        let activeBufferFrameCount = max(
            1,
            Int((audioSession.ioBufferDuration * activeSampleRate).rounded())
        )

        return (activeSampleRate, activeBufferFrameCount)
    }

    private func makePlaybackPlanner(
        sampleRate: Double,
        bufferFrameCount: Int
    ) -> CalibratedTonePlaybackPlanner {
        CalibratedTonePlaybackPlanner(
            converter: converter,
            sampleRate: sampleRate,
            bufferFrameCount: bufferFrameCount,
            dateProvider: dateProvider
        )
    }

    @discardableResult
    func stop() -> CalibratedTonePlaybackMetadata? {
        guard let renderState else {
            return lastMetadata
        }

        let rampDuration = renderState.beginRampOut()
        let stoppedMetadata = (currentMetadata ?? lastMetadata)?.stopped(at: dateProvider())
        currentMetadata = stoppedMetadata
        lastMetadata = stoppedMetadata

        scheduledStopCoordinator.scheduleStop(after: rampDuration) { [weak self] in
            self?.stopImmediately()
        }

        return stoppedMetadata
    }

    @discardableResult
    func stopAndWaitForSilence() async -> CalibratedTonePlaybackMetadata? {
        let metadata = stop()
        await waitForSilenceAfterStop()
        return metadata
    }

    func waitForSilenceAfterStop() async {
        guard let renderState else { return }
        let rampDuration = renderState.beginRampOut()
        scheduledStopCoordinator.invalidatePlayback()
        if rampDuration > 0 {
            do {
                try await Task.sleep(
                    nanoseconds: UInt64(rampDuration * 1_000_000_000)
                )
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
        guard !Task.isCancelled else { return }
        stopImmediately()
    }

    private func configureAudioSession() throws {
        try audioSessionCoordinator.configureForPlayback(
            preferredSampleRate: preferredSampleRate,
            preferredBufferFrameCount: preferredBufferFrameCount
        )
    }

    private func startGuardrailMonitoring() {
        guard let guardrailMonitor else {
            return
        }

        guardrailMonitor.startMonitoring { [weak self] validation in
            guard validation.state != .passed else {
                return
            }

            Task { @MainActor in
                self?.stop()
            }
        }
    }

    private func scheduleNaturalStop(after duration: TimeInterval) {
        scheduledStopCoordinator.scheduleStop(after: duration) { [weak self] in
            guard self?.renderState != nil else {
                return
            }
            self?.stopImmediately()
        }
    }

    private func stopImmediately() {
        scheduledStopCoordinator.invalidatePlayback()

        guard engine != nil || renderState != nil else {
            guardrailMonitor?.stopMonitoring()
            return
        }

        if currentMetadata?.stoppedAt == nil {
            let stoppedMetadata = (currentMetadata ?? lastMetadata)?.stopped(at: dateProvider())
            currentMetadata = stoppedMetadata
            lastMetadata = stoppedMetadata
        }

        guardrailMonitor?.stopMonitoring()
        engine?.stop()
        engine?.reset()
        if let sourceNode {
            engine?.detach(sourceNode)
        }
        sourceNode = nil
        renderState = nil
        engine = nil
        currentMetadata = nil
    }
}

private final class CalibratedToneAudioRenderState: @unchecked Sendable {
    private let lock = NSLock()
    private var renderer = CalibratedToneRenderer()
    private var configuration: CalibratedToneRenderConfiguration
    private var amplitudeTransition: CalibratedToneAmplitudeTransition?
    private var isStopping = false

    init(configuration: CalibratedToneRenderConfiguration) {
        self.configuration = configuration
    }

    func beginRampOut() -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }

        guard !isStopping else {
            return configuration.rampDuration
        }

        let rampFrames = max(configuration.rampFrameCount, 1)
        let stopFrameCount = renderer.renderedFrameCount + rampFrames
        configuration = CalibratedToneRenderConfiguration(
            frequencyHz: configuration.frequencyHz,
            amplitude: configuration.amplitude,
            channel: configuration.channel,
            duration: Double(stopFrameCount) / configuration.sampleRate,
            rampDuration: configuration.rampDuration,
            stopsAfterDuration: true,
            sampleRate: configuration.sampleRate
        )
        isStopping = true

        return configuration.rampDuration
    }

    func transition(
        to newConfiguration: CalibratedToneRenderConfiguration,
        duration: TimeInterval
    ) {
        lock.lock()
        defer { lock.unlock() }

        let currentFrame = renderer.renderedFrameCount
        let currentAmplitude = amplitudeTransition?.amplitude(at: currentFrame)
            ?? configuration.amplitude
        let transitionFrameCount = max(1, Int((duration * configuration.sampleRate).rounded()))
        amplitudeTransition = CalibratedToneAmplitudeTransition(
            startAmplitude: currentAmplitude,
            endAmplitude: newConfiguration.amplitude,
            startFrame: currentFrame,
            frameCount: transitionFrameCount
        )
        configuration = newConfiguration
        isStopping = false
    }

    func render(
        frameCount: Int,
        into audioBufferList: UnsafeMutablePointer<AudioBufferList>
    ) {
        lock.lock()
        let transition = amplitudeTransition
        let buffer = (try? renderer.renderNextFrames(
            frameCount,
            configuration: configuration,
            amplitudeProvider: { absoluteFrame, configuredAmplitude in
                transition?.amplitude(at: absoluteFrame) ?? configuredAmplitude
            }
        ))
            ?? CalibratedTonePCMBuffer(
                left: Array(repeating: .zero, count: frameCount),
                right: Array(repeating: .zero, count: frameCount),
                sampleRate: configuration.sampleRate
            )
        if let transition,
           renderer.renderedFrameCount >= transition.endFrame {
            amplitudeTransition = nil
        }
        lock.unlock()

        let audioBuffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        for bufferIndex in 0..<audioBuffers.count {
            guard let data = audioBuffers[bufferIndex].mData?.assumingMemoryBound(to: Float.self) else {
                continue
            }

            let samples = bufferIndex == 0 ? buffer.left : buffer.right
            for frame in 0..<frameCount {
                data[frame] = frame < samples.count ? samples[frame] : 0.0
            }
        }
    }
}

private struct CalibratedToneAmplitudeTransition {
    let startAmplitude: Double
    let endAmplitude: Double
    let startFrame: Int
    let frameCount: Int

    var endFrame: Int {
        startFrame + frameCount
    }

    func amplitude(at absoluteFrame: Int) -> Double {
        guard absoluteFrame >= startFrame else {
            return startAmplitude
        }
        guard absoluteFrame < endFrame else {
            return endAmplitude
        }

        let progress = Double(absoluteFrame - startFrame) / Double(frameCount)
        return startAmplitude + ((endAmplitude - startAmplitude) * progress)
    }
}
