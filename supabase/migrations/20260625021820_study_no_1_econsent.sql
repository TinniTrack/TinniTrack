-- Study No. 1 eConsent persistence, private PDF storage, and validated enrollment.

ALTER TABLE public.consents ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.consents
  ADD COLUMN IF NOT EXISTS signer_given_name text,
  ADD COLUMN IF NOT EXISTS signer_family_name text,
  ADD COLUMN IF NOT EXISTS consent_pdf_bucket text,
  ADD COLUMN IF NOT EXISTS consent_pdf_sha256 text,
  ADD COLUMN IF NOT EXISTS researchkit_task_identifier text,
  ADD COLUMN IF NOT EXISTS researchkit_finish_state text,
  ADD COLUMN IF NOT EXISTS app_version text,
  ADD COLUMN IF NOT EXISTS device_info jsonb,
  ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();

UPDATE public.consents
SET consent_pdf_bucket = 'study-consents'
WHERE consent_pdf_bucket IS NULL;

UPDATE public.consents
SET consent_pdf_sha256 = repeat('0', 64)
WHERE consent_pdf_sha256 IS NULL;

ALTER TABLE public.consents
  ALTER COLUMN user_id SET NOT NULL,
  ALTER COLUMN study_id SET NOT NULL,
  ALTER COLUMN consent_version SET NOT NULL,
  ALTER COLUMN signed_at SET NOT NULL,
  ALTER COLUMN consent_pdf_path SET NOT NULL,
  ALTER COLUMN consent_pdf_bucket SET NOT NULL,
  ALTER COLUMN consent_pdf_sha256 SET NOT NULL,
  ALTER COLUMN device_info SET DEFAULT '{}'::jsonb;

ALTER TABLE public.consents
  DROP CONSTRAINT IF EXISTS consents_pdf_sha256_hex_check,
  ADD CONSTRAINT consents_pdf_sha256_hex_check
    CHECK (consent_pdf_sha256 ~ '^[0-9a-f]{64}$');

ALTER TABLE public.consents
  DROP CONSTRAINT IF EXISTS consents_pdf_bucket_check,
  ADD CONSTRAINT consents_pdf_bucket_check
    CHECK (consent_pdf_bucket = 'study-consents');

CREATE INDEX IF NOT EXISTS consents_user_study_version_idx
ON public.consents (user_id, study_id, consent_version);

CREATE INDEX IF NOT EXISTS consents_signed_at_idx
ON public.consents (signed_at DESC);

REVOKE ALL ON TABLE public.consents FROM anon;
REVOKE UPDATE, DELETE ON TABLE public.consents FROM authenticated;
GRANT SELECT, INSERT ON TABLE public.consents TO authenticated;

DROP POLICY IF EXISTS consents_select_own ON public.consents;
CREATE POLICY consents_select_own
ON public.consents
FOR SELECT
TO authenticated
USING ((SELECT auth.uid()) = user_id);

DROP POLICY IF EXISTS consents_insert_own ON public.consents;
CREATE POLICY consents_insert_own
ON public.consents
FOR INSERT
TO authenticated
WITH CHECK (
  (SELECT auth.uid()) = user_id
  AND consent_pdf_bucket = 'study-consents'
  AND consent_pdf_path LIKE ((SELECT auth.uid())::text || '/%')
);

INSERT INTO storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
VALUES (
  'study-consents',
  'study-consents',
  false,
  10485760,
  ARRAY['application/pdf']
)
ON CONFLICT (id) DO UPDATE
SET
  public = false,
  file_size_limit = 10485760,
  allowed_mime_types = ARRAY['application/pdf'];

DROP POLICY IF EXISTS study_consents_objects_select_own ON storage.objects;
CREATE POLICY study_consents_objects_select_own
ON storage.objects
FOR SELECT
TO authenticated
USING (
  bucket_id = 'study-consents'
  AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
);

DROP POLICY IF EXISTS study_consents_objects_insert_own ON storage.objects;
CREATE POLICY study_consents_objects_insert_own
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'study-consents'
  AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
  AND lower(name) LIKE '%.pdf'
);

CREATE OR REPLACE FUNCTION public.enroll_in_study_after_consent(
  p_study_id uuid,
  p_consent_id uuid
)
RETURNS public.study_enrollments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, storage
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_consent public.consents%ROWTYPE;
  v_enrollment public.study_enrollments%ROWTYPE;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication is required to enroll in a study.';
  END IF;

  PERFORM 1
  FROM public.studies s
  WHERE s.id = p_study_id
    AND s.slug = 'study-no-1'
    AND s.status = 'recruiting';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Study is not currently recruiting.';
  END IF;

  SELECT *
  INTO v_consent
  FROM public.consents
  WHERE id = p_consent_id
    AND user_id = v_user_id
    AND study_id = p_study_id
    AND consent_version = 'study-no-1-consent-v1'
    AND consent_pdf_bucket = 'study-consents'
    AND consent_pdf_sha256 ~ '^[0-9a-f]{64}$';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'A valid signed consent is required before enrollment.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM storage.objects so
    WHERE so.bucket_id = v_consent.consent_pdf_bucket
      AND so.name = v_consent.consent_pdf_path
  ) THEN
    RAISE EXCEPTION 'Signed consent PDF was not found in storage.';
  END IF;

  INSERT INTO public.study_enrollments (
    user_id,
    study_id,
    status,
    enrolled_at
  )
  VALUES (
    v_user_id,
    p_study_id,
    'enrolled',
    now()
  )
  ON CONFLICT (user_id, study_id) DO UPDATE
  SET
    status = 'enrolled',
    enrolled_at = now()
  RETURNING *
  INTO v_enrollment;

  RETURN v_enrollment;
