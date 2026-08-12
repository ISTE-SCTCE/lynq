-- Migration: Allow Authenticated Admins/Execoms to Insert/Update Certificates
ALTER TABLE public.certificates ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins and Execom manage certificates" ON public.certificates;

CREATE POLICY "Admins and Execom manage certificates"
  ON public.certificates
  FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);
