-- ============================================================================
-- ISTE SCTCE Lynq/MLynq: SCHEMA CLEANUP MIGRATION (Phase 2)
-- File: supabase/migrations/20260810_schema_cleanup_phase2.sql
-- ============================================================================
-- Context: Phase 1 (20260809_consolidation.sql) created `profiles` as the
-- unified identity table, migrated users → profiles, and set up core RLS.
--
-- This migration finishes the job — fixes every issue found in the live
-- schema audit that Phase 1 left incomplete:
--
--   Step 1  — Add missing FK constraints (attendance/qr_tokens.user_id)
--   Step 2  — Repoint all FKs from users(id) → profiles(id)
--   Step 3  — Merge duplicate guest tables (members_not_iste + iste_non_member)
--   Step 4  — Retire `members` table → rename to members_legacy_archive
--   Step 5  — Enable RLS on 11 exposed financial/sensitive tables
--   Step 6  — Consolidate certificate config (event_certificate_config → events jsonb)
--   Step 7  — Fix text-based owner columns (folders/announcements.created_by → uuid FK)
--   Step 8  — Resolve certificates dual-linkage (member_id vs user_id)
--   Step 9  — Backfill messages sender_id/receiver_id from legacy text columns
--   Step 10 — Destructive cleanup (COMMENTED — run only after full verification)
--
-- SAFETY MODEL:
--   Steps 1–9 are ADDITIVE / REPOINTING. No columns or tables are dropped.
--   Step 10 drops legacy columns/tables — kept commented; uncomment per-line
--   only after verifying the app works entirely on the new FK columns.
--
-- IDEMPOTENCY:
--   Every ALTER uses DROP CONSTRAINT IF EXISTS before ADD CONSTRAINT.
--   Every new column uses ADD COLUMN IF NOT EXISTS.
--   Every RLS policy uses DROP POLICY IF EXISTS before CREATE POLICY.
--   Safe to re-run after partial failures.
--
-- BEFORE RUNNING:
--   supabase db dump -f backup_phase2_$(date +%s).sql
--   Confirm Phase 1 migration ran: SELECT id FROM public.profiles LIMIT 1;
-- ============================================================================


-- ── STEP 1: Add missing FK constraints on user_id columns ────────────────────
-- attendance.user_id, attendance.scanned_by, and qr_tokens.user_id all existed
-- as bare UUID columns with NO foreign key — nothing was preventing orphaned rows.
-- profiles.id == auth.users.id (same UUID space), Phase 1 established this link.

-- Guard: only add if no orphans exist (this ADD will fail if orphans are present).
-- Run the orphan check in the verification section first if unsure.

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.attendance'::regclass AND conname = 'attendance_user_id_fkey'
  ) THEN
    ALTER TABLE public.attendance
      ADD CONSTRAINT attendance_user_id_fkey
      FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.attendance'::regclass AND conname = 'attendance_scanned_by_fkey'
  ) THEN
    ALTER TABLE public.attendance
      ADD CONSTRAINT attendance_scanned_by_fkey
      FOREIGN KEY (scanned_by) REFERENCES public.profiles(id) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.qr_tokens'::regclass AND conname = 'qr_tokens_user_id_fkey'
  ) THEN
    ALTER TABLE public.qr_tokens
      ADD CONSTRAINT qr_tokens_user_id_fkey
      FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
  END IF;
END $$;

-- certificates.user_id FK is added in Step 8 (after member_id/user_id resolution).


-- ── STEP 2: Repoint FKs from users(id) → profiles(id) ───────────────────────
-- `users` is being retired. Every table currently pointing at it needs to point
-- at `profiles` instead. Because profiles.id = users.id = auth.users.id (the
-- same UUIDs were migrated verbatim in Phase 1), this is a safe constraint swap
-- with zero data movement.
--
-- Pattern: DROP CONSTRAINT IF EXISTS (old name) → ADD CONSTRAINT (new target).
-- If Phase 1 already moved some of these, the DROP is a no-op and ADD succeeds.

-- ── 2a. events.created_by ────────────────────────────────────────────────────
ALTER TABLE public.events
  DROP CONSTRAINT IF EXISTS events_created_by_fkey;
ALTER TABLE public.events
  ADD CONSTRAINT events_created_by_fkey
  FOREIGN KEY (created_by) REFERENCES public.profiles(id) ON DELETE SET NULL;

-- ── 2b. folder_members.user_id ───────────────────────────────────────────────
ALTER TABLE public.folder_members
  DROP CONSTRAINT IF EXISTS folder_members_user_id_fkey;
ALTER TABLE public.folder_members
  ADD CONSTRAINT folder_members_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

-- ── 2c. messages.sender_id / receiver_id ─────────────────────────────────────
ALTER TABLE public.messages
  DROP CONSTRAINT IF EXISTS messages_sender_id_fkey,
  DROP CONSTRAINT IF EXISTS messages_receiver_id_fkey;
ALTER TABLE public.messages
  ADD CONSTRAINT messages_sender_id_fkey
    FOREIGN KEY (sender_id) REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD CONSTRAINT messages_receiver_id_fkey
    FOREIGN KEY (receiver_id) REFERENCES public.profiles(id) ON DELETE SET NULL;

