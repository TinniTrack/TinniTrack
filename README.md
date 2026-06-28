# TinniTrack

TinniTrack is an iOS research app for tinnitus study workflows. The current app supports participant authentication, profile onboarding, study enrollment, HealthKit audiogram import, Study No. 1 task scheduling, AirPods Pro 2 route and volume guardrails, quiet-room screening, and a fixed 1 kHz tinnitus loudness-match task.

The goal is to make repeated tinnitus measurements more structured and interpretable than informal self-report. The app is not a diagnostic device. Current loudness-match results are model-calibrated estimates derived from public iOS audio route data, ResearchKit AirPods Pro 2 calibration reference tables, system output volume, and app-owned playback logic. They are not exact patient-specific in-ear SPL values.

## Current State

This project is a SwiftUI iOS research app targeting iOS 18.1+. It uses:

- SwiftUI for the product UI and task flows.
- HealthKit for importing participant audiograms from Apple Hearing Test or other HealthKit audiogram sources.
- AVFoundation for audio route inspection, output volume, calibrated tone playback, and ambient microphone sampling.
- ResearchKit as a vendored framework, reference implementation, and future presentation boundary.
- Supabase Auth, Postgres, Row Level Security, RPCs, and Edge Functions for account state, study state, schedules, and submissions.

The currently implemented participant path is:

1. Sign up or sign in through Supabase Auth.
2. Complete profile onboarding with first name, last name, and date of birth.
3. View recruiting studies from Supabase.
4. Enroll in Study No. 1.
5. Complete Study No. 1 orientation:
   - review the Study No. 1 welcome page,
   - take an Apple Hearing Test if needed,
   - grant HealthKit audiogram read permission,
   - import at least one audiogram,
   - pass the same modal preflight used by Study No. 1 tasks,
   - complete and submit the one-time ResearchKit 1 kHz orientation threshold validation,
   - finish orientation, which generates the ongoing scheduled tasks through a Supabase RPC.
6. Start an available Study No. 1 scheduled loudness-match task during its active window.
7. Pass the modal preflight:
   - AirPods Pro 2 route heuristic,
   - quiet-room gate,
   - fit confirmation,
   - maximum system volume guardrail,
   - visible stop/safety acknowledgement.
8. Complete the active tinnitus task:
   - select tinnitus laterality,
   - resolve the selected-ear 1 kHz threshold from the imported HealthKit audiogram,
   - complete three loudness-match trials,
   - record confidence for each accepted match.
9. Submit a structured payload to Supabase.

The current implementation stores estimated dB HL, estimated dB SPL, dB SL, route metadata, AirPods heuristic evidence, quiet-room samples, guardrail metadata, playback metadata, protocol events, quality flags, and explicit measurement limitations.

## App Limitations

TinniTrack is unable to measure exact in-ear loudness. Public iOS APIs do not expose enough information to prove the exact acoustic output at the eardrum. We are, however, able to make informed estimates. 

Current limitations are intentional and are represented in code and payloads:

- Public APIs cannot prove exact AirPods Pro 2 generation, model number, firmware, serial number, ear-tip seal, in-ear state, or actual in-ear SPL.
- AVAudioSession exposes route category data, route names, route UIDs, channels, and `outputVolume`, but not a verified acoustic device identity.
- HealthKit audiograms provide participant hearing thresholds, but they do not make this app's own tone playback clinically validated.
- Ambient noise sampling is app-owned and currently simpler than ResearchKit's A-weighted SPL meter implementation.

The code and payload wording use "estimated model-calibrated output" rather than "exact SPL."

## Source Layout

The project uses a feature-first iOS structure:

- `TinniTrack/Features/`
  - Product flows, SwiftUI screens, and flow view models.
  - Feature code should remain mostly free of direct ResearchKit imports.
- `TinniTrack/Domain/`
  - Pure domain logic, calibration math, protocol engines, task models, and payload builders.
  - Domain code should be testable without iOS UI.
- `TinniTrack/Services/`
  - External-system boundaries and protocol implementations.
  - Examples: Supabase, HealthKit, AVFoundation audio, ResearchKit adapter.
- `TinniTrack/Shared/`
  - Cross-feature app infrastructure such as session state and shared app wiring.
- `TinniTrackTests/`
  - Unit tests for calibration, guardrails, protocol state machines, payload builders, HealthKit import coordination, dashboard state, session state, and configuration.
- `supabase/migrations/`
  - Append-only SQL migrations. Do not rewrite migrations that may already have been applied remotely.

## Code Map

Important current implementation areas:

- `TinniTrack/Shared/App/SessionStore.swift`
  - Authentication route, onboarding route, profile refresh, email verification, password reset, account updates, and delete-account flow orchestration.
- `TinniTrack/Services/Auth/SupabaseAuthService.swift`
  - Supabase Auth wrapper, sign-up metadata, auth callbacks, email verification, password recovery, email update, and delete-account Edge Function call.
- `TinniTrack/Services/Supabase/Supabase.swift`
  - Supabase URL/key resolution from environment or bundle configuration, environment badge naming, and shared client creation.
- `TinniTrack/Features/Dashboard/`
  - Study list, enrollment state, Study No. 1 orientation flow, task dashboard, scheduled task lists, and task entrypoints.
- `TinniTrack/Services/Studies/SupabaseStudyService.swift`
  - Study/enrollment/task fetches, orientation threshold RPCs, orientation completion RPC, and loudness-match submission RPC.
- `TinniTrack/Services/HealthKit/HealthKitManager.swift`
  - HealthKit audiogram authorization and sample parsing.
- `TinniTrack/Services/Audiograms/`
  - HealthKit import coordination and Supabase audiogram persistence.
- `TinniTrack/Features/LoudnessMatch/`
  - Study No. 1 modal flow, preflight screens, active task UI, and flow view model.
- `TinniTrack/Domain/TinnitusProtocol/`
  - Laterality, threshold, trial, confidence, event, summary, and quality-flag logic.
- `TinniTrack/Domain/Calibration/`
  - AirPods Pro 2 calibration tables, dB HL/dB SPL/amplitude conversion, guardrails, playback planning, and tone rendering.
- `TinniTrack/Services/Audio/`
  - AVAudioSession route/volume providers, AirPods route heuristic resolver, quiet-room SPL meter, guardrail monitor, and AVAudioEngine playback service.