END;
$$;

REVOKE ALL ON FUNCTION public.enroll_in_study_after_consent(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.enroll_in_study_after_consent(uuid, uuid) TO authenticated;

-- Preserve the existing Study No. 1 orientation flow while fixing the same
-- ambiguous ON CONFLICT lint issue previously fixed for the threshold task.
CREATE OR REPLACE FUNCTION public.begin_study_no_1_onboarding_loudness_task(
  p_enrollment_id uuid
)
RETURNS TABLE (
  id uuid,
  enrollment_id uuid,
  task_key text,
  task_version int,
  scheduled_for timestamptz,
  window_start timestamptz,
  window_end timestamptz,
  status text,
  day_index int,
  slot_index int,
  completed_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_enrollment public.study_enrollments%ROWTYPE;
  v_now timestamptz := NOW();
  v_task_id uuid;
BEGIN
  SELECT se.*
  INTO v_enrollment
  FROM public.study_enrollments se
  JOIN public.studies s ON s.id = se.study_id
  WHERE se.id = p_enrollment_id
    AND se.user_id = auth.uid()
    AND se.status = 'enrolled'
    AND s.slug = 'study-no-1'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Enrollment is not eligible for Study No. 1 onboarding.';
  END IF;

  IF v_enrollment.onboarding_completed_at IS NOT NULL THEN
    RAISE EXCEPTION 'Study No. 1 onboarding is already complete.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.audiograms a
    WHERE a.user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Import an Apple hearing test before starting the onboarding loudness task.';
  END IF;

  SELECT st.id
  INTO v_task_id
  FROM public.scheduled_tasks st
  WHERE st.enrollment_id = v_enrollment.id
    AND st.task_key = 'lm_1khz_v1'
    AND st.day_index = -1
    AND st.slot_index = 0
    AND st.status = 'scheduled'
    AND st.window_end > v_now
  ORDER BY st.created_at DESC
  LIMIT 1
  FOR UPDATE;

  IF v_task_id IS NULL THEN
    SELECT st.id
    INTO v_task_id
    FROM public.scheduled_tasks st
    WHERE st.enrollment_id = v_enrollment.id
      AND st.task_key = 'lm_1khz_v1'
      AND st.day_index = -1
      AND st.slot_index = 0
      AND st.status = 'completed'
    ORDER BY st.completed_at DESC NULLS LAST, st.created_at DESC
    LIMIT 1
    FOR UPDATE;
  END IF;

  IF v_task_id IS NULL THEN
    UPDATE public.scheduled_tasks st
    SET scheduled_for = v_now,
        window_start = v_now - INTERVAL '5 minutes',
        window_end = v_now + INTERVAL '12 hours',
        status = 'scheduled',
        completed_at = NULL
    WHERE st.enrollment_id = v_enrollment.id
      AND st.task_key = 'lm_1khz_v1'
      AND st.day_index = -1
      AND st.slot_index = 0
      AND st.status <> 'completed'
    RETURNING st.id INTO v_task_id;
  END IF;

  IF v_task_id IS NULL THEN
    INSERT INTO public.scheduled_tasks (
      enrollment_id,
      task_key,
      task_version,
      scheduled_for,
      window_start,
      window_end,
      status,
      day_index,
      slot_index
    ) VALUES (
      v_enrollment.id,
      'lm_1khz_v1',
      1,
      v_now,
      v_now - INTERVAL '5 minutes',
      v_now + INTERVAL '12 hours',
      'scheduled',
      -1,
      0
    )
    ON CONFLICT ON CONSTRAINT scheduled_tasks_unique_slot DO UPDATE
    SET task_key = EXCLUDED.task_key,
        task_version = EXCLUDED.task_version,
        scheduled_for = EXCLUDED.scheduled_for,
        window_start = EXCLUDED.window_start,
        window_end = EXCLUDED.window_end,
        status = EXCLUDED.status,
        completed_at = NULL
    WHERE scheduled_tasks.status <> 'completed'
    RETURNING public.scheduled_tasks.id INTO v_task_id;
  END IF;

  IF v_task_id IS NULL THEN
    SELECT st.id
    INTO v_task_id
    FROM public.scheduled_tasks st
    WHERE st.enrollment_id = v_enrollment.id
      AND st.task_key = 'lm_1khz_v1'
      AND st.day_index = -1
      AND st.slot_index = 0
      AND st.status = 'completed'
    ORDER BY st.completed_at DESC NULLS LAST, st.created_at DESC
    LIMIT 1;
  END IF;

  RETURN QUERY
  SELECT
    st.id,
    st.enrollment_id,
    st.task_key,
    st.task_version,
    st.scheduled_for,
    st.window_start,
    st.window_end,
    st.status,
    st.day_index,
    st.slot_index,
    st.completed_at
  FROM public.scheduled_tasks st
  WHERE st.id = v_task_id;
END;
$$;
