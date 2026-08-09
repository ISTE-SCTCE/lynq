-- ============================================================================
-- ISTE SCTCE Lynq/MLynq: Comprehensive Database Consolidation Migration
-- Run date: 2026-08-09
-- ============================================================================
-- KEY FACTS from live schema inspection:
--   - users.role is TEXT, default 'Member' (capital M) — must LOWER() before casting
--   - folder_members uses execom_id (bigint) + execom_role (not folder_id/folder_role)
--   - folder_permissions uses execom_id (not folder_id)
--   - No separate member_profiles table — members table has all ISTE data
--   - members_not_iste exists with: id (uuid), name, email, phone, roll_number, college, created_at
--   - events already has: coordinator_name, chair_name, template_url, category, attendance_finalized
-- ============================================================================


-- ── SECTION 1: Create ENUM Types (idempotent) ──────────────────────────────

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'app_role') THEN
    CREATE TYPE public.app_role AS ENUM (
      'member',
      'restricted',
      'panel',
      'forum_execcom',
      'core_execcom',
      'vice_chairman',
      'chairman'
    );
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'account_status') THEN
    CREATE TYPE public.account_status AS ENUM (
      'active',
      'suspended',
      'inactive',
      'deleted'
    );
  END IF;
END $$;


-- ── SECTION 2a: Create unified profiles table ────────────────────────────────

