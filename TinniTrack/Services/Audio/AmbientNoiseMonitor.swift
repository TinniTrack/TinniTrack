import Foundation
import AVFoundation

enum AmbientNoisePermissionStatus: Equatable {
    case notDetermined
    case denied
    case granted
}

enum AmbientNoiseMonitorError: LocalizedError {
    case permissionDenied
    case unavailable
    case failedToStart

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone access is required for ambient-noise checks."
        case .unavailable:
            return "Ambient noise monitoring is unavailable on this device."
        case .failedToStart:
            return "Unable to start ambient noise monitoring."
        }
    }
}

protocol AmbientNoiseMonitoring: AnyObject {
    func permissionStatus() -> AmbientNoisePermissionStatus
    func requestPermission() async -> Bool
    func startMonitoring(onUpdate: @escaping (Double) -> Void) throws
    func stopMonitoring()
}

final class AmbientNoiseMonitor: NSObject, AmbientNoiseMonitoring {
    private let audioSession: AVAudioSession
    private var recorder: AVAudioRecorder?
    private var timer: Timer?

    init(audioSession: AVAudioSession = .sharedInstance()) {
        self.audioSession = audioSession
    }

    func permissionStatus() -> AmbientNoisePermissionStatus {
        switch audioSession.recordPermission {
        case .undetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .granted:
            return .granted
        @unknown default:
            return .notDetermined
        }
    }

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            audioSession.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func startMonitoring(onUpdate: @escaping (Double) -> Void) throws {
        guard permissionStatus() == .granted else {
            throw AmbientNoiseMonitorError.permissionDenied
        }

        stopMonitoring()

        do {
            try audioSession.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.mixWithOthers, .allowBluetooth, .allowBluetoothA2DP]
            )
            try audioSession.setActive(true)
        } catch {
            throw AmbientNoiseMonitorError.unavailable
        }

        let fileURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ambient-meter.caf")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatAppleLossless,
            AVSampleRateKey: 44_100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.min.rawValue
        ]

        do {
            let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
            recorder.isMeteringEnabled = true
            guard recorder.prepareToRecord(), recorder.record() else {
                throw AmbientNoiseMonitorError.failedToStart
            }
            self.recorder = recorder
        } catch {
            throw AmbientNoiseMonitorError.failedToStart
        }

        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self, let recorder = self.recorder else { return }
            recorder.updateMeters()
            let averagePower = recorder.averagePower(forChannel: 0)
            // Heuristic mapping from dBFS meter values to an SPL-like scale for gating.
            let estimatedDB = max(0, Double(averagePower) + 100)
            onUpdate(estimatedDB)
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil

        recorder?.stop()
        recorder = nil
    }

    deinit {
        recorder?.stop()
        timer?.invalidate()
    }
}
