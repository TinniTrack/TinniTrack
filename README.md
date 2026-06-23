# TinniTrack

TinniTrack is an iOS research app for tinnitus study workflows. The current app supports participant authentication, profile onboarding, study enrollment, HealthKit audiogram import, Study No. 1 task scheduling, AirPods/quiet-room preflight checks, and a fixed 1 kHz tinnitus loudness-match task.

The long-term goal is to produce repeatable tinnitus measurements that can be interpreted scientifically across time and participants. The current implementation stores model-calibrated estimates and rich audit metadata, but it must not be described as exact patient-specific in-ear SPL or as clinically diagnostic. Public iOS APIs cannot prove exact AirPods Pro 2 identity, exact firmware/acoustic state, ear-tip seal, or actual in-ear SPL at runtime.

## Current App

The app is a SwiftUI iOS research prototype targeting iOS 18.1+. It uses Supabase for Auth/Postgres/RPCs, HealthKit for audiogram import, AVFoundation for audio route, microphone, and playback work, and a vendored ResearchKit project as a reference and future task-presentation boundary.

Current participant flow:

1. Sign up or log in with Supabase Auth.
2. Verify email when required by the Supabase project.
3. Complete profile onboarding with first name, last name, and date of birth if those fields were not completed during signup.
4. View recruiting studies on the dashboard.
5. Enroll in Study No. 1.
6. Complete Study No. 1 orientation:
   - take or locate an Apple Hearing Test,
   - authorize HealthKit audiogram access,
   - import at least one audiogram,
   - finish orientation so Supabase generates the task schedule.
7. Complete scheduled loudness-match tasks during their active time windows.

Study No. 1 is the only active study currently seeded by migrations. It schedules four `lm_1khz_v1` tasks per day for seven days at local hours 9, 13, 17, and 21, each with a 60-minute active window.

## Source Layout

The project intentionally uses a feature-first structure:

- `TinniTrack/Features/`: product flows, SwiftUI screens, and flow view models.
- `TinniTrack/Domain/`: pure domain models, calibration math, task protocols, and payload builders.
- `TinniTrack/Services/`: external-system boundaries for Supabase, HealthKit, ResearchKit, AVFoundation audio/device services, and developer tooling.
- `TinniTrack/Shared/`: app shell, session routing, and shared infrastructure.

Dependency direction:

- Features depend on domain types and service protocols.
- Services implement external integrations.
- Domain stays independent of Features and UI.
- Feature UI should not import ResearchKit directly.

## ResearchKit Boundary

ResearchKit is vendored under `Frameworks/ResearchKit` and linked through the app project. It is valuable because it contains hearing-study surfaces and AirPods Pro 2 calibration reference data, but it is not the default dependency for feature UI.

Use `TinniTrack/Services/ResearchKit/ResearchKitStudyTaskAdapter.swift` when the app needs ResearchKit task presentation or result handling. The adapter currently wraps:

- `ORKInstructionStep`,
- `ORKToneAudiometryStep`,
- `ORKdBHLToneAudiometryStep`,
- `ORKEnvironmentSPLMeterStep`,
- `ORKSpeechInNoiseStep`.

The current Study No. 1 loudness-match task is custom SwiftUI and domain-driven. ResearchKit informed the design, especially its dB HL audiometry and environment SPL task behavior, but feature code should remain SwiftUI-native unless a future task deliberately opts into the adapter.

Do not depend directly on `ORKdBHLToneAudiometryAudioGenerator` from app code. In the inspected ResearchKit source it is a private ResearchKitActiveTask implementation detail. TinniTrack instead owns its calibration and playback services in `TinniTrack/Domain/Calibration` and `TinniTrack/Services/Audio`.

## Study No. 1

Study No. 1 is a fixed-frequency loudness-match workflow. It deliberately avoids pitch matching for now so the app can collect a simpler standardized measure at 1,000 Hz.

Current task flow:

1. Intro modal.
2. AirPods correct-ear route step.
3. Continuous quiet-room gate.
4. AirPods fit/seal participant confirmation.
5. Maximum-volume and calibrated route guardrail step.
6. Active tinnitus task:
   - select tinnitus laterality,
   - collect a 1 kHz threshold with a staircase,
   - complete three loudness-match trials,
   - record confidence after each trial,
   - submit the completed run.

For unilateral tinnitus, playback uses the affected ear. For bilateral, central, or unclear tinnitus, the current Study A rule uses the left channel and records an ambiguous-laterality quality flag.

The active protocol lives in `TinnitusProtocolEngine`. The SwiftUI modal and `LoudnessMatchTaskFlowViewModel` coordinate user flow, playback, guardrails, environment monitoring, and Supabase submission without reimplementing the domain state machine.

## Loudness-Match Domain Logic

Study A uses `TinnitusProtocolConfiguration.studyAFixedOneKilohertz`:

- stimulus: pure tone,
- frequency: 1,000 Hz,
- required trials: 3,
- tone duration: 1.0 second,
- ramp duration: 0.2 seconds,
- minimum/maximum levels: -10 to 100 dB HL,
- initial loudness trial level: measured threshold + 5 dB SL,
- high within-session spread flag: spread greater than 10 dB.

Threshold collection uses `TinnitusThresholdStaircase`:

- start at 30 dB HL,
- step down 10 dB after `heard`,
- step up 5 dB after `not heard`,
- stop after two ascending hits at the same level,
- clamp to -10...100 dB HL.

Loudness adjustment uses four buttons:

- `muchSofter`: -5 dB,
- `softer`: -1 dB,
- `louder`: +1 dB,
- `muchLouder`: +5 dB.

Each trial stores accepted dB HL, estimated dB SPL, dB SL, confidence, and timestamp. The summary stores median dB HL, median estimated dB SPL, median dB SL, within-session spread, and quality flags.

## Calibration Model

TinniTrack uses an app-owned AirPods Pro 2 calibration profile derived from ResearchKit reference tables:

- `frequency_dBSPL_AIRPODSPROV2.plist`,
- `retspl_AIRPODSPROV2.plist`,
- `volume_curve_AIRPODSPROV2.plist`,
- `retspl_dBFS_AIRPODSPROV2.plist` as recorded reference data.

The active conversion path is in `CalibratedAudioConverter`:

```text
target_dBSPL = RETSPL(frequency, headphone) + requested_dBHL

estimated_full_scale_dBSPL =
    frequencySensitivity_dBSPL(frequency, headphone)
    + volumeCurveOffset_dB(iOSOutputVolume, headphone)
    + dBFSCalibrationOffset

attenuation_dB = target_dBSPL - estimated_full_scale_dBSPL
linearAmplitude = 10 ^ (attenuation_dB / 20)
```

The current AirPods Pro 2 profile supports 125, 250, 500, 750, 1000, 1500, 2000, 3000, 4000, 6000, and 8000 Hz. Study No. 1 uses only 1000 Hz.

Important 1000 Hz example:

- RETSPL at 1000 Hz: 9.27 dB SPL,
- frequency sensitivity at 1000 Hz: 83.67 dB SPL,
- volume offset at maximum iOS volume: 0 dB,
- dBFS calibration offset: +30 dB.

For a 30 dB HL request at max volume:

```text
target_dBSPL = 9.27 + 30 = 39.27 dB SPL
estimated_full_scale_dBSPL = 83.67 + 0 + 30 = 113.67 dB SPL
attenuation = 39.27 - 113.67 = -74.40 dB
linearAmplitude ~= 0.0001905
```

`CalibratedTonePlaybackPlanner` validates guardrails before producing a playback plan. `CalibratedToneAudioPlayer` then renders a stereo 44.1 kHz Float32 sine wave through `AVAudioEngine` and `AVAudioSourceNode`, writes samples only to the selected channel, fixes the mixer output at 1.0, and applies ramp-in/ramp-out to avoid clicks.

