# TinniTrack

TinniTrack is an iOS research-app prototype for tinnitus study workflows. The current app supports account onboarding, study enrollment state, HealthKit audiogram import, scheduled Study No. 1 tasks, headphone/ambient gates, and a 1 kHz loudness-match prototype.

The current loudness-match implementation is not scientifically valid end-to-end. It records normalized playback level, route metadata, ambient-meter traces, and protocol metadata so later calibrated work can map results to validated dB SPL, dB HL, or dB SL units.

## Current Scope

- iOS app target: `TinniTrack`
- Deployment target: iOS 18.1+
- UI: SwiftUI
- Backend: Supabase Auth/Postgres via version-controlled migrations
- Health data: HealthKit audiogram import
- Research-study task framework: StanfordBDHG ResearchKit Swift package, pinned in `Package.resolved`

## Source Layout

The app stays in a feature-first single target for now:

- `TinniTrack/Features/`: user-facing flows such as Onboarding, Dashboard, and LoudnessMatch.
- `TinniTrack/Domain/`: pure models, protocol definitions, calibration metadata, audio-engine abstractions, and payload builders.
- `TinniTrack/Services/`: external-system boundaries for Supabase, HealthKit, ResearchKit, audio route/ambient monitoring, and device metadata.
- `TinniTrack/Shared/`: app root/session infrastructure.

Dependency direction should remain:

- `Features` depend on `Domain` and service protocols.
- `Services` implement integration details.
- `Domain` does not depend on `Features` or UI frameworks.

## ResearchKit Direction

ResearchKit is integrated through SwiftPM from [StanfordBDHG/ResearchKit](https://github.com/StanfordBDHG/ResearchKit), currently resolved to version `3.1.4`. The package declares iOS 17+, so the app can target iOS 18.1.

Feature views should not import ResearchKit directly as the default path. Use the thin adapter in `TinniTrack/Services/ResearchKit/ResearchKitStudyTaskAdapter.swift` so future task presentation and result handling remain behind a boundary.

Relevant ResearchKit modules for future work:

- Consent/instructions: `ORKInstructionStep`; use instruction/web-style flows for consent content and signatures rather than spreading custom consent UI across features.
- Forms/surveys: `ORKFormStep` and `ORKFormItem` for demographics, EMA, screening, and questionnaires.
- Tone Audiometry: `ORKToneAudiometryStep` or `ORKOrderedTask.toneAudiometryTask(...)` for non-HL tone threshold tasks.
- dBHL Tone Audiometry: `ORKdBHLToneAudiometryStep` or `ORKOrderedTask.dBHLToneAudiometryTask(...)` for future calibrated threshold work. This still requires validation and correct device handling before use in analysis.
- SPL/environmental noise: `ORKEnvironmentSPLMeterStep` is available for ResearchKit-backed environmental SPL gating.
- Speech-in-Noise: `ORKSpeechInNoiseStep` or `ORKOrderedTask.speechInNoiseTask(...)` is relevant for later hearing studies, not Study No. 1 readiness.

## Study No. 1 Today

The active Study No. 1 flow is:

1. Participant signs in or signs up.
2. Participant enrolls in Study No. 1.
3. Study dashboard requires an Apple hearing-test/audiogram baseline from HealthKit.
4. The app generates scheduled loudness-match task windows through Supabase RPCs.
5. A task can start only inside its window.
6. The task gates on an AirPods Pro route-name match.
7. The task gates on estimated ambient level from local microphone metering.
8. The participant adjusts a 1 kHz tone and submits the match.

Current result payloads include:

- `matched_level`: normalized amplitude in `0...1`
- `loudness_trace`: normalized amplitude trace
- `ambient_trace`: estimated ambient dB trace from the current heuristic monitor
- `gating`: route and ambient gate outputs
- `device_info` and `headphone_info`
- `measurement_metadata`: protocol, payload schema, calibration-profile, and validity notice

Current result payloads do not include validated dB HL, dB SL, or calibrated dB SPL.

## Calibration and Measurement Readiness

The architecture now includes scaffolding for future calibrated work:

- `StudyProtocolDefinition` and `StudyProtocolCatalog` define protocol/task metadata.
- `AudioTaskDefinition` defines task type, stimulus, route requirement, ambient requirement, units, and ResearchKit mapping.
- `CalibrationProfileMetadata` and `OutputDeviceMetadata` describe calibration/profile status and device metadata.
- `StudyNo1LoudnessMatchResultBuilder` packages measurement traces and metadata consistently.
- `TonePlaying`, `HeadphoneRouteMonitoring`, `AudioRouteGating`, `AmbientNoiseMonitoring`, and `DeviceMetadataProviding` keep playback, route gating, ambient monitoring, and result packaging separate.

Deferred scientific-validation work:

- Confirm exact supported output devices, model identifiers, firmware, and route metadata.
- Replace route-name matching with model-aware output-device gating.
- Validate ambient SPL measurement against a reference meter or replace with ResearchKit SPL step where appropriate.
- Establish calibrated output profiles and RETSPL/device tables for the chosen transducers.
- Convert normalized output to validated dB SPL, dB HL, and dB SL only after calibration and audiogram linkage are verified.
- Define analysis-ready payload schemas and data export contracts with researchers.

## Supabase Migration Practice

Supabase schema is version-controlled infrastructure. Keep migrations in `supabase/migrations`.

Rules:

- Do not rewrite migrations that may have been applied remotely.
- Add a new migration for schema changes.
- Keep migrations explicit and reviewable.
- Do not commit secrets, service-role keys, real participant data, or private seed data.
- Client code uses anon/public credentials only.

Current Study No. 1 persistence uses `scheduled_tasks` and `task_runs`; the server RPC stores `protocol_version = 'lm_v1'` and app-provided calibration/device/gating/raw payload metadata.

## Local Development

Open `TinniTrack.xcodeproj` or build from the command line:

```sh
xcodebuild -project TinniTrack.xcodeproj -scheme TinniTrack -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
```

Run unit tests:

```sh
xcodebuild test -project TinniTrack.xcodeproj -scheme TinniTrack -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:TinniTrackTests
```

## Next Recommended Work

- Wire the ResearchKit adapter into a small non-production consent/instruction spike.
- Decide whether Study No. 1 should keep custom loudness UI or migrate pieces to ResearchKit active tasks.
- Add model-aware headphone metadata collection.
- Define a calibration-validation plan before any dB HL/dB SL claims.
- Add export/analysis documentation for `task_runs.raw_payload`.