- `TinniTrack/Domain/TinnitusProtocol/StudyNo1LoudnessMatchPayload.swift`
  - Current loudness-match payload builder and validation rules.
- `TinniTrack/Services/ResearchKit/ResearchKitStudyTaskAdapter.swift`
  - The boundary for presenting ResearchKit tasks when needed.

## ResearchKit Decision Record

ResearchKit is included because it has highly relevant audiometry and active-task components, but the current Study No. 1 loudness-match flow is not implemented as a stock ResearchKit task.

The decision is:

- Keep ResearchKit in the project as a dependency, reference, and future task-presentation layer.
- Keep SwiftUI feature code from importing ResearchKit directly by default.
- Use `ResearchKitStudyTaskAdapter` as the explicit boundary for ResearchKit presentation and result handling.
- Own the calibrated tinnitus playback API in this codebase because tinnitus loudness matching has different requirements from ResearchKit's built-in hearing-threshold tasks.

### What ResearchKit Provides

ResearchKit has several relevant modules:

- `ORKInstructionStep`
- form steps and surveys
- tone audiometry
- dB HL tone audiometry
- environment SPL meter
- speech-in-noise tasks

`ResearchKitStudyTaskAdapter` currently exposes request cases for:

- `.instruction`
- `.toneAudiometry`
- `.dBHLToneAudiometry`
- `.studyNo1OrientationThreshold`
- `.environmentSPLMeter`
- `.speechInNoise`

The adapter creates an `ORKOrderedTask`, wraps it in `ORKTaskViewController`, maps `ORKTaskFinishReason` into the app's `ResearchTaskFinishState`, and returns a compact result summary. The Study No. 1 orientation request presents only the threshold task; the app-owned preflight and quiet-room gate run before ResearchKit is launched. This keeps ResearchKit UI and delegates inside `TinniTrack/Services/ResearchKit/`.

### Why Stock dB HL Audiometry Is Not The Main Loudness Task

ResearchKit's `ORKdBHLToneAudiometryStep` is designed for dB HL hearing-threshold measurement. Its predefined task follows a threshold-finding workflow, not a tinnitus loudness-match workflow.

ResearchKit's dB HL audiometry behavior is still important because it documents a practical architecture:

- It uses calibrated headphone profiles.
- It gates on ambient sound before tones.
- It plays pure tones in dB HL, not arbitrary normalized volume.
- It tracks headphone route, environment, and task results.
- It separates task presentation from audio generation and result packaging.

But the Study No. 1 app flow needs behavior ResearchKit does not provide as a stock task:

- Tinnitus laterality selection.
- A fixed Study No. 1 1 kHz protocol.
- A HealthKit audiogram threshold at the same frequency and ear used for dB SL in recurring tasks.
- A one-time orientation threshold validation record against that imported audiogram.
- Repeated loudness-match trials.
- Participant confidence per accepted match.
- Study-specific quality flags.
- Payloads shaped for Supabase RPC submission.
- App-specific AirPods Pro 2 route heuristics and restart rules.

### Why The Audio Engine Was Rewritten Into The App

The inspected ResearchKit audio generator is not a stable public API for this app to call directly. The relevant ResearchKit implementation lives in ResearchKitActiveTask internals and is more appropriate as a reference than as an application API.

The app therefore owns:

- calibration data structures,
- dB HL to dB SPL conversion,
- output-volume bucketing,
- safe amplitude validation,
- playback planning,
- sine rendering,
- AVAudioEngine playback,
- Study No. 1 protocol logic,
- payload construction and validation.

This avoids tying feature behavior to private ResearchKit headers and lets the app record exactly which calibration profile, route, volume, and conversion rules were used for each trial.

### ResearchKit dB HL Defaults That Informed The Design

The ResearchKit dB HL audiometry task uses defaults that are useful reference points:

- 1 second tones.
- Maximum random pre-stimulus delay of 2 seconds.
- 1 second post-stimulus interval.
- Initial level of 30 dB HL.
- 5 dB up step.
- 10 dB down step.
- Minimum level of -10 dB HL.
- Default frequency list: 1000, 2000, 3000, 4000, 8000, 1000, 500, 250 Hz.

Study No. 1 does not copy the whole task, but it intentionally uses several compatible choices:

- 1 second pure tone playback.
- 0.2 second ramping.
- 30 dB HL threshold start.
- 10-down/5-up staircase behavior.
- -10 to 100 dB HL level clamp.
- 45 dB quiet-room threshold with 5 contiguous passing samples.

### ResearchKit Environment SPL Meter Lessons

ResearchKit's environment SPL step is more sophisticated than the app's current microphone implementation. It:

- saves and restores audio session state,
- requests microphone permission,
- uses a measurement audio session,
- targets built-in microphone input,
- applies A-weighting,
- converts RMS to dBA using device sensitivity information,
- counts contiguous below-threshold samples,
- resets the pass counter when sound becomes too loud,
- enables continuation only after the pass criterion is met,
- stops the engine and restores session state after completion.

The app's current `AVAudioEnvironmentSPLMeter` follows the same broad UX pattern, but it is not full ResearchKit parity yet. It records temporary audio, converts average power with a default sensitivity offset, and feeds the app's quiet-room gate evaluator. A-weighting, device-specific sensitivity tables, and stronger microphone-route controls remain future validation work.

## Study No. 1

Study No. 1 is the currently implemented study workflow. The task key generated by the backend is `lm_1khz_v1`.

The current study is centered on a fixed 1 kHz pure tone loudness match. Pitch matching is intentionally not part of the implemented Study No. 1 protocol. The future pitch-match work is described under future plans.

### Orientation

Study No. 1 requires an audiogram and one completed orientation threshold validation before ongoing task scheduling. The orientation is a full-screen modal flow that uses the same visual structure, controls, cleanup behavior, and preflight components as the scheduled Study No. 1 modal task flow.

The onboarding step order is:

1. Welcome
   - The participant sees a Study No. 1 welcome page before prerequisites.
2. Take an Apple Hearing Test
   - The participant is instructed to take an Apple Hearing Test with AirPods Pro 2 if no suitable audiogram is already available.
   - The UI links to Apple's support page for taking a hearing test.
   - The app requests HealthKit audiogram read permission.
   - If permission is granted, it imports HealthKit audiogram samples into Supabase.
   - If no audiogram is found, the participant is asked to complete the Apple Hearing Test and check again.
