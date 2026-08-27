import Foundation
import Testing
@testable import TinniTrack

@MainActor
struct ResearchKitStudyNo1OrientationThresholdSequencerTests {
    @Test
    func fixedThresholdListenerCompletesResearchKitStaircaseForEachEar() throws {
        let factory = ResearchKitStudyNo1OrientationThresholdSequencerFactory()

        for channel in [
            CalibratedTonePlaybackChannel.right,
            CalibratedTonePlaybackChannel.left
        ] {
            var timestamp: TimeInterval = 0
            let sequencer = try factory.makeSequencer(
                for: channel,
                configuration: .studyNo1,
                timestampProvider: { timestamp }
            )

            let earlyStimulus = try #require(sequencer.nextStimulus)
            sequencer.registerPreStimulusDelay(1.1)
            timestamp = 0.25
            sequencer.registerResponse(heard: true)

            #expect(sequencer.nextStimulus?.levelDBHL == earlyStimulus.levelDBHL)
            #expect(sequencer.isComplete == false)

            var trialCount = 0
            while !sequencer.isComplete, trialCount < 100 {
                let stimulus = try #require(sequencer.nextStimulus)
                let preStimulusDelay = 1.0
                    + (Double(trialCount % 10) * 0.1)
                sequencer.registerPreStimulusDelay(preStimulusDelay)
                timestamp += preStimulusDelay
                sequencer.registerStimulusPlayback()
                timestamp += 0.5
                sequencer.registerResponse(heard: stimulus.levelDBHL >= 15)
                timestamp += StudyNo1OrientationThresholdConfiguration
                    .studyNo1
                    .postStimulusDelay
                trialCount += 1
            }

            #expect(sequencer.isComplete)
            #expect(trialCount < 100)
            #expect(sequencer.progress > 0)

            let result = sequencer.makeEarResult(outputVolume: 0.8)
            #expect(result.channel == channel)
            #expect(result.thresholdDBHL == 15)
            #expect(result.outputVolume == 0.8)
            #expect(result.headphoneType == CalibratedHeadphoneIdentifier.airPodsPro2)
            #expect(result.tonePlaybackDuration == 1)
            #expect(result.postStimulusDelay == 1)

            let sample = try #require(result.samples.first)
            #expect(result.samples.count == 1)
            #expect(sample.frequencyHz == 1_000)
            #expect(sample.channel == channel)
            #expect(sample.calculatedThresholdDBHL == 15)
            #expect(sample.units.count > 1)
            #expect(sample.units.first?.startOfUnitTimeStamp == 0)
            #expect(sample.units.first?.preStimulusDelay == 1.1)
            #expect(sample.units.first?.userTapTimeStamp == 0.25)
            #expect(sample.units.contains { $0.userTapTimeStamp != nil })
            #expect(sample.units.contains { $0.timeoutTimeStamp != nil })
        }
    }

    @Test
    func factoryRejectsBinauralAndEmptyFrequencyConfigurations() throws {
        let factory = ResearchKitStudyNo1OrientationThresholdSequencerFactory()

        #expect(throws: StudyNo1OrientationThresholdSequencerFactoryError.unsupportedChannel(.both)) {
            _ = try factory.makeSequencer(
                for: .both,
                configuration: .studyNo1,
                timestampProvider: { 0 }
            )
        }

        let defaults = StudyNo1OrientationThresholdConfiguration.studyNo1
        let emptyConfiguration = StudyNo1OrientationThresholdConfiguration(
            frequenciesHz: [],
            toneDuration: defaults.toneDuration,
            minimumPreStimulusDelay: defaults.minimumPreStimulusDelay,
            maximumRandomPreStimulusDelay: defaults.maximumRandomPreStimulusDelay,
            preStimulusDelayResolution: defaults.preStimulusDelayResolution,
            postStimulusDelay: defaults.postStimulusDelay,
            maximumTransitionsPerFrequency: defaults.maximumTransitionsPerFrequency,
            initialLevelDBHL: defaults.initialLevelDBHL,
            stepUpDB: defaults.stepUpDB,
            firstMissStepUpDB: defaults.firstMissStepUpDB,
            secondMissStepUpDB: defaults.secondMissStepUpDB,
            thirdMissStepUpDB: defaults.thirdMissStepUpDB,
            stepDownDB: defaults.stepDownDB,
            minimumLevelDBHL: defaults.minimumLevelDBHL,
            headphoneTypeIdentifier: defaults.headphoneTypeIdentifier
        )

        #expect(throws: StudyNo1OrientationThresholdSequencerFactoryError.emptyFrequencyList) {
            _ = try factory.makeSequencer(
                for: .right,
                configuration: emptyConfiguration,
                timestampProvider: { 0 }
            )
        }
    }
}
