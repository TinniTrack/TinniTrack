-- Participant workflow state is server-managed. Clients may read their own
-- rows through RLS, but all enrollment, scheduling, and task-run mutations
-- must go through the validated RPCs below.

ALTER TABLE public.study_enrollments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.scheduled_tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.task_runs ENABLE ROW LEVEL SECURITY;

REVOKE ALL PRIVILEGES
ON TABLE
  public.study_enrollments,
  public.scheduled_tasks,
  public.task_runs
FROM PUBLIC, anon, authenticated;

GRANT SELECT
ON TABLE
  public.study_enrollments,
  public.scheduled_tasks,
  public.task_runs
TO authenticated;

DROP POLICY IF EXISTS study_enrollments_insert_own ON public.study_enrollments;
DROP POLICY IF EXISTS study_enrollments_update_own ON public.study_enrollments;
DROP POLICY IF EXISTS scheduled_tasks_insert_own ON public.scheduled_tasks;
DROP POLICY IF EXISTS scheduled_tasks_update_own ON public.scheduled_tasks;
DROP POLICY IF EXISTS task_runs_insert_own ON public.task_runs;
DROP POLICY IF EXISTS task_runs_update_own ON public.task_runs;

-- Reassert the intended public API after removing direct table mutations.
-- These functions validate auth.uid() and perform their writes as their owner.
REVOKE ALL ON FUNCTION public.enroll_in_study_after_consent(uuid, uuid)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.enroll_in_study_after_consent(uuid, uuid)
TO authenticated;

REVOKE ALL ON FUNCTION public.begin_study_no_1_orientation_threshold_task(uuid)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.begin_study_no_1_orientation_threshold_task(uuid)
TO authenticated;

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
)
FROM PUBLIC, anon;
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
)
TO authenticated;

REVOKE ALL ON FUNCTION public.complete_study_no_1_onboarding(uuid, text)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.complete_study_no_1_onboarding(uuid, text)
TO authenticated;

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
)
FROM PUBLIC, anon;
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
)
TO authenticated;
