-- ============================================================================
-- Permission Engine Bugfix: Global Feature Permissions Table
-- File: supabase/migrations/20260812_global_feature_permissions.sql
-- ============================================================================
-- The app code previously used folderPermissions[folderId=0] as a fake
-- "global" scope — but folders.id is a serial PK starting at 1, so no row
-- with id=0 ever existed. isFeatureEnabledGlobally() always returned false;
-- restricted-tier report/budget access via global toggle was dead code.
--
-- This creates a real table for org-wide feature toggles, independent of
-- any folder. Pairs with the permission-engine.ts / permission_engine.dart
-- fixes that added a `globalPermissions` field.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.global_feature_permissions (
  feature TEXT PRIMARY KEY,
  allowed BOOLEAN NOT NULL DEFAULT false,
  updated_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Seed with known features, all default-off (secure default)
INSERT INTO public.global_feature_permissions (feature, allowed) VALUES
  ('view_reports', false),
  ('view_total_budget', false)
ON CONFLICT (feature) DO NOTHING;

ALTER TABLE public.global_feature_permissions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone reads global permissions" ON public.global_feature_permissions;
CREATE POLICY "Anyone reads global permissions" ON public.global_feature_permissions
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Chairman manages global permissions" ON public.global_feature_permissions;
CREATE POLICY "Chairman manages global permissions" ON public.global_feature_permissions
  FOR ALL TO authenticated
  USING (public.my_role_rank() >= public.role_rank('chairman'))
  WITH CHECK (public.my_role_rank() >= public.role_rank('chairman'));

-- Migrate any legacy folder_permissions rows that were (incorrectly) stored
-- against execom_id=0, if any exist:
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'folder_permissions') THEN
    INSERT INTO public.global_feature_permissions (feature, allowed)
    SELECT feature, allowed FROM public.folder_permissions WHERE execom_id = 0
    ON CONFLICT (feature) DO UPDATE SET allowed = EXCLUDED.allowed, updated_at = NOW();

    DELETE FROM public.folder_permissions WHERE execom_id = 0;
  END IF;
END $$;
