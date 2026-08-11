-- ============================================================================
-- ISTE Lynq: RLS ROLE-HIERARCHY BUGFIX + Certificate Template Storage Setup
-- File: supabase/migrations/20260811_rls_role_hierarchy_bugfix.sql
-- ============================================================================
-- BUG: All prior RLS policies used text >= comparison, e.g.:
--   (SELECT role FROM profiles WHERE id = auth.uid())::text >= 'core_execcom'::text
-- This is ALPHABETICAL, not tier-based. Alphabetical order of roles:
--   chairman < core_execcom < forum_execcom < member < panel < restricted < vice_chairman
-- So 'member' > 'core_execcom' alphabetically → members pass execom checks. CRITICAL.
--
-- FIX: Replace with role_rank() integer comparison everywhere.
-- ============================================================================


-- ── FIX 1: Role rank helper functions ────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.role_rank(r public.app_role)
RETURNS INTEGER
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE r
    WHEN 'member'        THEN 1
    WHEN 'restricted'    THEN 2
    WHEN 'panel'         THEN 3
    WHEN 'forum_execcom' THEN 4
    WHEN 'core_execcom'  THEN 5
    WHEN 'vice_chairman' THEN 6
    WHEN 'chairman'      THEN 7
    ELSE 0
  END;
$$;

-- Convenience wrapper: rank of the current auth user (avoids repeating subquery in every policy)
CREATE OR REPLACE FUNCTION public.my_role_rank()
RETURNS INTEGER
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT public.role_rank(role) FROM public.profiles WHERE id = auth.uid();
$$;


-- ── FIX 2: Recreate every broken policy with proper rank comparison ───────────
-- Replacing: role::text >= 'X'::text
-- With:      public.my_role_rank() >= public.role_rank('X')

-- ── events ───────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Execom sees all events"      ON public.events;
DROP POLICY IF EXISTS "Members see permitted events" ON public.events;
DROP POLICY IF EXISTS "Execom manages events"        ON public.events;

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
  USING    (public.my_role_rank() >= public.role_rank('forum_execcom'))
  WITH CHECK (public.my_role_rank() >= public.role_rank('forum_execcom'));

-- ── profiles ─────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Execom reads all profiles" ON public.profiles;

CREATE POLICY "Execom reads all profiles"
  ON public.profiles FOR SELECT TO authenticated
  USING (public.my_role_rank() >= public.role_rank('core_execcom'));

-- ── attendance ───────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Execom reads all attendance" ON public.attendance;
DROP POLICY IF EXISTS "Execom manages attendance"   ON public.attendance;

CREATE POLICY "Execom reads all attendance"
  ON public.attendance FOR SELECT TO authenticated
  USING (public.my_role_rank() >= public.role_rank('forum_execcom'));

CREATE POLICY "Execom manages attendance"
  ON public.attendance FOR ALL TO authenticated
  USING    (public.my_role_rank() >= public.role_rank('forum_execcom'))
  WITH CHECK (public.my_role_rank() >= public.role_rank('forum_execcom'));

-- ── certificates ─────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Execom reads all certificates" ON public.certificates;

CREATE POLICY "Execom reads all certificates"
  ON public.certificates FOR SELECT TO authenticated
  USING (public.my_role_rank() >= public.role_rank('forum_execcom'));

-- ── folders ──────────────────────────────────────────────────────────────────
-- NOTE: folders.owner_id may not exist — policy falls back to chairman-only
-- if your folders table has no owner_id column, remove that clause.
DROP POLICY IF EXISTS "Folder owners manage"   ON public.folders;
DROP POLICY IF EXISTS "Execom manages folders" ON public.folders;

CREATE POLICY "Execom manages folders"
  ON public.folders FOR ALL TO authenticated
  USING    (public.my_role_rank() >= public.role_rank('core_execcom'))
  WITH CHECK (public.my_role_rank() >= public.role_rank('core_execcom'));

-- ── folder_members ────────────────────────────────────────────────────────────
-- IMPORTANT: folder_members uses execom_id + execom_role (NOT folder_id/folder_role)
-- as noted in Phase 1 migration header. Fixed here.
DROP POLICY IF EXISTS "Folder heads manage memberships" ON public.folder_members;
DROP POLICY IF EXISTS "Execom manages folder members"   ON public.folder_members;

