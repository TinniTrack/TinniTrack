import AVFoundation
import Foundation

protocol OutputVolumeMonitoring: AnyObject {
    func currentOutputVolume() -> Double?
    func startMonitoring(_ onChange: @escaping (Double) -> Void)
    func stopMonitoring()
}

final class SystemOutputVolumeMonitor: OutputVolumeMonitoring {
    private let audioSession: AVAudioSession
    private var observation: NSKeyValueObservation?
    private var onChange: ((Double) -> Void)?

    init(audioSession: AVAudioSession = .sharedInstance()) {
        self.audioSession = audioSession
    }

    func currentOutputVolume() -> Double? {
        Double(audioSession.outputVolume)
    }

    func startMonitoring(_ onChange: @escaping (Double) -> Void) {
        stopMonitoring()
        self.onChange = onChange
        onChange(Double(audioSession.outputVolume))

        observation = audioSession.observe(\.outputVolume, options: [.new]) { [weak self] session, _ in
            DispatchQueue.main.async {
                self?.onChange?(Double(session.outputVolume))
            }
        }
    }

    func stopMonitoring() {
        observation?.invalidate()
        observation = nil
        onChange = nil
    }

    deinit {
        stopMonitoring()
    }
}