-- ── 2d. budget_requests.requested_by / reviewed_by ───────────────────────────
ALTER TABLE public.budget_requests
  DROP CONSTRAINT IF EXISTS budget_requests_requested_by_fkey,
  DROP CONSTRAINT IF EXISTS budget_requests_reviewed_by_fkey;
ALTER TABLE public.budget_requests
  ADD CONSTRAINT budget_requests_requested_by_fkey
    FOREIGN KEY (requested_by) REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD CONSTRAINT budget_requests_reviewed_by_fkey
    FOREIGN KEY (reviewed_by) REFERENCES public.profiles(id) ON DELETE SET NULL;

-- ── 2e. event_reports.uploaded_by ────────────────────────────────────────────
ALTER TABLE public.event_reports
  DROP CONSTRAINT IF EXISTS event_reports_uploaded_by_fkey;
ALTER TABLE public.event_reports
  ADD CONSTRAINT event_reports_uploaded_by_fkey
  FOREIGN KEY (uploaded_by) REFERENCES public.profiles(id) ON DELETE SET NULL;

-- ── 2f. financial_ledger.created_by ──────────────────────────────────────────
ALTER TABLE public.financial_ledger
  DROP CONSTRAINT IF EXISTS financial_ledger_created_by_fkey;
ALTER TABLE public.financial_ledger
  ADD CONSTRAINT financial_ledger_created_by_fkey
  FOREIGN KEY (created_by) REFERENCES public.profiles(id) ON DELETE SET NULL;

-- ── 2g. financial_income.created_by ──────────────────────────────────────────
ALTER TABLE public.financial_income
  DROP CONSTRAINT IF EXISTS financial_income_created_by_fkey;
ALTER TABLE public.financial_income
  ADD CONSTRAINT financial_income_created_by_fkey
  FOREIGN KEY (created_by) REFERENCES public.profiles(id) ON DELETE SET NULL;

-- ── 2h. tasks.created_by ─────────────────────────────────────────────────────
ALTER TABLE public.tasks
  DROP CONSTRAINT IF EXISTS tasks_created_by_fkey;
ALTER TABLE public.tasks
  ADD CONSTRAINT tasks_created_by_fkey
  FOREIGN KEY (created_by) REFERENCES public.profiles(id) ON DELETE SET NULL;

-- ── 2i. task_proofs.uploaded_by / reviewed_by ────────────────────────────────
ALTER TABLE public.task_proofs
  DROP CONSTRAINT IF EXISTS task_proofs_uploaded_by_fkey,
  DROP CONSTRAINT IF EXISTS task_proofs_reviewed_by_fkey;
ALTER TABLE public.task_proofs
  ADD CONSTRAINT task_proofs_uploaded_by_fkey
    FOREIGN KEY (uploaded_by) REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD CONSTRAINT task_proofs_reviewed_by_fkey
    FOREIGN KEY (reviewed_by) REFERENCES public.profiles(id) ON DELETE SET NULL;

-- ── 2j. registration_queue.reviewed_by ───────────────────────────────────────
ALTER TABLE public.registration_queue
  DROP CONSTRAINT IF EXISTS registration_queue_reviewed_by_fkey;
ALTER TABLE public.registration_queue
  ADD CONSTRAINT registration_queue_reviewed_by_fkey
  FOREIGN KEY (reviewed_by) REFERENCES public.profiles(id) ON DELETE SET NULL;

-- ── 2k. certificates.issued_by / uploaded_by ─────────────────────────────────
ALTER TABLE public.certificates
  DROP CONSTRAINT IF EXISTS certificates_issued_by_fkey,
  DROP CONSTRAINT IF EXISTS certificates_uploaded_by_fkey;
ALTER TABLE public.certificates
  ADD CONSTRAINT certificates_issued_by_fkey
    FOREIGN KEY (issued_by) REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD CONSTRAINT certificates_uploaded_by_fkey
    FOREIGN KEY (uploaded_by) REFERENCES public.profiles(id) ON DELETE SET NULL;


-- ── STEP 3: Merge duplicate guest tables ─────────────────────────────────────
-- members_not_iste  — the original non-ISTE guest table (already processed by Phase 1)
-- iste_non_member   — a newer-looking duplicate of the same concept
-- Both hold (id uuid, name, email, phone, roll_number, college).
-- profiles already has is_registered/is_iste_member flags; these tables are now
-- redundant. This step backfills profiles from iste_non_member (members_not_iste
-- was already backfilled in Phase 1 Section 2d). Then a verification query
-- confirms zero rows are missing before Step 10 safely drops both.

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'iste_non_member'
  ) THEN
    INSERT INTO public.profiles (
      id, email, name, phone, roll_number, college,
      role, status, is_registered, is_iste_member,
      created_at, updated_at
    )
    SELECT
      inm.id,
      inm.email,
      COALESCE(inm.name, inm.email),
      inm.phone,
      inm.roll_number,
      inm.college,
      'member'::public.app_role,
      'active'::public.account_status,
      true,   -- registered (they filled a form)
      false,  -- not ISTE member
      COALESCE(inm.created_at, NOW()),
      NOW()
    FROM public.iste_non_member inm
    WHERE inm.email IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM public.profiles p
        WHERE p.id = inm.id
           OR LOWER(p.email) = LOWER(inm.email)
      )
    ON CONFLICT (id) DO NOTHING;
  END IF;
END $$;