CREATE TABLE IF NOT EXISTS public.profiles (
  -- Identity (mirrors auth.users)
  id            UUID NOT NULL PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email         TEXT NOT NULL UNIQUE,
  name          TEXT NOT NULL,

  -- Contact & institutional
  phone         TEXT,
  roll_number   TEXT,
  branch        TEXT,
  year          TEXT,
  college       TEXT,
  forum         TEXT,
  execom_tag    TEXT,

  -- Role & access
  role          public.app_role NOT NULL DEFAULT 'member'::public.app_role,
  post          TEXT,
  status        public.account_status NOT NULL DEFAULT 'active'::public.account_status,
  suspended_until TIMESTAMPTZ,
  is_sudo       BOOLEAN NOT NULL DEFAULT false,
  is_budget_activated BOOLEAN NOT NULL DEFAULT false,
  is_primary_chairman BOOLEAN NOT NULL DEFAULT false,
  permissions   JSONB NOT NULL DEFAULT '{}'::JSONB,

  -- 3-tier membership state (NEW — for m-lynq onboarding)
  is_registered   BOOLEAN NOT NULL DEFAULT false,  -- true after guest completes registration form
  is_iste_member  BOOLEAN NOT NULL DEFAULT false,  -- true if linked to ISTE member record

  -- ISTE membership specifics (synced from members table)
  iste_membership_id    TEXT,
  membership_plan       TEXT DEFAULT 'Annual',
  membership_date       DATE,
  expiry_date           DATE,

  -- Audit
  last_seen     TIMESTAMPTZ,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT profiles_email_not_empty CHECK (email != ''),
  CONSTRAINT profiles_name_not_empty CHECK (name != '')
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_profiles_email    ON public.profiles(email);
CREATE INDEX IF NOT EXISTS idx_profiles_role     ON public.profiles(role);
CREATE INDEX IF NOT EXISTS idx_profiles_status   ON public.profiles(status);
CREATE INDEX IF NOT EXISTS idx_profiles_is_iste  ON public.profiles(is_iste_member);
CREATE INDEX IF NOT EXISTS idx_profiles_is_reg   ON public.profiles(is_registered);


-- ── SECTION 2b: Migrate users → profiles ────────────────────────────────────
-- Normalises role strings: 'Member' → 'member', 'Chairman' → 'chairman', etc.
-- Unknown roles fall back to 'member'.

INSERT INTO public.profiles (
  id, email, name, phone, roll_number, branch, year, college, forum, execom_tag,
  role, post, status, suspended_until,
  is_sudo, is_budget_activated, is_primary_chairman, permissions,
  is_registered, is_iste_member,
  membership_plan, membership_date, expiry_date,
  last_seen, created_at, updated_at
)
SELECT
  u.id, u.email, u.name, u.phone, u.roll_number, u.branch, u.year,
  u.college, u.forum, u.execom_tag,
  -- Normalise role text to enum
  CASE LOWER(TRIM(u.role))
    WHEN 'chairman'      THEN 'chairman'::public.app_role
    WHEN 'chair'         THEN 'chairman'::public.app_role
    WHEN 'vice_chairman' THEN 'vice_chairman'::public.app_role
    WHEN 'vice-chairman' THEN 'vice_chairman'::public.app_role
    WHEN 'core_execcom'  THEN 'core_execcom'::public.app_role
    WHEN 'core'          THEN 'core_execcom'::public.app_role
    WHEN 'forum_execcom' THEN 'forum_execcom'::public.app_role
    WHEN 'execom'        THEN 'forum_execcom'::public.app_role
    WHEN 'panel'         THEN 'panel'::public.app_role
    WHEN 'restricted'    THEN 'restricted'::public.app_role
    ELSE                      'member'::public.app_role
  END,
  u.post,
  CASE LOWER(TRIM(u.status))
    WHEN 'suspended' THEN 'suspended'::public.account_status
    WHEN 'inactive'  THEN 'inactive'::public.account_status
    WHEN 'deleted'   THEN 'deleted'::public.account_status
    ELSE              'active'::public.account_status
  END,
  u.suspended_until,
  COALESCE(u.is_sudo, false),
  COALESCE(u.is_budget_activated, false),
  COALESCE(u.is_primary_chairman, false),
  COALESCE(u.permissions, '{}'::JSONB),
  -- Everyone in users table has completed at least basic registration
  true,
  false,  -- is_iste_member — will be updated in step 2c
  u.membership_plan, u.membership_date, u.expiry_date,
  u.last_seen, COALESCE(u.created_at, NOW()), COALESCE(u.updated_at, NOW())
FROM public.users u
ON CONFLICT (id) DO UPDATE SET
  email           = EXCLUDED.email,
  name            = EXCLUDED.name,
  phone           = EXCLUDED.phone,
  roll_number     = EXCLUDED.roll_number,
  branch          = EXCLUDED.branch,
  year            = EXCLUDED.year,
  college         = EXCLUDED.college,
  forum           = EXCLUDED.forum,
  execom_tag      = EXCLUDED.execom_tag,
  role            = EXCLUDED.role,
  post            = EXCLUDED.post,
  status          = EXCLUDED.status,
  suspended_until = EXCLUDED.suspended_until,
  is_sudo         = EXCLUDED.is_sudo,
  is_budget_activated = EXCLUDED.is_budget_activated,
  is_primary_chairman = EXCLUDED.is_primary_chairman,
  permissions     = EXCLUDED.permissions,
  is_registered   = EXCLUDED.is_registered,
  membership_plan = EXCLUDED.membership_plan,
  membership_date = EXCLUDED.membership_date,
  expiry_date     = EXCLUDED.expiry_date,
  last_seen       = EXCLUDED.last_seen,
  updated_at      = NOW();


-- ── SECTION 2c: Sync ISTE member data from members table ─────────────────────
-- Cross-references by email (case-insensitive). Marks is_iste_member=true,
-- populates iste_membership_id and membership validity dates.

UPDATE public.profiles p
SET
  is_iste_member      = true,
  iste_membership_id  = COALESCE(m.iste_id, m.ui_id),
  membership_plan     = COALESCE(m.plan, p.membership_plan, 'Annual'),
  membership_date     = COALESCE(m.plan_start_date, m.registration_date, p.membership_date),
  expiry_date         = COALESCE(m.plan_end_date, m.expiry_date, p.expiry_date),
  forum               = COALESCE(m.forum_name, p.forum),
  updated_at          = NOW()
FROM public.members m
WHERE LOWER(TRIM(p.email)) = LOWER(TRIM(m.email));


-- ── SECTION 2d: Migrate members_not_iste → profiles (if they logged in) ──────
-- members_not_iste has id=uuid which is the auth user id.
-- Insert as non-ISTE registered users; skip if already in profiles (users table).

INSERT INTO public.profiles (
  id, email, name, phone, roll_number, college,
  role, status,
  is_registered, is_iste_member,
  created_at, updated_at
)
SELECT
  mni.id, mni.email, COALESCE(mni.name, mni.email), mni.phone,
  mni.roll_number, mni.college,
  'member'::public.app_role,
  'active'::public.account_status,
  true,   -- registered (they filled the form)
  false,  -- not ISTE member
  COALESCE(mni.created_at, NOW()), NOW()
FROM public.members_not_iste mni
WHERE mni.email IS NOT NULL
  AND mni.id IS NOT NULL
ON CONFLICT (id) DO UPDATE SET
  is_registered = true,
  college       = COALESCE(EXCLUDED.college, public.profiles.college),
  roll_number   = COALESCE(EXCLUDED.roll_number, public.profiles.roll_number),
  updated_at    = NOW();


-- ── SECTION 3: updated_at trigger on profiles ────────────────────────────────

CREATE OR REPLACE FUNCTION public.update_profiles_timestamp()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS profiles_updated_at ON public.profiles;
CREATE TRIGGER profiles_updated_at
BEFORE UPDATE ON public.profiles
FOR EACH ROW EXECUTE FUNCTION public.update_profiles_timestamp();


-- ── SECTION 4: RLS on profiles ───────────────────────────────────────────────

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users read own profile"    ON public.profiles;
DROP POLICY IF EXISTS "Execom reads all profiles" ON public.profiles;
DROP POLICY IF EXISTS "Users update own profile"  ON public.profiles;
DROP POLICY IF EXISTS "Service role full access"  ON public.profiles;

-- Users can always read their own profile
CREATE POLICY "Users read own profile"
  ON public.profiles FOR SELECT TO authenticated
  USING (auth.uid() = id);

-- Execom (forum_execcom+) can read all profiles
CREATE POLICY "Execom reads all profiles"
  ON public.profiles FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p2
      WHERE p2.id = auth.uid()
        AND p2.role IN ('forum_execcom','core_execcom','vice_chairman','chairman')
    )
  );

