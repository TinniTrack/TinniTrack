# Technical Approach: Calibrated Tone Output for Tinnitus Loudness Matching on iOS

Date: 2026-06-21

## Executive summary

ResearchKit has a directly relevant hearing module: `ORKdBHLToneAudiometryStep`. It is designed for pure-tone audiometry in dB HL, includes an environment SPL gating step, supports AirPods Pro 2 through `ORKHeadphoneTypeIdentifierAirPodsProGen2`, and bundles AirPods Pro 2 calibration tables for:

- frequency-specific SPL sensitivity,
- RETSPL conversion from dB HL to dB SPL,
- iOS volume-position correction.

The best implementation path is not to use ResearchKit's predefined dB HL audiometry task as-is, because its interaction is Hughson-Westlake threshold finding, not tinnitus loudness matching. It is also not ideal to depend directly on `ORKdBHLToneAudiometryAudioGenerator`: in the inspected source it is a private ResearchKitActiveTask header, not part of the public umbrella header. Instead, reuse or port its calibrated tone generation model behind an app-owned API:

1. verify route, headphone model, system volume, fit, quiet-room state, and app/audio settings;
2. generate a pure tone at the patient's matched tinnitus pitch;
3. convert the requested clinical level into target SPL or dB HL using ResearchKit-style tables;
4. scale the PCM amplitude to produce the desired estimated ear-level output;
5. run a loudness matching procedure that records the final match in dB HL, dB SPL estimate, and, preferably, dB SL relative to that patient's threshold at the matched pitch.

The important limitation: public iOS APIs do not appear to expose Apple's private AirPods hearing-test calibration, fit-check, or exact in-ear SPL. ResearchKit's calibration gives a model-level calibrated output estimate for supported Apple headphones. It still needs validation for your exact app, route, OS version, AirPods firmware, and study protocol before being used as a research instrument.

## Sources reviewed

Primary code and documentation:

- ResearchKit repository, commit `daba8c9f103477bd0279cc52a924a85b480df601`: https://github.com/ResearchKit/ResearchKit
- ResearchKit README active-task warning and dBHL task sample: https://github.com/ResearchKit/ResearchKit/blob/daba8c9f103477bd0279cc52a924a85b480df601/README.md#active-tasks
- dB HL generator: https://github.com/ResearchKit/ResearchKit/blob/daba8c9f103477bd0279cc52a924a85b480df601/ResearchKitActiveTask/dBHL%20Tone%20Audiometry/ORKAudiometry/ORKdBHLToneAudiometryAudioGenerator.m
- dB HL step: https://github.com/ResearchKit/ResearchKit/blob/daba8c9f103477bd0279cc52a924a85b480df601/ResearchKitActiveTask/dBHL%20Tone%20Audiometry/ORKdBHLToneAudiometryStep.h
- dB HL audiometry engine: https://github.com/ResearchKit/ResearchKit/blob/daba8c9f103477bd0279cc52a924a85b480df601/ResearchKitActiveTask/dBHL%20Tone%20Audiometry/ORKAudiometry/ORKAudiometry.m
- Environment SPL meter: https://github.com/ResearchKit/ResearchKit/tree/daba8c9f103477bd0279cc52a924a85b480df601/ResearchKitActiveTask/environmentSPLMeter
- ResearchKit active-task docs: https://github.com/ResearchKit/ResearchKit/blob/daba8c9f103477bd0279cc52a924a85b480df601/ResearchKit/ResearchKit.docc/Resources/Understanding-Active-Tasks/Understanding-Active-Tasks.md
- ResearchKit release notes: https://github.com/ResearchKit/ResearchKit/blob/daba8c9f103477bd0279cc52a924a85b480df601/RELEASE-NOTES.md

Apple sources:

- Apple AirPods Pro 2 hearing-health white paper, October 2024: https://www.apple.com/health/pdf/Hearing_Health_Features_on_AirPods_Pro_2_October_2024.pdf
- Apple Hearing Test support page: https://support.apple.com/en-us/120991
- AirPods hearing health features support page: https://support.apple.com/guide/airpods/hearing-health-features-airpods-pro-2-3-devd9aac5b42/web
- Hearing Test Feature Instructions for Use: https://regulatoryinfo.apple.com/cwt/api/ext/file?fileId=hearingTest%2F099-46218-F+HTF+1.X+Instructions+for+Use_us_EN_1757482202568.pdf
- AVAudioSession outputVolume docs: https://developer.apple.com/documentation/avfaudio/avaudiosession/outputvolume
- HealthKit headphoneAudioExposure docs: https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/headphoneaudioexposure
- HealthKit audiogram docs: https://developer.apple.com/documentation/healthkit/hkaudiogramsample
- Apple Hearing Study tinnitus update: https://www.apple.com/newsroom/2024/05/apple-hearing-study-shares-preliminary-insights-on-tinnitus/

