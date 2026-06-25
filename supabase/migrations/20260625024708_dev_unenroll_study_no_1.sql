-- Developer-only Study No. 1 unenrollment and data cleanup.
--
-- This keeps the reset behind the existing developer_accounts allow-list and is
-- intended for non-production testing workflows.

DROP POLICY IF EXISTS study_consents_objects_dev_delete_own ON storage.objects;
CREATE POLICY study_consents_objects_dev_delete_own
ON storage.objects
FOR DELETE
TO authenticated
USING (
  bucket_id = 'study-consents'
  AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
  AND EXISTS (
    SELECT 1
    FROM public.developer_accounts da
    WHERE da.user_id = (SELECT auth.uid())
      AND da.enabled = true
  )
);

CREATE OR REPLACE FUNCTION public.dev_study_no_1_consent_pdf_paths()
RETURNS TABLE (
  path text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid := public.assert_current_user_is_developer();
  v_study_id uuid;
BEGIN
  SELECT s.id
  INTO v_study_id
  FROM public.studies s
  WHERE s.slug = 'study-no-1';

  IF v_study_id IS NULL THEN
    RAISE EXCEPTION 'Study No. 1 was not found.';
  END IF;

  RETURN QUERY
  SELECT DISTINCT c.consent_pdf_path
  FROM public.consents c
  WHERE c.user_id = v_user_id
    AND c.study_id = v_study_id
    AND c.consent_pdf_bucket = 'study-consents'
    AND c.consent_pdf_path IS NOT NULL
  ORDER BY c.consent_pdf_path;
END;
$$;

CREATE OR REPLACE FUNCTION public.dev_unenroll_study_no_1()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid := public.assert_current_user_is_developer();
  v_study_id uuid;
  v_storage_prefix text;
BEGIN
  SELECT s.id
  INTO v_study_id
  FROM public.studies s
  WHERE s.slug = 'study-no-1';

  IF v_study_id IS NULL THEN
    RAISE EXCEPTION 'Study No. 1 was not found.';
  END IF;

  DELETE FROM public.task_runs tr
  USING public.study_enrollments se
  WHERE tr.enrollment_id = se.id
    AND tr.user_id = v_user_id
    AND se.user_id = v_user_id
    AND se.study_id = v_study_id;

  DELETE FROM public.scheduled_tasks st
  USING public.study_enrollments se
  WHERE st.enrollment_id = se.id
    AND se.user_id = v_user_id
    AND se.study_id = v_study_id;

  DELETE FROM public.study_enrollments se
  WHERE se.user_id = v_user_id
    AND se.study_id = v_study_id;

  DELETE FROM public.consents c
  WHERE c.user_id = v_user_id
    AND c.study_id = v_study_id;

  -- Storage API deletion should remove the PDFs before this RPC runs. This is
  -- a metadata cleanup fallback for interrupted or older test runs.
  v_storage_prefix := lower(v_user_id::text) || '/' || lower(v_study_id::text) || '/';
  PERFORM set_config('storage.allow_delete_query', 'true', true);

  DELETE FROM storage.objects so
  WHERE so.bucket_id = 'study-consents'
    AND so.name LIKE v_storage_prefix || '%';
END;
$$;

REVOKE ALL ON FUNCTION public.dev_study_no_1_consent_pdf_paths() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.dev_study_no_1_consent_pdf_paths() FROM anon;
REVOKE ALL ON FUNCTION public.dev_unenroll_study_no_1() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.dev_unenroll_study_no_1() FROM anon;

GRANT EXECUTE ON FUNCTION public.dev_study_no_1_consent_pdf_paths() TO authenticated;
GRANT EXECUTE ON FUNCTION public.dev_unenroll_study_no_1() TO authenticated;
