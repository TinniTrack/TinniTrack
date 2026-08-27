# Quiet-Environment Screening

Study No. 1 uses a continuous quiet-environment screen before and between calibrated tone presentations. It is a study-policy guardrail, not a validated sound-level meter. In particular, values named `dBA` are provisional screening estimates derived from a generic microphone reference; they are not per-model or per-unit acoustic calibrations.

## Signal Path

`AVAudioEnvironmentSPLMeter` and `StudyAudioSessionCoordinator` own capture and audio-session handoffs. The capture path:

1. Requests microphone permission and configures `AVAudioSession` as `.playAndRecord` in `.measurement` mode with Bluetooth A2DP output allowed.
2. Selects a built-in microphone input, activates the session, and verifies that the actual current input is still `.builtInMic`. A Bluetooth HFP, wired, USB, line-in, unknown, or missing input does not satisfy the gate.
3. Waits `0.35` seconds for the route and session to settle.
4. Accepts non-interleaved Float32 PCM from `AVAudioEngine`, records the actual data-source orientation, sample rate, channel count, and input-gain state, and discards a `0.5`-second filter warm-up.
5. Applies the streaming IEC-style `AWeightingFilter`, normalized to 0 dB at 1 kHz, to each channel. `EnvironmentPCMWindowProcessor` accumulates mean-square energy across all frames and channels and emits a window only after exactly `round(sampleRate * 1.0)` frames. Tap-buffer boundaries therefore do not change the one-second decision window.
6. Converts A-weighted energy to digital level with `10 * log10(meanSquare)` and then applies the provisional calibration profile to produce the screening estimate.

The processor rejects empty, non-finite, clipped, discontinuous, incomplete, or format-mismatched PCM. Route, data-source, sample-format, and input-gain changes invalidate the current decision and require fresh acquisition. A decision window is valid only when its duration is one second within one input-frame tolerance, its recorded route is `builtInMicrophone`, and it has a finite provisional estimate.

## Estimate and Policy

`TinnitusEnvironmentCalibrationProfile.provisionalBuiltInMicrophone` has identifier `researchkit-generic-iphone-built-in-mic-v1`, status `provisional`, reference sensitivity `-23.3 dB`, and estimated offset `117.3 dB`. The estimate follows the generic `dBFS - sensitivity + 94` relationship. It has no measured uncertainty and has not been validated for a particular iPhone model or unit.

`TinnitusEnvironmentSPLGateConfiguration.studyNo1` applies the following screening policy:

| Decision | Current rule |
| --- | --- |
| Initial pass | Five contiguous, valid one-second windows strictly below `45.0` provisional dBA |
| Initial reset | A valid window at or above `45.0` resets the five-window count |
| One-shot limit | `runGate` returns failure after 12 valid windows without a pass |
| Suspected interruption | One valid window at or above `45.0`, or at least `8.0 dB` above the local baseline |
| Confirmed interruption | Two consecutive suspected-loudness windows |
| Recovery | Five consecutive, valid windows strictly below `43.0` provisional dBA |
| Retained live history | At most 120 measurement records |

Only `interruptedByLoudness` is a genuine participant-facing loudness interruption. The first qualifying loud window is `suspectedLoudness`; it does not show the overlay. Invalid input, intentional suspension, route invalidation, reacquisition, or missing samples also must not be presented as “too loud.”

### The baseline is secondary

The initial local baseline is the mean of the five passing windows. Afterward, a quiet sample can update it at a `0.05` adaptation rate, but only when the sample is below the `43.0` recovery threshold. The baseline supplies the additional `+8.0 dB` change detector; it never replaces the absolute `45.0` threshold. Consequently, adaptation cannot make a stable environment at or above `45.0` pass, and baseline changes cannot weaken the absolute interruption rule.

## Playback and Lifecycle Coordination

Microphone capture is intentionally stopped whenever the app cannot make an uncontaminated environmental decision:

- `.tonePlayback` suspends screening before a calibrated tone and waits for the monitor session to stop before playback takes ownership of the process-wide audio session.
- `.responseTap` suspends screening when a participant response stops a tone. Reacquisition waits for the player's ramp-down to reach silence.
- `.audioSessionHandoff` represents an explicit workflow/session transition.
- `.appInactive` is sent from the orientation and scheduled-task scene-phase hooks while the app is inactive.
- Audio-session interruptions and media-services resets invalidate capture and use the corresponding reacquisition reason.

A prior initial pass remains recorded, but suspension does not permit playback. After playback, a response, an interruption, or an app/session transition, capture must be reconfigured and route-verified, then complete the `0.35`-second settling period, `0.5`-second A-weighting warm-up, and a fresh full one-second window before the state can return to `quiet`. Generation tokens discard late callbacks from a stopped monitor so they cannot become false interruptions.

The audio workflow captures the external `AVAudioSession` state once, serializes measurement/playback mutations through `StudyAudioSessionCoordinator`, and restores that state once when the workflow ends.

## Privacy, Metadata, and Export Semantics