Research and clinical context:

- NICE evidence review for tinnitus psychoacoustic measures: https://www.ncbi.nlm.nih.gov/books/NBK557025/
- Hoare et al., Agreement and Reliability of Tinnitus Loudness Matching and Pitch Likeness Rating: https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0114553
- Clinical tinnitus matching procedure description: https://www.audiologyonline.com/articles/clinical-management-of-tinnitus-12558
- Moore overview of pitch/loudness matching issues: https://www.entandaudiologynews.com/features/audiology-features/post/measuring-the-pitch-and-loudness-of-tinnitus
- Smartphone tinnitus apps review: https://pmc.ncbi.nlm.nih.gov/articles/PMC7146490/
- Smartphone-based hearing test calibration paper: https://pmc.ncbi.nlm.nih.gov/articles/PMC8196774/
- Biologically calibrated mobile hearing tests: https://mhealth.jmir.org/2018/1/e10/
- AirPods Pro 2 hearing-test accuracy summary: https://www.vinayamanchaiah.com/pubs/apple-hearing-test-feature-for-airpods-pro-2-accuracy-reliability-and-time-efficiency/

## What ResearchKit provides

### 1. `ORKdBHLToneAudiometryStep`

`ORKdBHLToneAudiometryStep` is an active step for calibrated tone audiometry. Its configurable properties include:

- `toneDuration`
- `maxRandomPreStimulusDelay`
- `postStimulusDelay`
- `maxNumberOfTransitionsPerFrequency`
- `initialdBHLValue`
- `dBHLStepUpSize`
- `dBHLStepDownSize`
- `dBHLMinimumThreshold`
- `headphoneType`
- `earPreference`
- `frequencyList`
- injectable `ORKAudiometryProtocol` engine

The defaults in the source are audiometry-oriented: 1-second tones, 30 dB HL initial level, 5 dB up, 10 dB down, minimum -10 dB HL, and a frequency list of 1000, 2000, 3000, 4000, 8000, 1000, 500, and 250 Hz.

For tinnitus loudness matching, this step is useful mainly as a template. The default adaptive threshold logic is not the target interaction.

### 2. Supported headphone identifiers

ResearchKit defines identifiers for:

- generic AirPods,
- AirPods 1,
- AirPods 2,
- AirPods 3,
- AirPods Pro,
- AirPods Pro 2,
- AirPods Max,
- EarPods,
- unknown.

For your project, the important constant is:

```swift
ORKHeadphoneTypeIdentifierAirPodsProGen2 // "AIRPODSPROV2"
```

The dB HL generator maps this to AirPods Pro 2-specific calibration files:

- `frequency_dBSPL_AIRPODSPROV2.plist`
- `retspl_AIRPODSPROV2.plist`
- `volume_curve_AIRPODSPROV2.plist`
- also present: `retspl_dBFS_AIRPODSPROV2.plist`

The predefined `ORKOrderedTask.dBHLToneAudiometryTask` currently hardcodes `AirPodsGen1` for its right and left ear steps in the source I inspected. Do not rely on the predefined task unchanged for AirPods Pro 2. Set or detect `AIRPODSPROV2` explicitly.

### 3. Calibration tables

For AirPods Pro 2, the bundled ResearchKit tables include:

Frequency sensitivity table, `frequency_dBSPL_AIRPODSPROV2.plist`:

| Hz | dB SPL |
|---:|---:|
| 125 | 84.05 |
| 250 | 83.16 |
| 500 | 84.13 |
| 750 | 83.95 |
| 1000 | 83.67 |
| 1500 | 84.79 |
| 2000 | 86.52 |
| 3000 | 89.24 |
| 4000 | 86.64 |
| 6000 | 86.50 |
| 8000 | 90.11 |

