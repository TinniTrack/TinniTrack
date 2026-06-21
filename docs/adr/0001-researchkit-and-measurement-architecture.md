# ADR 0001: ResearchKit Boundary and Measurement Readiness

Date: 2026-06-06

## Status

Accepted for architecture readiness.

## Context

TinniTrack needs to continue toward ResearchKit-backed hearing-study workflows without pretending the current Study No. 1 loudness-match prototype is scientifically valid. The app also needs a lower deployment target than the Xcode-created iOS 26.1 default.

ResearchKit is integrated through Apple's embedded framework project flow by adding `ResearchKit.xcodeproj` to the app project and embedding the `ResearchKit`, `ResearchKitUI`, and `ResearchKitActiveTask` dynamic frameworks. TinniTrack targets iOS 18.1.

## Decision

- Set explicit iOS deployment target settings to 18.1.
- Keep a single app target with the existing feature-first layout: `Features`, `Domain`, `Services`, and `Shared`.
- Add `Services/ResearchKit/ResearchKitStudyTaskAdapter.swift` as the ResearchKit boundary.
- Keep feature views independent from direct ResearchKit imports by default.
- Add domain metadata for study protocols, audio task definitions, calibration profiles, output devices, and measurement payloads.
- Move loudness result packaging into `StudyNo1LoudnessMatchResultBuilder`.
- Keep current Study No. 1 behavior, but label output as normalized/unvalidated prototype data.

## Relevant ResearchKit Surfaces

- `ORKInstructionStep`: consent/instruction screens and task context.
- `ORKFormStep` / `ORKFormItem`: surveys, EMA, screening, demographics.
- `ORKToneAudiometryStep`: future tone audiometry work.
- `ORKdBHLToneAudiometryStep`: future dB HL audiometry work after validation.
- `ORKEnvironmentSPLMeterStep`: SPL/environmental noise gating option.
- `ORKSpeechInNoiseStep`: future speech-in-noise studies.

## Consequences

- ResearchKit is linked and compile-checked without forcing active feature flows to depend on it directly.
- Current custom loudness matching remains intact.
- Measurement payloads now carry enough metadata for future migration and analysis conversations.
- The app still does not produce validated dB HL, dB SL, or calibrated SPL results.

## Supabase Practice

Supabase migrations remain append-only once applied remotely. This readiness pass did not require a new migration because current `task_runs` fields already support app version, protocol version, calibration version, device info, headphone info, gating, and raw payload metadata.

Future schema changes should be added as new SQL files under `supabase/migrations` and must not include secrets, service-role keys, real participant data, or private seed data.

## Deferred Work

- Build a production consent flow on top of the ResearchKit adapter.
- Decide which Study No. 1 steps should migrate to ResearchKit versus remain custom.
- Validate output-device identity and headphone compatibility beyond route-name matching.
- Validate ambient SPL against reference equipment or migrate to `ORKEnvironmentSPLMeterStep`.
- Establish calibrated output profiles before producing dB HL or dB SL.
- Define export and analysis contracts for `task_runs.raw_payload`.