The screen does not create an audio recording. Raw PCM exists only while `EnvironmentPCMWindowProcessor` computes energy; it is not placed in `TinnitusEnvironmentSPLMeasurement`, written to a file, persisted to Supabase, or included in structured logs.

The provenance-bearing measurement schema is version `2`, with level algorithm `a-weighted-pcm-energy-v1` and filter algorithm `iec-a-weighting-bilinear-sos-v1`. A measurement records:

- window start, end, duration, validity, and any typed failure reason;
- A-weighted digital level in dBFS and the separate provisional estimated-dBA value;
- verified input route, data-source orientation, actual sample rate and channel count, and input-gain state;
- algorithm version plus calibration identifier, status, offsets, provenance, and uncertainty.

`StudyNo1EnvironmentSPLContext` preserves older fields and adds optional provenance fields. New gate results set `measurementSchemaVersion` to `2`, `levelSemantics` to `provisional_estimated_dba_screening`, and `measurements` to the five provenance-bearing windows that established the initial pass. Persistence maps each domain measurement to `StudyNo1EnvironmentSPLMeasurementContext`, whose field names carry their units and which deliberately omits raw PCM and accessory identifiers. The legacy `samplingInterval` field now means exact energy-window duration, and legacy `samplesDBA` values are the provisional screening estimates—not A-weighted digital dBFS.

Both Study No. 1 exporters put the full environment context in `raw_payload` and the same unit-explicit measurement provenance in `gating.environment`. The gating object retains these compatibility keys:

- `threshold_dba`, `required_contiguous_samples`, `sampling_interval`, `sensitivity_offset_db`, `samples_dba`, and `gate_result`.

It adds:

- `screening_threshold_estimated_dba`, `window_duration_seconds`, `legacy_samples_dba_semantics`, `measurement_schema_version`, `level_semantics`, and `measurements`;
- per-window `schema_version`, ISO-8601 `window_started_at`/`window_ended_at`, `duration_seconds`, `a_weighted_digital_level_dbfs`, `provisional_estimated_dba`, `validity`, `failure_reason`, and `algorithm_version`;
- an `input` object with `route`, `data_source_orientation`, `sample_rate_hz`, `channel_count`, `input_gain`, and `is_input_gain_settable`;
- a `calibration` object with `profile_identifier`, `status`, `estimated_dba_offset`, `reference_sensitivity_offset_db`, `provenance`, and `uncertainty_db`.

The current top-level payload versions are `study-no-1-loudness-match-v3` and `study-no-1-orientation-threshold-v2`; they require the environment schema version, level semantics, and at least one measurement. The older loudness-match v2 and orientation-threshold v1 shapes remain readable because the added environment fields are optional when decoding legacy payloads.

## Verification Boundary

Simulator and host-side tests can validate deterministic behavior, including A-weighting response, exact frame-count windows across arbitrary PCM buffer boundaries, warm-up discard, invalid PCM handling, gate debounce and hysteresis, stale-generation rejection, view-model lifecycle transitions, and JSON export compatibility. The relevant suites are `AWeightingFilterTests`, `EnvironmentPCMWindowProcessorTests`, `TinnitusEnvironmentSPLGateTests`, `LoudnessMatchTaskFlowViewModelTests`, and `StudyNo1LoudnessMatchSubmissionExporterTests`.

Simulator results cannot establish microphone routing, acoustic accuracy, device sensitivity, or the real interaction between built-in input and AirPods A2DP playback. Before making acoustic or clinical claims, physical-device validation must cover supported iPhone models and units, actual built-in-microphone route and data-source selection, AirPods A2DP measurement/playback handoffs, route changes, phone/audio interruptions, media-services resets, background/foreground transitions, permission denial and recovery, and tone ramp-down isolation. A calibrated reference sound source or sound-level meter should be used across relevant levels and spectra to quantify bias and uncertainty and to validate the `45.0`/`43.0` study thresholds. Until that work is complete, the calibration status and participant/researcher wording must remain provisional.

## Implementation Map

- `TinniTrack/Services/Audio/AWeightingFilter.swift`: streaming A-weighting filter.
- `TinniTrack/Services/Audio/EnvironmentPCMWindowProcessor.swift`: exact PCM energy windows and measurement construction.
- `TinniTrack/Services/Audio/EnvironmentSPLMeter.swift`: permission, capture, route-change observation, and monitor events.
- `TinniTrack/Services/Audio/StudyAudioSessionCoordinator.swift`: process-wide measurement/playback session ownership and restoration.
- `TinniTrack/Domain/TinnitusProtocol/TinnitusEnvironmentSPLGate.swift`: policy, provenance models, and lifecycle state machine.
- `TinniTrack/Features/LoudnessMatch/ViewModels/LoudnessMatchTaskFlowViewModel.swift`: task-flow suspension, reacquisition, and overlay eligibility.
- `TinniTrack/Domain/TinnitusProtocol/StudyNo1LoudnessMatchPayload.swift`: persisted environment context.
