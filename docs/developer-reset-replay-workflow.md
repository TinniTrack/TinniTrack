# Developer Reset and Replay Workflow

Use the hosted development Supabase project for normal simulator and device testing. The checked-in `TinniTrack Development` scheme uses the `Debug Development` build configuration, which points at that hosted development project for both local simulator runs and development-device testing.

Expected app configuration:

- `SUPABASE_URL`: hosted development Supabase project URL
- `SUPABASE_ANON_KEY`: hosted development project publishable or anon key
- `SUPABASE_ENVIRONMENT`: `Development`

Do not use a service-role key in the app. Developer reset/replay RPCs are disabled until an admin explicitly allow-lists a user in the target database:

```sql
insert into public.developer_accounts (user_id, note)
values ('<auth.users.id>', 'device testing');
```

## Manual SQL Verification

Run these checks in a non-production database after applying migrations.

```sql
-- As a normal authenticated user who is not allow-listed:
select public.dev_reset_profile_onboarding();
-- Expected: Developer tooling is not enabled for this account.

-- As an allow-listed developer:
select public.dev_reset_profile_onboarding();
-- Expected: only public.profiles.id = auth.uid() has onboarding fields cleared.

select public.dev_reset_study_no_1_orientation();
-- Expected: only the current user's Study No. 1 enrollment has onboarding_completed_at cleared,
-- and only that enrollment's scheduled_tasks are removed.

select public.dev_make_next_loudness_match_available_now();
-- Expected: returns the current user's next scheduled lm_1khz_v1 task id and moves its window to now.

select public.dev_reopen_last_completed_loudness_match();
-- Expected: returns the current user's latest completed lm_1khz_v1 task id, removes that task's
-- current-user task_runs, and reopens the task window.

-- Ownership spot-check: after each developer RPC, confirm no rows owned by another user changed.
select se.user_id, st.id, st.status, st.window_start, st.window_end
from public.scheduled_tasks st
join public.study_enrollments se on se.id = st.enrollment_id
where se.user_id <> auth.uid()
order by st.scheduled_for;
```
