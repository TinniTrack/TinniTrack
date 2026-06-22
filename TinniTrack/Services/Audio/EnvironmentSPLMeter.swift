import AVFoundation
import Foundation

enum EnvironmentSPLMeterError: Error, Equatable {
    case microphonePermissionDenied
    case recorderUnavailable
}

protocol EnvironmentSPLMeasuring {
    func runGate(configuration: TinnitusEnvironmentSPLGateConfiguration) async throws -> TinnitusEnvironmentSPLGateResult
}

struct AVAudioEnvironmentSPLMeter: EnvironmentSPLMeasuring {
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

        try audioSession.setCategory(.record, mode: .measurement, options: [])
        try audioSession.setActive(true)

        let recorder = try makeRecorder()
        recorder.isMeteringEnabled = true
        guard recorder.record() else {
            throw EnvironmentSPLMeterError.recorderUnavailable
        }
        defer {
            recorder.stop()
        }

        var samples: [Double] = []
        for _ in 0..<resolvedConfiguration.maximumSamples {
            try await Task.sleep(nanoseconds: UInt64(resolvedConfiguration.samplingInterval * 1_000_000_000))
            recorder.updateMeters()
            let dBFS = Double(recorder.averagePower(forChannel: 0))
            samples.append(dBFS + sensitivityOffsetDB)

            let partial = evaluator.evaluate(
                samplesDBA: samples,
                configuration: resolvedConfiguration
            )
            if partial.passed {
                return partial
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
}