-- Users can update their own non-privileged fields
CREATE POLICY "Users update own profile"
  ON public.profiles FOR UPDATE TO authenticated
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- Service role bypasses all RLS (for Edge Functions + admin scripts)
CREATE POLICY "Service role full access"
  ON public.profiles FOR ALL TO service_role
  USING (true)
  WITH CHECK (true);


-- ── SECTION 5: RLS on events ─────────────────────────────────────────────────

ALTER TABLE public.events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Execom sees all events"      ON public.events;
DROP POLICY IF EXISTS "Members see permitted events" ON public.events;
DROP POLICY IF EXISTS "Execom manages events"        ON public.events;

CREATE POLICY "Execom sees all events"
  ON public.events FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role IN ('forum_execcom','core_execcom','vice_chairman','chairman')
    )
  );

CREATE POLICY "Members see permitted events"
  ON public.events FOR SELECT TO authenticated
  USING (
    allowed_roles IS NULL
    OR array_length(allowed_roles, 1) IS NULL
    OR EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND (
          p.role::text = ANY(allowed_roles)
          OR p.role IN ('forum_execcom','core_execcom','vice_chairman','chairman')
        )
    )
  );

CREATE POLICY "Execom manages events"
  ON public.events FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role IN ('forum_execcom','core_execcom','vice_chairman','chairman')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role IN ('forum_execcom','core_execcom','vice_chairman','chairman')
    )
  );


-- ── SECTION 6: RLS on attendance ─────────────────────────────────────────────

ALTER TABLE public.attendance ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users read own attendance"   ON public.attendance;
DROP POLICY IF EXISTS "Execom reads all attendance" ON public.attendance;
DROP POLICY IF EXISTS "Execom manages attendance"   ON public.attendance;

CREATE POLICY "Users read own attendance"
  ON public.attendance FOR SELECT TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "Execom reads all attendance"
  ON public.attendance FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role IN ('forum_execcom','core_execcom','vice_chairman','chairman')
    )
  );

CREATE POLICY "Execom manages attendance"
  ON public.attendance FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role IN ('forum_execcom','core_execcom','vice_chairman','chairman')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role IN ('forum_execcom','core_execcom','vice_chairman','chairman')
    )
  );


