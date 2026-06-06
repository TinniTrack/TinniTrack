import Foundation
import AVFoundation

struct AudioOutputRoute: Equatable {
    let name: String
    let portType: String
}

protocol HeadphoneRouteMonitoring: AnyObject {
    func currentRoute() -> AudioOutputRoute?
    func startMonitoring(_ onChange: @escaping (AudioOutputRoute?) -> Void)
    func stopMonitoring()
}

final class HeadphoneRouteMonitor: HeadphoneRouteMonitoring {
    private let audioSession: AVAudioSession
    private var observer: NSObjectProtocol?
    private var onChange: ((AudioOutputRoute?) -> Void)?

    init(audioSession: AVAudioSession = .sharedInstance()) {
        self.audioSession = audioSession
    }

    func currentRoute() -> AudioOutputRoute? {
        guard let output = audioSession.currentRoute.outputs.first else {
            return nil
        }

        return AudioOutputRoute(
            name: output.portName,
            portType: output.portType.rawValue
        )
    }

    func startMonitoring(_ onChange: @escaping (AudioOutputRoute?) -> Void) {
        stopMonitoring()
        self.onChange = onChange

        onChange(currentRoute())

        observer = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: audioSession,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.onChange?(self.currentRoute())
        }
    }

    func stopMonitoring() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
        onChange = nil
    }

    deinit {
        stopMonitoring()
    }
}
