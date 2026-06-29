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
    ON CONFLICT ON CONSTRAINT scheduled_tasks_unique_slot DO UPDATE
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

REVOKE ALL ON FUNCTION public.begin_study_no_1_orientation_threshold_task(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.begin_study_no_1_orientation_threshold_task(uuid) TO authenticated;
