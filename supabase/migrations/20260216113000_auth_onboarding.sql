-- V1 auth + onboarding hardening
-- Keeps migration idempotent for local/remote schema drift.

ALTER TABLE public.profiles
  DROP COLUMN IF EXISTS biological_sex;

ALTER TABLE public.profiles
  ALTER COLUMN first_name DROP NOT NULL,
  ALTER COLUMN last_name DROP NOT NULL,
  ALTER COLUMN date_of_birth DROP NOT NULL;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS onboarding_completed_at timestamptz;

ALTER TABLE public.profiles
  DROP CONSTRAINT IF EXISTS profiles_onboarding_completed_requires_required_fields_check;

ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_onboarding_completed_requires_required_fields_check
  CHECK (
    onboarding_completed_at IS NULL
    OR (
      first_name IS NOT NULL
      AND last_name IS NOT NULL
      AND date_of_birth IS NOT NULL
    )
  );

CREATE OR REPLACE FUNCTION public.handle_new_user_profile()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  metadata jsonb := COALESCE(NEW.raw_user_meta_data, '{}'::jsonb);
  metadata_first_name text := NULLIF(BTRIM(metadata ->> 'first_name'), '');
  metadata_last_name text := NULLIF(BTRIM(metadata ->> 'last_name'), '');
  metadata_date_of_birth date;
BEGIN
  IF NULLIF(metadata ->> 'date_of_birth', '') IS NOT NULL THEN
    BEGIN
      metadata_date_of_birth := (metadata ->> 'date_of_birth')::date;
    EXCEPTION
      WHEN OTHERS THEN
        metadata_date_of_birth := NULL;
    END;
  END IF;

  INSERT INTO public.profiles (
    id,
    first_name,
    last_name,
    date_of_birth,
    onboarding_completed_at
  ) VALUES (
    NEW.id,
    metadata_first_name,
    metadata_last_name,
    metadata_date_of_birth,
    CASE
      WHEN metadata_first_name IS NOT NULL
        AND metadata_last_name IS NOT NULL
        AND metadata_date_of_birth IS NOT NULL
      THEN NOW()
      ELSE NULL
    END
  )
  ON CONFLICT (id) DO NOTHING;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user_profile();

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS profiles_select_own ON public.profiles;
CREATE POLICY profiles_select_own
ON public.profiles
FOR SELECT
USING (id = auth.uid());

DROP POLICY IF EXISTS profiles_insert_own ON public.profiles;
CREATE POLICY profiles_insert_own
ON public.profiles
FOR INSERT
WITH CHECK (id = auth.uid());

DROP POLICY IF EXISTS profiles_update_own ON public.profiles;
CREATE POLICY profiles_update_own
ON public.profiles
FOR UPDATE
USING (id = auth.uid())
WITH CHECK (id = auth.uid());
