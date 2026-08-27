-- A task run is valid only when its scheduled task belongs to the same
-- enrollment and that enrollment belongs to the same user. Existing
-- single-column foreign keys guarantee that each referenced row exists, but
-- they do not guarantee that the three references describe one lineage.
--
-- If this migration aborts, use this read-only audit query to review every
-- inconsistent row before any approved research-data correction:
--
-- SELECT
--   tr.id AS task_run_id,
--   tr.scheduled_task_id,
--   tr.enrollment_id AS task_run_enrollment_id,
--   st.enrollment_id AS scheduled_task_enrollment_id,
--   tr.user_id AS task_run_user_id,
--   se.user_id AS enrollment_user_id
-- FROM public.task_runs tr
-- LEFT JOIN public.scheduled_tasks st ON st.id = tr.scheduled_task_id
-- LEFT JOIN public.study_enrollments se ON se.id = tr.enrollment_id
-- WHERE st.id IS NULL
--    OR se.id IS NULL
--    OR st.enrollment_id IS DISTINCT FROM tr.enrollment_id
--    OR se.user_id IS DISTINCT FROM tr.user_id
-- ORDER BY tr.id;

SET lock_timeout = '5s';
SET statement_timeout = '30s';

DO $ownership_audit$
DECLARE
  v_invalid_count bigint;
  v_orphan_count bigint;
  v_task_enrollment_mismatch_count bigint;
  v_enrollment_user_mismatch_count bigint;
  v_sample_ids text;
BEGIN
  SELECT
    COUNT(*) FILTER (
      WHERE st.id IS NULL
         OR se.id IS NULL
         OR st.enrollment_id IS DISTINCT FROM tr.enrollment_id
         OR se.user_id IS DISTINCT FROM tr.user_id
    ),
    COUNT(*) FILTER (WHERE st.id IS NULL OR se.id IS NULL),
    COUNT(*) FILTER (
      WHERE st.id IS NOT NULL
        AND st.enrollment_id IS DISTINCT FROM tr.enrollment_id
    ),
    COUNT(*) FILTER (
      WHERE se.id IS NOT NULL
        AND se.user_id IS DISTINCT FROM tr.user_id
    )
  INTO
    v_invalid_count,
    v_orphan_count,
    v_task_enrollment_mismatch_count,
    v_enrollment_user_mismatch_count
  FROM public.task_runs tr
  LEFT JOIN public.scheduled_tasks st ON st.id = tr.scheduled_task_id
  LEFT JOIN public.study_enrollments se ON se.id = tr.enrollment_id;

  IF v_invalid_count > 0 THEN
    SELECT string_agg(invalid.id::text, ', ' ORDER BY invalid.id)
    INTO v_sample_ids
    FROM (
      SELECT tr.id
      FROM public.task_runs tr
      LEFT JOIN public.scheduled_tasks st ON st.id = tr.scheduled_task_id
      LEFT JOIN public.study_enrollments se ON se.id = tr.enrollment_id
      WHERE st.id IS NULL
         OR se.id IS NULL
         OR st.enrollment_id IS DISTINCT FROM tr.enrollment_id
         OR se.user_id IS DISTINCT FROM tr.user_id
      ORDER BY tr.id
      LIMIT 20
    ) AS invalid;

    RAISE EXCEPTION USING
      MESSAGE = format(
        'Task-run ownership integrity precondition failed: %s inconsistent row(s).',
        v_invalid_count
      ),
      DETAIL = format(
        'orphan references=%s; scheduled-task/enrollment mismatches=%s; enrollment/user mismatches=%s; sample task_runs.id values=%s',
        v_orphan_count,
        v_task_enrollment_mismatch_count,
        v_enrollment_user_mismatch_count,
        COALESCE(v_sample_ids, '(none)')
      ),
      HINT = 'Run the read-only audit query documented at the top of this migration; correct research data only through an approved process, then rerun the migration.';
  END IF;
END;
$ownership_audit$;

-- Build the exact parent and child indexes in one transactional phase. These
-- research tables are expected to be small; bounded timeouts make the
-- migration fail and roll back instead of causing an extended write outage if
-- production size or activity is higher than expected. Apply during a
-- low-traffic window. The indexes are not attached to constraints until the
-- later attach_task_run_ownership_constraints migration.
-- Parent indexes are created in enrollment -> scheduled-task order to match
-- the order used by the onboarding workflow.
CREATE UNIQUE INDEX IF NOT EXISTS study_enrollments_id_user_id_key
ON public.study_enrollments (id, user_id);

CREATE UNIQUE INDEX IF NOT EXISTS scheduled_tasks_id_enrollment_id_key
ON public.scheduled_tasks (id, enrollment_id);

-- Postgres does not automatically index the referencing side of foreign keys.
-- These indexes support referential checks/cascades, while the standalone
-- user_id index supports task_runs_select_own RLS filtering.
CREATE INDEX IF NOT EXISTS task_runs_enrollment_user_idx
ON public.task_runs (enrollment_id, user_id);

CREATE INDEX IF NOT EXISTS task_runs_scheduled_task_enrollment_idx
ON public.task_runs (scheduled_task_id, enrollment_id);

CREATE INDEX IF NOT EXISTS task_runs_user_id_idx
ON public.task_runs (user_id);

RESET statement_timeout;
RESET lock_timeout;