CREATE POLICY "Execom manages folder members"
  ON public.folder_members FOR ALL TO authenticated
  USING (
    public.my_role_rank() >= public.role_rank('core_execcom')
    OR execom_id IN (
      SELECT fm.execom_id FROM public.folder_members fm
      WHERE fm.user_id = auth.uid()
        AND fm.execom_role IN ('head', 'chair')
    )
  )
  WITH CHECK (
    public.my_role_rank() >= public.role_rank('core_execcom')
    OR execom_id IN (
      SELECT fm.execom_id FROM public.folder_members fm
      WHERE fm.user_id = auth.uid()
        AND fm.execom_role IN ('head', 'chair')
    )
  );

-- ── folder_permissions ────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Folder heads manage permissions" ON public.folder_permissions;
DROP POLICY IF EXISTS "Execom manages folder permissions" ON public.folder_permissions;

CREATE POLICY "Execom manages folder permissions"
  ON public.folder_permissions FOR ALL TO authenticated
  USING (
    public.my_role_rank() >= public.role_rank('core_execcom')
    OR execom_id IN (
      SELECT fm.execom_id FROM public.folder_members fm
      WHERE fm.user_id = auth.uid()
        AND fm.execom_role IN ('head', 'chair')
    )
  )
  WITH CHECK (
    public.my_role_rank() >= public.role_rank('core_execcom')
    OR execom_id IN (
      SELECT fm.execom_id FROM public.folder_members fm
      WHERE fm.user_id = auth.uid()
        AND fm.execom_role IN ('head', 'chair')
    )
  );

-- ── financial_ledger ─────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Execom manages ledger"      ON public.financial_ledger;
DROP POLICY IF EXISTS "Folder members read ledger" ON public.financial_ledger;

CREATE POLICY "Folder members read ledger"
  ON public.financial_ledger FOR SELECT TO authenticated
  USING (
    execom_id IN (
      SELECT fm.execom_id FROM public.folder_members fm WHERE fm.user_id = auth.uid()
    )
    OR public.my_role_rank() >= public.role_rank('core_execcom')
  );

-- Only forum heads / treasurers / core+ can write ledger entries
CREATE POLICY "Execom manages ledger"
  ON public.financial_ledger FOR INSERT TO authenticated
  WITH CHECK (
    public.my_role_rank() >= public.role_rank('core_execcom')
    OR execom_id IN (
      SELECT fm.execom_id FROM public.folder_members fm
      WHERE fm.user_id = auth.uid()
        AND fm.execom_role IN ('head', 'chair', 'treasurer')
    )
  );

-- ── financial_income ─────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Execom manages income"       ON public.financial_income;
DROP POLICY IF EXISTS "Folder members read income"  ON public.financial_income;

CREATE POLICY "Folder members read income"
  ON public.financial_income FOR SELECT TO authenticated
  USING (
    execom_id IN (
      SELECT fm.execom_id FROM public.folder_members fm WHERE fm.user_id = auth.uid()
    )
    OR public.my_role_rank() >= public.role_rank('core_execcom')
  );

CREATE POLICY "Execom manages income"
  ON public.financial_income FOR ALL TO authenticated
  USING    (public.my_role_rank() >= public.role_rank('core_execcom'))
  WITH CHECK (public.my_role_rank() >= public.role_rank('core_execcom'));

-- ── forum_budgets ─────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Execom manages forum budgets"       ON public.forum_budgets;
DROP POLICY IF EXISTS "Folder members read forum budgets"  ON public.forum_budgets;

CREATE POLICY "Folder members read forum budgets"
  ON public.forum_budgets FOR SELECT TO authenticated
  USING (
    execom_id IN (
      SELECT fm.execom_id FROM public.folder_members fm WHERE fm.user_id = auth.uid()
    )
    OR public.my_role_rank() >= public.role_rank('core_execcom')
  );

CREATE POLICY "Execom manages forum budgets"
  ON public.forum_budgets FOR ALL TO authenticated
  USING    (public.my_role_rank() >= public.role_rank('core_execcom'))
  WITH CHECK (public.my_role_rank() >= public.role_rank('core_execcom'));