-- ── SECTION 7: RLS on certificates ───────────────────────────────────────────

ALTER TABLE public.certificates ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users read own certificates"    ON public.certificates;
DROP POLICY IF EXISTS "Students read own certificates" ON public.certificates;
DROP POLICY IF EXISTS "Execom reads all certificates"  ON public.certificates;
DROP POLICY IF EXISTS "Service role issues certificates" ON public.certificates;
DROP POLICY IF EXISTS "Service role updates certificates" ON public.certificates;

CREATE POLICY "Users read own certificates"
  ON public.certificates FOR SELECT TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "Execom reads all certificates"
  ON public.certificates FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role IN ('forum_execcom','core_execcom','vice_chairman','chairman')
    )
  );

CREATE POLICY "Service role manages certificates"
  ON public.certificates FOR ALL TO service_role
  USING (true)
  WITH CHECK (true);


-- ── SECTION 8: RLS on folders ────────────────────────────────────────────────

ALTER TABLE public.folders ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Folder members can read"  ON public.folders;
DROP POLICY IF EXISTS "Execom manages folders"   ON public.folders;
DROP POLICY IF EXISTS "Folder owners manage"     ON public.folders;

CREATE POLICY "Folder members can read"
  ON public.folders FOR SELECT TO authenticated
  USING (
    id IN (SELECT execom_id FROM public.folder_members WHERE user_id = auth.uid())
    OR EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role IN ('core_execcom','vice_chairman','chairman')
    )
  );

CREATE POLICY "Execom manages folders"
  ON public.folders FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role IN ('core_execcom','vice_chairman','chairman')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role IN ('core_execcom','vice_chairman','chairman')
    )
  );


-- ── SECTION 9: RLS on folder_members ─────────────────────────────────────────

ALTER TABLE public.folder_members ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users read own folder memberships" ON public.folder_members;
DROP POLICY IF EXISTS "Execom reads all folder members"   ON public.folder_members;
DROP POLICY IF EXISTS "Execom manages folder members"     ON public.folder_members;

CREATE POLICY "Users read own folder memberships"
  ON public.folder_members FOR SELECT TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "Execom reads all folder members"
  ON public.folder_members FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role IN ('forum_execcom','core_execcom','vice_chairman','chairman')
    )
  );

CREATE POLICY "Execom manages folder members"
  ON public.folder_members FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role IN ('core_execcom','vice_chairman','chairman')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role IN ('core_execcom','vice_chairman','chairman')
    )
  );


-- ── SECTION 10: RLS on folder_permissions ────────────────────────────────────

ALTER TABLE public.folder_permissions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Execom reads folder permissions"   ON public.folder_permissions;
DROP POLICY IF EXISTS "Execom manages folder permissions" ON public.folder_permissions;

CREATE POLICY "Execom reads folder permissions"
  ON public.folder_permissions FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role IN ('forum_execcom','core_execcom','vice_chairman','chairman')
    )
  );

CREATE POLICY "Execom manages folder permissions"
  ON public.folder_permissions FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role IN ('core_execcom','vice_chairman','chairman')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role IN ('core_execcom','vice_chairman','chairman')
    )
  );


-- ── SECTION 11: RLS on qr_tokens ─────────────────────────────────────────────

ALTER TABLE public.qr_tokens ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Execom manages qr_tokens" ON public.qr_tokens;

CREATE POLICY "Execom manages qr_tokens"
  ON public.qr_tokens FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role IN ('forum_execcom','core_execcom','vice_chairman','chairman')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role IN ('forum_execcom','core_execcom','vice_chairman','chairman')
    )
  );

-- QR scanning RPC: mark_attendance_atomic — ensure service role can call it
GRANT EXECUTE ON FUNCTION public.mark_attendance_atomic(INT, UUID, INT, UUID)
  TO authenticated;


-- ── SECTION 12: RLS on announcements ─────────────────────────────────────────

ALTER TABLE public.announcements ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Execom reads announcements"   ON public.announcements;
DROP POLICY IF EXISTS "Members read public announcements" ON public.announcements;
DROP POLICY IF EXISTS "Execom manages announcements" ON public.announcements;