RETSPL table, `retspl_AIRPODSPROV2.plist`:

| Hz | 0 dB HL equivalent, dB SPL |
|---:|---:|
| 125 | 34.04 |
| 250 | 23.52 |
| 500 | 12.99 |
| 750 | 11.13 |
| 1000 | 9.27 |
| 1500 | 11.69 |
| 2000 | 14.11 |
| 3000 | 13.42 |
| 4000 | 12.72 |
| 6000 | 14.62 |
| 8000 | 16.51 |

Volume curve table, `volume_curve_AIRPODSPROV2.plist`:

| iOS volume | SPL offset |
|---:|---:|
| 0.0625 | -65.5 |
| 0.1250 | -58.5 |
| 0.1875 | -52.5 |
| 0.2500 | -47.0 |
| 0.3125 | -42.0 |
| 0.3750 | -37.5 |
| 0.4375 | -33.0 |
| 0.5000 | -29.0 |
| 0.5625 | -25.0 |
| 0.6250 | -21.0 |
| 0.6875 | -17.0 |
| 0.7500 | -13.5 |
| 0.8125 | -10.0 |
| 0.8750 | -6.5 |
| 0.9375 | -3.0 |
| 1.0000 | 0.0 |

This is the core reason ResearchKit is valuable here: it already contains the transducer-specific lookup data needed to estimate output level.

### 4. Audio generation

ResearchKit's dB HL generator:

- builds an Audio Unit graph with `RemoteIO` output and a `SpatialMixer`;
- sets a 44.1 kHz non-interleaved float PCM stream;
- renders a sine wave in a callback;
- writes the tone into the requested output channel set;
- fades in/out over about 0.2 seconds;
- computes a linear amplitude from requested dB HL before playback;
- warns the audiometry engine if the requested level would clip.

The actual render sample is effectively:

```text
sample = sin(theta) * amplitudeGain * fadeEnvelope
```

where `amplitudeGain` is the output of the dB HL calibration conversion.

#### API visibility

`ORKdBHLToneAudiometryAudioGenerator` is not exposed through the public `ResearchKitActiveTask.h` umbrella header. In the inspected Xcode project it is marked as a private header and imported through `ResearchKitActiveTask_Private.h`.

That distinction matters for app architecture:

- The stock `ORKdBHLToneAudiometryStepViewController` can use the generator because it is inside the ResearchKitActiveTask module.
- App code that imports normal `ResearchKitActiveTask` should not treat the generator as a stable public API.
- Depending on the private header is technically possible when building ResearchKit from source, but it couples the app to ResearchKit internals.
- The generator's public-ish Objective-C surface is very small: initialize with a headphone type, play frequency/channel/dB HL, stop, and receive clipping callbacks. It does not expose calibration metadata, target dB SPL, attenuation, table versions, or detailed diagnostics that a tinnitus research app should record.

This makes the generator more useful as a reference implementation than as the direct long-term dependency for a custom loudness-match UI.

### 5. Environment SPL meter

ResearchKit includes `ORKEnvironmentSPLMeterStep`, used by the predefined dB HL task before tone playback. It:

- records from the built-in mic;
- uses `AVAudioSessionModeMeasurement`;
- applies an A-weighting EQ;
- converts RMS to dBA using a device sensitivity offset table;
- requires a configurable number of contiguous samples below the threshold before continuing.

The predefined dB HL task sets:

```text
thresholdValue = 45 dBA
requiredContiguousSamples = 5
```

Apple's own AirPods hearing test similarly requires a quiet room and can pause when the environment is too loud. For your app, environment gating should be mandatory, not optional.

### 6. Speech-in-noise

ResearchKit also has `ORKSpeechInNoiseStep`, which mixes a speech file with a noise file and controls the noise gain. It is probably not central to tinnitus loudness matching, but it may be useful later if the study wants to correlate tinnitus measures with speech-in-noise performance or hearing function.

## The conversion chain: digital signal to estimated ear-level output

The ResearchKit dB HL generator implements this conceptual model:

```text
target_dBSPL = RETSPL(frequency, headphone) + requested_dBHL

estimated_full_scale_dBSPL =
    frequencySensitivity_dBSPL(frequency, headphone)
    + volumeCurveOffset_dB(iOSOutputVolume, headphone)
    + dBFSCalibrationOffset

attenuation_dB = target_dBSPL - estimated_full_scale_dBSPL

linearAmplitude = 10 ^ (attenuation_dB / 20)
```