## Measurement Limits

The app can know exactly what PCM values it renders and can estimate model-calibrated output for AirPods Pro 2 under controlled conditions. It cannot know exact patient-specific in-ear SPL without additional hardware or private Apple APIs.

Known confounders include:

- AirPods unit variation and firmware,
- iPhone model and OS,
- Bluetooth route/profile behavior,
- system output volume,
- Headphone Accommodations, Media Assist, EQ, Sound Check, Reduce Loud Audio, and other output modifiers,
- ANC/transparency/adaptive settings,
- ear-tip seal and insertion depth,
- ear canal acoustics,
- environmental noise,
- dirty or obstructed microphones/speakers.

The payload explicitly records this limitation: output is estimated from ResearchKit AirPods Pro 2 tables, route, and system output volume, and is not exact patient-specific in-ear SPL.

## AirPods Runtime Verification

Public iOS APIs do not expose a signed AirPods identity, generation, serial number, firmware version, model number, Bluetooth MAC address, or Apple Hearing Test fit/noise state.

Current runtime verification therefore uses two layers:

- `HeadphoneRouteAssessor` checks the live AVAudioSession route and classifies it.
- `CalibratedAudioGuardrailPolicy` requires a single `.bluetoothA2DP` output, an AirPods Pro 2-looking route name resolved to `AIRPODSPROV2`, and maximum system volume.

The route-name check is a heuristic. It helps block obviously wrong outputs, but it cannot prove AirPods Pro 2 because users can rename devices and public APIs do not expose model identity.

The current guardrails require:

- exactly one active output route,
- Bluetooth A2DP rather than speaker, receiver, wired, AirPlay, car audio, Bluetooth HFP, or Bluetooth LE,
- route resolver verification for the AirPods Pro 2 calibration identifier,
- `AVAudioSession.outputVolume == 1.0` within `0.0001`,
- restart or interruption handling when route or volume changes after validation.

The app records route output count, port type, port name, UID, channel names, output volume, verification source, and calibration identifier when available. UID may be useful for audit/correlation but is not stable model proof.

Future supervised workflows should add explicit participant or researcher model confirmation using Apple Settings > Bluetooth > AirPods > Info. AirPods Pro 2 model numbers include A2931, A2699, A2698, A3047, A3048, and A3049.

## Quiet-Room Gate

Study No. 1 uses `TinnitusEnvironmentSPLGateConfiguration.studyA`:

- threshold: 45 dBA,
- required contiguous passing samples: 5,
- sampling interval: 1 second,
- one-shot max sample count: 12.

The modal task uses continuous monitoring via `EnvironmentSPLGateMonitoring`. The current concrete service, `AVAudioEnvironmentSPLMeter`, uses `AVAudioRecorder` metering, requests microphone permission, temporarily configures the audio session for `playAndRecord` + `measurement`, adds a sensitivity offset, emits updates until pass or cancellation, and restores the previous audio session afterward.

Status behavior:

- `In Progress...`: measuring and not yet passed,
- `Too much noise`: latest sample is at or above threshold and the gate continues sampling,
- `Noise Ok`: enough contiguous samples were below threshold and the Next button is enabled.

ResearchKit's `ORKEnvironmentSPLMeterStep` uses an A-weighted AVAudioEngine path and is the reference for a future higher-fidelity implementation. The current app-owned meter should be validated against reference equipment before being treated as a calibrated environmental SPL instrument.

## Payload And Submission

Completed Study No. 1 runs are built with `Phase6LoudnessMatchPayloadBuilder` and submitted through `Phase6LoudnessMatchSubmissionExporter`.

The payload version is `phase-6-study-a-v1` and validates that a completed Study A run has:

