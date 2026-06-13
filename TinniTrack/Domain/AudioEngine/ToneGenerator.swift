import AVFoundation
import OSLog

protocol TonePlaying: AnyObject {
    func start()
    func stop()
    func setVolume(_ volume: Double)
}

final class ToneGenerator: TonePlaying {
    static let shared = ToneGenerator()

    private let logger = Logger(subsystem: "com.BARScapstone.TinniTrack", category: "AudioEngine")

    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode!

    private let frequency: Double = 1000.0
    private var theta: Double = 0.0
    private var currentVolume: Float = 0.0
    private var isRunning = false

    private init() {
        setupEngine()
    }

    private func setupEngine() {
        let main = engine.mainMixerNode
        let output = engine.outputNode
        let format = output.inputFormat(forBus: 0)
        let sampleRate = format.sampleRate
        
        sourceNode = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self = self else { return noErr }
            
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let delta = 2.0 * Double.pi * self.frequency / sampleRate
            
            for frame in 0..<Int(frameCount) {
                let sample = sin(self.theta) * Double(self.currentVolume)
                self.theta += delta
                if self.theta > 2.0 * Double.pi {
                    self.theta -= 2.0 * Double.pi
                }
                
                for buffer in ablPointer {
                    let buf = buffer.mData!.assumingMemoryBound(to: Float.self)
                    buf[frame] = Float(sample)
                }
            }
            return noErr
        }

        engine.attach(sourceNode)
        engine.connect(sourceNode, to: main, format: format)
    }

    func start() {
        guard !isRunning else { return }
        do {
            try engine.start()
            isRunning = true
        } catch {
            logger.error("Failed to start audio engine: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stop() {
        engine.stop()
        isRunning = false
    }

    func setVolume(_ volume: Double) {
        currentVolume = max(0.0, min(1.0, Float(volume)))
    }
}