3. Modal orientation threshold flow
   - The participant continues through the same preflight step order used by the scheduled task flow: intro, correct ear / AirPods route check, quiet room, fit confirmation, and max volume.
   - The quiet-room gate is app-owned and uses the shared animated gate visualization before ResearchKit starts.
   - Before the ResearchKit threshold task starts, the app calls `begin_study_no_1_orientation_threshold_task` to create or reuse a special onboarding scheduled task.
   - ResearchKit presents only the 1 kHz threshold task and returns threshold result traces through `ResearchKitStudyTaskAdapter`.
   - The orientation threshold validation submits through `submit_study_no_1_orientation_threshold`.
4. Finish orientation
   - After the orientation threshold validation is submitted, the app calls `complete_study_no_1_onboarding`.
   - The backend marks the enrollment orientation complete and generates ongoing scheduled loudness-match tasks.

The dashboard stays blocked until the audiogram prerequisite is met, the orientation threshold validation task is submitted, and Study No. 1 onboarding completion succeeds. Once tasks have been unlocked, later HealthKit sync failures are shown as warnings instead of re-locking previously available tasks.

### Schedule Generation

The one-time orientation threshold validation is prepared by the Supabase RPC `begin_study_no_1_orientation_threshold_task(p_enrollment_id)`. It creates or returns a special `lm_1khz_v1` scheduled task with `day_index = -1` and `slot_index = 0`, a current active window, and the normal scheduled-task ownership requirements.

The ongoing 7-day schedule is generated by the Supabase RPC `complete_study_no_1_onboarding(p_enrollment_id, p_timezone)`.

Current scheduling behavior:

- Only enrolled users in Study No. 1 can complete onboarding for their own enrollment.
- Onboarding completion requires a completed `task_runs` row for the special orientation threshold task.
- The function validates the timezone and falls back to UTC if invalid.
- If local time is after 9:00 AM, scheduling starts the next local date; otherwise it starts the current local date.
- It creates 7 days of tasks.
- Each day has 4 slots: 9:00, 13:00, 17:00, and 21:00 local time.
- Each slot has a 60 minute active window.
- Duplicate day/slot inserts are ignored through `ON CONFLICT`.

After onboarding is complete, the dashboard fetches scheduled tasks for the enrollment, separates future scheduled tasks from completed tasks, and only allows task start when `ScheduledTask.isStartable(at:)` returns true.

### Modal Task Flow

The dashboard currently launches scheduled loudness-match tasks through:

- `.fullScreenCover(item: $activeLoudnessTask)`
- `LoudnessMatchTaskModalFlowView`
- `LoudnessMatchTaskFlowViewModel`

Study No. 1 onboarding uses `StudyTaskOrientationSheet` as a full-screen modal and shares `LoudnessMatchTaskFlowViewModel`, `LoudnessMatchPreparationStepView`, and `LoudnessMatchActiveTestView` for the preflight and active test portions.

The modal step order in code is:

1. Intro
2. Correct ear / AirPods route check
3. Quiet room
4. Fit confirmation
5. Max volume
6. Active test

The full-screen modal owns its local step state and performs cleanup when dismissed. If a scheduled task or orientation threshold task has started, closing the modal requires confirmation. Cleanup stops active tone playback, route monitoring, continuity monitoring, quiet-room monitoring, volume monitoring, and aborts active protocol state if needed.

### Preflight Gates

The current preflight readiness check requires:

- calibrated playback enabled,
- guardrails passed,
- AirPods Pro 2 route heuristic passed,
- no active AirPods route interruption,
- quiet-room gate passed,
- fit seal confirmed,
- safety acknowledged.

The app continues monitoring route, volume, and ambient noise after initial gates. If AirPods route continuity is lost after the route step, the task shows an interruption popup and blocks progress until restarted. If quietness was already passed and later continuous monitoring reports the room is no longer quiet, the app clears the pass result and stops tone playback.

### Active Test

The active Study No. 1 protocol has these states:

- collecting laterality,
- awaiting threshold,
- ready for trial,
- awaiting confidence,
- completed,
- aborted,
- restart required.

Scheduled tasks move from laterality selection directly into loudness-match trials after resolving the selected-ear 1 kHz threshold from the latest imported HealthKit audiogram. They do not launch ResearchKit threshold steps and do not ask the participant to complete threshold testing. The current UI shows the participant numerical dB HL readouts during active testing. Earlier planning suggested hiding numeric dB values to reduce anchoring; that is not the current implemented behavior. If blinding or anchoring reduction becomes important, that should be treated as a future UI change and tested against the active view.

## Tinnitus Protocol Domain Logic

The protocol state machine lives in `TinnitusProtocolEngine`. It is intentionally independent from SwiftUI.

### Study No. 1 Configuration

The current configuration is `TinnitusProtocolConfiguration.studyNo1FixedOneKilohertz`:

- protocol kind: `studyNo1FixedOneKilohertz`
- stimulus: pure tone
- frequency: 1000 Hz
- trial count: 3
- tone duration: 1.0 second
- ramp duration: 0.2 seconds
- threshold start offset for trials: +5 dB SL
- conservative fallback start: 10 dB HL
- minimum level: -10 dB HL
- maximum level: 100 dB HL
- high spread threshold: 10 dB
- supported pitch frequencies: inherited from the AirPods Pro 2 calibration profile

Although the configuration type includes `studyNo2TablePitchMatched`, Study No. 2 pitch matching is not implemented in the product flow today.

### Laterality

Participants report tinnitus laterality as:

- left,
- right,
- bilateral,
- central,
- unclear.

The current channel rule is:

- left tinnitus uses left channel,
- right tinnitus uses right channel,
- bilateral, central, or unclear tinnitus uses left channel and records `ambiguousLaterality`.

The engine records this rule in the event response as `study_no_1_rule_unilateral_affected_else_left_first`.

### Threshold Source

Study No. 1 uses the imported HealthKit audiogram threshold at 1000 Hz for the selected playback ear before loudness matching. The threshold is needed for dB SL:

```text
dB SL = matched dB HL - threshold dB HL
```

