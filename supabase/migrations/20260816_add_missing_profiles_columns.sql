-- ============================================================================
-- FIX: "column suspended_until does not exist" (code 42703)
-- ============================================================================
-- Ensure all missing columns on public.profiles are safely added via
-- ADD COLUMN IF NOT EXISTS, and update the public.users compatibility view.
-- ============================================================================

-- ── 1. Ensure all columns exist on public.profiles ─────────────────────────
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS phone TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS roll_number TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS branch TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS year TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS college TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS forum TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS execom_tag TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS post TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS suspended_until TIMESTAMPTZ;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS is_sudo BOOLEAN DEFAULT false;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS is_budget_activated BOOLEAN DEFAULT false;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS is_primary_chairman BOOLEAN DEFAULT false;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS permissions JSONB DEFAULT '{}'::jsonb;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS is_registered BOOLEAN DEFAULT false;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS is_iste_member BOOLEAN DEFAULT false;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS iste_membership_id TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS membership_plan TEXT DEFAULT 'Annual';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS membership_date DATE;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS expiry_date DATE;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS fcm_token TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS last_active TIMESTAMPTZ;

-- ── 2. Recreate public.users compatibility view ─────────────────────────────
DROP VIEW IF EXISTS public.users CASCADE;

CREATE VIEW public.users AS
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
  suspended_until,
  is_sudo,
  is_budget_activated,
  is_primary_chairman,
  permissions,
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