Then the PCM generator writes:

```text
pcm[n] = sin(2*pi*f*n/sampleRate) * linearAmplitude * envelope[n]
```

The key clinical formula behind this is:

```text
dB HL = dB SPL - RETSPL
dB SPL = dB HL + RETSPL
```

This is standard audiometric calibration logic: dB HL is not an absolute pressure level. It is referenced to frequency- and transducer-specific normal-hearing thresholds. The RETSPL table tells you what dB SPL corresponds to 0 dB HL for that frequency/transducer/coupler arrangement.

Example at 1000 Hz with AirPods Pro 2:

```text
RETSPL(1000) = 9.27 dB SPL
requested level = 30 dB HL
target_dBSPL = 39.27 dB SPL

frequency sensitivity table at 1000 Hz = 83.67 dB SPL
volume offset at iOS volume 1.0 = 0 dB
dBFS calibration offset in ResearchKit code = 30 dB
estimated_full_scale_dBSPL = 113.67 dB SPL

attenuation = 39.27 - 113.67 = -74.40 dB
linear amplitude = 10 ^ (-74.40 / 20) ~= 0.0001905
```

That linear amplitude is the scalar applied to the sine wave.

## What "exact volume in the patient's ear" really means

There are three levels of "knowing volume":

### Level 1: digital level

You know exactly what PCM values your app writes: sample rate, frequency, waveform shape, RMS/peak, fade envelope, and digital gain in dBFS.

This is necessary but not clinically sufficient.

### Level 2: estimated acoustic output for a supported headphone model

Using ResearchKit calibration tables, system volume, and a known route, you can estimate dB SPL and dB HL at the output transducer. This is the practical public-API approach.

This is likely good enough for a research prototype if validated and disclosed as model-calibrated output.

### Level 3: actual in-ear SPL for this patient at this moment

This depends on:

- AirPods unit-to-unit variation,
- AirPods firmware,
- iPhone/iPad model and OS,
- system volume,
- Bluetooth route/profile and codec behavior,
- Headphone Accommodations / Media Assist / Hearing Aid settings,
- volume limits and safety settings,
- ANC/transparency/adaptive features,
- ear-tip seal and insertion depth,
- ear canal acoustics,
- wax/obstruction,
- environmental noise,
- whether the AirPods microphones/speakers are clean and unobstructed.

Apple's own hearing-test feature explicitly uses a quiet-room check, fit check, and technical safeguards while AirPods are in the case. Those are not all public APIs. Without a probe microphone, coupler calibration, or public AirPods calibration API, your app cannot guarantee exact individual in-ear SPL. It can provide an estimated calibrated level under controlled conditions.

## Apple AirPods hearing-test relevance

Apple's AirPods Pro 2 hearing test confirms that accurate enough self-administered pure-tone audiometry is feasible on AirPods Pro 2:

- It plays tones from 250 Hz to 8000 Hz at different dB HL intensities.
- It requires a quiet environment.
- It performs fit/noise checks.
- Apple's white paper reports validation against reference audiometry, including median absolute differences around 1.8 dB HL for 4-frequency PTA and 1.75 dB HL for 8-frequency PTA.
- An independent study summary reported 86.5% of Apple Hearing Test Feature thresholds within 10 dB HL of pure-tone audiometry and test-retest reliability with 96.6% within 10 dB HL.

But Apple does not appear to expose its hearing-test engine or a public API like "play 4 kHz at 42 dB HL through AirPods Pro 2." The public path remains normal audio playback plus your own calibration model.

## High-level app architecture

### Pre-test checks

Before loudness matching:

1. Confirm supported route:
   - require AirPods Pro 2;
   - reject speaker, generic Bluetooth, wired headphones, unknown model;
   - observe route changes and abort/redo if the route changes.

2. Confirm clean audio state:
   - set a measurement/playback audio session;
   - prevent mixing where possible;
   - avoid speech/voice-processing modes;
   - use a known sample rate;
   - disable app-level EQ, spatialization, loudness normalization, compressors, limiters.

3. Ask the user to disable or neutralize system features that may change output:
   - Headphone Accommodations,
   - Media Assist,
   - Hearing Aid mode,
   - Personalized Volume,
   - Sound Check / EQ in any source path,
   - Reduce Loud Audio if it affects generated tones.

