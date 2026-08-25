-- Make consent-enrollment retries audit-preserving. A repeated call returns an
-- already-enrolled row unchanged, including its original enrolled_at value,
-- while terminal enrollment states can never be revived by a retry.

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.consents c
    GROUP BY c.user_id, c.study_id, c.consent_version
    HAVING COUNT(*) > 1
  ) THEN
    RAISE EXCEPTION USING
      MESSAGE = 'Duplicate consent versions must be reconciled before enforcing retry idempotency.',
      HINT = 'Audit public.consents by (user_id, study_id, consent_version); preserve the authoritative signed evidence rather than deleting rows automatically.';
  END IF;
END;
$$;

CREATE UNIQUE INDEX IF NOT EXISTS consents_user_study_version_key
ON public.consents (user_id, study_id, consent_version);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint c
    WHERE c.conrelid = 'public.consents'::regclass
      AND c.conname = 'consents_user_study_version_key'
  ) THEN
    ALTER TABLE public.consents
      ADD CONSTRAINT consents_user_study_version_key
      UNIQUE USING INDEX consents_user_study_version_key;
  END IF;
END;
$$;

DROP INDEX IF EXISTS public.consents_user_study_version_idx;

ALTER TABLE public.study_enrollments
  ADD COLUMN IF NOT EXISTS eligibility_snapshot jsonb;

ALTER TABLE public.study_enrollments
  DROP CONSTRAINT IF EXISTS study_enrollments_eligibility_snapshot_object_check,
  ADD CONSTRAINT study_enrollments_eligibility_snapshot_object_check
    CHECK (
      eligibility_snapshot IS NULL
      OR jsonb_typeof(eligibility_snapshot) = 'object'
    )
    NOT VALID;

ALTER TABLE public.study_enrollments
  VALIDATE CONSTRAINT study_enrollments_eligibility_snapshot_object_check;

COMMENT ON COLUMN public.study_enrollments.eligibility_snapshot IS
  'Eligibility evidence captured by the trusted enrollment RPC. Legacy rows remain null rather than fabricating retrospective evidence.';

CREATE OR REPLACE FUNCTION public.enroll_in_study_after_consent(
  p_study_id uuid,
  p_consent_id uuid
)
RETURNS public.study_enrollments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_consent public.consents%ROWTYPE;
  v_enrollment public.study_enrollments%ROWTYPE;
  v_profile public.profiles%ROWTYPE;
  v_eligibility_evaluated_at timestamptz := NOW();
  v_eligibility_date date;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication is required to enroll in a study.';
  END IF;

  SELECT *
  INTO v_consent
  FROM public.consents
  WHERE id = p_consent_id
    AND user_id = v_user_id
    AND study_id = p_study_id
    AND consent_version = 'study-no-1-consent-v2'
    AND consent_pdf_bucket = 'study-consents'
    AND consent_pdf_sha256 ~ '^[0-9a-f]{64}$'
    AND consent_content_sha256 ~ '^[0-9a-f]{64}$'
    AND signature_image_sha256 ~ '^[0-9a-f]{64}$'
    AND collection_method = 'native_swiftui_v2'
    AND NULLIF(BTRIM(attestation_text), '') IS NOT NULL
    AND NULLIF(BTRIM(attestation_version), '') IS NOT NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'A valid signed native consent is required before enrollment.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM storage.objects so
    WHERE so.bucket_id = v_consent.consent_pdf_bucket
      AND so.name = v_consent.consent_pdf_path
  ) THEN
    RAISE EXCEPTION 'Signed consent PDF was not found in storage.';
  END IF;

  SELECT se.*
  INTO v_enrollment
  FROM public.study_enrollments se
  WHERE se.user_id = v_user_id
    AND se.study_id = p_study_id
  FOR UPDATE;

  IF FOUND THEN
    IF v_enrollment.status <> 'enrolled' THEN
      RAISE EXCEPTION USING
        MESSAGE = 'An existing terminal enrollment cannot be reactivated by a consent retry.',
        DETAIL = format('Current enrollment status: %s', v_enrollment.status);
    END IF;

    RETURN v_enrollment;
  END IF;

  -- Use an explicit UTC eligibility date until the study protocol defines a
  -- different authoritative timezone. Lock the source row through insertion
  -- and snapshot the exact facts used by this decision.
  v_eligibility_date := (
    v_eligibility_evaluated_at AT TIME ZONE 'UTC'
  )::date;

  SELECT p.*
  INTO v_profile
  FROM public.profiles p
  WHERE p.id = v_user_id
  FOR SHARE;

  IF NOT FOUND
     OR v_profile.date_of_birth IS NULL
     OR v_profile.date_of_birth > (
       v_eligibility_date - INTERVAL '18 years'
     )::date THEN
    RAISE EXCEPTION 'Participants must be 18 years or older to enroll in Study No. 1.';
  END IF;

  -- Recruitment status gates only a new enrollment. An idempotent retry of an
  -- existing enrollment remains valid if recruitment closes afterward.
  PERFORM 1
  FROM public.studies s
  WHERE s.id = p_study_id
    AND s.slug = 'study-no-1'
    AND s.status = 'recruiting'
  FOR SHARE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Study is not currently recruiting.';
  END IF;

  INSERT INTO public.study_enrollments (
    user_id,
    study_id,
    status,
    enrolled_at,
    eligibility_snapshot
  )
  VALUES (
    v_user_id,
    p_study_id,
    'enrolled',
    v_eligibility_evaluated_at,
    jsonb_build_object(
      'schema_version', 1,
      'study_slug', 'study-no-1',
      'consent_id', p_consent_id,
      'minimum_age_years', 18,
      'profile_date_of_birth', v_profile.date_of_birth,
      'eligibility_evaluated_at', v_eligibility_evaluated_at,
      'eligibility_date', v_eligibility_date,
      'eligibility_timezone', 'UTC',
      'age_requirement_passed', true,
      'recruitment_status', 'recruiting'
    )
  )
  ON CONFLICT ON CONSTRAINT study_enrollments_user_study_key DO NOTHING
  RETURNING *
  INTO v_enrollment;

  IF FOUND THEN
    RETURN v_enrollment;
  END IF;

  SELECT se.*
  INTO v_enrollment
  FROM public.study_enrollments se
  WHERE se.user_id = v_user_id
    AND se.study_id = p_study_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Enrollment could not be created or recovered.';
  END IF;

  IF v_enrollment.status <> 'enrolled' THEN
    RAISE EXCEPTION USING
      MESSAGE = 'An existing terminal enrollment cannot be reactivated by a consent retry.',
      DETAIL = format('Current enrollment status: %s', v_enrollment.status);
  END IF;

  RETURN v_enrollment;
END;
$$;

REVOKE ALL ON FUNCTION public.enroll_in_study_after_consent(uuid, uuid)
FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.enroll_in_study_after_consent(uuid, uuid)
TO authenticated;
