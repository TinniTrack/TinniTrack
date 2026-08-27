import AVFoundation
import Foundation
import OSLog

enum EnvironmentSPLMeterError: Error, Equatable {
    case microphonePermissionDenied
    case builtInMicrophoneUnavailable
    case routeInvalid
    case engineUnavailable
    case monitorEndedBeforeDecision
}

@MainActor
protocol EnvironmentSPLMeasuring {
    func runGate(
        configuration: TinnitusEnvironmentSPLGateConfiguration
    ) async throws -> TinnitusEnvironmentSPLGateResult
}

@MainActor
protocol EnvironmentSPLMonitorSession: AnyObject {
    var events: AsyncThrowingStream<TinnitusEnvironmentSPLMonitorEvent, Error> { get }
    func stop() async
}

@MainActor
protocol EnvironmentSPLGateMonitoring {
    func makeMonitor(
        configuration: TinnitusEnvironmentSPLGateConfiguration,
        reason: TinnitusEnvironmentSPLReacquisitionReason
    ) -> any EnvironmentSPLMonitorSession
}

@MainActor
protocol EnvironmentSPLWorkflowManaging {
    func endAudioWorkflow()
}

@MainActor
final class AVAudioEnvironmentSPLMeter: EnvironmentSPLMeasuring, EnvironmentSPLGateMonitoring, EnvironmentSPLWorkflowManaging {
    private let audioSessionCoordinator: StudyAudioSessionCoordinating
    private let notificationCenter: NotificationCenter
    private let engineFactory: () -> AVAudioEngine
    private let dateProvider: () -> Date

    init(
        audioSessionCoordinator: StudyAudioSessionCoordinating? = nil,
        notificationCenter: NotificationCenter = .default,
        engineFactory: @escaping () -> AVAudioEngine = AVAudioEngine.init,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.audioSessionCoordinator = audioSessionCoordinator ?? StudyAudioSessionCoordinator.shared
        self.notificationCenter = notificationCenter
        self.engineFactory = engineFactory
        self.dateProvider = dateProvider
    }

    func runGate() async throws -> TinnitusEnvironmentSPLGateResult {
        try await runGate(configuration: .studyNo1)
    }

    func runGate(
        configuration: TinnitusEnvironmentSPLGateConfiguration
    ) async throws -> TinnitusEnvironmentSPLGateResult {
        var machine = TinnitusEnvironmentSPLGateStateMachine(configuration: configuration)
        let started = machine.beginMonitoring(reason: .initial)
        let monitor = makeMonitor(configuration: configuration, reason: .initial)
        var validWindowCount = 0

        do {
            for try await event in monitor.events {
                if case .measurement(let measurement) = event, measurement.isValid {
                    validWindowCount += 1
                }
                if case .unavailable(let reason) = event {
                    await monitor.stop()
                    throw Self.error(for: reason)
                }
                _ = machine.handle(event, generation: started.generation)
                if let result = machine.passedResult {
                    await monitor.stop()
                    return result
                }
                if validWindowCount >= configuration.maximumSamples {
                    let result = TinnitusEnvironmentSPLGateResult(
                        configuration: configuration,
                        measurements: machine.measurements,
                        gateResult: .failed
                    )
                    await monitor.stop()
                    return result
                }
            }
        } catch {
            await monitor.stop()
            throw error
        }

        await monitor.stop()
        throw EnvironmentSPLMeterError.monitorEndedBeforeDecision
    }

    func makeMonitor(
        configuration: TinnitusEnvironmentSPLGateConfiguration,
        reason: TinnitusEnvironmentSPLReacquisitionReason
    ) -> any EnvironmentSPLMonitorSession {
        AVAudioEnvironmentSPLMonitorSession(
            configuration: configuration,
            initialReason: reason,
            audioSessionCoordinator: audioSessionCoordinator,
            notificationCenter: notificationCenter,
            engineFactory: engineFactory,
            dateProvider: dateProvider
        )
    }

    func endAudioWorkflow() {
        audioSessionCoordinator.endWorkflow()
    }