The in-app threshold staircase still lives in `TinnitusThresholdStaircase` as pure domain logic and for test coverage, but it is not part of scheduled Study No. 1 tasks. The one-time ResearchKit orientation threshold task is used only during onboarding as a validation record against the imported audiogram.

- start: 30 dB HL
- minimum: -10 dB HL
- maximum: 100 dB HL
- step down after heard response: 10 dB
- step up after not-heard response: 5 dB
- completion criterion: two ascending hits at the same level after a miss below that candidate level

The engine can represent an unavailable threshold, but the current Study No. 1 loudness-match payload builder rejects submissions without a measured threshold. In practice, current recurring Study No. 1 submissions require a 1000 Hz HealthKit audiogram threshold.

### Loudness Matching

After threshold resolution, each trial starts at threshold + 5 dB SL. Participants adjust the candidate tone level using four adjustments:

- much softer: -5 dB
- softer: -1 dB
- louder: +1 dB
- much louder: +5 dB

The adjusted level is clamped to -10...100 dB HL. When the participant accepts a level, the engine records:

- trial index,
- accepted dB HL,
- estimated dB SPL if conversion succeeded,
- dB SL if threshold was measured,
- confidence rating,
- acceptance timestamp.

Confidence values are:

- low,
- medium,
- high.

Low confidence adds the `lowConfidence` quality flag.

### Summary And Quality Flags

After three trials, the engine computes:

- median matched dB HL,
- median estimated dB SPL,
- median dB SL,
- within-session spread,
- quality flags,
- completion timestamp.

If the spread between accepted trial levels exceeds 10 dB, the summary records `highWithinSessionSpread`.

Current quality flags include:

- `ambiguousLaterality`
- `thresholdUnavailable`
- `dbSLInvalid`
- `highWithinSessionSpread`
- `lowConfidence`
- `guardrailNotEvaluated`
- `guardrailFailed`
- `restartRequired`
- `playbackRefused`
- `safetyLimitRefused`
- `unsupportedFrequency`

The engine records events throughout the session: session start, laterality selection, HealthKit audiogram threshold recording, trial starts, level adjustments, playback requests, accepted levels, confidence, guardrail changes, aborts, and completion. Manual threshold tone events remain in the domain model but are not emitted by scheduled Study No. 1 tasks.

## Calibrated Audio Engine

The calibrated audio engine is app-owned. ResearchKit informed the design, but the app does not call ResearchKit's internal generator for Study No. 1 playback.

The relevant domain files are:

- `CalibratedAudioConversion.swift`
- `CalibratedAudioGuardrails.swift`
- `CalibratedTonePlayback.swift`
- `CalibratedToneRenderer.swift`

The AVFoundation playback implementation is:

- `CalibratedToneAudioPlayer.swift`

### Headphone Profile

The only implemented calibrated headphone identifier is:

```text
AIRPODSPROV2
```

The calibration metadata records:

- source repository URL: ResearchKit repository,
- vendored ResearchKit commit: `55d57711949ce08c745883d51af0b1dc025d022f`,
- design-document ResearchKit commit: `daba8c9f103477bd0279cc52a924a85b480df601`,
- source files:
  - `frequency_dBSPL_AIRPODSPROV2.plist`
  - `retspl_AIRPODSPROV2.plist`
  - `volume_curve_AIRPODSPROV2.plist`
  - `retspl_dBFS_AIRPODSPROV2.plist`
- validation status: ResearchKit reference available.

There are two AirPods Pro 2 RETSPL-related files with different meanings:

- `retspl_AIRPODSPROV2.plist` is the active audiology RETSPL table. It maps each supported frequency to the acoustic dB SPL value that corresponds to 0 dB HL, and the app uses it to convert requested dB HL into target dB SPL.
- `retspl_dBFS_AIRPODSPROV2.plist` contains negative dBFS reference values. It appears relevant to a possible direct digital-level calibration path, but the inspected ResearchKit generator does not load or consume this file.

The app therefore records `retspl_dBFS_AIRPODSPROV2.plist` as provenance/reference data, but does not blindly use it as the playback conversion policy. The implemented conversion follows the inspected generator behavior: compute target dB SPL from the active acoustic RETSPL table, estimate full-scale output from the frequency sensitivity table and system volume curve, then apply the generator's hardcoded +30 dB dBFS calibration offset before calculating digital attenuation.

### Calibration Tables

AirPods Pro 2 frequency sensitivity table:

| Frequency Hz | dB SPL |
| --- | ---: |
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

AirPods Pro 2 RETSPL table:

| Frequency Hz | RETSPL dB SPL |
| --- | ---: |
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

AirPods Pro 2 system volume curve:

| Output volume bucket | Offset dB |
| --- | ---: |
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

The supported playback frequencies are table-driven. Arbitrary future pitch matching must either restrict to these frequencies, use a validated interpolation policy, or add additional calibration data.

### Conversion Formula

For a requested dB HL tone:

```text
target_dBSPL = RETSPL(frequency, headphone) + requested_dBHL
estimated_full_scale_dBSPL =
    frequencySensitivity(frequency, headphone)
    + volumeCurveOffset(outputVolumeBucket)
    + dBFSCalibrationOffset
attenuation_dB = target_dBSPL - estimated_full_scale_dBSPL
linearAmplitude = 10 ^ (attenuation_dB / 20)
```

At 1000 Hz and maximum system volume:

```text
RETSPL = 9.27 dB SPL
requested_dBHL = 30 dB HL
target_dBSPL = 39.27 dB SPL

frequencySensitivity = 83.67 dB SPL
volumeCurveOffset = 0 dB
dBFSCalibrationOffset = 30 dB
estimated_full_scale_dBSPL = 113.67 dB SPL

attenuation_dB = -74.40 dB
linearAmplitude = about 0.0001905
```

This is why tone generation uses very small normalized amplitudes even for clinically ordinary dB HL levels.

### Volume Bucketing

`AVAudioSession.outputVolume` is a continuous-looking public value from 0.0 to 1.0, but the calibration table is bucketed in 1/16 steps.

The app buckets output volume by:

```text
bucketIndex = floor(outputVolume / 0.0625)
bucketIndex is clamped to 1...16
bucketedVolume = bucketIndex * 0.0625
```

Invalid, non-finite, below-zero, or above-one volumes are rejected.