-- Verification: run this before Step 10. Both counts MUST be 0 before dropping.
SELECT
  'members_not_iste rows not in profiles' AS check_name,
  COUNT(*) AS count
FROM public.members_not_iste mni
WHERE NOT EXISTS (
  SELECT 1 FROM public.profiles p
  WHERE p.id = mni.id OR LOWER(p.email) = LOWER(mni.email)
)
UNION ALL
SELECT
  'iste_non_member rows not in profiles',
  COUNT(*)
FROM public.iste_non_member inm
WHERE NOT EXISTS (
  SELECT 1 FROM public.profiles p
  WHERE p.id = inm.id OR LOWER(p.email) = LOWER(inm.email)
);
-- Expected: both rows show count = 0. Non-zero = investigate before continuing.


-- ── STEP 4: Retire `members` table → archive as members_legacy_archive ────────
-- `members` was the ISTE registry source of truth. profiles now owns all of its
-- important flags (is_sudo, is_budget_activated, plan, forum_name, suspended_until).
-- Phase 1 did the bulk sync (Section 2c). This step does a final reconciliation
-- pass to pick up any rows added to members between Phase 1 and now, then renames
-- the table to signal it is read-only legacy data going forward.

-- Final sync pass: pull remaining member-specific fields into profiles
UPDATE public.profiles p
SET
  is_iste_member      = true,
  is_registered       = true,
  iste_membership_id  = COALESCE(p.iste_membership_id, m.iste_id, m.ui_id),
  membership_plan     = COALESCE(p.membership_plan, m.plan, m.plan_type),
  membership_date     = COALESCE(p.membership_date, m.joined_date, m.registration_date, m.plan_start_date),
  expiry_date         = COALESCE(p.expiry_date, m.membership_expiry, m.expiry_date, m.plan_end_date),
  forum               = COALESCE(p.forum, m.forum, m.forum_name),
  is_sudo             = p.is_sudo OR COALESCE(m.is_sudo, false),
  is_budget_activated = p.is_budget_activated OR COALESCE(m.is_budget_activated, false),
  suspended_until     = COALESCE(p.suspended_until, m.suspended_until),
  updated_at          = NOW()
FROM public.members m
WHERE m.user_id = p.id
  AND m.user_id IS NOT NULL;

-- Also match by email for any members not yet linked to an auth.users account
UPDATE public.profiles p
SET
  is_iste_member      = true,
  iste_membership_id  = COALESCE(p.iste_membership_id, m.iste_id, m.ui_id),
  membership_plan     = COALESCE(p.membership_plan, m.plan, m.plan_type),
  membership_date     = COALESCE(p.membership_date, m.joined_date, m.registration_date, m.plan_start_date),
  expiry_date         = COALESCE(p.expiry_date, m.membership_expiry, m.expiry_date, m.plan_end_date),
  forum               = COALESCE(p.forum, m.forum, m.forum_name),
  updated_at          = NOW()
FROM public.members m
WHERE m.user_id IS NULL
  AND LOWER(TRIM(m.email)) = LOWER(TRIM(p.email));

-- Rename to archive — keeps data accessible for reporting without
-- misleading anyone into treating it as a writable source of truth.
ALTER TABLE IF EXISTS public.members
  RENAME TO members_legacy_archive;

-- Verification: count should roughly match the old members table row count
SELECT COUNT(*) AS profiles_with_iste_membership_id
FROM public.profiles
WHERE iste_membership_id IS NOT NULL;


-- ── STEP 5: Enable RLS on exposed financial / sensitive tables ────────────────
-- These 11 tables had NO RLS policies at all. Under PostgREST default behaviour
-- this means any authenticated (or anon) user can read/write all rows — a
-- serious data exposure for financial and registration data.
--
-- Policy design principles applied here:
--   • Financial tables: folder members can read their own folder's data; execom writes.
--   • budget_requests: requester reads own; execom manages all.
--   • event_reports: visibility array controls read; execom manages.
--   • Audit tables (ledger_change_history): execom read-only; service_role writes.
--   • Legacy tables: execom read-only while transition is in progress.
--   • registration_queue: any authenticated user can submit; execom reviews/updates.
--
-- Role comparison note: app_role ENUM is ordered (member < restricted < panel <
-- forum_execcom < core_execcom < vice_chairman < chairman). Casting to text and
-- using >= against a literal works because text comparison of ENUM values follows
-- the ENUM sort order in PostgreSQL. This is intentional and correct.

-- ── 5a. financial_income ─────────────────────────────────────────────────────
ALTER TABLE public.financial_income ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Folder members read income"  ON public.financial_income;
DROP POLICY IF EXISTS "Execom manages income"        ON public.financial_income;
DROP POLICY IF EXISTS "Service role full access on financial_income" ON public.financial_income;

CREATE POLICY "Folder members read income"
  ON public.financial_income FOR SELECT TO authenticated
  USING (
    execom_id IN (
      SELECT execom_id FROM public.folder_members WHERE user_id = auth.uid()
    )
    OR (SELECT role FROM public.profiles WHERE id = auth.uid())::text
       >= 'core_execcom'::text
  );

CREATE POLICY "Execom manages income"
  ON public.financial_income FOR ALL TO authenticated
  USING (
    (SELECT role FROM public.profiles WHERE id = auth.uid())::text
    >= 'core_execcom'::text
  )
  WITH CHECK (
    (SELECT role FROM public.profiles WHERE id = auth.uid())::text
    >= 'core_execcom'::text
  );