- enrollment and scheduled-task identifiers,
- device and audio-session context,
- AirPods/calibration metadata,
- audio route outputs,
- maximum-volume metadata and volume-curve bucket,
- passed environment samples,
- participant fit/seal confirmation,
- safety acknowledgement and visible stop control,
- fixed 1000 Hz pure-tone stimulus,
- measured 1000 Hz threshold,
- three loudness-match trials,
- finite estimated dB SPL and dB SL values,
- protocol events, playback events, refusals, lifecycle timestamps, and limitations.

The exported Supabase `LoudnessMatchSubmission` stores:

- `matched_level`: median matched dB HL,
- `gating`: environment, fit/seal, safety, and volume context,
- `raw_payload`: full Phase 6 payload plus `matched_level`,
- `device_info`,
- `headphone_info`,
- app version,
- calibration asset version.

Submission calls the `submit_study_no_1_loudness_match` RPC. The RPC verifies the task belongs to the authenticated enrolled user, verifies the task is still scheduled and inside its active window, inserts a `task_runs` row, and marks the scheduled task completed.

## Supabase Backend

Supabase is the backend for authentication, study state, schedule state, audiogram records, and task runs. Schema changes must be append-only SQL migrations under `supabase/migrations/`; do not rewrite migrations that may already have been applied remotely.

Current core tables:

- `auth.users`: Supabase-managed user accounts.
- `public.profiles`: app profile metadata, participant id, optional timezone, onboarding completion.
- `public.studies`: recruiting study definitions.
- `public.study_enrollments`: user-study enrollment state and Study No. 1 onboarding completion.
- `public.consents`: consent records and signed PDF storage paths. The current UI still uses a simple enrollment action rather than a production ResearchKit consent flow.
- `public.audiograms`: HealthKit-imported audiogram records, HealthKit sample UUID, source, optional headphone/device name, and JSON frequency data.
- `public.scheduled_tasks`: generated task schedule with task key/version, windows, status, day index, and slot index.
- `public.task_runs`: completed/aborted/failed task execution data and raw payloads.
- `public.developer_accounts`: allow-list for developer-only reset/replay RPCs in non-production projects.

Current RLS and access model:

- `studies`: authenticated users can read recruiting studies.
- `profiles`: users can select, insert, and update only their own profile row.
- `audiograms`: users can select, insert, and update only their own rows.
- `study_enrollments`: users can select, insert, and update only their own enrollments.
- `scheduled_tasks`: users can select, insert, and update tasks through their own enrollment.
- `task_runs`: users can select, insert, and update only their own runs.
- `developer_accounts`: table access is revoked from public, anon, and authenticated roles; RPCs call a security-definer assertion function.

Current RPCs:

- `complete_study_no_1_onboarding(enrollment_id, timezone)`: verifies an active Study No. 1 enrollment for the authenticated user, stamps onboarding completion, and generates 7 days of task slots.
- `submit_study_no_1_loudness_match(...)`: verifies task ownership/window/status, inserts `task_runs`, and completes the scheduled task.
- `dev_reset_profile_onboarding()`: developer-only profile onboarding reset.
- `dev_reset_study_no_1_orientation()`: developer-only orientation reset and scheduled-task deletion for the current user's Study No. 1 enrollment.
- `dev_make_next_loudness_match_available_now()`: developer-only replay helper that moves the next scheduled task window to now.
- `dev_reopen_last_completed_loudness_match()`: developer-only helper that deletes the current user's latest task run for a completed task and reopens that task.

Do not put service-role keys, secrets, real participant data, screenshots with identifiers, or private seed data in the repository or app bundle. Client code must use only anon/publishable credentials.

## Local Setup

This repo uses Apple ResearchKit as a git submodule at `Frameworks/ResearchKit`.

For a fresh clone:

```sh
git clone --recurse-submodules <repo-url>
cd Tinnitus-Capstone
git -C Frameworks/ResearchKit lfs pull --include='LFS-Files/**' --exclude=''
```