4. Set and verify volume protocol:
   - easiest: require the user to set iOS volume to maximum, because the volume offset is 0 dB and the calculation is most direct;
   - record `AVAudioSession.outputVolume`;
   - observe changes during the test;
   - abort or recalculate if volume changes.

5. Run environment SPL gate:
   - use ResearchKit's `ORKEnvironmentSPLMeterStep` or an equivalent;
   - require several consecutive below-threshold samples;
   - store the samples with the result.

6. Fit/seal check:
   - Apple has a native Ear Tip Fit Test, but public access is limited;
   - at minimum, instruct the user to run Apple's fit test before the study session and confirm pass/fail;
   - ideally, develop a study-specific fit/leak check and validate it.

7. Safety:
   - impose maximum output limits;
   - provide stop/panic control;
   - use gradual ramping;
   - define exclusion and clinical escalation criteria with an audiologist/IRB.

### Measurement flow

A tinnitus loudness match should probably not report only dB SPL. Report at least:

- matched pitch/frequency,
- matched ear/channel,
- matched estimated dB SPL,
- matched dB HL,
- matched dB SL,
- patient's threshold at that frequency,
- route/headphone type,
- system volume,
- calibration table version,
- environment SPL samples,
- repeat/trial metadata.

Recommended flow:

1. Collect laterality:
   - left, right, bilateral, central/unclear.

2. Pitch match:
   - allow pure tone and narrowband noise options;
   - use a bracketing or two-alternative forced choice method;
   - include high frequencies because Apple Hearing Study data suggests most pure-tone tinnitus reports cluster at 4 kHz or higher.

3. Threshold at matched pitch:
   - use a threshold procedure at the matched frequency for the same ear/channel.
   - This can use ResearchKit's dB HL audiometry engine or a custom simpler threshold staircase.

4. Loudness match:
   - start at or just above threshold;
   - increase in small steps, often 1 dB clinically;
   - allow up/down adjustment until "same loudness as tinnitus";
   - repeat several times and use median or a robust summary.

5. Report dB SL:
   - `dB SL = matched_level_dBHL - threshold_dBHL_at_same_frequency`.
   - Clinically, loudness matches are often described relative to threshold because the same SPL can be perceived very differently by people with different hearing thresholds.

6. Store both raw and derived data:
   - all presented levels,
   - all user responses,
   - timestamps,
   - aborts/route changes/volume changes,
   - chosen stimulus type,
   - calibration asset identifiers.

## Proposed study protocol and UI plan

The app should implement one reusable loudness-matching engine that can be used for different study configurations.

1. Fixed-frequency loudness matching at 1000 Hz.
2. Pitch matching followed by loudness matching at the matched pitch.

Both studies should share the same preflight checks, calibrated playback service, loudness-match UI, event logging, and result schema. The difference is whether the test frequency is fixed in advance or estimated through a pitch-matching phase.

### Shared preflight protocol

Before either study starts:

1. Confirm AirPods Pro 2 route.
2. Confirm stable system volume, preferably maximum volume.
3. Run or request a fit/seal confirmation.
4. Run environment SPL gating.
5. Ask tinnitus laterality: left, right, both, central, or unclear.
6. Display safety stop affordance before any stimulus is played.

### Study No. 1: fixed 1000 Hz loudness matching

This study intentionally removes pitch matching to produce a simpler, standardized measure. The stimulus is always a 1000 Hz pure tone.

Recommended flow:

1. Run preflight checks.
2. Measure hearing threshold at 1000 Hz in the test ear.
3. Start loudness matching slightly above threshold, for example threshold + 5 dB SL.
4. Let the participant adjust the 1000 Hz tone until it is the same loudness as their tinnitus.
5. Repeat the loudness match three times.
6. Report the median matched level and within-session variability.

Also store estimated dB SPL and dB HL, but dB SL is the most interpretable value because it accounts for that participant's threshold at the tested frequency.

### Study No. 2: pitch matching plus loudness matching

This study estimates tinnitus pitch first, then runs the same loudness-matching flow at that pitch.

Recommended flow:

1. Run preflight checks.
2. Ask the participant whether the tinnitus is more tone-like, hiss/noise-like, buzzing, or unclear.
3. Run pitch matching.
4. Confirm matched pitch with one or more replay checks.
5. Measure hearing threshold at the matched pitch.
6. Run the same loudness-match UI used in Study No. 1.
7. Repeat loudness matching three times.
8. Report median matched dB SL, estimated dB SPL, dB HL, pitch, and confidence.

### Pitch-matching UI options

There are three reasonable pitch-matching approaches:

1. **Two-choice bracketing**
   Present Tone A and Tone B, then ask which is closer to the tinnitus pitch. This is controlled and analyzable, but slower.

2. **Frequency slider**
   Let the participant scrub frequency until it sounds closest. This is fast, but noisier and more prone to anchoring or accidental overshoot.

3. **Hybrid**
   Start with coarse two-choice bracketing, then allow fine adjustment with constrained buttons or a narrow slider. This is the best balance for Study No. 2.

Recommended Study No. 2 pitch UI:

```text
Which tone is closer to your tinnitus?

[ Play A ]    [ Play B ]

[ A is closer ]    [ B is closer ]    [ About the same ]
```

After the coarse pitch is found, use a fine adjustment screen:

```text
[ Play Tone ]

Much Lower    Lower    Matches Pitch    Higher    Much Higher
```

Use octave checks because tinnitus pitch matching can be vulnerable to octave confusion. For example, after a candidate pitch is selected, compare it with half and double the frequency when those values are within the calibrated or validated range.

### Loudness-matching UI pattern

Use the same loudness UI in both studies. The recommended first implementation is a button-based method of adjustment:

```text
[ Play Tone ]

Much Softer    Softer    Same Loudness    Louder    Much Louder

[ Stop ]
```

Design details:

- Keep the numeric dB level hidden from the participant to reduce anchoring.
- Use ramp-in and ramp-out to avoid clicks.
- Make `Stop` always visible and immediate.
- Log every button press, level change, playback event, route change, and volume change.
- Use larger steps early and smaller steps near the match.

Suggested step sizes:

```text
Much Softer / Much Louder = 5 dB
Softer / Louder = 1 or 2 dB
Same Loudness = accept current candidate
```

A practical trial sequence:

1. Start at threshold + 5 dB SL, or a randomized value around threshold + 5 to +15 dB SL.
2. Let the participant move up/down with the buttons.
3. When they choose `Same Loudness`, run a refinement pass using 1 dB steps.
4. Save the accepted level.
5. Repeat for three trials, with randomized starting levels.
6. Use the median accepted level as the study result and store the spread as a reliability metric.


### Confidence and quality checks

After each match, ask for a confidence rating:

```text
How confident are you in this match?

Low    Medium    High
```

Also flag sessions where:

- the three repeated matches differ by more than a predefined threshold;
- the participant reports low confidence;
- route or volume changed;
- environment SPL gate failed or was marginal;
- the requested level approached the clipping/safety limit;
- the matched pitch was outside the validated calibration range.

## High-level Swift shape

This is intentionally pseudocode, not implementation:

```swift
struct CalibrationContext {
    let headphoneType: ORKHeadphoneTypeIdentifier // must be AIRPODSPROV2
    let outputVolume: Float
    let frequencySensitivityDBSPL: [Double: Double]
    let retspl: [Double: Double]
    let volumeCurve: [Float: Double]
    let calibrationVersion: String
}

struct StimulusRequest {
    let frequencyHz: Double
    let ear: ORKAudioChannel
    let levelDBHL: Double
    let duration: TimeInterval
}

struct CalibratedStimulus {
    let request: StimulusRequest
    let targetDBSPL: Double
    let attenuationDB: Double
    let linearAmplitude: Double
}
```

The conversion service:

```swift
protocol CalibratedToneCalibrator {
    func makeStimulus(_ request: StimulusRequest,
                      context: CalibrationContext) throws -> CalibratedStimulus
}
```

Conceptually:

```swift
let targetDBSPL = retspl[frequency] + request.levelDBHL
let outputReferenceDBSPL =
    frequencySensitivityDBSPL[frequency]
    + volumeCurve[volumeBucket]
    + dBFSCalibrationOffset

let attenuationDB = targetDBSPL - outputReferenceDBSPL
let linearAmplitude = pow(10.0, attenuationDB / 20.0)
```

Tone playback:

```swift
protocol TonePlayer {
    func prepare(audioSession: AVAudioSession, route: VerifiedRoute) throws
    func play(_ stimulus: CalibratedStimulus) throws
    func stop()
}
```

Loudness match coordinator:

```swift
final class TinnitusLoudnessMatchController {
    func runSession() async throws -> TinnitusLoudnessMatchResult {
        let route = try await routeVerifier.requireAirPodsPro2()
        let volume = try await volumeVerifier.requireStableVolume()
        let environment = try await environmentGate.requireQuietRoom()
        let pitch = try await pitchMatcher.matchPitch(route: route)
        let threshold = try await thresholdEstimator.threshold(at: pitch)
        let matches = try await loudnessMatcher.matchLoudness(
            frequency: pitch.frequencyHz,
            thresholdDBHL: threshold.levelDBHL
        )
        return resultBuilder.makeResult(route, volume, environment, pitch, threshold, matches)
    }
}
```

The key implementation decision is whether to wrap ResearchKit's existing Objective-C generator or port the calibration logic into a modern Swift `AVAudioEngine`/`AVAudioSourceNode` implementation. I would start by wrapping/replicating the calibration logic in Swift while keeping the calibration tables intact and versioned. The playback engine can be Swift-native as long as it is validated against the same output-level math.

## Important ResearchKit source caveats

### 1. The predefined dB HL task defaults to older AirPods

The predefined dB HL task source sets `headphoneType = ORKHeadphoneTypeIdentifierAirPodsGen1` for the right and left ear steps. For AirPods Pro 2, do not use the predefined task unchanged.

### 2. The dB HL generator has a suspicious output-volume bucketing expression

The inspected generator contains this expression:

```objc
currentVolume = ((int)(currentVolume / 0.0625) * 0.0625) >= DeviceVolumeMinimumValue ?: DeviceVolumeMinimumValue;
```

This appears likely to evaluate the boolean comparison and then use the Objective-C/GNU elvis operator. If so, most nonzero volumes become `1.0` rather than the intended 0.0625-step bucket. That would effectively ignore the volume curve except at very low volume.

Before relying on ResearchKit's generator, verify this behavior in a unit test and inspect whether there is an upstream issue or newer branch fix. The likely intended logic is something like:

```text
bucketedVolume = floor(outputVolume / 0.0625) * 0.0625
currentVolume = max(bucketedVolume, 0.0625)
```

For a clinical/research app, I would not ship without explicitly testing this conversion at all 16 volume steps.

### 3. Some AirPods Pro 2 calibration data is unused

`retspl_dBFS_AIRPODSPROV2.plist` is present, but the generator uses a hardcoded 30 dB calibration offset in the inspected source. Investigate the intended role of this plist before deciding whether to use the generator unchanged. It may represent a newer or alternate calibration model that has not been wired into the code.

### 4. Frequencies are table-driven

The main frequency and RETSPL tables are defined at discrete frequencies. If you allow arbitrary pitch matching, you need a policy:

- restrict matching to calibrated frequencies;
- interpolate calibration tables between calibrated frequencies;
- or add/measure your own calibration table for finer frequencies.

For tinnitus, arbitrary pitch matching may be tempting, but calibrated measurement is stronger if the final loudness match is done at supported/calibrated frequencies or at well-validated interpolated frequencies.

## Custom UI integration options

Because the app needs a tinnitus-specific loudness-match UI rather than the stock threshold UI, there must be an alternative approach.

### Option: Hybrid ResearchKit + custom audio. Port the calibration and playback into an app-owned Swift module

Use ResearchKit for consent, instructions, surveys, environment SPL gating, and result collection, but run the tinnitus loudness-match screen with your app-owned calibrated tone service.

This keeps the useful research workflow scaffolding while avoiding the stock dB HL threshold UI.

This is the most pragmatic app architecture. Treat ResearchKit's generator and plists as a reference, preserve the relevant licenses and source attribution, and build an app-owned calibrated tone service using `AVAudioEngine` or `AVAudioSourceNode`.

Advantages:

- fully custom SwiftUI/UIKit tinnitus workflow;
- no dependency on private ResearchKit headers;
- calibration math can be unit-tested directly;
- easier to log target dB SPL, dB HL, dB SL, attenuation, clipping margins, output volume, route, and table versions;
- easier to fix or validate the volume-bucketing behavior;
- easier to support repeated matches and study-specific result models.