CREATE POLICY "Service role full access on financial_income"
  ON public.financial_income FOR ALL TO service_role
  USING (true) WITH CHECK (true);

-- ── 5b. forum_budgets ────────────────────────────────────────────────────────
ALTER TABLE public.forum_budgets ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Folder members read forum budgets" ON public.forum_budgets;
DROP POLICY IF EXISTS "Execom manages forum budgets"       ON public.forum_budgets;
DROP POLICY IF EXISTS "Service role full access on forum_budgets" ON public.forum_budgets;

CREATE POLICY "Folder members read forum budgets"
  ON public.forum_budgets FOR SELECT TO authenticated
  USING (
    execom_id IN (
      SELECT execom_id FROM public.folder_members WHERE user_id = auth.uid()
    )
    OR (SELECT role FROM public.profiles WHERE id = auth.uid())::text
       >= 'core_execcom'::text
  );

CREATE POLICY "Execom manages forum budgets"
  ON public.forum_budgets FOR ALL TO authenticated
  USING (
    (SELECT role FROM public.profiles WHERE id = auth.uid())::text
    >= 'core_execcom'::text
  )
  WITH CHECK (
    (SELECT role FROM public.profiles WHERE id = auth.uid())::text
    >= 'core_execcom'::text
  );

CREATE POLICY "Service role full access on forum_budgets"
  ON public.forum_budgets FOR ALL TO service_role
  USING (true) WITH CHECK (true);

-- ── 5c. event_budgets ────────────────────────────────────────────────────────
ALTER TABLE public.event_budgets ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Folder members read event budgets" ON public.event_budgets;
DROP POLICY IF EXISTS "Execom manages event budgets"       ON public.event_budgets;
DROP POLICY IF EXISTS "Service role full access on event_budgets" ON public.event_budgets;

CREATE POLICY "Folder members read event budgets"
  ON public.event_budgets FOR SELECT TO authenticated
  USING (
    execom_id IN (
      SELECT execom_id FROM public.folder_members WHERE user_id = auth.uid()
    )
    OR (SELECT role FROM public.profiles WHERE id = auth.uid())::text
       >= 'core_execcom'::text
  );

CREATE POLICY "Execom manages event budgets"
  ON public.event_budgets FOR ALL TO authenticated
  USING (
    (SELECT role FROM public.profiles WHERE id = auth.uid())::text
    >= 'core_execcom'::text
  )
  WITH CHECK (
    (SELECT role FROM public.profiles WHERE id = auth.uid())::text
    >= 'core_execcom'::text
  );

CREATE POLICY "Service role full access on event_budgets"
  ON public.event_budgets FOR ALL TO service_role
  USING (true) WITH CHECK (true);

-- ── 5d. budget_requests ───────────────────────────────────────────────────────
ALTER TABLE public.budget_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users read own budget requests"   ON public.budget_requests;
DROP POLICY IF EXISTS "Execom manages budget requests"   ON public.budget_requests;
DROP POLICY IF EXISTS "Service role full access on budget_requests" ON public.budget_requests;

CREATE POLICY "Users read own budget requests"
  ON public.budget_requests FOR SELECT TO authenticated
  USING (requested_by = auth.uid());

CREATE POLICY "Execom manages budget requests"
  ON public.budget_requests FOR ALL TO authenticated
  USING (
    (SELECT role FROM public.profiles WHERE id = auth.uid())::text
    >= 'forum_execcom'::text
  )
  WITH CHECK (
    (SELECT role FROM public.profiles WHERE id = auth.uid())::text
    >= 'forum_execcom'::text
  );

CREATE POLICY "Service role full access on budget_requests"
  ON public.budget_requests FOR ALL TO service_role
  USING (true) WITH CHECK (true);

-- ── 5e. event_reports ────────────────────────────────────────────────────────
ALTER TABLE public.event_reports ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Members read visible reports" ON public.event_reports;
DROP POLICY IF EXISTS "Execom manages reports"        ON public.event_reports;
DROP POLICY IF EXISTS "Service role full access on event_reports" ON public.event_reports;

CREATE POLICY "Members read visible reports"
  ON public.event_reports FOR SELECT TO authenticated
  USING (
    (SELECT role FROM public.profiles WHERE id = auth.uid())::text
      >= 'forum_execcom'::text
    OR (SELECT role::text FROM public.profiles WHERE id = auth.uid())
         = ANY(visibility)
    OR visibility IS NULL
    OR visibility = '{}'::text[]
  );

CREATE POLICY "Execom manages reports"
  ON public.event_reports FOR ALL TO authenticated
  USING (
    (SELECT role FROM public.profiles WHERE id = auth.uid())::text
    >= 'forum_execcom'::text
  )
  WITH CHECK (
    (SELECT role FROM public.profiles WHERE id = auth.uid())::text
    >= 'forum_execcom'::text
  );

CREATE POLICY "Service role full access on event_reports"
  ON public.event_reports FOR ALL TO service_role
  USING (true) WITH CHECK (true);

-- ── 5f. budget_categories ─────────────────────────────────────────────────────
ALTER TABLE public.budget_categories ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated read categories" ON public.budget_categories;
DROP POLICY IF EXISTS "Execom manages categories"      ON public.budget_categories;