    private static func error(
        for reason: TinnitusEnvironmentMeasurementFailureReason
    ) -> EnvironmentSPLMeterError {
        switch reason {
        case .microphonePermissionDenied:
            return .microphonePermissionDenied
        case .builtInMicrophoneUnavailable:
            return .builtInMicrophoneUnavailable
        case .routeMismatch,
             .routeChanged,
             .dataSourceChanged,
             .sampleFormatChanged,
             .inputGainChanged,
             .mediaServicesReset:
            return .routeInvalid
        case .emptyInput,
             .invalidPCM,
             .clippedPCM,
             .discontinuousSampleTime,
             .incompleteWindow,
             .audioSessionInterrupted,
             .engineFailure,
             .missingCalibrationEstimate,
             .cancelled,
             .unavailable:
            return .engineUnavailable
        }
    }
}

@MainActor
private final class AVAudioEnvironmentSPLMonitorSession: EnvironmentSPLMonitorSession {
    let events: AsyncThrowingStream<TinnitusEnvironmentSPLMonitorEvent, Error>

    private let configuration: TinnitusEnvironmentSPLGateConfiguration
    private let audioSessionCoordinator: StudyAudioSessionCoordinating
    private let notificationCenter: NotificationCenter
    private let engineFactory: () -> AVAudioEngine
    private let dateProvider: () -> Date
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "TinniTrack",
        category: "EnvironmentQuietScreen"
    )
    private let continuation: AsyncThrowingStream<TinnitusEnvironmentSPLMonitorEvent, Error>.Continuation
    private var engine: AVAudioEngine?
    private var processorBox: EnvironmentPCMProcessorBox?
    private var observers: [NSObjectProtocol] = []
    private var lifecycleTask: Task<Void, Never>?
    private var captureGeneration: UInt64 = 0
    private var isStopped = false
    private var isReconfiguring = false
    private var hasEmittedReady = false

    init(
        configuration: TinnitusEnvironmentSPLGateConfiguration,
        initialReason: TinnitusEnvironmentSPLReacquisitionReason,
        audioSessionCoordinator: StudyAudioSessionCoordinating,
        notificationCenter: NotificationCenter,
        engineFactory: @escaping () -> AVAudioEngine,
        dateProvider: @escaping () -> Date
    ) {
        var capturedContinuation: AsyncThrowingStream<TinnitusEnvironmentSPLMonitorEvent, Error>.Continuation!
        events = AsyncThrowingStream { capturedContinuation = $0 }
        continuation = capturedContinuation
        self.configuration = configuration
        self.audioSessionCoordinator = audioSessionCoordinator
        self.notificationCenter = notificationCenter
        self.engineFactory = engineFactory
        self.dateProvider = dateProvider

        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in
                await self?.stop()
            }
        }
        lifecycleTask = Task { @MainActor [weak self] in
            await self?.start(reason: initialReason)
        }
    }

    func stop() async {
        guard !isStopped else {
            return
        }
        isStopped = true
        captureGeneration &+= 1
        lifecycleTask?.cancel()
        lifecycleTask = nil
        stopEngine()
        removeObservers()
        continuation.finish()
        logger.info("Environment monitor stopped intentionally")
    }

    private func start(reason: TinnitusEnvironmentSPLReacquisitionReason) async {
        continuation.yield(.warmingUp(reason))
        guard await requestMicrophonePermission() else {
            continuation.yield(.unavailable(.microphonePermissionDenied))
            continuation.finish()
            return
        }
        registerObservers()
        await configureAndStartCapture(reason: reason)
    }

    private func configureAndStartCapture(
        reason: TinnitusEnvironmentSPLReacquisitionReason
    ) async {
        guard !isStopped else {
            return
        }
        isReconfiguring = true
        stopEngine()
        captureGeneration &+= 1
        let generation = captureGeneration
        hasEmittedReady = false
        continuation.yield(.warmingUp(reason))

        do {
            let sessionInput = try audioSessionCoordinator.configureForMeasurement()
            if configuration.settlingDuration > 0 {
                try await Task.sleep(
                    nanoseconds: UInt64(configuration.settlingDuration * 1_000_000_000)
                )
            }
            guard !Task.isCancelled,
                  !isStopped,
                  generation == captureGeneration
            else {
                isReconfiguring = false
                return
            }

            let captureEngine = engineFactory()
            let inputNode = captureEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            guard format.commonFormat == .pcmFormatFloat32,
                  !format.isInterleaved,
                  format.sampleRate.isFinite,
                  format.sampleRate > 0,
                  format.channelCount > 0
            else {
                continuation.yield(.unavailable(.sampleFormatChanged))
                isReconfiguring = false
                return
            }

            let actualInput = TinnitusEnvironmentInputConfiguration(
                route: sessionInput.route,
                dataSourceOrientation: sessionInput.dataSourceOrientation,
                sampleRate: format.sampleRate,
                channelCount: Int(format.channelCount),
                inputGain: sessionInput.inputGain,
                isInputGainSettable: sessionInput.isInputGainSettable
            )
            let processor = try EnvironmentPCMWindowProcessor(
                input: actualInput,
                windowDuration: configuration.windowDuration,
                warmUpDuration: configuration.warmUpDuration
            )
            let box = EnvironmentPCMProcessorBox(processor: processor)

            inputNode.installTap(
                onBus: 0,
                bufferSize: 4_096,
                format: format
            ) { [weak self, box] buffer, time in
                guard let self else {
                    return
                }
                let result = box.process(
                    buffer: buffer,
                    timestamp: self.dateProvider(),
                    sampleTime: time.isSampleTimeValid ? time.sampleTime : nil
                )
                Task { @MainActor [weak self] in
                    self?.receive(
                        result,
                        expectedInput: actualInput,
                        generation: generation
                    )
                }
            }
            captureEngine.prepare()
            try captureEngine.start()
            engine = captureEngine
            processorBox = box
            isReconfiguring = false
            logger.info(
                "PCM capture started generation=\(generation, privacy: .public) sampleRate=\(format.sampleRate, privacy: .public) channels=\(format.channelCount, privacy: .public)"
            )
        } catch is CancellationError {
            isReconfiguring = false
        } catch let error as StudyAudioSessionCoordinatorError {
            isReconfiguring = false
            let reason: TinnitusEnvironmentMeasurementFailureReason
            switch error {
            case .builtInMicrophoneUnavailable:
                reason = .builtInMicrophoneUnavailable
            case .actualInputRouteMismatch:
                reason = .routeMismatch
            case .invalidInputFormat:
                reason = .sampleFormatChanged
            }
            continuation.yield(.unavailable(reason))
            logger.error("Measurement route setup failed reason=\(reason.rawValue, privacy: .public)")
        } catch {
            isReconfiguring = false
            continuation.yield(.unavailable(.engineFailure))
            logger.error("PCM engine failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func receive(
        _ result: EnvironmentPCMProcessingResult,
        expectedInput: TinnitusEnvironmentInputConfiguration,
        generation: UInt64
    ) {
        guard !isStopped, generation == captureGeneration else {
            logger.info("Ignored stale PCM callback generation=\(generation, privacy: .public)")
            return
        }
        guard let currentInput = audioSessionCoordinator.verifiedCurrentMeasurementInput() else {
            beginReacquisition(reason: .routeChange, failure: .routeMismatch)
            return
        }
        if let change = configurationChange(from: expectedInput, to: currentInput) {
            beginReacquisition(reason: reacquisitionReason(for: change), failure: change)
            return
        }

        if result.didCompleteWarmUp, !hasEmittedReady {
            hasEmittedReady = true
            continuation.yield(.ready)
            logger.info("PCM warm-up complete; next full window is decision-eligible")
        }
        for measurement in result.measurements {
            continuation.yield(.measurement(measurement))
            if let digitalLevel = measurement.aWeightedDigitalLevelDBFS {
                logger.info(
                    "Window valid=\(measurement.isValid, privacy: .public) duration=\(measurement.duration, privacy: .public) aWeightedDBFS=\(digitalLevel, privacy: .public) estimatedDBA=\(measurement.provisionalEstimatedDBA ?? -999, privacy: .public)"
                )
            } else if case .invalid(let reason) = measurement.validity {
                logger.info("Window excluded reason=\(reason.rawValue, privacy: .public)")
            }
        }
    }

    private func beginReacquisition(
        reason: TinnitusEnvironmentSPLReacquisitionReason,
        failure: TinnitusEnvironmentMeasurementFailureReason
    ) {
        guard !isStopped, !isReconfiguring else {
            return
        }
        continuation.yield(.invalidated(failure))
        logger.info(
            "Measurement invalidated reason=\(failure.rawValue, privacy: .public); reacquiring"
        )
        lifecycleTask?.cancel()
        lifecycleTask = Task { @MainActor [weak self] in
            await self?.configureAndStartCapture(reason: reason)
        }
    }

    private func registerObservers() {
        guard observers.isEmpty else {
            return
        }
        let reference = SendableWeakEnvironmentMonitorReference(self)
        let route = notificationCenter.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [reference] _ in
            Task { @MainActor [reference] in
                reference.value?.beginReacquisition(reason: .routeChange, failure: .routeChanged)
            }
        }
        let interruption = notificationCenter.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [reference] notification in
            let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            Task { @MainActor [reference] in
                reference.value?.handleInterruption(rawType: rawType)
            }
        }
        let mediaReset = notificationCenter.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: .main
        ) { [reference] _ in
            Task { @MainActor [reference] in
                reference.value?.beginReacquisition(reason: .mediaServicesReset, failure: .mediaServicesReset)
            }
        }
        let engineConfiguration = notificationCenter.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: nil,
            queue: .main
        ) { [reference] _ in
            Task { @MainActor [reference] in
                reference.value?.beginReacquisition(reason: .sampleFormatChange, failure: .sampleFormatChanged)
            }
        }
        observers = [route, interruption, mediaReset, engineConfiguration]
    }

    private func handleInterruption(rawType: UInt?) {
        let type = rawType.flatMap(AVAudioSession.InterruptionType.init(rawValue:))
        switch type {
        case .began:
            continuation.yield(.invalidated(.audioSessionInterrupted))
            stopEngine()
        case .ended:
            beginReacquisition(
                reason: .audioSessionInterruption,
                failure: .audioSessionInterrupted
            )
        case .none:
            break
        @unknown default:
            break
        }
    }

    private func removeObservers() {
        observers.forEach(notificationCenter.removeObserver)
        observers = []
    }

    private func stopEngine() {
        guard let engine else {
            processorBox = nil
            return
        }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        engine.reset()
        self.engine = nil
        processorBox = nil
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func configurationChange(
        from expected: TinnitusEnvironmentInputConfiguration,
        to current: TinnitusEnvironmentInputConfiguration
    ) -> TinnitusEnvironmentMeasurementFailureReason? {
        guard current.route == .builtInMicrophone else {
            return .routeMismatch
        }
        if expected.dataSourceOrientation != current.dataSourceOrientation {
            return .dataSourceChanged
        }
        if expected.sampleRate != current.sampleRate || expected.channelCount != current.channelCount {
            return .sampleFormatChanged
        }
        if abs(expected.inputGain - current.inputGain) > 0.000_1
            || expected.isInputGainSettable != current.isInputGainSettable {
            return .inputGainChanged
        }
        return nil
    }

    private func reacquisitionReason(
        for failure: TinnitusEnvironmentMeasurementFailureReason
    ) -> TinnitusEnvironmentSPLReacquisitionReason {
        switch failure {
        case .routeMismatch, .routeChanged, .builtInMicrophoneUnavailable:
            return .routeChange
        case .dataSourceChanged:
            return .dataSourceChange
        case .inputGainChanged:
            return .inputConfigurationChange
        case .mediaServicesReset:
            return .mediaServicesReset
        case .audioSessionInterrupted:
            return .audioSessionInterruption
        default:
            return .sampleFormatChange
        }
    }
}