Study No. 1 currently requires raw system output volume to be 1.0 within a tolerance of 0.0001. This makes the calibration path simpler and avoids relying on participant-adjusted device volume during measurement.

### Safety And Clipping Policy

The profile has `maximumSafeAttenuationDB = -1.0`. The conversion rejects amplitudes that are non-finite, non-positive, or too close to full scale. This is a conservative clipping/safety check, not a complete medical safety model.

Additional safety behavior:

- tones ramp in and out over 0.2 seconds,
- maximum requested level is clamped to 100 dB HL,
- a visible stop control is part of the modal task,
- playback is refused if guardrails are not passed,
- route or volume changes after passing guardrails require restart.

### Playback Planning And Rendering

`CalibratedTonePlaybackPlanner` builds a playback plan from:

- frequency,
- requested dB HL,
- channel,
- duration,
- ramp duration,
- guardrail validation,
- headphone identifier,
- route metadata,
- output volume,
- calibration conversion.

A valid plan contains:

- sample rate,
- buffer frame count,
- selected channel,
- requested dB HL,
- target dB SPL,
- attenuation dB,
- linear amplitude,
- calibration metadata,
- route metadata,
- output volume.

`CalibratedToneRenderer` generates a sine wave:

- stable phase,
- selected channel only,
- opposite channel zeroed,
- ramp in and ramp out envelope,
- sample-rate-aware phase increment.

`CalibratedToneAudioPlayer` uses:

- `AVAudioEngine`,
- `AVAudioSourceNode`,
- playback audio session category,
- preferred sample rate of 44100 Hz,
- preferred render buffer of 512 frames,
- main mixer output volume of 1.0,
- natural stop after duration,
- explicit ramped stop for user stop.

The original ResearchKit generator used Audio Unit RemoteIO and SpatialMixer. The app's implementation uses AVAudioEngine instead, while keeping the relevant math, channel isolation, ramping, and calibration metadata.

## AirPods Pro 2 Runtime Verification

The app has AirPods Pro 2 guardrails, but public APIs prevent a perfect runtime proof.

### What Public APIs Expose

AVAudioSession can expose:

- output route count,
- port type,
- port name,
- port UID,
- channel names,
- route-change notifications,
- output-volume value.

It cannot expose:

- exact AirPods generation,
- model number,
- serial number,
- firmware version,
- MAC address,
- whether A2DP is specifically AirPods,
- whether the device is in the participant's ear,
- ear-tip seal quality,
- actual acoustic output.

CoreBluetooth, ExternalAccessory, AccessorySetupKit, HealthKit, and CMHeadphoneMotionManager do not solve exact AirPods Pro 2 identity verification for this app. CMHeadphoneMotion can be a supporting signal in future, but it is not model proof.

### Implemented Verification Levels

The current code implements:

- `failed`
- `compatibleBluetoothPlaybackRoute`
- `likelyAirPodsPro2Route`

Participant-confirmed and researcher-confirmed AirPods Pro 2 levels are not implemented in the product flow today. The calibration guardrail currently relies on a route-name heuristic resolver, not a verified external device registry.

### Route Heuristic

`HeadphoneRouteAssessment` treats a route as likely AirPods Pro 2 when:

- the route is Bluetooth A2DP,
- there is exactly one output,
- the normalized route name contains an AirPods signal,
- the normalized route name contains Pro,
- the normalized route name contains a second-generation signal such as `2`, `second generation`, `2nd generation`, `gen 2`, or `generation 2`.

The app fingerprints route UIDs for diagnostics rather than storing raw identifiers as participant-facing proof. Exact serials and screenshots should not be collected unless the study protocol and IRB explicitly allow it.

### Guardrail Policy

`CalibratedAudioGuardrailPolicy` requires:

- a supported calibration profile,
- non-empty route data,
- exactly one output,
- Bluetooth A2DP route,
- verified calibrated headphone identifier `AIRPODSPROV2`,
- non-nil verification source,
- finite output volume from 0.0 through 1.0,
- maximum output volume.

After a guardrail session passes, route changes or volume changes move the state to `restartRequired`. The task should not continue from the previous calibration assumptions after a route or volume change.

## Quiet-Room Gate

Study No. 1 requires a quiet-room gate before active tone playback.

Current configuration:

- threshold: 45 dB,
- required contiguous passing samples: 5,
- sample interval: 1 second,
- max one-shot samples: 12,
- pass comparison: sample must be strictly less than threshold,
- any sample at or above threshold resets the contiguous pass count.

The modal quiet-room UI reports states such as:

- measuring,
- too loud,
- passed.

The quiet-room screen uses the shared animated level visualization for both onboarding orientation and scheduled tasks. It also offers suggestions such as moving rooms, closing windows, turning off fans or AC, and trying again later.

Current implementation details:

- `AVAudioEnvironmentSPLMeter` requests microphone permission through `AVAudioApplication.requestRecordPermission`.
- It uses an audio session suited to recording and measurement.
- It records a temporary `tinnitrack-environment-spl.caf`.
- It uses 44100 Hz, one channel, and Apple IMA4 format.
- It converts recorder average power using a default sensitivity offset.
- It restores prior audio session state after monitoring.

This implementation is useful for an app-level quietness gate, but it is not yet ResearchKit-equivalent dBA measurement. Future validation work should add A-weighting, device-specific sensitivity handling, built-in microphone route enforcement, and microphone calibration checks if the study needs stronger ambient-noise claims.

## HealthKit Audiogram Import

HealthKit audiograms are used as the Study No. 1 prerequisite and as participant hearing-threshold context.

`HealthKitManager`:

- checks whether Health data is available,
- reads authorization status for `HKObjectType.audiogramSampleType()`,
- requests read authorization,
- queries all audiogram samples sorted newest first,
- parses `HKAudiogramSample.sensitivityPoints`,
- supports iOS 18.1 `HKAudiogramSensitivityTest`,
- prefers air-conduction sensitivity when available,
- falls back to legacy left/right sensitivity properties on earlier iOS versions,
- keeps source name, device name, sample UUID, measured date, frequency, left ear, right ear, and detailed tests.

`AudiogramImportCoordinator`:

- first checks whether a Supabase audiogram already exists,
- requests HealthKit permission when needed,
- imports authorized HealthKit data,
- maps errors into product states,
- returns prerequisite states such as needs permission, permission denied, no audiogram in Health, met, or error.