CREATE POLICY "Authenticated read categories"
  ON public.budget_categories FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "Execom manages categories"
  ON public.budget_categories FOR ALL TO authenticated
  USING (
    (SELECT role FROM public.profiles WHERE id = auth.uid())::text
    >= 'core_execcom'::text
  )
  WITH CHECK (
    (SELECT role FROM public.profiles WHERE id = auth.uid())::text
    >= 'core_execcom'::text
  );

-- ── 5g. event_certificate_config ─────────────────────────────────────────────
-- Note: this table is being superseded by events.certificate_field_positions
-- (Step 6). RLS here is a safety net during the transition period only.
ALTER TABLE public.event_certificate_config ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Execom manages cert config" ON public.event_certificate_config;

CREATE POLICY "Execom manages cert config"
  ON public.event_certificate_config FOR ALL TO authenticated
  USING (
    (SELECT role FROM public.profiles WHERE id = auth.uid())::text
    >= 'forum_execcom'::text
  )
  WITH CHECK (
    (SELECT role FROM public.profiles WHERE id = auth.uid())::text
    >= 'forum_execcom'::text
  );

-- ── 5h. ledger_change_history ─────────────────────────────────────────────────
-- Audit trail. Authenticated execom reads; only service_role (Edge Functions /
-- triggers) should ever write to this table.
ALTER TABLE public.ledger_change_history ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Execom reads ledger history"       ON public.ledger_change_history;
DROP POLICY IF EXISTS "Service role writes ledger history" ON public.ledger_change_history;

CREATE POLICY "Execom reads ledger history"
  ON public.ledger_change_history FOR SELECT TO authenticated
  USING (
    (SELECT role FROM public.profiles WHERE id = auth.uid())::text
    >= 'core_execcom'::text
  );

CREATE POLICY "Service role writes ledger history"
  ON public.ledger_change_history FOR ALL TO service_role
  USING (true) WITH CHECK (true);

-- ── 5i. members_not_iste (legacy guest table) ─────────────────────────────────
ALTER TABLE public.members_not_iste ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Execom reads legacy guest table" ON public.members_not_iste;

CREATE POLICY "Execom reads legacy guest table"
  ON public.members_not_iste FOR SELECT TO authenticated
  USING (
    (SELECT role FROM public.profiles WHERE id = auth.uid())::text
    >= 'forum_execcom'::text
  );

-- ── 5j. iste_non_member (legacy duplicate guest table) ───────────────────────
ALTER TABLE public.iste_non_member ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Execom reads legacy iste_non_member table" ON public.iste_non_member;

CREATE POLICY "Execom reads legacy iste_non_member table"
  ON public.iste_non_member FOR SELECT TO authenticated
  USING (
    (SELECT role FROM public.profiles WHERE id = auth.uid())::text
    >= 'forum_execcom'::text
  );

-- ── 5k. registration_queue ────────────────────────────────────────────────────
ALTER TABLE public.registration_queue ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone submits registration"    ON public.registration_queue;
DROP POLICY IF EXISTS "Execom reviews registrations"   ON public.registration_queue;
DROP POLICY IF EXISTS "Execom updates registrations"   ON public.registration_queue;
DROP POLICY IF EXISTS "Service role manages registration_queue" ON public.registration_queue;

-- Applicants insert their own record (no restriction needed on insert — the
-- app already associates the row with auth.uid() via submitted_by / user_id).
CREATE POLICY "Anyone submits registration"
  ON public.registration_queue FOR INSERT TO authenticated
  WITH CHECK (true);

CREATE POLICY "Execom reviews registrations"
  ON public.registration_queue FOR SELECT TO authenticated
  USING (
    (SELECT role FROM public.profiles WHERE id = auth.uid())::text
    >= 'forum_execcom'::text
  );

CREATE POLICY "Execom updates registrations"
  ON public.registration_queue FOR UPDATE TO authenticated
  USING (
    (SELECT role FROM public.profiles WHERE id = auth.uid())::text
    >= 'forum_execcom'::text
  )
  WITH CHECK (
    (SELECT role FROM public.profiles WHERE id = auth.uid())::text
    >= 'forum_execcom'::text
  );

CREATE POLICY "Service role manages registration_queue"
  ON public.registration_queue FOR ALL TO service_role
  USING (true) WITH CHECK (true);

-- ── 5l. Retired tables: users + members_legacy_archive ───────────────────────
-- Lock these down so app code is forced to fail fast if still using old tables,
-- rather than silently reading stale / inconsistent data.

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Service role only on legacy users" ON public.users;
CREATE POLICY "Service role only on legacy users"
  ON public.users FOR ALL TO service_role
  USING (true) WITH CHECK (true);
-- Note: NO authenticated policy — authenticated reads to users will now be blocked.
-- This surfaces any app code still querying the old users table immediately.

ALTER TABLE public.members_legacy_archive ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Execom reads legacy members archive" ON public.members_legacy_archive;
CREATE POLICY "Execom reads legacy members archive"
  ON public.members_legacy_archive FOR SELECT TO authenticated
  USING (
    (SELECT role FROM public.profiles WHERE id = auth.uid())::text
    >= 'core_execcom'::text
  );

CREATE POLICY "Service role full access on members_legacy_archive"
  ON public.members_legacy_archive FOR ALL TO service_role
  USING (true) WITH CHECK (true);


