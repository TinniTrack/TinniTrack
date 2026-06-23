import AVFoundation
import Foundation

enum EnvironmentSPLMeterError: Error, Equatable {
    case microphonePermissionDenied
    case recorderUnavailable
}

protocol EnvironmentSPLMeasuring {
    func runGate(configuration: TinnitusEnvironmentSPLGateConfiguration) async throws -> TinnitusEnvironmentSPLGateResult
}

protocol EnvironmentSPLGateMonitoring {
    func monitorGate(
        configuration: TinnitusEnvironmentSPLGateConfiguration
    ) -> AsyncThrowingStream<TinnitusEnvironmentSPLGateUpdate, Error>
}

struct AVAudioEnvironmentSPLMeter: EnvironmentSPLMeasuring, EnvironmentSPLGateMonitoring {
    private let audioSession: AVAudioSession
    private let evaluator: TinnitusEnvironmentSPLGateEvaluator
    private let sensitivityOffsetDB: Double

    init(
        audioSession: AVAudioSession = .sharedInstance(),
        evaluator: TinnitusEnvironmentSPLGateEvaluator = TinnitusEnvironmentSPLGateEvaluator(),
        sensitivityOffsetDB: Double = 90.0
    ) {
        self.audioSession = audioSession
        self.evaluator = evaluator
        self.sensitivityOffsetDB = sensitivityOffsetDB
    }

    func runGate(configuration: TinnitusEnvironmentSPLGateConfiguration = .studyA) async throws -> TinnitusEnvironmentSPLGateResult {
        try await sampleGate(configuration: configuration, maximumSamples: configuration.maximumSamples) { _ in }
    }

    func monitorGate(
        configuration: TinnitusEnvironmentSPLGateConfiguration = .studyA
    ) -> AsyncThrowingStream<TinnitusEnvironmentSPLGateUpdate, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    _ = try await sampleGate(configuration: configuration, maximumSamples: nil) { update in
                        continuation.yield(update)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func sampleGate(
        configuration: TinnitusEnvironmentSPLGateConfiguration,
        maximumSamples: Int?,
        onUpdate: (TinnitusEnvironmentSPLGateUpdate) -> Void
    ) async throws -> TinnitusEnvironmentSPLGateResult {
        guard await requestMicrophonePermission() else {
            throw EnvironmentSPLMeterError.microphonePermissionDenied
        }

        let resolvedConfiguration = TinnitusEnvironmentSPLGateConfiguration(
            thresholdDBA: configuration.thresholdDBA,
            requiredContiguousSamples: configuration.requiredContiguousSamples,
            samplingInterval: configuration.samplingInterval,
            maximumSamples: configuration.maximumSamples,
            sensitivityOffsetDB: sensitivityOffsetDB
        )

        let previousCategory = audioSession.category
        let previousMode = audioSession.mode
        let previousOptions = audioSession.categoryOptions
        try audioSession.setCategory(.record, mode: .measurement, options: [])
        try audioSession.setActive(true)

        let recorder = try makeRecorder()
        recorder.isMeteringEnabled = true
        guard recorder.record() else {
            throw EnvironmentSPLMeterError.recorderUnavailable
        }
        defer {
            recorder.stop()
            restoreAudioSession(category: previousCategory, mode: previousMode, options: previousOptions)
        }

        var samples: [Double] = []
        var sampleCount = 0
        while maximumSamples == nil || sampleCount < (maximumSamples ?? 0) {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: UInt64(resolvedConfiguration.samplingInterval * 1_000_000_000))
            try Task.checkCancellation()
            recorder.updateMeters()
            let dBFS = Double(recorder.averagePower(forChannel: 0))
            samples.append(dBFS + sensitivityOffsetDB)
            sampleCount += 1

            let update = evaluator.update(
                samplesDBA: samples,
                configuration: resolvedConfiguration
            )
            onUpdate(update)

            if let result = update.result {
                return result
            }
        }

        return evaluator.evaluate(samplesDBA: samples, configuration: resolvedConfiguration)
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func makeRecorder() throws -> AVAudioRecorder {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tinnitrack-environment-spl.caf")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatAppleIMA4),
            AVSampleRateKey: 44_100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.min.rawValue
        ]
        return try AVAudioRecorder(url: url, settings: settings)
    }

    private func restoreAudioSession(
        category: AVAudioSession.Category,
        mode: AVAudioSession.Mode,
        options: AVAudioSession.CategoryOptions
    ) {
        do {
            try audioSession.setActive(false, options: [.notifyOthersOnDeactivation])
            try audioSession.setCategory(category, mode: mode, options: options)
            try audioSession.setActive(true)
        } catch {
            // Later playback guardrail validation fails safely if restoration is incomplete.
        }
    }
}
