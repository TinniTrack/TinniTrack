-- Fix developer-only Storage deletes for Study No. 1 consent PDFs.
--
-- Storage RLS policies run as the authenticated caller, so directly querying
-- developer_accounts from the policy fails because that table intentionally has
-- no authenticated SELECT grant. Keep the table hidden and expose only the
-- allow-list boolean needed by Storage policy evaluation in a non-API schema.

CREATE SCHEMA IF NOT EXISTS private;

REVOKE ALL ON SCHEMA private FROM PUBLIC;
REVOKE ALL ON SCHEMA private FROM anon;
GRANT USAGE ON SCHEMA private TO authenticated;

CREATE OR REPLACE FUNCTION private.current_user_is_developer()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT COALESCE(
    EXISTS (
      SELECT 1
      FROM public.developer_accounts da
      WHERE da.user_id = (SELECT auth.uid())
        AND da.enabled = true
    ),
    false
  );
$$;

REVOKE ALL ON FUNCTION private.current_user_is_developer() FROM PUBLIC;
REVOKE ALL ON FUNCTION private.current_user_is_developer() FROM anon;
GRANT EXECUTE ON FUNCTION private.current_user_is_developer() TO authenticated;

DROP POLICY IF EXISTS study_consents_objects_dev_delete_own ON storage.objects;
CREATE POLICY study_consents_objects_dev_delete_own
ON storage.objects
FOR DELETE
TO authenticated
USING (
  bucket_id = 'study-consents'
  AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
  AND private.current_user_is_developer()
);

DROP FUNCTION IF EXISTS public.current_user_is_developer();
