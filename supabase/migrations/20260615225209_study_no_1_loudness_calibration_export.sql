-- Study No. 1 calibrated loudness-match hardening and export path.
-- Keeps task_runs JSONB as the source of truth while requiring accepted-valid
-- calibrated payloads before a scheduled task can be marked complete.

CREATE INDEX IF NOT EXISTS task_runs_lm_validation_status_idx
ON public.task_runs ((raw_payload #>> '{quality,validation_status}'))
WHERE protocol_version = 'lm_v1';

CREATE OR REPLACE FUNCTION public.submit_study_no_1_loudness_match(
  p_scheduled_task_id uuid,
  p_enrollment_id uuid,
  p_started_at timestamptz,
  p_completed_at timestamptz,
  p_matched_level double precision,
  p_gating jsonb,
  p_raw_payload jsonb,
  p_device_info jsonb,
  p_headphone_info jsonb,
  p_app_version text,
  p_calibration_version text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_task public.scheduled_tasks%ROWTYPE;
  v_task_run_id uuid;
  v_validation_status text := COALESCE(p_raw_payload #>> '{quality,validation_status}', '');
  v_payload_schema_version text := COALESCE(p_raw_payload #>> '{measurement_metadata,schema_version}', '');
BEGIN
  SELECT st.*
  INTO v_task
  FROM public.scheduled_tasks st
  JOIN public.study_enrollments se ON se.id = st.enrollment_id
  JOIN public.studies s ON s.id = se.study_id
  WHERE st.id = p_scheduled_task_id
    AND st.enrollment_id = p_enrollment_id
    AND se.user_id = auth.uid()
    AND se.status = 'enrolled'
    AND s.slug = 'study-no-1'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Scheduled task is not eligible for Study No. 1 submission.';
  END IF;

  IF v_task.status <> 'scheduled' THEN
    RAISE EXCEPTION 'Scheduled task is not startable.';
  END IF;

  IF NOW() < v_task.window_start OR NOW() > v_task.window_end THEN
    RAISE EXCEPTION 'Scheduled task is outside its active window.';
  END IF;

  IF v_payload_schema_version <> 'study-no-1-lm-payload-v2' THEN
    RAISE EXCEPTION 'Study No. 1 loudness-match payload schema is not accepted.';
  END IF;

  IF v_validation_status <> 'acceptedValid' THEN
    RAISE EXCEPTION 'Study No. 1 loudness-match submission is invalid and will not complete the scheduled task.';
  END IF;

  INSERT INTO public.task_runs (
    scheduled_task_id,
    enrollment_id,
    user_id,
    run_status,
    started_at,
    completed_at,
    submitted_at,
    app_version,
    protocol_version,
    calibration_version,
    device_info,
    headphone_info,
    gating,
    raw_payload
  ) VALUES (
    v_task.id,
    v_task.enrollment_id,
    auth.uid(),
    'completed',
    p_started_at,
    p_completed_at,
    NOW(),
    p_app_version,
    'lm_v1',
    p_calibration_version,
    COALESCE(p_device_info, '{}'::jsonb),
    COALESCE(p_headphone_info, '{}'::jsonb),
    COALESCE(p_gating, '{}'::jsonb),
    COALESCE(p_raw_payload, '{}'::jsonb) || jsonb_build_object('matched_level', p_matched_level)
  )
  RETURNING id INTO v_task_run_id;

  UPDATE public.scheduled_tasks
  SET status = 'completed',
      completed_at = NOW()
  WHERE id = v_task.id;

  RETURN v_task_run_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.export_study_no_1_loudness_matches()
RETURNS TABLE (
  task_run_id uuid,
  scheduled_task_id uuid,
  enrollment_id uuid,
  user_id uuid,
  participant_id integer,
  submitted_at timestamptz,
  scheduled_for timestamptz,
  day_index int,
  slot_index int,
  started_at timestamptz,
  completed_at timestamptz,
  schema_version text,
  validation_status text,
  quality_flags text,
  task_key text,
  task_version int,
  matched_normalized_amplitude double precision,
  peak_dbfs double precision,
  rms_dbfs double precision,
  estimated_db_spl double precision,
  estimated_db_hl double precision,
  estimated_db_sl_left double precision,
  estimated_db_sl_right double precision,
  estimated_db_sl_bilateral_mean double precision,
  calibration_profile_id text,
  calibration_profile_version text,
  calibration_source_table_version text,
  route_name text,
  route_port_type text,
  system_output_volume double precision,
  volume_curve_offset_db double precision,
  audiogram_threshold_left_db_hl double precision,
  audiogram_threshold_right_db_hl double precision,
  audiogram_threshold_derivation text,
  ambient_db_at_submit double precision,
  trial_count int,
  trial_standard_deviation double precision,
  export_payload jsonb
)
LANGUAGE sql
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT
    tr.id AS task_run_id,
    tr.scheduled_task_id,
    tr.enrollment_id,
    tr.user_id,
    p.participant_id,
    tr.submitted_at,
    st.scheduled_for,
    st.day_index,
    st.slot_index,
    tr.started_at,
    tr.completed_at,
    tr.raw_payload #>> '{measurement_metadata,schema_version}' AS schema_version,
    tr.raw_payload #>> '{quality,validation_status}' AS validation_status,
    array_to_string(
      ARRAY(
        SELECT jsonb_array_elements_text(COALESCE(tr.raw_payload #> '{quality,quality_flags}', '[]'::jsonb))
      ),
      '|'
    ) AS quality_flags,
    tr.raw_payload #>> '{task_key}' AS task_key,
    NULLIF(tr.raw_payload #>> '{task_version}', '')::int AS task_version,
    NULLIF(tr.raw_payload #>> '{raw_inputs,matched_level}', '')::double precision AS matched_normalized_amplitude,
    NULLIF(tr.raw_payload #>> '{derived_outputs,peak_dbfs}', '')::double precision AS peak_dbfs,
    NULLIF(tr.raw_payload #>> '{derived_outputs,rms_dbfs}', '')::double precision AS rms_dbfs,
    NULLIF(tr.raw_payload #>> '{derived_outputs,estimated_db_spl}', '')::double precision AS estimated_db_spl,
    NULLIF(tr.raw_payload #>> '{derived_outputs,estimated_db_hl}', '')::double precision AS estimated_db_hl,
    NULLIF(tr.raw_payload #>> '{derived_outputs,estimated_db_sl_left}', '')::double precision AS estimated_db_sl_left,
    NULLIF(tr.raw_payload #>> '{derived_outputs,estimated_db_sl_right}', '')::double precision AS estimated_db_sl_right,
    NULLIF(tr.raw_payload #>> '{derived_outputs,estimated_db_sl_bilateral_mean}', '')::double precision AS estimated_db_sl_bilateral_mean,
    tr.raw_payload #>> '{measurement_metadata,active_headphone_calibration_profile,profile_id}' AS calibration_profile_id,
    tr.raw_payload #>> '{measurement_metadata,active_headphone_calibration_profile,profile_version}' AS calibration_profile_version,
    tr.raw_payload #>> '{measurement_metadata,active_headphone_calibration_profile,source_table_version}' AS calibration_source_table_version,
    tr.raw_payload #>> '{gating,headphone_gate,route_name}' AS route_name,
    tr.raw_payload #>> '{gating,headphone_gate,route_port_type}' AS route_port_type,
    NULLIF(tr.raw_payload #>> '{raw_inputs,system_output_volume_at_submit}', '')::double precision AS system_output_volume,
    NULLIF(tr.raw_payload #>> '{derived_outputs,volume_curve_lookup,offset_db}', '')::double precision AS volume_curve_offset_db,
    NULLIF(tr.raw_payload #>> '{raw_inputs,audiogram_threshold,left_db_hl}', '')::double precision AS audiogram_threshold_left_db_hl,
    NULLIF(tr.raw_payload #>> '{raw_inputs,audiogram_threshold,right_db_hl}', '')::double precision AS audiogram_threshold_right_db_hl,
    tr.raw_payload #>> '{raw_inputs,audiogram_threshold,derivation}' AS audiogram_threshold_derivation,
    NULLIF(tr.raw_payload #>> '{gating,ambient,db_at_submit}', '')::double precision AS ambient_db_at_submit,
    NULLIF(tr.raw_payload #>> '{trial_summary,count}', '')::int AS trial_count,
    NULLIF(tr.raw_payload #>> '{trial_summary,standard_deviation_normalized_amplitude}', '')::double precision AS trial_standard_deviation,
    jsonb_build_object(
      'schema_version', tr.raw_payload #>> '{measurement_metadata,schema_version}',
      'task_run_id', tr.id,
      'scheduled_task_id', tr.scheduled_task_id,
      'enrollment_id', tr.enrollment_id,
      'user_id', tr.user_id,
      'participant_id', p.participant_id,
      'submitted_at', tr.submitted_at,
      'scheduled_for', st.scheduled_for,
      'day_index', st.day_index,
      'slot_index', st.slot_index,
      'validation_status', tr.raw_payload #>> '{quality,validation_status}',
      'quality_flags', tr.raw_payload #> '{quality,quality_flags}',
      'raw_inputs', tr.raw_payload #> '{raw_inputs}',
      'derived_outputs', tr.raw_payload #> '{derived_outputs}',
      'trial_summary', tr.raw_payload #> '{trial_summary}',
      'calibration', tr.raw_payload #> '{measurement_metadata,active_headphone_calibration_profile}',
      'gating', tr.gating,
      'device_info', tr.device_info,
      'headphone_info', tr.headphone_info
    ) AS export_payload
  FROM public.task_runs tr
  JOIN public.scheduled_tasks st ON st.id = tr.scheduled_task_id
  JOIN public.study_enrollments se ON se.id = tr.enrollment_id
  JOIN public.studies s ON s.id = se.study_id
  LEFT JOIN public.profiles p ON p.id = tr.user_id
  WHERE s.slug = 'study-no-1'
    AND tr.protocol_version = 'lm_v1'
    AND tr.user_id = auth.uid()
  ORDER BY st.scheduled_for, tr.submitted_at;
$$;

REVOKE ALL ON FUNCTION public.submit_study_no_1_loudness_match(
  uuid,
  uuid,
  timestamptz,
  timestamptz,
  double precision,
  jsonb,
  jsonb,
  jsonb,
  jsonb,
  text,
  text
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_study_no_1_loudness_match(
  uuid,
  uuid,
  timestamptz,
  timestamptz,
  double precision,
  jsonb,
  jsonb,
  jsonb,
  jsonb,
  text,
  text
) TO authenticated;

REVOKE ALL ON FUNCTION public.export_study_no_1_loudness_matches() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.export_study_no_1_loudness_matches() TO authenticated;