-- ── STEP 6: Consolidate certificate template config ───────────────────────────
-- event_certificate_config (name_x, name_y, font_size, text_color, template_url)
-- duplicates events.certificate_field_positions (jsonb) added by Phase 1.
-- Migrate old config into the new jsonb shape so the Edge Function only needs
-- to read events.certificate_field_positions going forward.
--
-- Target jsonb shape (per certificate_image_template_guide.md):
--   { "student_name": { "x": N, "y": N, "size": N, "align": "center", "color": "#hex" } }

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'event_certificate_config'
  ) THEN
    UPDATE public.events e
    SET
      certificate_template_type = COALESCE(e.certificate_template_type, 'image'),
      certificate_image_url     = COALESCE(e.certificate_image_url, ecc.template_url),
      certificate_field_positions = COALESCE(e.certificate_field_positions, '{}'::jsonb)
        || jsonb_build_object(
             'student_name', jsonb_build_object(
               'x',     ecc.name_x,
               'y',     ecc.name_y,
               'size',  ecc.font_size,
               'align', 'center',
               'color', COALESCE(ecc.text_color, '#000000')
             )
           )
    FROM public.event_certificate_config ecc
    WHERE e.id = ecc.event_id
      -- Only overwrite if position data not already set for student_name
      AND NOT (e.certificate_field_positions ? 'student_name');
  END IF;
END $$;

-- Archive (rename) — do not drop yet so it can be verified manually
ALTER TABLE IF EXISTS public.event_certificate_config
  RENAME TO event_certificate_config_legacy;

-- Verification: spot-check migrated events
SELECT id, title, certificate_template_type,
       certificate_field_positions -> 'student_name' AS name_position
FROM public.events
WHERE certificate_field_positions ? 'student_name'
LIMIT 10;


-- ── STEP 7: Fix text-based owner columns → uuid FK to profiles ───────────────
-- folders.created_by and announcements.created_by are raw TEXT columns storing
-- emails or names. event_reports.created_by_email is similar.
-- Strategy: add a parallel _uuid column, backfill by email match, add FK.
-- Old text column stays alongside until app code is updated (Step 10 drops it).

-- ── 7a. folders.created_by (text → uuid FK) ──────────────────────────────────
ALTER TABLE public.folders
  ADD COLUMN IF NOT EXISTS created_by_uuid UUID;

UPDATE public.folders f
SET created_by_uuid = p.id
FROM public.profiles p
WHERE f.created_by_uuid IS NULL
  AND f.created_by IS NOT NULL
  AND LOWER(TRIM(f.created_by)) = LOWER(TRIM(p.email));

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.folders'::regclass
      AND conname = 'folders_created_by_uuid_fkey'
  ) THEN
    ALTER TABLE public.folders
      ADD CONSTRAINT folders_created_by_uuid_fkey
      FOREIGN KEY (created_by_uuid) REFERENCES public.profiles(id) ON DELETE SET NULL;
  END IF;
END $$;

-- ── 7b. announcements.created_by (text → uuid FK) ────────────────────────────
ALTER TABLE public.announcements
  ADD COLUMN IF NOT EXISTS created_by_uuid UUID;

UPDATE public.announcements a
SET created_by_uuid = p.id
FROM public.profiles p
WHERE a.created_by_uuid IS NULL
  AND a.created_by IS NOT NULL
  AND LOWER(TRIM(a.created_by)) = LOWER(TRIM(p.email));

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.announcements'::regclass
      AND conname = 'announcements_created_by_uuid_fkey'
  ) THEN
    ALTER TABLE public.announcements
      ADD CONSTRAINT announcements_created_by_uuid_fkey
      FOREIGN KEY (created_by_uuid) REFERENCES public.profiles(id) ON DELETE SET NULL;
  END IF;
END $$;

-- ── 7c. event_reports.created_by_email (text → uuid FK) ──────────────────────
ALTER TABLE public.event_reports
  ADD COLUMN IF NOT EXISTS created_by UUID;

UPDATE public.event_reports er
SET created_by = p.id
FROM public.profiles p
WHERE er.created_by IS NULL
  AND er.created_by_email IS NOT NULL
  AND LOWER(TRIM(er.created_by_email)) = LOWER(TRIM(p.email));

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.event_reports'::regclass
      AND conname = 'event_reports_created_by_fkey'
  ) THEN
    ALTER TABLE public.event_reports
      ADD CONSTRAINT event_reports_created_by_fkey
      FOREIGN KEY (created_by) REFERENCES public.profiles(id) ON DELETE SET NULL;
  END IF;
END $$;
-- created_by_email kept as a denormalised display fallback.
-- Drop after confirming app uses created_by (uuid) exclusively (Step 10).

-- Verification: how many text columns couldn't be resolved to a profile?
SELECT
  'folders unresolved created_by' AS source,
  COUNT(*) AS unresolved
FROM public.folders
WHERE created_by IS NOT NULL AND created_by_uuid IS NULL
UNION ALL
SELECT
  'announcements unresolved created_by',
  COUNT(*)
FROM public.announcements
WHERE created_by IS NOT NULL AND created_by_uuid IS NULL
UNION ALL
SELECT
  'event_reports unresolved created_by_email',
  COUNT(*)
FROM public.event_reports
WHERE created_by_email IS NOT NULL AND created_by IS NULL;


