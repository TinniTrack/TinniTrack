CREATE OR REPLACE FUNCTION public.begin_study_no_1_onboarding_loudness_task(
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
    RAISE EXCEPTION 'Import an Apple hearing test before starting the onboarding loudness task.';
  END IF;

  SELECT st.id
  INTO v_task_id
  FROM public.scheduled_tasks st
  WHERE st.enrollment_id = v_enrollment.id
    AND st.task_key = 'lm_1khz_v1'
    AND st.day_index = -1
    AND st.slot_index = 0
    AND st.status = 'scheduled'
    AND st.window_end > v_now
  ORDER BY st.created_at DESC
  LIMIT 1
  FOR UPDATE;

  IF v_task_id IS NULL THEN
    SELECT st.id
    INTO v_task_id
    FROM public.scheduled_tasks st
    WHERE st.enrollment_id = v_enrollment.id
      AND st.task_key = 'lm_1khz_v1'
      AND st.day_index = -1
      AND st.slot_index = 0
      AND st.status = 'completed'
    ORDER BY st.completed_at DESC NULLS LAST, st.created_at DESC
    LIMIT 1
    FOR UPDATE;
  END IF;

  IF v_task_id IS NULL THEN
    UPDATE public.scheduled_tasks st
    SET scheduled_for = v_now,
        window_start = v_now - INTERVAL '5 minutes',
        window_end = v_now + INTERVAL '12 hours',
        status = 'scheduled',
        completed_at = NULL
    WHERE st.enrollment_id = v_enrollment.id
      AND st.task_key = 'lm_1khz_v1'
      AND st.day_index = -1
      AND st.slot_index = 0
      AND st.status <> 'completed'
    RETURNING st.id INTO v_task_id;
  END IF;

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
      'lm_1khz_v1',
      1,
      v_now,
      v_now - INTERVAL '5 minutes',
      v_now + INTERVAL '12 hours',
      'scheduled',
      -1,
      0
    )
    ON CONFLICT (enrollment_id, day_index, slot_index) DO UPDATE
    SET scheduled_for = EXCLUDED.scheduled_for,
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
      AND st.task_key = 'lm_1khz_v1'
      AND st.day_index = -1
      AND st.slot_index = 0
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
         AND st.task_key = 'lm_1khz_v1'
         AND st.day_index = -1
         AND st.slot_index = 0
         AND st.status = 'completed'
         AND tr.run_status = 'completed'
     ) THEN
    RAISE EXCEPTION 'Complete the Study No. 1 onboarding loudness task before finishing onboarding.';
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

  FOR v_day_index IN 0..6 LOOP
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
        'lm_1khz_v1',
        1,
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

REVOKE ALL ON FUNCTION public.begin_study_no_1_onboarding_loudness_task(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.begin_study_no_1_onboarding_loudness_task(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.complete_study_no_1_onboarding(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.complete_study_no_1_onboarding(uuid, text) TO authenticated;