`SupabaseAudiogramRepository`:

- fetches the latest stored audiogram for the current user,
- deduplicates imported samples by HealthKit sample UUID,
- stores `source = healthkit`,
- stores optional headphone/device name,
- stores `frequency_data` JSON with `schema_version = 1`,
- skips already-imported HealthKit samples.

The current fetch-latest path returns high-level audiogram record metadata. It does not rehydrate all frequency points when checking the prerequisite.

## Payload And Submission

The current payload builder is `StudyNo1LoudnessMatchPayloadBuilder`.

Payload version:

```text
study-no-1-loudness-match-v1
```

Protocol kind:

```text
studyNo1FixedOneKilohertz
```

The builder validates:

- participant ID,
- study session/enrollment ID,
- scheduled task ID,
- supported device metadata,
- AirPods model assessment or unavailable status,
- audio route output metadata,
- output volume from 0.0 through 1.0,
- non-empty environment samples,
- passed quiet-room result,
- fit seal confirmed,
- safety acknowledgement,
- visible stop control,
- lifecycle timestamps,
- 1000 Hz pure tone protocol,
- HealthKit audiogram threshold at 1000 Hz,
- exactly three trials,
- finite estimated dB SPL and dB SL values.

The payload includes:

- app version,
- calibration version,
- device context,
- AirPods/route context,
- audio session context,
- environment gate context,
- fit/safety context,
- threshold source,
- trial data,
- protocol events,
- playback event context,
- guardrail metadata,
- summary values,
- quality flags,
- limitations.

The core limitation string is:

```text
Estimated model-calibrated output from ResearchKit AirPods Pro 2 tables, route, and system output volume. This is not exact patient-specific in-ear SPL.
```

Additional limitations document:

- public API limits around AirPods Pro 2 identity,
- model-calibrated rather than exact in-ear output,
- lack of diagnostic claim.

`StudyNo1LoudnessMatchSubmissionExporter` maps the payload into the RPC submission:

- `startedAt`
- `completedAt`
- `matchedLevel` as median matched dB HL
- `gating`
- `rawPayload`
- `deviceInfo`
- `headphoneInfo`
- `appVersion`
- `calibrationVersion`

`SupabaseStudyService.submitLoudnessMatch` calls:

```text
submit_study_no_1_loudness_match
```

The RPC verifies that the authenticated user owns the enrollment, the enrollment belongs to Study No. 1, the scheduled task is still scheduled, and the current time is within the task window. This applies to regular scheduled loudness-match tasks. It inserts a `task_runs` row, sets protocol version `lm_v1`, merges `matched_level` into `raw_payload`, and marks the scheduled task completed.

## Supabase Backend

Supabase is the backend for:

- Auth,
- profile state,
- study definitions,
- enrollment state,
- scheduled tasks,
- task runs,
- audiogram records,
- developer-only reset/replay tools.

### Configuration

`SupabaseConfiguration` resolves:

- `SUPABASE_URL`,
- `SUPABASE_ANON_KEY`,
- optional `SUPABASE_ENVIRONMENT`.

Configuration can come from process environment or bundle Info.plist. The app uses the anon key. Do not put service-role credentials in the iOS app.

Environment naming:

- explicit `SUPABASE_ENVIRONMENT` wins,
- a runtime URL differing from bundled URL resolves as Development,
- otherwise Production.

### Main Tables

Current schema is migration-driven. Important tables include:

- `profiles`
  - User profile state tied to Supabase Auth users.
  - Current onboarding fields are first name, last name, date of birth, and onboarding completion time.
  - Biological sex was removed from profile requirements.
- `studies`
  - Study catalog rows such as `study-no-1`.
  - Recruiting studies are public catalog rows.
- `consents`
  - User-scoped consent records.
- `audiograms`
  - HealthKit-imported audiogram records.
  - Includes user ID, measured time, source, optional headphone/device name, HealthKit sample UUID, and JSON frequency data.
- `study_enrollments`
  - User enrollment in a study.
  - Includes onboarding completion for Study No. 1 task generation after the orientation threshold validation is complete.
- `scheduled_tasks`
  - Generated task schedule for an enrollment, plus the special Study No. 1 orientation threshold task.
  - Includes task key, task version, scheduled time, window start/end, day index, slot index, status, and completion time.
- `task_runs`
  - Submitted task executions.
  - Includes scheduled task, enrollment, user, run status, timestamps, app version, protocol version, calibration version, device info, headphone info, gating, and raw payload.
- `developer_accounts`
  - Allowlist for developer-only reset/replay RPCs.

### Row Level Security

RLS is enabled for user-scoped tables. The current policies are based on ownership through `auth.uid()`.

Important policy intent:

- users can read and update their own profile,
- anon and authenticated clients can select recruiting study catalog rows,
- users can select, insert, and update their own audiograms,
- users can select, insert, and update their own enrollments,
- users can select scheduled tasks linked to their own enrollments,
- task runs are user-scoped,
- developer tooling RPCs check an allowlist internally.

RPC functions are `SECURITY DEFINER` where needed, revoke execution from `PUBLIC`, and grant execution to `authenticated`.

Study No. 1 onboarding RPCs include:

- `begin_study_no_1_orientation_threshold_task`
  - Creates or returns the special onboarding `lm_1khz_v1` scheduled task after audiogram import.
- `submit_study_no_1_orientation_threshold`
  - Stores the one-time orientation threshold validation payload and marks the special onboarding scheduled task complete.
- `complete_study_no_1_onboarding`
  - Requires the orientation threshold task to have a completed `task_runs` row before marking enrollment onboarding complete and generating the ongoing schedule.

### Developer Tooling

The migration `20260622211617_developer_reset_replay_rpc.sql` adds developer-only helper RPCs:

- reset profile onboarding,
- reset Study No. 1 orientation,
- make the next loudness-match task available now,
- reopen the last completed loudness-match task.

These functions are intended for local development and manual replay workflows. They should remain guarded by the developer allowlist.

### Migration Rule

Schema changes must be new SQL migration files under `supabase/migrations/`. Do not edit or rewrite migrations that might already have been applied remotely.

## Auth And Profile Flow

The session flow is centralized in `SessionStore`.

Current session routes:

- bootstrapping,
- unauthenticated,
- awaiting email verification,
- needs onboarding,
- ready.

