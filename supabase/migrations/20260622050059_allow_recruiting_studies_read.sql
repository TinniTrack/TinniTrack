-- Allow signed-in participants to discover currently recruiting studies.
-- User-owned study data remains protected by separate RLS policies.

ALTER TABLE public.studies ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS studies_select_recruiting ON public.studies;
CREATE POLICY studies_select_recruiting
ON public.studies
FOR SELECT
TO authenticated
USING (status = 'recruiting');
