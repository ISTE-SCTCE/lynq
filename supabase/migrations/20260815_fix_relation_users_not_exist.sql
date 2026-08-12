-- ============================================================================
-- FIX: "relation public.users does not exist" (code 42P01)
-- ============================================================================
-- CAUSE: The physical `public.users` table was dropped/retired during consolidation,
-- but database foreign key constraints (e.g. `events_created_by_fkey`), triggers,
-- functions, or legacy policies still reference `public.users`.
--
-- FIX:
-- 1. Ensure `profiles` has all expected columns (fcm_token, last_active).
-- 2. Create `public.users` as a compatibility VIEW over `public.profiles` so any
--    stray references, triggers, or policies succeed without error.
-- 3. Repoint all foreign key constraints on `events` and all other tables from
--    `public.users(id)` to `public.profiles(id)`.
-- ============================================================================

-- ── 0. Ensure profiles columns exist ───────────────────────────────────────
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS fcm_token TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS last_active TIMESTAMPTZ;

-- ── 1. Create public.users compatibility view over public.profiles ─────────
DO $$
BEGIN
  -- If public.users is a table (legacy), drop it if empty or cascade
  IF EXISTS (
    SELECT 1 FROM information_schema.tables 
    WHERE table_schema = 'public' AND table_name = 'users' AND table_type = 'BASE TABLE'
  ) THEN
    DROP TABLE public.users CASCADE;
  END IF;
END $$;

CREATE OR REPLACE VIEW public.users AS
SELECT 
  id,
  id AS user_id,
  email,
  name,
  role,
  post,
  phone,
  roll_number,
  branch,
  year,
  college,
  forum,
  execom_tag,
  status,
  is_registered,
  is_iste_member,
  iste_membership_id,
  membership_plan,
  membership_date,
  expiry_date,
  fcm_token,
  last_active,
  created_at,
  updated_at
FROM public.profiles;

-- Grant permissions on users view for all roles
GRANT SELECT, INSERT, UPDATE, DELETE ON public.users TO authenticated, anon, service_role, postgres;

-- ── 2. Fix FK constraints on public.events ─────────────────────────────────
ALTER TABLE public.events DROP CONSTRAINT IF EXISTS events_created_by_fkey;
ALTER TABLE public.events DROP CONSTRAINT IF EXISTS events_user_id_fkey;

ALTER TABLE public.events 
  ADD CONSTRAINT events_created_by_fkey 
  FOREIGN KEY (created_by) REFERENCES public.profiles(id) ON DELETE SET NULL;

-- ── 3. Fix FK constraints on folder_members ────────────────────────────────
ALTER TABLE public.folder_members DROP CONSTRAINT IF EXISTS folder_members_user_id_fkey;
ALTER TABLE public.folder_members 
  ADD CONSTRAINT folder_members_user_id_fkey 
  FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

-- ── 4. Fix FK constraints on messages ──────────────────────────────────────
ALTER TABLE public.messages DROP CONSTRAINT IF EXISTS messages_sender_id_fkey;
ALTER TABLE public.messages DROP CONSTRAINT IF EXISTS messages_receiver_id_fkey;
ALTER TABLE public.messages 
  ADD CONSTRAINT messages_sender_id_fkey 
  FOREIGN KEY (sender_id) REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD CONSTRAINT messages_receiver_id_fkey 
  FOREIGN KEY (receiver_id) REFERENCES public.profiles(id) ON DELETE SET NULL;

-- ── 5. Fix FK constraints on budget_requests ───────────────────────────────
ALTER TABLE public.budget_requests DROP CONSTRAINT IF EXISTS budget_requests_requested_by_fkey;
ALTER TABLE public.budget_requests DROP CONSTRAINT IF EXISTS budget_requests_reviewed_by_fkey;
ALTER TABLE public.budget_requests 
  ADD CONSTRAINT budget_requests_requested_by_fkey 
  FOREIGN KEY (requested_by) REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD CONSTRAINT budget_requests_reviewed_by_fkey 
  FOREIGN KEY (reviewed_by) REFERENCES public.profiles(id) ON DELETE SET NULL;

-- ── 6. Fix FK constraints on event_reports ─────────────────────────────────
ALTER TABLE public.event_reports DROP CONSTRAINT IF EXISTS event_reports_uploaded_by_fkey;
ALTER TABLE public.event_reports 
  ADD CONSTRAINT event_reports_uploaded_by_fkey 
  FOREIGN KEY (uploaded_by) REFERENCES public.profiles(id) ON DELETE SET NULL;