Sign-up metadata includes:

- first name,
- last name,
- date of birth.

Supabase Auth flows include:

- sign up,
- sign in,
- sign out,
- current session lookup,
- auth state stream,
- resend sign-up verification,
- password reset request,
- auth callback handling,
- password update,
- email update,
- delete current user through the `delete-account` Edge Function.

Profile completion is separate from account creation. The app can route an authenticated user to profile onboarding when the profile is incomplete.

## Local Development

Open the Xcode project:

```bash
open TinniTrack.xcodeproj
```

Install or update the ResearchKit submodule when needed:

```bash
git submodule update --init --recursive
```

If Xcode cannot resolve `ResearchKit`, `ResearchKitUI`, or `ResearchKitActiveTask`, make sure the submodule is present and that the package references in `TinniTrack.xcodeproj/project.pbxproj` point at the local `ResearchKit/` checkout.

Simulator guidance:

- Run only one iOS Simulator at a time.
- Use `TinniTrack Development` for simulator and development-device testing against the hosted development Supabase project.
- Use `TinniTrack` only for production testing on a physical device.
- Do not run app tests against a local Supabase stack. Development, UI testing, and manual replay checks should use the hosted development Supabase project.

Supabase configuration:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- optional `SUPABASE_ENVIRONMENT`

The iOS app uses a publishable anon key. That key is safe to ship only because Row Level Security defines the data boundary. Keep unauthenticated access limited to public catalog data such as recruiting study rows; participant-specific records, consent records, task state, profiles, audiograms, and developer reset/replay tools must remain authenticated and user-scoped.

HealthKit and AirPods behavior is limited in the simulator. The full Study No. 1 path requires physical-device testing for:

- Apple Hearing Test / HealthKit audiogram availability,
- AirPods route names and route changes,
- system output volume,
- microphone quiet-room measurement,
- calibrated playback behavior.

## Tests

The current test suite includes coverage for:

- calibrated audio conversion,
- guardrail policy,
- guardrail monitor,
- calibrated tone playback planning,
- acoustic validation helpers,
- headphone route assessment,
- quiet-room gate evaluator,
- tinnitus threshold staircase,
- tinnitus protocol engine,
- loudness-match flow view model,
- Study No. 1 loudness-match payload builder,
- Study No. 1 loudness-match submission exporter,
- HealthKit audiogram import coordinator,
- Study No. 1 configuration,
- Study Task dashboard view model,
- Supabase configuration,
- SessionStore,
- signup draft store,
- developer tools view model.

Typical Xcode test execution should use `TinniTrack Development` and the hosted development Supabase project. UI tests that need authenticated app state should use test hooks, seeded development users, or test-only credentials supplied outside source control; do not commit real personal account credentials or passwords. For documentation-only changes, a markdown/diff check is usually enough; for behavior changes, run the relevant unit tests, UI tests for changed navigation or flows, and any physical-device checks that match the changed boundary.

## Future Plans

### ResearchKit Parity

ResearchKit remains useful for:

- informed consent flows,
- standardized surveys,
- environment SPL meter parity,
- future audiometry modules,
- speech-in-noise modules,
- task result conventions.

Future ResearchKit use should go through `ResearchKitStudyTaskAdapter` unless there is a deliberate architecture decision to create a new boundary.

### AirPods Verification

Potential future improvements:

- participant-confirmed AirPods Pro 2 setup step,
- researcher-confirmed model-number workflow using A2931, A2699, A2698, A3047, A3048, or A3049,
- explicit logging of verification level and source,
- route UID hashing policy review,
- optional CMHeadphoneMotion support signal,
- restart and exclusion rules for route changes during active playback.

### Quiet-Room Measurement

Potential future improvements:

- A-weighting,
- built-in microphone route enforcement,
- device-specific microphone sensitivity offsets,
- microphone permission recovery UX,
- comparison to ResearchKit SPL meter behavior,
- study-specific threshold tuning,
- recording of environmental failure reasons.

### Pitch-Match Study

A future Study No. 2 can add pitch matching before loudness matching.

Open design choices:

- pure-tone pitch match, narrowband-noise pitch match, or both,
- two-choice bracketing,
- slider selection,
- hybrid coarse/fine protocol,
- octave confusion checks,
- whether to restrict pitch choices to calibrated table frequencies,
- whether to interpolate calibration between table frequencies,
- how to handle bilateral, central, or unclear tinnitus,
- whether the loudness match uses the pitch-matched frequency or a table-rounded frequency.

The future pitch-match study should preserve the same measurement principle:

```text
dB SL = matched dB HL - threshold dB HL
```

That requires a participant threshold at the selected frequency and ear, not only a pitch estimate.


### Product And Study Expansion

Potential future work:

- additional study protocols beyond Study No. 1,
- richer consent and eligibility flows,
- adverse-event and stop criteria,
- researcher dashboards,
- export tooling for study data,
- longitudinal analytics,
- offline or retryable submissions,
- improved participant education around Apple Hearing Test and AirPods setup.

## Vocabulary And Scientific Background

This section is intentionally detailed because project decisions depend on these terms.

### Sound

Sound is vibrating air creating pressure waves.

- Frequency is cycles per second, measured in hertz. It is perceived roughly as pitch.
- Amplitude is the size of the pressure swing. It is related to loudness, but perceived loudness is not linear.
- Phase is the timing position within a repeating waveform cycle.
- Pressure is measured in Pascals. The conventional threshold reference for dB SPL is 20 uPa.
- RMS amplitude is a standard way to summarize changing signal pressure or sample values for loudness-related calculations.

The app renders sine waves for current Study No. 1 tones. A sine wave is useful here because it is a simple pure tone with one frequency component.

### Decibels

The ear responds roughly logarithmically. Decibels describe ratios on a logarithmic scale. A dB value is only meaningful when its reference is known.

For amplitude-like quantities:

```text
dB = 20 * log10(value / reference)
```

For converting attenuation in dB to a linear amplitude:

```text
linearAmplitude = 10 ^ (attenuationDB / 20)
```

This is why a -20 dB attenuation is a 0.1 amplitude multiplier, and a -40 dB attenuation is a 0.01 amplitude multiplier.

### dB SPL

dB SPL means sound pressure level. It is an absolute acoustic pressure scale relative to 20 uPa.

