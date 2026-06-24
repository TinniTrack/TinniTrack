CREATE OR REPLACE FUNCTION public.begin_study_no_1_orientation_threshold_task(
  p_enrollment_id uuid
)
RETURNS TABLE (
  id uuid,
  enrollment_id uuid,
  task_key text,
  task_version int,
  scheduled_for timestamptz,
  window_start timestamptz,
  window_end timestamptz,
  status text,
  day_index int,
  slot_index int,
  completed_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_enrollment public.study_enrollments%ROWTYPE;
  v_now timestamptz := NOW();
  v_task_id uuid;
BEGIN
  SELECT se.*
  INTO v_enrollment
  FROM public.study_enrollments se
  JOIN public.studies s ON s.id = se.study_id
  WHERE se.id = p_enrollment_id
    AND se.user_id = auth.uid()
    AND se.status = 'enrolled'
    AND s.slug = 'study-no-1'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Enrollment is not eligible for Study No. 1 onboarding.';
  END IF;

  IF v_enrollment.onboarding_completed_at IS NOT NULL THEN
    RAISE EXCEPTION 'Study No. 1 onboarding is already complete.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.audiograms a
    WHERE a.user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Import an Apple hearing test before starting the orientation threshold task.';
  END IF;

  SELECT st.id
  INTO v_task_id
  FROM public.scheduled_tasks st
  WHERE st.enrollment_id = v_enrollment.id
    AND st.task_key = 'threshold_1khz_orientation_v1'
    AND st.day_index = -1
    AND st.slot_index = 1
    AND st.status = 'scheduled'
    AND st.window_end > v_now
  ORDER BY st.created_at DESC
  LIMIT 1
  FOR UPDATE;

  IF v_task_id IS NULL THEN
    INSERT INTO public.scheduled_tasks (
      enrollment_id,
      task_key,
      task_version,
      scheduled_for,
      window_start,
      window_end,
      status,
      day_index,
      slot_index
    ) VALUES (
      v_enrollment.id,
      'threshold_1khz_orientation_v1',
      1,
      v_now,
      v_now - INTERVAL '5 minutes',
      v_now + INTERVAL '12 hours',
      'scheduled',
      -1,
      1
    )
    ON CONFLICT (enrollment_id, day_index, slot_index) DO UPDATE
    SET task_key = EXCLUDED.task_key,
        task_version = EXCLUDED.task_version,
        scheduled_for = EXCLUDED.scheduled_for,
        window_start = EXCLUDED.window_start,
        window_end = EXCLUDED.window_end,
        status = EXCLUDED.status,
        completed_at = NULL
    WHERE scheduled_tasks.status <> 'completed'
    RETURNING public.scheduled_tasks.id INTO v_task_id;
  END IF;

  IF v_task_id IS NULL THEN
    SELECT st.id
    INTO v_task_id
    FROM public.scheduled_tasks st
    WHERE st.enrollment_id = v_enrollment.id
      AND st.task_key = 'threshold_1khz_orientation_v1'
      AND st.day_index = -1
      AND st.slot_index = 1
      AND st.status = 'completed'
    ORDER BY st.completed_at DESC NULLS LAST, st.created_at DESC
    LIMIT 1;
  END IF;

  RETURN QUERY
  SELECT
    st.id,
    st.enrollment_id,
    st.task_key,
    st.task_version,
    st.scheduled_for,
    st.window_start,
    st.window_end,
    st.status,
    st.day_index,
    st.slot_index,
    st.completed_at
  FROM public.scheduled_tasks st
  WHERE st.id = v_task_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.submit_study_no_1_orientation_threshold(
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
BEGIN
  SELECT st.*
  INTO v_task
  FROM public.scheduled_tasks st
  JOIN public.study_enrollments se ON se.id = st.enrollment_id
  JOIN public.studies s ON s.id = se.study_id
  WHERE st.id = p_scheduled_task_id
    AND st.enrollment_id = p_enrollment_id
    AND st.task_key = 'threshold_1khz_orientation_v1'
    AND se.user_id = auth.uid()
    AND se.status = 'enrolled'
    AND s.slug = 'study-no-1'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Orientation threshold task is not eligible for submission.';
  END IF;

  IF v_task.status <> 'scheduled' THEN
    RAISE EXCEPTION 'Orientation threshold task is not startable.';
  END IF;

  IF NOW() < v_task.window_start OR NOW() > v_task.window_end THEN
    RAISE EXCEPTION 'Orientation threshold task is outside its active window.';
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
    'orientation_threshold_v1',
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

CREATE OR REPLACE FUNCTION public.complete_study_no_1_onboarding(
  p_enrollment_id uuid,
  p_timezone text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_enrollment public.study_enrollments%ROWTYPE;
  v_timezone text := COALESCE(NULLIF(BTRIM(p_timezone), ''), 'UTC');
  v_local_now timestamp;
  v_start_date date;
  v_day_index int;
  v_slot_hour int;
  v_slot_index int;
  v_window_start timestamptz;
  v_slot_hours int[] := ARRAY[9, 13, 17, 21];
BEGIN
  SELECT se.*
  INTO v_enrollment
  FROM public.study_enrollments se
  JOIN public.studies s ON s.id = se.study_id
  WHERE se.id = p_enrollment_id
    AND se.user_id = auth.uid()
    AND se.status = 'enrolled'
    AND s.slug = 'study-no-1'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Enrollment is not eligible for Study No. 1 onboarding completion.';
  END IF;

  IF v_enrollment.onboarding_completed_at IS NULL
     AND NOT EXISTS (
       SELECT 1
       FROM public.scheduled_tasks st
       JOIN public.task_runs tr ON tr.scheduled_task_id = st.id
       WHERE st.enrollment_id = v_enrollment.id
         AND st.task_key = 'threshold_1khz_orientation_v1'
         AND st.day_index = -1
         AND st.slot_index = 1
         AND st.status = 'completed'
         AND tr.run_status = 'completed'
         AND tr.protocol_version = 'orientation_threshold_v1'
     ) THEN
    RAISE EXCEPTION 'Complete the Study No. 1 orientation threshold task before finishing onboarding.';
  END IF;

  BEGIN
    PERFORM NOW() AT TIME ZONE v_timezone;
  EXCEPTION
    WHEN OTHERS THEN
      v_timezone := 'UTC';
  END;

  IF v_enrollment.onboarding_completed_at IS NULL THEN
    UPDATE public.study_enrollments
    SET onboarding_completed_at = NOW()
    WHERE id = v_enrollment.id;
  END IF;

  v_local_now := NOW() AT TIME ZONE v_timezone;
  IF v_local_now::time > TIME '09:00' THEN
    v_start_date := (v_local_now::date + 1);
  ELSE
    v_start_date := v_local_now::date;
  END IF;

  FOR v_day_index IN SELECT generate_series(0, 6) LOOP
    v_slot_index := 0;

    FOREACH v_slot_hour IN ARRAY v_slot_hours LOOP
      v_window_start := make_timestamptz(
        EXTRACT(YEAR FROM (v_start_date + v_day_index))::int,
        EXTRACT(MONTH FROM (v_start_date + v_day_index))::int,
        EXTRACT(DAY FROM (v_start_date + v_day_index))::int,
        v_slot_hour,
        0,
        0,
        v_timezone
      );

      INSERT INTO public.scheduled_tasks (
        enrollment_id,
        task_key,
        task_version,
        scheduled_for,
        window_start,
        window_end,
        status,
        day_index,
        slot_index
      ) VALUES (
        v_enrollment.id,
        'lm_1khz_v2',
        2,
        v_window_start,
        v_window_start,
        v_window_start + INTERVAL '60 minutes',
        'scheduled',
        v_day_index,
        v_slot_index
      )
      ON CONFLICT (enrollment_id, day_index, slot_index) DO NOTHING;

      v_slot_index := v_slot_index + 1;
    END LOOP;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.dev_make_next_loudness_match_available_now()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_task_id uuid;
BEGIN
  SELECT st.id
  INTO v_task_id
  FROM public.scheduled_tasks st
  JOIN public.study_enrollments se ON se.id = st.enrollment_id
  JOIN public.studies s ON s.id = se.study_id
  WHERE se.user_id = auth.uid()
    AND se.status = 'enrolled'
    AND s.slug = 'study-no-1'
    AND st.status = 'scheduled'
    AND st.day_index >= 0
    AND st.task_key = 'lm_1khz_v2'
  ORDER BY st.scheduled_for ASC
  LIMIT 1;

  IF v_task_id IS NULL THEN
    RAISE EXCEPTION 'No scheduled loudness-match task found for current user.';
  END IF;

  UPDATE public.scheduled_tasks
  SET scheduled_for = NOW(),
      window_start = NOW() - INTERVAL '5 minutes',
      window_end = NOW() + INTERVAL '60 minutes'
  WHERE id = v_task_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.dev_reopen_last_completed_loudness_match()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_task_id uuid;
BEGIN
  SELECT st.id
  INTO v_task_id
  FROM public.scheduled_tasks st
  JOIN public.study_enrollments se ON se.id = st.enrollment_id
  JOIN public.studies s ON s.id = se.study_id
  WHERE se.user_id = auth.uid()
    AND se.status = 'enrolled'
    AND s.slug = 'study-no-1'
    AND st.status = 'completed'
    AND st.day_index >= 0
    AND st.task_key = 'lm_1khz_v2'
  ORDER BY st.completed_at DESC NULLS LAST, st.scheduled_for DESC
  LIMIT 1;

  IF v_task_id IS NULL THEN
    RAISE EXCEPTION 'No completed loudness-match task found for current user.';
  END IF;

  DELETE FROM public.task_runs
  WHERE scheduled_task_id = v_task_id;

  UPDATE public.scheduled_tasks
  SET status = 'scheduled',
      scheduled_for = NOW(),
      window_start = NOW() - INTERVAL '5 minutes',
      window_end = NOW() + INTERVAL '60 minutes',
      completed_at = NULL
  WHERE id = v_task_id;
END;
$$;

REVOKE ALL ON FUNCTION public.begin_study_no_1_orientation_threshold_task(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.begin_study_no_1_orientation_threshold_task(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.submit_study_no_1_orientation_threshold(
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
GRANT EXECUTE ON FUNCTION public.submit_study_no_1_orientation_threshold(
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

REVOKE ALL ON FUNCTION public.complete_study_no_1_onboarding(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.complete_study_no_1_onboarding(uuid, text) TO authenticated;

REVOKE ALL ON FUNCTION public.dev_make_next_loudness_match_available_now() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.dev_reopen_last_completed_loudness_match() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.dev_make_next_loudness_match_available_now() TO authenticated;
GRANT EXECUTE ON FUNCTION public.dev_reopen_last_completed_loudness_match() TO authenticated;
