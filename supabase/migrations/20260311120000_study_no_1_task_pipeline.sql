-- Study No. 1 task pipeline
-- Adds enrollment onboarding completion, task RLS, and RPCs for
-- schedule generation + loudness-match submission.

ALTER TABLE public.study_enrollments
  ADD COLUMN IF NOT EXISTS onboarding_completed_at timestamptz;

CREATE INDEX IF NOT EXISTS scheduled_tasks_enrollment_status_scheduled_for_idx
ON public.scheduled_tasks (enrollment_id, status, scheduled_for);

ALTER TABLE public.study_enrollments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.scheduled_tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.task_runs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS study_enrollments_select_own ON public.study_enrollments;
CREATE POLICY study_enrollments_select_own
ON public.study_enrollments
FOR SELECT
USING (user_id = auth.uid());

DROP POLICY IF EXISTS study_enrollments_insert_own ON public.study_enrollments;
CREATE POLICY study_enrollments_insert_own
ON public.study_enrollments
FOR INSERT
WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS study_enrollments_update_own ON public.study_enrollments;
CREATE POLICY study_enrollments_update_own
ON public.study_enrollments
FOR UPDATE
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS scheduled_tasks_select_own ON public.scheduled_tasks;
CREATE POLICY scheduled_tasks_select_own
ON public.scheduled_tasks
FOR SELECT
USING (
  EXISTS (
    SELECT 1
    FROM public.study_enrollments se
    WHERE se.id = scheduled_tasks.enrollment_id
      AND se.user_id = auth.uid()
  )
);

DROP POLICY IF EXISTS scheduled_tasks_insert_own ON public.scheduled_tasks;
CREATE POLICY scheduled_tasks_insert_own
ON public.scheduled_tasks
FOR INSERT
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.study_enrollments se
    WHERE se.id = scheduled_tasks.enrollment_id
      AND se.user_id = auth.uid()
  )
);

DROP POLICY IF EXISTS scheduled_tasks_update_own ON public.scheduled_tasks;
CREATE POLICY scheduled_tasks_update_own
ON public.scheduled_tasks
FOR UPDATE
USING (
  EXISTS (
    SELECT 1
    FROM public.study_enrollments se
    WHERE se.id = scheduled_tasks.enrollment_id
      AND se.user_id = auth.uid()
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.study_enrollments se
    WHERE se.id = scheduled_tasks.enrollment_id
      AND se.user_id = auth.uid()
  )
);

DROP POLICY IF EXISTS task_runs_select_own ON public.task_runs;
CREATE POLICY task_runs_select_own
ON public.task_runs
FOR SELECT
USING (user_id = auth.uid());

DROP POLICY IF EXISTS task_runs_insert_own ON public.task_runs;
CREATE POLICY task_runs_insert_own
ON public.task_runs
FOR INSERT
WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS task_runs_update_own ON public.task_runs;
CREATE POLICY task_runs_update_own
ON public.task_runs
FOR UPDATE
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

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
  v_day_index int;
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

REVOKE ALL ON FUNCTION public.complete_study_no_1_onboarding(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.complete_study_no_1_onboarding(uuid, text) TO authenticated;

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