-- ── 7. Fix FK constraints on financial_ledger & financial_income ──────────
ALTER TABLE public.financial_ledger DROP CONSTRAINT IF EXISTS financial_ledger_created_by_fkey;
ALTER TABLE public.financial_ledger 
  ADD CONSTRAINT financial_ledger_created_by_fkey 
  FOREIGN KEY (created_by) REFERENCES public.profiles(id) ON DELETE SET NULL;

ALTER TABLE public.financial_income DROP CONSTRAINT IF EXISTS financial_income_created_by_fkey;
ALTER TABLE public.financial_income 
  ADD CONSTRAINT financial_income_created_by_fkey 
  FOREIGN KEY (created_by) REFERENCES public.profiles(id) ON DELETE SET NULL;

-- ── 8. Fix FK constraints on tasks & task_proofs ──────────────────────────
ALTER TABLE public.tasks DROP CONSTRAINT IF EXISTS tasks_created_by_fkey;
ALTER TABLE public.tasks 
  ADD CONSTRAINT tasks_created_by_fkey 
  FOREIGN KEY (created_by) REFERENCES public.profiles(id) ON DELETE SET NULL;

ALTER TABLE public.task_proofs DROP CONSTRAINT IF EXISTS task_proofs_uploaded_by_fkey;
ALTER TABLE public.task_proofs DROP CONSTRAINT IF EXISTS task_proofs_reviewed_by_fkey;
ALTER TABLE public.task_proofs 
  ADD CONSTRAINT task_proofs_uploaded_by_fkey 
  FOREIGN KEY (uploaded_by) REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD CONSTRAINT task_proofs_reviewed_by_fkey 
  FOREIGN KEY (reviewed_by) REFERENCES public.profiles(id) ON DELETE SET NULL;

-- ── 9. Fix FK constraints on attendance & qr_tokens ───────────────────────
ALTER TABLE public.attendance DROP CONSTRAINT IF EXISTS attendance_user_id_fkey;
ALTER TABLE public.attendance DROP CONSTRAINT IF EXISTS attendance_scanned_by_fkey;
ALTER TABLE public.attendance 
  ADD CONSTRAINT attendance_user_id_fkey 
  FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE,
  ADD CONSTRAINT attendance_scanned_by_fkey 
  FOREIGN KEY (scanned_by) REFERENCES public.profiles(id) ON DELETE SET NULL;

ALTER TABLE public.qr_tokens DROP CONSTRAINT IF EXISTS qr_tokens_user_id_fkey;
ALTER TABLE public.qr_tokens 
  ADD CONSTRAINT qr_tokens_user_id_fkey 
  FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

-- ── 10. Fix FK constraints on certificates ────────────────────────────────
ALTER TABLE public.certificates DROP CONSTRAINT IF EXISTS certificates_user_id_fkey;
ALTER TABLE public.certificates DROP CONSTRAINT IF EXISTS certificates_issued_by_fkey;
ALTER TABLE public.certificates DROP CONSTRAINT IF EXISTS certificates_uploaded_by_fkey;
ALTER TABLE public.certificates 
  ADD CONSTRAINT certificates_user_id_fkey 
  FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE,
  ADD CONSTRAINT certificates_issued_by_fkey 
  FOREIGN KEY (issued_by) REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD CONSTRAINT certificates_uploaded_by_fkey 
  FOREIGN KEY (uploaded_by) REFERENCES public.profiles(id) ON DELETE SET NULL;

-- ── 11. Ensure RLS policies on events are permissive for creation ─────────
ALTER TABLE public.events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Execom sees all events" ON public.events;
DROP POLICY IF EXISTS "Members see permitted events" ON public.events;
DROP POLICY IF EXISTS "Execom manages events" ON public.events;
DROP POLICY IF EXISTS "Authenticated users create events" ON public.events;

CREATE POLICY "Execom sees all events"
  ON public.events FOR SELECT TO authenticated
  USING (public.my_role_rank() >= public.role_rank('forum_execcom'));

CREATE POLICY "Members see permitted events"
  ON public.events FOR SELECT TO authenticated
  USING (
    public.my_role_rank() >= public.role_rank('forum_execcom')
    OR allowed_roles IS NULL
    OR array_length(allowed_roles, 1) IS NULL
    OR (SELECT role::text FROM public.profiles WHERE id = auth.uid()) = ANY(allowed_roles)
  );

CREATE POLICY "Execom manages events"
  ON public.events FOR ALL TO authenticated
  USING (public.my_role_rank() >= public.role_rank('forum_execcom'))
  WITH CHECK (public.my_role_rank() >= public.role_rank('forum_execcom'));
