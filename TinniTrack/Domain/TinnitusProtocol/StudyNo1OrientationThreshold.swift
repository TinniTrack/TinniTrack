import Foundation

/// The app-owned configuration for the Study No. 1 orientation hearing threshold.
///
/// The staircase values deliberately mirror `ORKdBHLToneAudiometryStep` defaults,
/// while the pre-stimulus bounds preserve its step controller's 1.0–1.9 second
/// timing in 0.1 second increments. Keeping them explicit prevents a future
/// ResearchKit update from silently changing the study protocol. Study No. 1
/// narrows ResearchKit's default frequency list to the required 1 kHz measurement.
nonisolated struct StudyNo1OrientationThresholdConfiguration: Equatable {
    let frequenciesHz: [Double]
    let toneDuration: TimeInterval
    let minimumPreStimulusDelay: TimeInterval
    let maximumRandomPreStimulusDelay: TimeInterval
    let preStimulusDelayResolution: TimeInterval
    let postStimulusDelay: TimeInterval
    let maximumTransitionsPerFrequency: Int
    let initialLevelDBHL: Double
    let stepUpDB: Double
    let firstMissStepUpDB: Double
    let secondMissStepUpDB: Double
    let thirdMissStepUpDB: Double
    let stepDownDB: Double
    let minimumLevelDBHL: Double
    let headphoneTypeIdentifier: String

    static let studyNo1 = StudyNo1OrientationThresholdConfiguration(
        frequenciesHz: [1_000],
        toneDuration: 1.0,
        minimumPreStimulusDelay: 1.0,
        maximumRandomPreStimulusDelay: 2.0,
        preStimulusDelayResolution: 0.1,
        postStimulusDelay: 1.0,
        maximumTransitionsPerFrequency: 20,
        initialLevelDBHL: 30.0,
        stepUpDB: 5.0,
        firstMissStepUpDB: 20.0,
        secondMissStepUpDB: 10.0,
        thirdMissStepUpDB: 10.0,
        stepDownDB: 10.0,
        minimumLevelDBHL: -10.0,
        headphoneTypeIdentifier: CalibratedHeadphoneIdentifier.airPodsPro2
    )
}

/// A presentation-neutral description of the tone currently requested by the
/// orientation threshold algorithm.
nonisolated struct StudyNo1OrientationThresholdStimulus: Equatable {
    let frequencyHz: Double
    let levelDBHL: Double
    let channel: CalibratedTonePlaybackChannel
}

/// The complete app-owned result for the two-ear orientation threshold run.
nonisolated struct StudyNo1OrientationThresholdResult: Equatable {
    let taskIdentifier: String
    let rightEar: StudyNo1OrientationThresholdEarResult?
    let leftEar: StudyNo1OrientationThresholdEarResult?
    let environment: StudyNo1OrientationThresholdEnvironmentResult?

    var isComplete: Bool {
        rightEar?.thresholdDBHL != nil && leftEar?.thresholdDBHL != nil
    }
}

nonisolated struct StudyNo1OrientationThresholdEnvironmentResult: Equatable {
    let thresholdDBA: Double
    let requiredContiguousSamples: Int
}

/// Result fields intentionally retain the semantics and units of the previous
/// ResearchKit-presented orientation task so submission payloads remain stable.
nonisolated struct StudyNo1OrientationThresholdEarResult: Equatable {
    let channel: CalibratedTonePlaybackChannel
    let thresholdDBHL: Double?
    let outputVolume: Double
    let headphoneType: String?
    let tonePlaybackDuration: TimeInterval
    let postStimulusDelay: TimeInterval
    let samples: [StudyNo1OrientationThresholdFrequencySample]
}

nonisolated struct StudyNo1OrientationThresholdFrequencySample: Equatable {
    let frequencyHz: Double
    let calculatedThresholdDBHL: Double?
    let channel: CalibratedTonePlaybackChannel
    let units: [StudyNo1OrientationThresholdUnit]
}

nonisolated struct StudyNo1OrientationThresholdUnit: Equatable {
    let levelDBHL: Double
    let startOfUnitTimeStamp: TimeInterval
    let preStimulusDelay: TimeInterval
    let userTapTimeStamp: TimeInterval?
    let timeoutTimeStamp: TimeInterval?
}