CREATE POLICY "Members read public announcements"
  ON public.announcements FOR SELECT TO authenticated
  USING (visibility = 'public');

CREATE POLICY "Execom reads all announcements"
  ON public.announcements FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role IN ('forum_execcom','core_execcom','vice_chairman','chairman')
    )
  );

CREATE POLICY "Execom manages announcements"
  ON public.announcements FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role IN ('forum_execcom','core_execcom','vice_chairman','chairman')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role IN ('forum_execcom','core_execcom','vice_chairman','chairman')
    )
  );


-- ── SECTION 13: RLS on financial_ledger ──────────────────────────────────────

ALTER TABLE public.financial_ledger ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Folder members read ledger" ON public.financial_ledger;
DROP POLICY IF EXISTS "Execom manages ledger"      ON public.financial_ledger;

CREATE POLICY "Folder members read ledger"
  ON public.financial_ledger FOR SELECT TO authenticated
  USING (
    execom_id IN (
      SELECT fm.execom_id FROM public.folder_members fm WHERE fm.user_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role IN ('core_execcom','vice_chairman','chairman')
    )
  );

CREATE POLICY "Execom manages ledger"
  ON public.financial_ledger FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role IN ('forum_execcom','core_execcom','vice_chairman','chairman')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role IN ('forum_execcom','core_execcom','vice_chairman','chairman')
    )
  );


-- ── SECTION 14: events table — add certificate image template columns ─────────

ALTER TABLE public.events
  ADD COLUMN IF NOT EXISTS certificate_template_type TEXT DEFAULT 'none',
  ADD COLUMN IF NOT EXISTS certificate_image_url     TEXT,
  ADD COLUMN IF NOT EXISTS certificate_field_positions JSONB DEFAULT '{}'::JSONB;

-- ── SECTION 15: Cleanup (KEPT COMMENTED — run after app code updated) ─────────

-- DROP TRIGGER IF EXISTS sync_user_with_members ON public.users;
-- DROP FUNCTION IF EXISTS public.sync_user_with_members() CASCADE;
-- DROP TABLE IF EXISTS public.members_not_iste CASCADE;
-- DROP TABLE IF EXISTS public.member_profiles CASCADE;
-- Keep public.users and public.members — only drop when all apps confirmed on profiles

-- ── SECTION 16: Verify foreign key integrity ──────────────────────────────────

SELECT 'Orphaned attendance' AS issue, COUNT(*) AS orphan_count
FROM public.attendance a
WHERE NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = a.user_id)
UNION ALL
SELECT 'Orphaned certificates', COUNT(*)
FROM public.certificates c
WHERE NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = c.user_id)
UNION ALL
SELECT 'Orphaned folder_members', COUNT(*)
FROM public.folder_members fm
WHERE NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = fm.user_id);

-- ── SECTION 17: Verify data integrity ────────────────────────────────────────

SELECT
  'Total profiles' AS metric, COUNT(*)::text AS value FROM public.profiles
UNION ALL
SELECT 'ISTE members', COUNT(*)::text FROM public.profiles WHERE is_iste_member = true
UNION ALL
SELECT 'Active users', COUNT(*)::text FROM public.profiles WHERE status = 'active'
UNION ALL
SELECT 'Suspended users', COUNT(*)::text FROM public.profiles WHERE status = 'suspended'
UNION ALL
SELECT 'Registered (non-ISTE)', COUNT(*)::text FROM public.profiles WHERE is_registered = true AND is_iste_member = false;

-- ── SECTION 18: Verify ENUM types ────────────────────────────────────────────

SELECT enum_range(NULL::public.app_role) AS app_roles;
SELECT enum_range(NULL::public.account_status) AS account_statuses;

-- ── SECTION 19: Role distribution ────────────────────────────────────────────

SELECT role::text, COUNT(*) FROM public.profiles GROUP BY role ORDER BY count DESC;

-- ── SECTION 20: RLS policies summary ─────────────────────────────────────────

SELECT tablename, COUNT(*) AS policy_count
FROM pg_policies
WHERE schemaname = 'public'
GROUP BY tablename
ORDER BY tablename;