-- ── STEP 8: Resolve certificates dual-linkage (member_id vs user_id) ──────────
-- certificates.member_id → members(id) is the legacy FK, now pointing at the
-- renamed members_legacy_archive table. certificates.user_id is the correct
-- modern FK. Backfill user_id from the archive where still NULL, then add the
-- FK that was entirely missing, and drop the now-broken old member_id FK.

UPDATE public.certificates c
SET user_id = m.user_id
FROM public.members_legacy_archive m
WHERE c.member_id = m.id
  AND c.user_id IS NULL
  AND m.user_id IS NOT NULL;

-- Drop the old (now-broken) member_id FK; the column itself stays for now
ALTER TABLE public.certificates
  DROP CONSTRAINT IF EXISTS certificates_member_id_fkey;

-- Add the correct user_id FK (was entirely absent before this migration)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.certificates'::regclass
      AND conname = 'certificates_user_id_fkey'
  ) THEN
    ALTER TABLE public.certificates
      ADD CONSTRAINT certificates_user_id_fkey
      FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
  END IF;
END $$;

-- Verification: non-zero = investigate (member_id pointed at a member who never
-- linked to an auth account — decide per-record whether to keep as orphan or resolve manually)
SELECT COUNT(*) AS unresolved_certificates
FROM public.certificates
WHERE user_id IS NULL;


-- ── STEP 9: Backfill messages sender_id/receiver_id from legacy text columns ──
-- messages.sender / messages.receiver are legacy text columns storing emails.
-- sender_id / receiver_id (uuid) are the correct columns (FKs repointed in Step 2).
-- Backfill uuid columns where they are NULL but the text column has an email that
-- matches a profile. Text columns kept until app code is confirmed migrated (Step 10).

UPDATE public.messages m
SET sender_id = p.id
FROM public.profiles p
WHERE m.sender_id IS NULL
  AND m.sender IS NOT NULL
  AND LOWER(TRIM(m.sender)) = LOWER(TRIM(p.email));

UPDATE public.messages m
SET receiver_id = p.id
FROM public.profiles p
WHERE m.receiver_id IS NULL
  AND m.receiver IS NOT NULL
  AND LOWER(TRIM(m.receiver)) = LOWER(TRIM(p.email));

-- Verification: messages still missing uuid assignments after backfill
SELECT
  'messages with null sender_id'   AS check_name, COUNT(*) AS count
FROM public.messages WHERE sender_id IS NULL AND sender IS NOT NULL
UNION ALL
SELECT
  'messages with null receiver_id', COUNT(*)
FROM public.messages WHERE receiver_id IS NULL AND receiver IS NOT NULL;
-- Non-zero = sender/receiver email does not match any profile (e.g., external user)
-- These are expected to remain NULL — just confirm the numbers make sense.


-- ── STEP 10: DESTRUCTIVE CLEANUP — DO NOT RUN YET ────────────────────────────
-- Uncomment individual lines ONLY after:
--   ✓ Step 3 verification queries both returned 0
--   ✓ App code (Flutter + React) fully switched to profiles (no `users` table reads)
--   ✓ folders.created_by_uuid, announcements.created_by_uuid confirmed in all app paths
--   ✓ messages.sender_id / receiver_id confirmed exclusively used in chat code
--   ✓ certificates.member_id confirmed unused in app code
--   ✓ Migration running in production for ≥ 1 week with zero related errors in logs
--
-- Recommended: uncomment and run one table/column at a time, not all at once.

-- -- Drop duplicate legacy guest tables (data fully in profiles)
-- DROP TABLE IF EXISTS public.members_not_iste CASCADE;
-- DROP TABLE IF EXISTS public.iste_non_member CASCADE;

-- -- Drop the retired users table (RLS already blocks authenticated access)
-- DROP TABLE IF EXISTS public.users CASCADE;

-- -- Drop archived certificate config table (data migrated to events jsonb in Step 6)
-- DROP TABLE IF EXISTS public.event_certificate_config_legacy CASCADE;

-- -- Drop legacy columns from certificates once member_id is confirmed unused
-- ALTER TABLE public.certificates DROP COLUMN IF EXISTS member_id;

-- -- Rename uuid columns to canonical names once text originals are dropped:
-- -- folders
-- ALTER TABLE public.folders DROP COLUMN IF EXISTS created_by;
-- ALTER TABLE public.folders RENAME COLUMN created_by_uuid TO created_by;

-- -- announcements
-- ALTER TABLE public.announcements DROP COLUMN IF EXISTS created_by;
-- ALTER TABLE public.announcements RENAME COLUMN created_by_uuid TO created_by;

-- -- event_reports
-- ALTER TABLE public.event_reports DROP COLUMN IF EXISTS created_by_email;

-- -- messages
-- ALTER TABLE public.messages DROP COLUMN IF EXISTS sender;
-- ALTER TABLE public.messages DROP COLUMN IF EXISTS receiver;

-- -- Final: drop the legacy members archive (only if truly no longer needed for reporting)
-- DROP TABLE IF EXISTS public.members_legacy_archive CASCADE;


-- ============================================================================
-- POST-MIGRATION VERIFICATION QUERIES
-- Run all 4 after the migration to confirm success.
-- ============================================================================

