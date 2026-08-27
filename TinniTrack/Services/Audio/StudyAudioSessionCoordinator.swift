import AVFoundation
import Foundation
import OSLog

@MainActor
protocol StudyAudioSessionCoordinating: AnyObject {
    var isWorkflowActive: Bool { get }

    func beginWorkflow()
    func configureForMeasurement() throws -> TinnitusEnvironmentInputConfiguration
    func configureForPlayback(
        preferredSampleRate: Double,
        preferredBufferFrameCount: Int
    ) throws
    func verifiedCurrentMeasurementInput() -> TinnitusEnvironmentInputConfiguration?
    func endWorkflow()
}

enum StudyAudioSessionCoordinatorError: Error, Equatable {
    case builtInMicrophoneUnavailable
    case actualInputRouteMismatch
    case invalidInputFormat
}

/// Serializes every process-global AVAudioSession mutation for the hearing-test
/// workflow. External state is captured once and restored once, idempotently.
@MainActor
final class StudyAudioSessionCoordinator: StudyAudioSessionCoordinating {
    static let shared = StudyAudioSessionCoordinator()

    private struct ExternalState {
        let category: AVAudioSession.Category
        let mode: AVAudioSession.Mode
        let options: AVAudioSession.CategoryOptions
        let preferredSampleRate: Double
        let preferredIOBufferDuration: TimeInterval
        let preferredInput: AVAudioSessionPortDescription?
    }

    private let audioSession: AVAudioSession
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "TinniTrack",
        category: "StudyAudioSession"
    )
    private var externalState: ExternalState?
    private(set) var isWorkflowActive = false

    init(audioSession: AVAudioSession = .sharedInstance()) {
        self.audioSession = audioSession
    }

    func beginWorkflow() {
        guard !isWorkflowActive else {
            return
        }
        externalState = ExternalState(
            category: audioSession.category,
            mode: audioSession.mode,
            options: audioSession.categoryOptions,
            preferredSampleRate: audioSession.preferredSampleRate,
            preferredIOBufferDuration: audioSession.preferredIOBufferDuration,
            preferredInput: audioSession.preferredInput
        )
        isWorkflowActive = true
        logger.info("Audio workflow began; external session state captured")
    }

    func configureForMeasurement() throws -> TinnitusEnvironmentInputConfiguration {
        beginWorkflow()
        try audioSession.setCategory(
            .playAndRecord,
            mode: .measurement,
            options: [.allowBluetoothA2DP]
        )

        guard let builtInMicrophone = audioSession.availableInputs?.first(where: {
            $0.portType == .builtInMic
        }) else {
            logger.error("Measurement route invalid: built-in microphone unavailable")
            throw StudyAudioSessionCoordinatorError.builtInMicrophoneUnavailable
        }

        if let dataSource = preferredDataSource(for: builtInMicrophone) {
            if dataSource.supportedPolarPatterns?.contains(.omnidirectional) == true {
                try? dataSource.setPreferredPolarPattern(.omnidirectional)
            }
            try builtInMicrophone.setPreferredDataSource(dataSource)
        }
        try audioSession.setPreferredInput(builtInMicrophone)
        if audioSession.maximumInputNumberOfChannels >= 1 {
            try audioSession.setPreferredInputNumberOfChannels(1)
        }
        try audioSession.setActive(true)

        guard let input = verifiedCurrentMeasurementInput() else {
            logger.error("Measurement route invalid: actual input is not built-in microphone")
            throw StudyAudioSessionCoordinatorError.actualInputRouteMismatch
        }
        logger.info(
            "Measurement session ready sampleRate=\(input.sampleRate, privacy: .public) channels=\(input.channelCount, privacy: .public) orientation=\(input.dataSourceOrientation?.rawValue ?? "none", privacy: .public) gainSettable=\(self.audioSession.isInputGainSettable, privacy: .public)"
        )
        return input
    }

    func configureForPlayback(
        preferredSampleRate: Double,
        preferredBufferFrameCount: Int
    ) throws {
        beginWorkflow()
        try audioSession.setCategory(.playback, mode: .default, options: [])
        try audioSession.setPreferredSampleRate(preferredSampleRate)
        try audioSession.setPreferredIOBufferDuration(
            Double(preferredBufferFrameCount) / preferredSampleRate
        )
        try audioSession.setActive(true)
        logger.info("Audio session handed to calibrated playback")
    }

    func verifiedCurrentMeasurementInput() -> TinnitusEnvironmentInputConfiguration? {
        guard audioSession.category == .playAndRecord,
              audioSession.mode == .measurement,
              let actualInput = audioSession.currentRoute.inputs.first,
              actualInput.portType == .builtInMic
        else {
            return nil
        }
        let sampleRate = audioSession.sampleRate
        let channelCount = actualInput.channels?.count ?? audioSession.inputNumberOfChannels
        guard sampleRate.isFinite, sampleRate > 0, channelCount > 0 else {
            return nil
        }
        return TinnitusEnvironmentInputConfiguration(
            route: .builtInMicrophone,
            dataSourceOrientation: Self.orientation(actualInput.selectedDataSource?.orientation),
            sampleRate: sampleRate,
            channelCount: channelCount,
            inputGain: audioSession.inputGain,
            isInputGainSettable: audioSession.isInputGainSettable
        )
    }

    func endWorkflow() {
        guard isWorkflowActive else {
            return
        }
        defer {
            externalState = nil
            isWorkflowActive = false
        }

        do {
            try audioSession.setActive(false, options: [.notifyOthersOnDeactivation])
            if let externalState {
                try audioSession.setCategory(
                    externalState.category,
                    mode: externalState.mode,
                    options: externalState.options
                )
                try audioSession.setPreferredSampleRate(externalState.preferredSampleRate)
                try audioSession.setPreferredIOBufferDuration(externalState.preferredIOBufferDuration)
                try audioSession.setPreferredInput(externalState.preferredInput)
            }
            logger.info("Audio workflow ended; external session state restored once")
        } catch {
            logger.error("Audio workflow restoration failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func preferredDataSource(
        for input: AVAudioSessionPortDescription
    ) -> AVAudioSessionDataSourceDescription? {
        let priority: [AVAudioSession.Orientation] = [.bottom, .front, .back, .top]
        for orientation in priority {
            if let match = input.dataSources?.first(where: { $0.orientation == orientation }) {
                return match
            }
        }
        return input.dataSources?.first
    }

    private static func orientation(
        _ orientation: AVAudioSession.Orientation?
    ) -> TinnitusEnvironmentDataSourceOrientation? {
        switch orientation {
        case .bottom:
            return .bottom
        case .front:
            return .front
        case .back:
            return .back
        case .top:
            return .top
        case .none:
            return nil
        default:
            return .unknown
        }
    }
}
