# Study No. 1 Loudness Match Data Contract

This contract describes the 1,000 Hz loudness-match payload used for calibrated Study No. 1 task runs.

## Calibration Profile

- Active supported profile: `ork-airpods-pro-2-1khz-v1`
- Output route: AirPods Pro 2
- Source: Apple/ResearchKit ORKAudiometry AirPods Pro 2 tables
- Source table version: `ResearchKit/ResearchKit main commit daba8c9f103477bd0279cc52a924a85b480df601, verified 2026-06-15`
- Source files: `frequency_dBSPL_AIRPODSPROV2.plist`, `volume_curve_AIRPODSPROV2.plist`, `retspl_AIRPODSPROV2.plist`, `retspl_dBFS_AIRPODSPROV2.plist`
- 1,000 Hz values: `frequency_dBSPL = 83.67`, `RETSPL = 9.27 dB SPL`, `RETSPL dBFS = -97`

AirPods Pro 3 remains route-allowed for participant gating but is not an accepted calibrated submission route until a real calibration profile is added.

## Derivation

The app stores both raw inputs and derived outputs so results remain reproducible if calibration tables change.

- `matched_level`: peak-normalized sine amplitude after app safe bounds.
- `peak_dbfs`: `20 * log10(matched_level)`.
- `rms_dbfs`: `20 * log10(matched_level / sqrt(2))`.
- `estimated_db_spl`: `frequency_dBSPL + volume_curve_offset_db + rms_dbfs`.
- `estimated_db_hl`: `estimated_db_spl - RETSPL`.
- `estimated_db_sl_*`: `estimated_db_hl - participant 1,000 Hz audiogram threshold`; emitted only for exact 1,000 Hz thresholds.

Interpolation is intentionally not implemented. Missing exact 1,000 Hz audiogram threshold marks the submission invalid for accepted Study No. 1 completion.

## Payload Shape

`task_runs.raw_payload` uses schema `study-no-1-lm-payload-v2` and includes:

- `raw_inputs`: matched amplitude, safe bounds, system output volume, ambient value, audiogram threshold source.
- `derived_outputs`: dBFS, estimated dB SPL, dB HL, dB SL, units, volume-curve lookup.
- `trials` and `trial_summary`: trial-level adjustment trace and variability.
- `loudness_trace`, `ambient_trace`, `system_output_volume_trace`: timestamped trace preservation.
- `gating`: route, ambient, volume, calibration, and audiogram gate state.
- `quality`: `validation_status`, quality flags, and invalidation reasons.
- `measurement_metadata`: schema/protocol version, calibration profile id/version, table provenance, and dBFS convention.

## Export Columns

The local CSV/JSON export builder and Supabase RPC expose the same flat columns for researcher tooling:

- Participant/task metadata: `task_run_id`, `scheduled_task_id`, `enrollment_id`, `user_id`, `participant_id`, `submitted_at`, `scheduled_for`, `day_index`, `slot_index`.
- Validity: `schema_version`, `validation_status`, `quality_flags`.
- Measurement: `matched_normalized_amplitude`, `peak_dbfs`, `rms_dbfs`, `estimated_db_spl`, `estimated_db_hl`, `estimated_db_sl_left`, `estimated_db_sl_right`, `estimated_db_sl_bilateral_mean`.
- Calibration: `calibration_profile_id`, `calibration_profile_version`, `calibration_source_table_version`.
- Conditions: `route_name`, `route_port_type`, `system_output_volume`, `volume_curve_offset_db`, `ambient_db_at_submit`.
- Audiogram: `audiogram_threshold_left_db_hl`, `audiogram_threshold_right_db_hl`, `audiogram_threshold_derivation`.
- Variability: `trial_count`, `trial_standard_deviation`.

## Dashboard Integration

The next researcher dashboard should call `export_study_no_1_loudness_matches()` through `StudyServiceProtocol.fetchStudyNo1LoudnessMatchExports()`. The dashboard can display longitudinal values from the flat columns while retaining `export_payload` server-side for audit and reproducibility.

Dashboard filters should include `validation_status`, `quality_flags`, `calibration_profile_id`, `calibration_profile_version`, participant, day/slot, and date range. CSV and JSON download controls should use the domain export builder to keep app-local and web/admin exports aligned.
