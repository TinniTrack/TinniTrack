-- Developer-only reset/replay tooling.
--
-- The allow-list is intentionally empty after migration. Add developer users
-- only in non-production Supabase projects with an admin/service context:
--
--   insert into public.developer_accounts (user_id, note)
--   values ('<auth.users.id>', 'device testing');

CREATE TABLE IF NOT EXISTS public.developer_accounts (
  user_id    uuid PRIMARY KEY
    REFERENCES auth.users (id)
    ON DELETE CASCADE,
  enabled    boolean NOT NULL DEFAULT true,
  note       text,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.developer_accounts ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.developer_accounts FROM PUBLIC;
REVOKE ALL ON TABLE public.developer_accounts FROM anon;
REVOKE ALL ON TABLE public.developer_accounts FROM authenticated;

CREATE OR REPLACE FUNCTION public.assert_current_user_is_developer()
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Developer tooling requires an authenticated user.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.developer_accounts da
    WHERE da.user_id = v_user_id
      AND da.enabled = true
  ) THEN
    RAISE EXCEPTION 'Developer tooling is not enabled for this account.';
  END IF;

  RETURN v_user_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.dev_reset_profile_onboarding()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid := public.assert_current_user_is_developer();
BEGIN
  UPDATE public.profiles
  SET first_name = NULL,
      last_name = NULL,
      date_of_birth = NULL,
      onboarding_completed_at = NULL
  WHERE id = v_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No profile found for current user.';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.dev_reset_study_no_1_orientation()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid := public.assert_current_user_is_developer();
  v_enrollment_id uuid;
BEGIN
  SELECT se.id
  INTO v_enrollment_id
  FROM public.study_enrollments se
  JOIN public.studies s ON s.id = se.study_id
  WHERE se.user_id = v_user_id
    AND se.status = 'enrolled'
    AND s.slug = 'study-no-1'
  ORDER BY se.enrolled_at DESC
  LIMIT 1
  FOR UPDATE OF se;

  IF v_enrollment_id IS NULL THEN
    RAISE EXCEPTION 'No active Study No. 1 enrollment found for current user.';
  END IF;

  DELETE FROM public.scheduled_tasks
  WHERE enrollment_id = v_enrollment_id;

  UPDATE public.study_enrollments
  SET onboarding_completed_at = NULL
  WHERE id = v_enrollment_id
    AND user_id = v_user_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.dev_make_next_loudness_match_available_now()
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid := public.assert_current_user_is_developer();
  v_task_id uuid;
BEGIN
  SELECT st.id
  INTO v_task_id
  FROM public.scheduled_tasks st
  JOIN public.study_enrollments se ON se.id = st.enrollment_id
  JOIN public.studies s ON s.id = se.study_id
  WHERE se.user_id = v_user_id
    AND se.status = 'enrolled'
    AND s.slug = 'study-no-1'
    AND st.task_key = 'lm_1khz_v1'
    AND st.status = 'scheduled'
  ORDER BY st.scheduled_for ASC
  LIMIT 1
  FOR UPDATE OF st;

  IF v_task_id IS NULL THEN
    RAISE EXCEPTION 'No scheduled loudness-match task found for current user.';
  END IF;

  UPDATE public.scheduled_tasks
  SET scheduled_for = now(),
      window_start = now() - INTERVAL '5 minutes',
      window_end = now() + INTERVAL '60 minutes'
  WHERE id = v_task_id;

  RETURN v_task_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.dev_reopen_last_completed_loudness_match()
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid := public.assert_current_user_is_developer();
  v_task_id uuid;
BEGIN
  SELECT st.id
  INTO v_task_id
  FROM public.scheduled_tasks st
  JOIN public.study_enrollments se ON se.id = st.enrollment_id
  JOIN public.studies s ON s.id = se.study_id
  WHERE se.user_id = v_user_id
    AND se.status = 'enrolled'
    AND s.slug = 'study-no-1'
    AND st.task_key = 'lm_1khz_v1'
    AND st.status = 'completed'
  ORDER BY COALESCE(st.completed_at, st.scheduled_for) DESC
  LIMIT 1
  FOR UPDATE OF st;

  IF v_task_id IS NULL THEN
    RAISE EXCEPTION 'No completed loudness-match task found for current user.';
  END IF;

  DELETE FROM public.task_runs
  WHERE scheduled_task_id = v_task_id
    AND user_id = v_user_id;

  UPDATE public.scheduled_tasks
  SET status = 'scheduled',
      completed_at = NULL,
      scheduled_for = now(),
      window_start = now() - INTERVAL '5 minutes',
      window_end = now() + INTERVAL '60 minutes'
  WHERE id = v_task_id;

  RETURN v_task_id;
END;
$$;

REVOKE ALL ON FUNCTION public.assert_current_user_is_developer() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.assert_current_user_is_developer() FROM anon;
REVOKE ALL ON FUNCTION public.assert_current_user_is_developer() FROM authenticated;

REVOKE ALL ON FUNCTION public.dev_reset_profile_onboarding() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.dev_reset_study_no_1_orientation() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.dev_make_next_loudness_match_available_now() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.dev_reopen_last_completed_loudness_match() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.dev_reset_profile_onboarding() TO authenticated;
GRANT EXECUTE ON FUNCTION public.dev_reset_study_no_1_orientation() TO authenticated;
GRANT EXECUTE ON FUNCTION public.dev_make_next_loudness_match_available_now() TO authenticated;
GRANT EXECUTE ON FUNCTION public.dev_reopen_last_completed_loudness_match() TO authenticated;
