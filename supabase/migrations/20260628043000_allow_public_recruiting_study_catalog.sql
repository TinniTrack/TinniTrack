-- Recruiting study catalog rows are public product information.
-- Participant-specific enrollment, consent, task, and profile data remain authenticated/user-scoped.

ALTER TABLE public.studies ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS studies_select_recruiting ON public.studies;
CREATE POLICY studies_select_recruiting
ON public.studies
FOR SELECT
TO anon, authenticated
USING (status = 'recruiting');