-- ── event_budgets ─────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Execom manages event budgets"       ON public.event_budgets;
DROP POLICY IF EXISTS "Folder members read event budgets"  ON public.event_budgets;

CREATE POLICY "Folder members read event budgets"
  ON public.event_budgets FOR SELECT TO authenticated
  USING (
    execom_id IN (
      SELECT fm.execom_id FROM public.folder_members fm WHERE fm.user_id = auth.uid()
    )
    OR public.my_role_rank() >= public.role_rank('core_execcom')
  );

CREATE POLICY "Execom manages event budgets"
  ON public.event_budgets FOR ALL TO authenticated
  USING    (public.my_role_rank() >= public.role_rank('core_execcom'))
  WITH CHECK (public.my_role_rank() >= public.role_rank('core_execcom'));

-- ── budget_requests ───────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Execom manages budget requests" ON public.budget_requests;

CREATE POLICY "Execom manages budget requests"
  ON public.budget_requests FOR ALL TO authenticated
  USING    (public.my_role_rank() >= public.role_rank('forum_execcom'))
  WITH CHECK (public.my_role_rank() >= public.role_rank('forum_execcom'));

-- ── event_reports ─────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Members read visible reports" ON public.event_reports;
DROP POLICY IF EXISTS "Execom manages reports"        ON public.event_reports;

CREATE POLICY "Members read visible reports"
  ON public.event_reports FOR SELECT TO authenticated
  USING (
    public.my_role_rank() >= public.role_rank('forum_execcom')
    OR (SELECT role::text FROM public.profiles WHERE id = auth.uid()) = ANY(visibility)
    OR visibility IS NULL
    OR visibility = '{}'::text[]
  );

CREATE POLICY "Execom manages reports"
  ON public.event_reports FOR ALL TO authenticated
  USING    (public.my_role_rank() >= public.role_rank('forum_execcom'))
  WITH CHECK (public.my_role_rank() >= public.role_rank('forum_execcom'));

-- ── budget_categories ─────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Execom manages categories" ON public.budget_categories;

CREATE POLICY "Execom manages categories"
  ON public.budget_categories FOR ALL TO authenticated
  USING    (public.my_role_rank() >= public.role_rank('core_execcom'))
  WITH CHECK (public.my_role_rank() >= public.role_rank('core_execcom'));

-- ── event_certificate_config_legacy ──────────────────────────────────────────
-- Guarded: only applies if the legacy table still exists (may have been dropped in Step 10)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'event_certificate_config_legacy'
  ) THEN
    DROP POLICY IF EXISTS "Execom manages cert config" ON public.event_certificate_config_legacy;
    EXECUTE $p$
      CREATE POLICY "Execom manages cert config"
        ON public.event_certificate_config_legacy FOR ALL TO authenticated
        USING    (public.my_role_rank() >= public.role_rank('forum_execcom'))
        WITH CHECK (public.my_role_rank() >= public.role_rank('forum_execcom'))
    $p$;
  END IF;
END $$;

-- ── ledger_change_history ─────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Execom reads ledger history" ON public.ledger_change_history;

CREATE POLICY "Execom reads ledger history"
  ON public.ledger_change_history FOR SELECT TO authenticated
  USING (public.my_role_rank() >= public.role_rank('core_execcom'));

-- ── registration_queue ────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Execom reviews registrations" ON public.registration_queue;
DROP POLICY IF EXISTS "Execom updates registrations" ON public.registration_queue;

CREATE POLICY "Execom reviews registrations"
  ON public.registration_queue FOR SELECT TO authenticated
  USING (public.my_role_rank() >= public.role_rank('forum_execcom'));

CREATE POLICY "Execom updates registrations"
  ON public.registration_queue FOR UPDATE TO authenticated
  USING    (public.my_role_rank() >= public.role_rank('forum_execcom'))
  WITH CHECK (public.my_role_rank() >= public.role_rank('forum_execcom'));

-- ── members_legacy_archive ────────────────────────────────────────────────────
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'members_legacy_archive'
  ) THEN
    DROP POLICY IF EXISTS "Execom reads legacy members archive" ON public.members_legacy_archive;
    EXECUTE $p$
      CREATE POLICY "Execom reads legacy members archive"
        ON public.members_legacy_archive FOR SELECT TO authenticated
        USING (public.my_role_rank() >= public.role_rank('core_execcom'))
    $p$;
  END IF;