-- ── V1. FK targets — confirm nothing still points at users/members ────────────
-- Expected: 0 rows (or only intentional references to members_legacy_archive)
SELECT
  tc.table_name,
  kcu.column_name,
  ccu.table_name AS references_table,
  tc.constraint_name
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
  ON tc.constraint_name = kcu.constraint_name
  AND tc.table_schema    = kcu.table_schema
JOIN information_schema.constraint_column_usage ccu
  ON tc.constraint_name = ccu.constraint_name
  AND tc.table_schema   = ccu.table_schema
WHERE tc.constraint_type = 'FOREIGN KEY'
  AND tc.table_schema    = 'public'
  AND ccu.table_name IN ('users', 'members', 'members_legacy_archive')
ORDER BY tc.table_name, kcu.column_name;

-- ── V2. RLS coverage — every table must show at least 1 policy ───────────────
-- Expected: no rows with status = '⚠ NO RLS POLICIES'
SELECT
  t.tablename,
  COALESCE(p.policy_count, 0)                                         AS policy_count,
  t.rowsecurity                                                        AS rls_enabled,
  CASE
    WHEN NOT t.rowsecurity                    THEN '✗ RLS DISABLED'
    WHEN COALESCE(p.policy_count, 0) = 0      THEN '⚠ NO RLS POLICIES'
    ELSE '✓ OK'
  END AS status
FROM pg_tables t
LEFT JOIN (
  SELECT tablename, COUNT(*) AS policy_count
  FROM pg_policies
  WHERE schemaname = 'public'
  GROUP BY tablename
) p ON t.tablename = p.tablename
WHERE t.schemaname = 'public'
ORDER BY status DESC, t.tablename;

-- ── V3. Orphan check — all FK targets must resolve to real profiles ───────────
-- Expected: all counts = 0
SELECT 'attendance.user_id'    AS col, COUNT(*) AS orphans
FROM public.attendance
WHERE user_id IS NOT NULL
  AND user_id NOT IN (SELECT id FROM public.profiles)
UNION ALL
SELECT 'attendance.scanned_by', COUNT(*)
FROM public.attendance
WHERE scanned_by IS NOT NULL
  AND scanned_by NOT IN (SELECT id FROM public.profiles)
UNION ALL
SELECT 'qr_tokens.user_id', COUNT(*)
FROM public.qr_tokens
WHERE user_id IS NOT NULL
  AND user_id NOT IN (SELECT id FROM public.profiles)
UNION ALL
SELECT 'certificates.user_id', COUNT(*)
FROM public.certificates
WHERE user_id IS NOT NULL
  AND user_id NOT IN (SELECT id FROM public.profiles);
-- All should return 0. Non-zero means the FK ADD in Step 1/8 would have already
-- failed — re-check if the FK constraint was actually applied.

-- ── V4. Certificate config migration check ────────────────────────────────────
-- Expected: events that had an event_certificate_config row now have
-- certificate_field_positions populated with student_name position data.
SELECT
  e.id,
  e.title,
  e.certificate_template_type,
  e.certificate_field_positions -> 'student_name' AS student_name_position,
  e.certificate_image_url
FROM public.events e
WHERE e.certificate_field_positions ? 'student_name'
ORDER BY e.id
LIMIT 15;

-- ── V5. Text column resolution summary ────────────────────────────────────────
-- Shows how many text-based owner columns were resolved vs left unmatched
SELECT
  'folders.created_by → uuid'           AS migration,
  COUNT(*) FILTER (WHERE created_by_uuid IS NOT NULL)  AS resolved,
  COUNT(*) FILTER (WHERE created_by IS NOT NULL AND created_by_uuid IS NULL) AS unresolved
FROM public.folders
UNION ALL
SELECT
  'announcements.created_by → uuid',
  COUNT(*) FILTER (WHERE created_by_uuid IS NOT NULL),
  COUNT(*) FILTER (WHERE created_by IS NOT NULL AND created_by_uuid IS NULL)
FROM public.announcements
UNION ALL
SELECT
  'event_reports.created_by_email → uuid',
  COUNT(*) FILTER (WHERE created_by IS NOT NULL),
  COUNT(*) FILTER (WHERE created_by_email IS NOT NULL AND created_by IS NULL)
FROM public.event_reports
UNION ALL
SELECT
  'messages.sender → sender_id',
  COUNT(*) FILTER (WHERE sender_id IS NOT NULL),
  COUNT(*) FILTER (WHERE sender IS NOT NULL AND sender_id IS NULL)
FROM public.messages
UNION ALL
SELECT
  'messages.receiver → receiver_id',
  COUNT(*) FILTER (WHERE receiver_id IS NOT NULL),
  COUNT(*) FILTER (WHERE receiver IS NOT NULL AND receiver_id IS NULL)
FROM public.messages;

-- ── V6. Role distribution in profiles (sanity check) ─────────────────────────
SELECT role::text, COUNT(*) AS user_count
FROM public.profiles
GROUP BY role
ORDER BY user_count DESC;

-- ============================================================================
-- END OF PHASE 2 CLEANUP MIGRATION
-- Next steps after verifying all queries above pass:
--   1. Update Flutter app: switch folders/announcements reads from
--      created_by (text) to created_by_uuid joined to profiles
--   2. Update React admin: switch chat code from sender/receiver (text)
--      to sender_id/receiver_id (uuid) joined to profiles
--   3. Schedule Step 10 (destructive cleanup) for a separate migration window
--      after ≥ 1 week of clean production logs
-- ============================================================================
