-- Supabase-managed default privileges can grant EXECUTE directly to anon,
-- so revoking PUBLIC alone does not fully close a SECURITY DEFINER RPC.
-- Keep the participant/developer RPCs available to signed-in users while
-- removing every unauthenticated (anon role) execution path.

REVOKE ALL ON FUNCTION public.begin_study_no_1_onboarding_loudness_task(uuid)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.begin_study_no_1_onboarding_loudness_task(uuid)
TO authenticated;

REVOKE ALL ON FUNCTION public.dev_reset_profile_onboarding()
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.dev_reset_profile_onboarding()
TO authenticated;

REVOKE ALL ON FUNCTION public.dev_reset_study_no_1_orientation()
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.dev_reset_study_no_1_orientation()
TO authenticated;

REVOKE ALL ON FUNCTION public.dev_make_next_loudness_match_available_now()
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.dev_make_next_loudness_match_available_now()
TO authenticated;

REVOKE ALL ON FUNCTION public.dev_reopen_last_completed_loudness_match()
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.dev_reopen_last_completed_loudness_match()
TO authenticated;

-- This function is invoked only by the on_auth_user_created database trigger.
-- Client roles do not need permission to call it through the Data API.
REVOKE ALL ON FUNCTION public.handle_new_user_profile()
FROM PUBLIC, anon, authenticated;
