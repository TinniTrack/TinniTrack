-- Native Study No. 1 consent v2 evidence and canonical 8/12/16/20 scheduling.

ALTER TABLE public.consents
  ADD COLUMN IF NOT EXISTS consent_content_sha256 text,
  ADD COLUMN IF NOT EXISTS signature_image_sha256 text,
  ADD COLUMN IF NOT EXISTS collection_method text,
  ADD COLUMN IF NOT EXISTS attestation_text text,
  ADD COLUMN IF NOT EXISTS attestation_version text;

ALTER TABLE public.consents
  DROP CONSTRAINT IF EXISTS consents_content_sha256_hex_check,
  ADD CONSTRAINT consents_content_sha256_hex_check
    CHECK (consent_content_sha256 IS NULL OR consent_content_sha256 ~ '^[0-9a-f]{64}$'),
  DROP CONSTRAINT IF EXISTS consents_signature_image_sha256_hex_check,
  ADD CONSTRAINT consents_signature_image_sha256_hex_check
    CHECK (signature_image_sha256 IS NULL OR signature_image_sha256 ~ '^[0-9a-f]{64}$'),
  DROP CONSTRAINT IF EXISTS consents_collection_method_check,
  ADD CONSTRAINT consents_collection_method_check
    CHECK (collection_method IS NULL OR collection_method IN ('researchkit', 'native_swiftui_v2')),
  DROP CONSTRAINT IF EXISTS consents_native_v2_metadata_check,
  ADD CONSTRAINT consents_native_v2_metadata_check
    CHECK (
      consent_version <> 'study-no-1-consent-v2'
      OR (
        consent_content_sha256 IS NOT NULL
        AND signature_image_sha256 IS NOT NULL
        AND collection_method = 'native_swiftui_v2'
        AND NULLIF(BTRIM(attestation_text), '') IS NOT NULL
        AND NULLIF(BTRIM(attestation_version), '') IS NOT NULL
      )
    );

CREATE INDEX IF NOT EXISTS consents_user_study_content_hash_idx
ON public.consents (user_id, study_id, consent_content_sha256);

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

CREATE OR REPLACE FUNCTION public.complete_study_no_1_onboarding(
  p_enrollment_id uuid,
  p_timezone text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_enrollment public.study_enrollments%ROWTYPE;
  v_timezone text := COALESCE(NULLIF(BTRIM(p_timezone), ''), 'UTC');
  v_local_now timestamp;
  v_start_date date;
  v_day_index int;
  v_slot_hour int;
  v_slot_index int;
  v_window_start timestamptz;
  v_slot_hours int[] := ARRAY[8, 12, 16, 20];
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
    RAISE EXCEPTION 'Enrollment is not eligible for Study No. 1 onboarding completion.';
  END IF;

  IF v_enrollment.onboarding_completed_at IS NULL
     AND NOT EXISTS (
       SELECT 1
       FROM public.scheduled_tasks st
       JOIN public.task_runs tr ON tr.scheduled_task_id = st.id
       WHERE st.enrollment_id = v_enrollment.id
         AND st.task_key = 'threshold_1khz_orientation_v1'
         AND st.day_index = -1
         AND st.slot_index = 1
         AND st.status = 'completed'
         AND tr.run_status = 'completed'
         AND tr.protocol_version = 'orientation_threshold_v1'
     ) THEN
    RAISE EXCEPTION 'Complete the Study No. 1 orientation threshold task before finishing onboarding.';
  END IF;

  BEGIN
    PERFORM NOW() AT TIME ZONE v_timezone;
  EXCEPTION
    WHEN OTHERS THEN
      v_timezone := 'UTC';
  END;

  IF v_enrollment.onboarding_completed_at IS NULL THEN
    UPDATE public.study_enrollments
    SET onboarding_completed_at = NOW()
    WHERE id = v_enrollment.id;
  END IF;

  DELETE FROM public.scheduled_tasks st
  WHERE st.enrollment_id = v_enrollment.id
    AND st.day_index >= 0
    AND st.status = 'scheduled'
    AND st.task_key IN ('lm_1khz_v1', 'lm_1khz_v2');

  v_local_now := NOW() AT TIME ZONE v_timezone;
  IF v_local_now::time > TIME '08:00' THEN
    v_start_date := (v_local_now::date + 1);
  ELSE
    v_start_date := v_local_now::date;
  END IF;

  FOR v_day_index IN SELECT generate_series(0, 13) LOOP
    v_slot_index := 0;

    FOREACH v_slot_hour IN ARRAY v_slot_hours LOOP
      v_window_start := make_timestamptz(
        EXTRACT(YEAR FROM (v_start_date + v_day_index))::int,
        EXTRACT(MONTH FROM (v_start_date + v_day_index))::int,
        EXTRACT(DAY FROM (v_start_date + v_day_index))::int,
        v_slot_hour,
        0,
        0,
        v_timezone
      );

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
        'lm_1khz_v2',
        2,
        v_window_start,
        v_window_start,
        v_window_start + INTERVAL '60 minutes',
        'scheduled',
        v_day_index,
        v_slot_index
      )
      ON CONFLICT (enrollment_id, day_index, slot_index) DO UPDATE
      SET task_key = EXCLUDED.task_key,
          task_version = EXCLUDED.task_version,
          scheduled_for = EXCLUDED.scheduled_for,
          window_start = EXCLUDED.window_start,
          window_end = EXCLUDED.window_end,
          status = EXCLUDED.status,
          completed_at = NULL
      WHERE scheduled_tasks.status <> 'completed';

      v_slot_index := v_slot_index + 1;
    END LOOP;
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.complete_study_no_1_onboarding(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.complete_study_no_1_onboarding(uuid, text) TO authenticated;
