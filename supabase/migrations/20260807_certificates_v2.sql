-- ============================================================
-- Migration: Certificates V2 + Events Extensions
-- Run in Supabase SQL Editor. All sections are idempotent.
-- ============================================================


-- ── 1. events table additions ────────────────────────────────────────────────

ALTER TABLE public.events
  ADD COLUMN IF NOT EXISTS attendance_finalized BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS coordinator_name     TEXT,
  ADD COLUMN IF NOT EXISTS chair_name           TEXT,
  ADD COLUMN IF NOT EXISTS template_url         TEXT,
  ADD COLUMN IF NOT EXISTS category             TEXT;
-- category values: 'Hackathon' | 'Workshop' | 'Seminar' | 'General'


-- ── 2. certificates table additions (preserve existing rows) ─────────────────

ALTER TABLE public.certificates
  ADD COLUMN IF NOT EXISTS student_name     TEXT,
  ADD COLUMN IF NOT EXISTS certificate_url  TEXT,
  ADD COLUMN IF NOT EXISTS storage_path     TEXT,
  ADD COLUMN IF NOT EXISTS issued_at        TIMESTAMPTZ DEFAULT now();

-- Unique constraint (event_id, user_id) — idempotent via DO block
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.certificates'::regclass
      AND conname  = 'cert_event_user_unique'
  ) THEN
    ALTER TABLE public.certificates
      ADD CONSTRAINT cert_event_user_unique UNIQUE (event_id, user_id);
  END IF;
END
$$;


-- ── 3. RLS on certificates ───────────────────────────────────────────────────

ALTER TABLE public.certificates ENABLE ROW LEVEL SECURITY;

-- Drop old policies first (idempotent recreate)
DROP POLICY IF EXISTS "Students read own certificates"   ON public.certificates;
DROP POLICY IF EXISTS "Service role manages certificates" ON public.certificates;

-- Students can only SELECT their own rows
CREATE POLICY "Students read own certificates"
  ON public.certificates
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

-- All writes (INSERT / UPDATE / DELETE) only via service role key
-- (No authenticated INSERT policy → anon/authenticated users cannot write)


-- ── 4. Storage bucket setup ──────────────────────────────────────────────────
-- Run these in Supabase Dashboard → Storage, or via CLI.
-- Shown here as reference comments:

-- Bucket: 'certificate-templates'  (private)
--   Exec upload:   INSERT allowed for execom roles
--   Read:          Service role only (Edge Function reads via service key)

-- Bucket: 'certificates'  (private)
--   Student read:  Path pattern certificates/{eventId}/{userId}.pdf
--                  RLS: (storage.foldername(name))[2] = auth.uid()::text
--   Write:         Service role only (Edge Function uploads)

-- SQL-based Storage bucket RLS (if using SQL editor approach):
-- These statements are for reference; apply them in the Supabase Storage RLS editor.

/*
-- For 'certificates' bucket, student read-own policy:
CREATE POLICY "Students read own certificate PDFs"
  ON storage.objects
  FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'certificates'
    AND (storage.foldername(name))[2] = auth.uid()::text
  );
*/


-- ── 5. Performance indexes ───────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_certificates_user_id
  ON public.certificates (user_id);

CREATE INDEX IF NOT EXISTS idx_certificates_event_id
  ON public.certificates (event_id);

CREATE INDEX IF NOT EXISTS idx_events_finalized
  ON public.events (attendance_finalized)
  WHERE attendance_finalized = true;


-- ── 6. Helper RPC: get_certificates_for_student ──────────────────────────────
-- Returns all certificates for a student with full event details.
-- Used by m-lynq My Certificates page.

CREATE OR REPLACE FUNCTION public.get_student_certificates(p_user_id UUID)
RETURNS TABLE (
  id            UUID,
  event_id      BIGINT,
  event_title   TEXT,
  event_date    DATE,
  category      TEXT,
  student_name  TEXT,
  cert_url      TEXT,
  file_url      TEXT,
  issued_at     TIMESTAMPTZ
)
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT
    c.id,
    c.event_id,
    e.title        AS event_title,
    e.date         AS event_date,
    e.category,
    c.student_name,
    c.certificate_url AS cert_url,
    c.file_url,
    c.issued_at
  FROM public.certificates c
  JOIN public.events e ON e.id = c.event_id
  WHERE c.user_id = p_user_id
  ORDER BY c.issued_at DESC NULLS LAST;
$$;

GRANT EXECUTE ON FUNCTION public.get_student_certificates(UUID) TO authenticated;
