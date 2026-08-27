import Foundation
import ResearchKit
import ResearchKitActiveTask

nonisolated enum StudyNo1OrientationThresholdSequencerFactoryError: Error, Equatable {
    case unsupportedChannel(CalibratedTonePlaybackChannel)
    case emptyFrequencyList
}

/// Presentation-neutral access to one ear's threshold staircase.
///
/// The owner is responsible for scheduling tone playback and timeouts. Calling
/// these methods in the same order as playback preserves ResearchKit's handling
/// of early taps, heard responses, misses, clipping, and result timestamps.
@MainActor
protocol StudyNo1OrientationThresholdSequencing: AnyObject {
    var channel: CalibratedTonePlaybackChannel { get }
    var configuration: StudyNo1OrientationThresholdConfiguration { get }
    var nextStimulus: StudyNo1OrientationThresholdStimulus? { get }
    var progress: Double { get }
    var isComplete: Bool { get }

    func registerPreStimulusDelay(_ delay: TimeInterval)
    func registerStimulusPlayback()
    func registerResponse(heard: Bool)
    func signalClipped()
    func makeEarResult(outputVolume: Double) -> StudyNo1OrientationThresholdEarResult
}

@MainActor
protocol StudyNo1OrientationThresholdSequencerBuilding {
    func makeSequencer(
        for channel: CalibratedTonePlaybackChannel,
        configuration: StudyNo1OrientationThresholdConfiguration,
        timestampProvider: @escaping () -> TimeInterval
    ) throws -> any StudyNo1OrientationThresholdSequencing
}

@MainActor
final class ResearchKitStudyNo1OrientationThresholdSequencerFactory:
    StudyNo1OrientationThresholdSequencerBuilding
{
    func makeSequencer(
        for channel: CalibratedTonePlaybackChannel,
        configuration: StudyNo1OrientationThresholdConfiguration = .studyNo1,
        timestampProvider: @escaping () -> TimeInterval
    ) throws -> any StudyNo1OrientationThresholdSequencing {
        guard !configuration.frequenciesHz.isEmpty else {
            throw StudyNo1OrientationThresholdSequencerFactoryError.emptyFrequencyList
        }
        guard let researchKitChannel = ORKAudioChannel(channel) else {
            throw StudyNo1OrientationThresholdSequencerFactoryError.unsupportedChannel(channel)
        }

        let step = ORKdBHLToneAudiometryStep(
            identifier: "study-no-1.orientation-threshold.\(channel.rawValue)"
        )
        step.frequencyList = configuration.frequenciesHz
        step.toneDuration = configuration.toneDuration
        step.maxRandomPreStimulusDelay = configuration.maximumRandomPreStimulusDelay
        step.postStimulusDelay = configuration.postStimulusDelay
        step.maxNumberOfTransitionsPerFrequency = configuration.maximumTransitionsPerFrequency
        step.initialdBHLValue = configuration.initialLevelDBHL
        step.dBHLStepUpSize = configuration.stepUpDB
        step.dBHLStepUpSizeFirstMiss = configuration.firstMissStepUpDB
        step.dBHLStepUpSizeSecondMiss = configuration.secondMissStepUpDB
        step.dBHLStepUpSizeThirdMiss = configuration.thirdMissStepUpDB
        step.dBHLStepDownSize = configuration.stepDownDB
        step.dBHLMinimumThreshold = configuration.minimumLevelDBHL
        step.headphoneType = ORKHeadphoneTypeIdentifier(
            rawValue: configuration.headphoneTypeIdentifier
        )
        step.earPreference = researchKitChannel

        let engine = step.audiometryEngine()
        engine.timestampProvider = timestampProvider

        return ResearchKitStudyNo1OrientationThresholdSequencer(
            channel: channel,
            configuration: configuration,
            engine: engine
        )
    }
}