private final class SendableWeakEnvironmentMonitorReference: @unchecked Sendable {
    weak var value: AVAudioEnvironmentSPLMonitorSession?

    init(_ value: AVAudioEnvironmentSPLMonitorSession) {
        self.value = value
    }
}

private final class EnvironmentPCMProcessorBox: @unchecked Sendable {
    private let lock = NSLock()
    private var processor: EnvironmentPCMWindowProcessor

    init(processor: EnvironmentPCMWindowProcessor) {
        self.processor = processor
    }

    func process(
        buffer: AVAudioPCMBuffer,
        timestamp: Date,
        sampleTime: Int64?
    ) -> EnvironmentPCMProcessingResult {
        lock.lock()
        defer { lock.unlock() }

        guard let channelData = buffer.floatChannelData else {
            return processor.process(channels: [], timestamp: timestamp, sampleTime: sampleTime)
        }
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameCount > 0, channelCount > 0 else {
            return processor.process(channels: [], timestamp: timestamp, sampleTime: sampleTime)
        }

        var channels: [[Float]] = []
        channels.reserveCapacity(channelCount)
        for channel in 0..<channelCount {
            channels.append(Array(UnsafeBufferPointer(
                start: channelData[channel],
                count: frameCount
            )))
        }
        return processor.process(
            channels: channels,
            timestamp: timestamp,
            sampleTime: sampleTime
        )
    }
}
