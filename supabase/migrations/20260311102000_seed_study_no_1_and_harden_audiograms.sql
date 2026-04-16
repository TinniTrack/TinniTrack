-- Seed Study No. 1 and do HealthKit audiogram imports.

DELETE FROM public.studies
WHERE slug = 'test-study';

INSERT INTO public.studies (slug, title, description, status)
VALUES (
  'study-no-1',
  'Study No. 1: Audiogram Import and Loudness Match',
  'Import baseline audiogram data from Apple Health, then complete scheduled loudness-matching tasks.',
  'recruiting'
)
ON CONFLICT (slug) DO UPDATE SET
  title = EXCLUDED.title,
  description = EXCLUDED.description,
  status = EXCLUDED.status;

ALTER TABLE public.audiograms
  ADD COLUMN IF NOT EXISTS healthkit_sample_uuid uuid;

ALTER TABLE public.audiograms
  ALTER COLUMN headphone_name DROP NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS audiograms_user_healthkit_sample_uuid_key
ON public.audiograms (user_id, healthkit_sample_uuid)
WHERE healthkit_sample_uuid IS NOT NULL;

ALTER TABLE public.audiograms ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS audiograms_select_own ON public.audiograms;
CREATE POLICY audiograms_select_own
ON public.audiograms
FOR SELECT
USING (user_id = auth.uid());

DROP POLICY IF EXISTS audiograms_insert_own ON public.audiograms;
CREATE POLICY audiograms_insert_own
ON public.audiograms
FOR INSERT
WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS audiograms_update_own ON public.audiograms;
CREATE POLICY audiograms_update_own
ON public.audiograms
FOR UPDATE
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());