@MainActor
private final class ResearchKitStudyNo1OrientationThresholdSequencer:
    StudyNo1OrientationThresholdSequencing
{
    let channel: CalibratedTonePlaybackChannel
    let configuration: StudyNo1OrientationThresholdConfiguration

    private let engine: any ORKAudiometryProtocol

    init(
        channel: CalibratedTonePlaybackChannel,
        configuration: StudyNo1OrientationThresholdConfiguration,
        engine: any ORKAudiometryProtocol
    ) {
        self.channel = channel
        self.configuration = configuration
        self.engine = engine
    }

    var nextStimulus: StudyNo1OrientationThresholdStimulus? {
        guard let stimulus = engine.nextStimulus?(),
              let channel = CalibratedTonePlaybackChannel(stimulus.channel)
        else {
            return nil
        }

        return StudyNo1OrientationThresholdStimulus(
            frequencyHz: stimulus.frequency,
            levelDBHL: stimulus.level,
            channel: channel
        )
    }

    var progress: Double {
        Double(engine.progress)
    }

    var isComplete: Bool {
        engine.testEnded
    }

    func registerPreStimulusDelay(_ delay: TimeInterval) {
        engine.registerPreStimulusDelay?(delay)
    }

    func registerStimulusPlayback() {
        engine.registerStimulusPlayback()
    }

    func registerResponse(heard: Bool) {
        engine.registerResponse?(heard, for: nil)
    }

    func signalClipped() {
        engine.signalClipped?()
    }

    func makeEarResult(outputVolume: Double) -> StudyNo1OrientationThresholdEarResult {
        let samples = (engine.resultSamples?() ?? []).compactMap(
            StudyNo1OrientationThresholdFrequencySample.init
        )
        let resolvedChannel = samples.first?.channel ?? channel
        let thresholdFrequency = configuration.frequenciesHz.first { $0 == 1_000 }
            ?? configuration.frequenciesHz[0]
        let threshold = samples.first {
            $0.frequencyHz == thresholdFrequency && $0.channel == resolvedChannel
        }?.calculatedThresholdDBHL

        return StudyNo1OrientationThresholdEarResult(
            channel: resolvedChannel,
            thresholdDBHL: threshold,
            outputVolume: outputVolume,
            headphoneType: configuration.headphoneTypeIdentifier,
            tonePlaybackDuration: configuration.toneDuration,
            postStimulusDelay: configuration.postStimulusDelay,
            samples: samples
        )
    }
}

private extension StudyNo1OrientationThresholdFrequencySample {
    init?(_ sample: ORKdBHLToneAudiometryFrequencySample) {
        guard let channel = CalibratedTonePlaybackChannel(sample.channel) else {
            return nil
        }

        frequencyHz = sample.frequency
        calculatedThresholdDBHL = sample.calculatedThreshold == ORKInvalidDBHLValue
            ? nil
            : sample.calculatedThreshold
        self.channel = channel
        units = (sample.units ?? []).map(StudyNo1OrientationThresholdUnit.init)
    }
}

private extension StudyNo1OrientationThresholdUnit {
    init(_ unit: ORKdBHLToneAudiometryUnit) {
        levelDBHL = unit.dBHLValue
        startOfUnitTimeStamp = unit.startOfUnitTimeStamp
        preStimulusDelay = unit.preStimulusDelay
        userTapTimeStamp = unit.userTapTimeStamp > 0 ? unit.userTapTimeStamp : nil
        timeoutTimeStamp = unit.timeoutTimeStamp > 0 ? unit.timeoutTimeStamp : nil
    }
}

private extension CalibratedTonePlaybackChannel {
    init?(_ channel: ORKAudioChannel) {
        switch channel {
        case .left:
            self = .left
        case .right:
            self = .right
        @unknown default:
            return nil
        }
    }
}

private extension ORKAudioChannel {
    init?(_ channel: CalibratedTonePlaybackChannel) {
        switch channel {
        case .left:
            self = .left
        case .right:
            self = .right
        case .both:
            return nil
        }
    }
}
