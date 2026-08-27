-- Attach the ownership-lineage indexes prepared by the prior migration, then
-- enforce and validate the composite relationships. Keeping this transactional
-- phase separate means a short lock timeout can be retried without rebuilding
-- already-completed indexes.

SET lock_timeout = '5s';

-- Attach the prepared unique indexes as exact referenced keys.
-- Enrollment comes first to match the lock order used by onboarding workflows.
ALTER TABLE public.study_enrollments
  ADD CONSTRAINT study_enrollments_id_user_id_key
  UNIQUE USING INDEX study_enrollments_id_user_id_key;

ALTER TABLE public.scheduled_tasks
  ADD CONSTRAINT scheduled_tasks_id_enrollment_id_key
  UNIQUE USING INDEX scheduled_tasks_id_enrollment_id_key;

-- NOT VALID avoids a blocking validation scan while the constraints are
-- installed. New writes are checked immediately; existing rows are validated
-- in the following online scans.
ALTER TABLE public.task_runs
  ADD CONSTRAINT task_runs_enrollment_user_fkey
  FOREIGN KEY (enrollment_id, user_id)
  REFERENCES public.study_enrollments (id, user_id)
  ON DELETE CASCADE
  NOT VALID;

ALTER TABLE public.task_runs
  ADD CONSTRAINT task_runs_scheduled_task_enrollment_fkey
  FOREIGN KEY (scheduled_task_id, enrollment_id)
  REFERENCES public.scheduled_tasks (id, enrollment_id)
  ON DELETE CASCADE
  NOT VALID;

ALTER TABLE public.task_runs
  VALIDATE CONSTRAINT task_runs_enrollment_user_fkey;

ALTER TABLE public.task_runs
  VALIDATE CONSTRAINT task_runs_scheduled_task_enrollment_fkey;

-- The composite constraints fully subsume these original single-column FKs.
-- Removing them avoids duplicate cascade triggers and ambiguous PostgREST
-- relationships between the same tables.
ALTER TABLE public.task_runs
  DROP CONSTRAINT task_runs_enrollment_id_fkey,
  DROP CONSTRAINT task_runs_scheduled_task_id_fkey;

RESET lock_timeout;