## Recommended implementation strategy

### Phase 1: Build a calibration abstraction

Create a pure conversion module that:

- loads calibration assets for AirPods Pro 2;
- exposes `dBHL -> dBSPL -> dBFS amplitude`;
- exposes inverse conversions where useful;
- records table versions and commit/source;
- has unit tests for known examples.

This module should be independent of UI and playback.

### Phase 2: Build route and volume guardrails

Implement:

- `AVAudioSession.currentRoute` verification;
- route-change observer;
- volume observer for `AVAudioSession.outputVolume`;
- known volume policy, preferably maximum volume;
- abort/restart rules.

Do not let a session silently continue if the route or volume changes.

### Phase 3: Build calibrated tone playback

Use an app-owned `AVAudioEngine`/`AVAudioSourceNode` player, or expose a deliberate public player from a ResearchKit fork. Avoid depending on `ORKdBHLToneAudiometryAudioGenerator` as a private runtime API except for prototyping. Requirements:

- fixed sample rate or explicitly captured hardware sample rate;
- sine generation with stable phase;
- channel-specific output;
- no unintended mixer gain;
- ramp in/out to avoid clicks;
- clipping detection;
- logging of exact amplitude and duration;
- offline tests proving sample RMS/peak are correct.

### Phase 4: Build the tinnitus protocol

Separate the clinical protocol from the audio engine:

- pitch match;
- threshold at pitch;
- loudness match in 1 dB or study-defined steps;
- repeat trials;
- compute median and variability;
- store all raw events.

### Phase 5: Validate acoustically

Before using in a study:

- measure AirPods Pro 2 output in a standardized coupler or ear simulator if available;
- verify levels at 250, 500, 1000, 2000, 3000, 4000, 6000, 8000 Hz;
- test across volume steps if you do not force max volume;
- test across OS and firmware versions used in the study;
- test left/right channel separation;
- test with ANC/transparency/off and decide what mode is allowed;
- compare against a clinical audiometer for a pilot sample.

### Phase 6: Data model

For each match, store:

```text
participantId/studySessionId
timestamp
iPhone/iPad model
iOS version
AirPods model identifier if available 
AirPods firmware if available
ResearchKit commit/calibration asset version
audio route port type/name/UID
AVAudioSession category/mode/options
sample rate, buffer size
system outputVolume
environment SPL samples and threshold
ear/channel
stimulus type: pure tone or narrowband noise
frequency Hz
threshold dB HL at matched frequency
matched dB HL
matched estimated dB SPL
matched dB SL
step size and staircase/adjustment method
all presented levels and responses
route/volume interruptions
patient confirmation and confidence rating
```

## Safety and regulatory considerations

ResearchKit's README warns that active tasks are not diagnostic tools or medical devices, and developers/researchers are responsible for applicable laws and regulations. A tinnitus measurement app intended for medical research may still need IRB review, consent language, adverse-event handling, and possibly medical device/regulatory analysis depending on claims and use.

From an audio-safety standpoint:

- cap maximum SPL/dB HL;
- avoid sudden high-level presentations;
- use ramping;
- warn users with hyperacusis/sound sensitivity;
- allow immediate stop;
- do not run if recent loud-noise exposure, ear infection, congestion, or other exclusion criteria apply unless approved by the clinical protocol;
- consider that tinnitus-focused matching can increase distress for some users.

NICE notes that tinnitus psychoacoustic measures are historically used as part of assessment/research, but reliability/usefulness in routine clinical management is questionable and protocols are not standardized. This does not mean "do not measure" for research; it means the app should be careful about claims and should quantify repeatability.

## Bottom line

The technically sound approach is:

1. Use ResearchKit's AirPods Pro 2 calibration tables and dB HL conversion model as the starting point.
2. Do not use the predefined dB HL audiometry task unchanged; build a tinnitus-specific protocol.
3. Force a tightly controlled playback environment: AirPods Pro 2 only, stable volume, quiet room, stable route, known audio settings.
4. Report loudness both acoustically and clinically: estimated dB SPL, dB HL, and dB SL relative to the patient's threshold at the matched pitch.
5. Treat "exact volume in the ear" as an estimate unless validated with external acoustic measurements or a public/private AirPods calibration API.
6. Validate the entire pipeline before collecting study data.