END $$;

-- ── announcements ─────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Execom reads all announcements" ON public.announcements;
DROP POLICY IF EXISTS "Execom manages announcements"   ON public.announcements;

CREATE POLICY "Execom reads all announcements"
  ON public.announcements FOR SELECT TO authenticated
  USING (public.my_role_rank() >= public.role_rank('forum_execcom'));

CREATE POLICY "Execom manages announcements"
  ON public.announcements FOR ALL TO authenticated
  USING    (public.my_role_rank() >= public.role_rank('forum_execcom'))
  WITH CHECK (public.my_role_rank() >= public.role_rank('forum_execcom'));

-- ── qr_tokens ────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Execom manages qr_tokens" ON public.qr_tokens;

CREATE POLICY "Execom manages qr_tokens"
  ON public.qr_tokens FOR ALL TO authenticated
  USING    (public.my_role_rank() >= public.role_rank('forum_execcom'))
  WITH CHECK (public.my_role_rank() >= public.role_rank('forum_execcom'));

-- ── tasks / task_proofs ───────────────────────────────────────────────────────
-- Guard: only apply if these tables exist and had old-style policies
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'tasks') THEN
    ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;
    DROP POLICY IF EXISTS "Execom manages tasks" ON public.tasks;
    EXECUTE $p$
      CREATE POLICY "Execom manages tasks"
        ON public.tasks FOR ALL TO authenticated
        USING    (public.my_role_rank() >= public.role_rank('forum_execcom'))
        WITH CHECK (public.my_role_rank() >= public.role_rank('forum_execcom'))
    $p$;
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'task_proofs') THEN
    ALTER TABLE public.task_proofs ENABLE ROW LEVEL SECURITY;
    DROP POLICY IF EXISTS "Execom manages task_proofs" ON public.task_proofs;
    EXECUTE $p$
      CREATE POLICY "Execom manages task_proofs"
        ON public.task_proofs FOR ALL TO authenticated
        USING    (public.my_role_rank() >= public.role_rank('forum_execcom'))
        WITH CHECK (public.my_role_rank() >= public.role_rank('forum_execcom'))
    $p$;
  END IF;
END $$;


-- ── VERIFY: rank function output ─────────────────────────────────────────────
SELECT
  role_val,
  public.role_rank(role_val::public.app_role) AS rank
FROM unnest(ARRAY[
  'member','restricted','panel','forum_execcom',
  'core_execcom','vice_chairman','chairman'
]) AS role_val
ORDER BY rank;
-- Expected: member=1, restricted=2, panel=3, forum_execcom=4,
--           core_execcom=5, vice_chairman=6, chairman=7

-- Spot-check: a real user's rank (replace with an actual execom user's UUID)
-- SELECT public.my_role_rank(), (SELECT role FROM public.profiles WHERE id = auth.uid());


-- ============================================================================
-- CERTIFICATE TEMPLATE STORAGE SETUP
-- ============================================================================

-- Bucket for template background images (separate from 'certificates' bucket
-- which holds generated per-student PDFs)
INSERT INTO storage.buckets (id, name, public)
VALUES ('certificate_templates', 'certificate_templates', true)
ON CONFLICT (id) DO NOTHING;

-- Storage RLS: execom uploads/updates, anyone reads (images aren't sensitive)
DROP POLICY IF EXISTS "Execom uploads cert templates" ON storage.objects;
DROP POLICY IF EXISTS "Execom updates cert templates" ON storage.objects;
DROP POLICY IF EXISTS "Anyone reads cert templates"   ON storage.objects;

CREATE POLICY "Execom uploads cert templates"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'certificate_templates'
    AND public.my_role_rank() >= public.role_rank('forum_execcom')
  );

CREATE POLICY "Execom updates cert templates"
  ON storage.objects FOR UPDATE TO authenticated
  USING (
    bucket_id = 'certificate_templates'
    AND public.my_role_rank() >= public.role_rank('forum_execcom')
  );

CREATE POLICY "Anyone reads cert templates"
  ON storage.objects FOR SELECT TO public
  USING (bucket_id = 'certificate_templates');

-- ============================================================================
-- END OF RLS BUGFIX + STORAGE SETUP
-- ============================================================================