If the repo was cloned without submodules:

```sh
git submodule update --init --recursive
git -C Frameworks/ResearchKit lfs pull --include='LFS-Files/**' --exclude=''
```

Then ensure `Frameworks/ResearchKit/ResearchKit.xcodeproj` is present in `TinniTrack.xcodeproj` and that `ResearchKit.framework`, `ResearchKitUI.framework`, and `ResearchKitActiveTask.framework` are embedded in the app target.

Open `TinniTrack.xcodeproj` in Xcode. Use schemes intentionally:

- `TinniTrack Local Dev`: simulator testing against local development settings.
- `TinniTrack iPhone Dev`: physical-device testing against the separate development database.
- `TinniTrack`: production physical-device testing.

Run only one iOS Simulator at a time.

Command-line build:

```sh
xcodebuild -project TinniTrack.xcodeproj -scheme "TinniTrack Local Dev" -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
```

Run unit tests:

```sh
xcodebuild test -project TinniTrack.xcodeproj -scheme "TinniTrack Local Dev" -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:TinniTrackTests CODE_SIGNING_ALLOWED=NO
```

For physical-device development, do not point the app at `http://127.0.0.1:54321`; on a phone that address points to the phone itself. Use a hosted development Supabase project and set the Debug scheme environment variables:

- `SUPABASE_URL`,
- `SUPABASE_ANON_KEY`,
- `SUPABASE_ENVIRONMENT=Development`.

## Future Plans

High-priority validation and research-readiness work:

- Validate calibrated output on supported device/OS/AirPods firmware combinations before making research-grade dB HL, dB SPL, or dB SL claims.
- Validate or replace the current AVAudioRecorder-based quiet-room meter with an A-weighted AVAudioEngine or ResearchKit-backed SPL implementation.
- Add explicit participant/researcher AirPods Pro 2 model confirmation and store confirmation metadata separately from route-name heuristics.
- Define controls for system audio modifiers such as Headphone Accommodations, Media Assist, Sound Check/EQ, Reduce Loud Audio, Personalized Volume, and noise-control modes.
- Build a validated fit/seal workflow or a supervised study procedure for documenting fit checks.
- Create export and analysis documentation for `task_runs.raw_payload`.

Product and study expansion:

- Production eConsent using ResearchKit instruction/consent surfaces or another auditable consent flow.
- EMA questionnaires for tinnitus context, mood, annoyance, sleep, medication, noise exposure, and daily events.
- Pitch-match study workflow before loudness matching.
- Multi-frequency and pitch-matched loudness workflows.
- Speech-in-noise or other hearing-function studies.
- Researcher dashboard and analysis exports.
- Local notifications for upcoming task windows.
- Biometric unlock for returning participants.
- AirPods Pro 3 or other headphone calibration profiles after compatible reference tables and validation exist.
- Optional SensorKit research entitlement spike for acoustic-settings confounders. SensorKit should not be assumed to prove AirPods model identity.

## Vocabulary

- dB SPL: sound pressure level, an absolute physical pressure scale relative to 20 uPa.
- dB HL: hearing level, a clinical scale normalized by frequency/transducer RETSPL values.
- dB SL: sensation level, a level relative to an individual's hearing threshold at the same frequency and ear. `dB SL = matched dB HL - threshold dB HL`.
- RETSPL: reference equivalent threshold sound pressure level. It maps 0 dB HL to dB SPL for a frequency and transducer.
- Audiogram: hearing threshold by frequency and ear.
- EMA: ecological momentary assessment, usually brief in-the-moment questionnaires.
- A2DP: Bluetooth high-quality playback profile. The app rejects HFP for calibrated playback because HFP is the headset/call profile.

## Historical Docs

Older planning documents under `docs/` are useful for provenance and research notes, but this README is the current source of truth for app behavior and implementation decisions. If a planning document conflicts with current code or this README, update the README first and treat the older document as historical context.
