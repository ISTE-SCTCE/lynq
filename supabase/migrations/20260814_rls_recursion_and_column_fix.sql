-- ============================================================================
-- FIX: Infinite Recursion in folder_members RLS + Wrong Column Names
-- File: supabase/migrations/20260814_rls_recursion_and_column_fix.sql
-- ============================================================================
-- BUG 1 (recursion): Earlier policies on folder_members did:
--   USING (folder_id IN (SELECT fm.folder_id FROM folder_members fm WHERE ...))
-- A policy ON folder_members that queries folder_members INSIDE its own
-- USING clause causes Postgres to recursively re-evaluate the same policy
-- for the subquery, forever -> "infinite recursion detected in policy for
-- relation folder_members".
--
-- BUG 2 (wrong columns): The live schema's actual column names on
-- folder_members are `execom_id` and `execom_role` — NOT `folder_id` /
-- `folder_role` as earlier migration drafts assumed. Same mismatch exists
-- in policies on financial_ledger, forum_budgets, event_budgets that
-- reference folder_members. This fix corrects both issues everywhere.
--
-- FIX: SECURITY DEFINER helper functions bypass RLS when querying
-- folder_members internally, breaking the recursion. Policies then call
-- the function instead of subquerying the same table directly.
-- ============================================================================

-- ── Helper functions (bypass RLS internally, safe to call from any policy) ─

CREATE OR REPLACE FUNCTION public.my_execom_head_ids()
RETURNS SETOF BIGINT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT execom_id FROM public.folder_members
  WHERE user_id = auth.uid() AND execom_role IN ('head', 'chair', 'treasurer');
$$;

CREATE OR REPLACE FUNCTION public.my_execom_member_ids()
RETURNS SETOF BIGINT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT execom_id FROM public.folder_members
  WHERE user_id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION public.is_execom_member(target_execom_id BIGINT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.folder_members
    WHERE user_id = auth.uid() AND execom_id = target_execom_id
  );
$$;

-- ── Fix folder_members policies (the recursion source) ─────────────────────

DROP POLICY IF EXISTS "Users read own folder memberships" ON public.folder_members;
CREATE POLICY "Users read own folder memberships" ON public.folder_members FOR SELECT TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Folder heads read memberships" ON public.folder_members;
CREATE POLICY "Folder heads read memberships" ON public.folder_members FOR SELECT TO authenticated
  USING (
    public.my_role_rank() >= public.role_rank('core_execcom')
    OR execom_id IN (SELECT public.my_execom_head_ids())
  );

DROP POLICY IF EXISTS "Folder heads manage memberships" ON public.folder_members;
CREATE POLICY "Folder heads manage memberships" ON public.folder_members FOR ALL TO authenticated
  USING (
    public.my_role_rank() >= public.role_rank('chairman')
    OR execom_id IN (SELECT public.my_execom_head_ids())
  )
  WITH CHECK (
    public.my_role_rank() >= public.role_rank('chairman')
    OR execom_id IN (SELECT public.my_execom_head_ids())
  );

-- ── Fix folder_permissions policies (correct column, use helper fn) ────────

DROP POLICY IF EXISTS "Execom reads folder permissions" ON public.folder_permissions;
DROP POLICY IF EXISTS "Folder heads manage permissions" ON public.folder_permissions;
CREATE POLICY "Execom reads folder permissions" ON public.folder_permissions FOR SELECT TO authenticated
  USING (
    public.my_role_rank() >= public.role_rank('core_execcom')
    OR execom_id IN (SELECT public.my_execom_member_ids())
  );
CREATE POLICY "Folder heads manage permissions" ON public.folder_permissions FOR ALL TO authenticated
  USING (
    public.my_role_rank() >= public.role_rank('chairman')
    OR execom_id IN (SELECT public.my_execom_head_ids())
  )
  WITH CHECK (
    public.my_role_rank() >= public.role_rank('chairman')
    OR execom_id IN (SELECT public.my_execom_head_ids())
  );

-- ── Fix folders policy (uses folder_members subquery indirectly — was fine,
--    no recursion since it's a different table, but standardize on helper) ──

DROP POLICY IF EXISTS "Folder members can read" ON public.folders;
CREATE POLICY "Folder members can read" ON public.folders FOR SELECT TO authenticated
  USING (
    public.my_role_rank() >= public.role_rank('forum_execcom')
    OR id IN (SELECT public.my_execom_member_ids())
  );

DROP POLICY IF EXISTS "Execom manages folders" ON public.folders;
CREATE POLICY "Execom manages folders" ON public.folders FOR ALL TO authenticated
  USING (public.my_role_rank() >= public.role_rank('core_execcom'))
  WITH CHECK (public.my_role_rank() >= public.role_rank('core_execcom'));

-- ── Fix financial_ledger, forum_budgets, event_budgets (wrong column was
--    `folder_id` — real column is `execom_id`; also fix the folder_members
--    subquery reference to use the correct execom_id/user_id columns) ──────

DROP POLICY IF EXISTS "Folder members read ledger" ON public.financial_ledger;
CREATE POLICY "Folder members read ledger" ON public.financial_ledger FOR SELECT TO authenticated
  USING (execom_id IN (SELECT public.my_execom_member_ids()));

DROP POLICY IF EXISTS "Folder members read forum budgets" ON public.forum_budgets;
CREATE POLICY "Folder members read forum budgets" ON public.forum_budgets FOR SELECT TO authenticated
  USING (execom_id IN (SELECT public.my_execom_member_ids()));

DROP POLICY IF EXISTS "Folder members read event budgets" ON public.event_budgets;
CREATE POLICY "Folder members read event budgets" ON public.event_budgets FOR SELECT TO authenticated
  USING (execom_id IN (SELECT public.my_execom_member_ids()));

DROP POLICY IF EXISTS "Folder members read income" ON public.financial_income;
CREATE POLICY "Folder members read income" ON public.financial_income FOR SELECT TO authenticated
  USING (execom_id IN (SELECT public.my_execom_member_ids()));

-- ── VERIFY: this must run without error now (previously threw recursion) ──

SELECT * FROM public.folder_members LIMIT 1;
SELECT * FROM public.folder_permissions LIMIT 1;

-- ── VERIFY: helper functions work ───────────────────────────────────────
SELECT public.my_execom_member_ids();
SELECT public.my_execom_head_ids();

-- ============================================================================
-- END OF RECURSION + COLUMN NAME FIX
-- ============================================================================