When people say a quiet room is around some number of dB SPL, they are usually talking about a physical sound pressure measurement. In practice, environmental sound meters often use A-weighting and report dBA, which weights frequencies to approximate human hearing sensitivity.

The app's current quiet-room gate stores app-estimated ambient levels. It should not be treated as a fully validated dBA meter yet.

### dB HL

dB HL means hearing level. It is a clinical audiology scale. 0 dB HL is not 0 dB SPL. Instead, 0 dB HL means the average normal-hearing threshold for a specific frequency and transducer.

The reason dB HL exists is that human hearing sensitivity changes by frequency. A low-frequency 250 Hz tone needs a different physical SPL than a 1000 Hz tone to be perceived as threshold-level by average normal-hearing listeners.

For this app, dB HL is useful because:

- HealthKit audiograms report thresholds in dB HL.
- ResearchKit dB HL audiometry uses dB HL.
- Tinnitus loudness matching can be compared against audiometric thresholds when the frequency and ear are known.

### dB SL

dB SL means sensation level. It is a level above an individual's own threshold at the same frequency and ear.

```text
dB SL = stimulus dB HL - participant threshold dB HL
```

Example:

- participant threshold at 1000 Hz left ear: 10 dB HL,
- accepted tinnitus loudness match: 40 dB HL,
- loudness match: 30 dB SL.

dB SL is important because two participants can receive the same dB HL stimulus but experience different sensation levels if their hearing thresholds differ.

### RETSPL

RETSPL means Reference Equivalent Threshold Sound Pressure Level.

It is a table that maps 0 dB HL to a dB SPL value for a frequency and transducer measured under reference conditions.

Conversions:

```text
SPL = HL + RETSPL(frequency, transducer)
HL = SPL - RETSPL(frequency, transducer)
```

For AirPods Pro 2 at 1000 Hz, the ResearchKit RETSPL value used by the app is 9.27 dB SPL. That means:

```text
0 dB HL at 1000 Hz maps to 9.27 dB SPL
30 dB HL at 1000 Hz maps to 39.27 dB SPL
```

### dBFS

dBFS means decibels relative to digital full scale. It is a digital-audio scale, not an acoustic scale.

In PCM audio, full scale is the largest representable signal before clipping. A sine wave rendered at a normalized amplitude of 1.0 is near full scale. The app renders tones at much smaller linear amplitudes after converting desired dB HL into a model-calibrated digital attenuation.

dBFS alone does not tell us what came out of the headphones. The same digital amplitude can produce different acoustic SPL depending on transducer, volume setting, frequency response, operating system behavior, and fit.

### Attenuation And Linear Amplitude

The calibration engine computes how far below estimated full-scale acoustic output a requested tone should be.

If the estimated full-scale output at a frequency and volume is 113.67 dB SPL, and the target is 39.27 dB SPL, the attenuation is:

```text
39.27 - 113.67 = -74.40 dB
```

The renderer uses:

```text
10 ^ (-74.40 / 20) = about 0.0001905
```

That value is the digital sine amplitude used before ramping.

### Audiogram

An audiogram is a set of hearing thresholds by frequency and ear. It is commonly shown as a graph, but the app stores it as structured data.

HealthKit audiogram points can include:

- frequency,
- left ear sensitivity,
- right ear sensitivity,
- air-conduction tests,
- side,
- masking flag,
- source device,
- source app,
- measured date.

The current Study No. 1 prerequisite needs an imported audiogram, and recurring loudness-match tasks use the imported 1000 Hz threshold for the selected ear when calculating dB SL.

### Hearing Threshold

A hearing threshold is the quietest level a person detects reliably for a given frequency and ear under a specified protocol.

Study No. 1 recurring tasks use the imported HealthKit audiogram 1000 Hz threshold because dB SL for the loudness match must use a threshold at the same frequency and playback ear. The one-time onboarding orientation threshold task is a validation record; it is not repeated in scheduled tasks.

### Tinnitus

Tinnitus is the perception of sound without a matching external sound source. It can be perceived in one ear, both ears, centrally, or unclearly. It can vary over time and can be affected by fatigue, stress, noise exposure, medication, sleep, and environment.

Because tinnitus is subjective, the app cannot directly measure the tinnitus itself. It measures participant responses to controlled sounds intended to match aspects of the tinnitus percept.

### Loudness Matching

Loudness matching asks the participant to adjust or choose an external sound until it matches the perceived loudness of their tinnitus.

### Pitch Matching

Pitch matching asks the participant to identify the external sound frequency or noise band that best matches their tinnitus pitch.

### EMA

EMA means Ecological Momentary Assessment. In this project, it would mean short in-the-moment questionnaires around tinnitus context, symptoms, annoyance, mood, sleep, noise exposure, or daily events.

EMA is different from calibrated psychoacoustic measurement. It can explain context but does not replace calibrated sound presentation.

### A2DP, HFP, And Bluetooth Routes

A2DP is the Bluetooth profile used for higher-quality media playback. HFP is the hands-free profile often used for calls. The app requires Bluetooth A2DP for calibrated playback because HFP and other route types can have different bandwidth, processing, and routing behavior.

The guardrail rejects:

- built-in speaker,
- built-in receiver,
- wired headphones,
- Bluetooth HFP,
- Bluetooth LE unless explicitly validated in future,
- AirPlay,
- car audio,
- HDMI,
- USB audio,
- unknown unsupported routes.

### Model-Calibrated Output

Model-calibrated output means the app estimates acoustic level from:

- known calibration tables,
- target frequency,
- requested dB HL,
- RETSPL,
- output volume bucket,
- dBFS calibration policy,
- rendered digital amplitude,
- route metadata.

It does not mean measured in-ear output. Real output can vary with:

- ear canal geometry,
- ear-tip seal,
- AirPods firmware,
- iOS audio path,
- route changes,
- device model,
- individual fit,
- ambient noise,
- active audio processing.

This is why the payload limitation language is part of the data model, not just documentation.

### ResearchKit

ResearchKit is Apple's open-source framework for research tasks. In this project, it is both a dependency and an architectural reference.

The app uses ResearchKit as:

- a future task-presentation boundary through `ResearchKitStudyTaskAdapter`,
- a source of audiometry design patterns,
- a source of AirPods Pro 2 calibration reference data,
- a reference for ambient SPL gating behavior.
