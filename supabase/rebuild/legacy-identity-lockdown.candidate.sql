-- LOCAL CANDIDATE. Requires tested recovery and coordinated client cutover.
-- Does not delete data. Old client-side signup/admin writes will be rejected.
BEGIN;
SET LOCAL lock_timeout='5s';

-- Keep the existing Auth trigger valid, but never relabel an existing identity.
-- Verified server provisioning is responsible for explicit identity resolution.
CREATE OR REPLACE FUNCTION public.handle_auth_user_sync()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path=''
AS $$ BEGIN RETURN NEW; END $$;
REVOKE ALL ON FUNCTION public.handle_auth_user_sync() FROM PUBLIC,anon,authenticated;

-- Retire legacy APIs that accept arbitrary roles or identities, or infer forum
-- membership from self-editable branch text. Website consumers must migrate first.
DO $$
DECLARE fn record;
BEGIN
 FOR fn IN SELECT p.oid::regprocedure AS signature FROM pg_catalog.pg_proc p
   JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname IN
    ('provision_member','authenticate_user','get_user_profile',
     'verify_membership_status','verify_leetlaunch_membership','users_view_dml','sync_user_with_members')
 LOOP
   EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated',fn.signature);
 END LOOP;
END $$;

-- A view's DEFINER DML trigger must not be a back door to protected columns.
REVOKE INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER
 ON public.users,public.profiles FROM PUBLIC,anon,authenticated;

-- Table revocation alone does not remove pre-existing column-level grants.
DO $$
DECLARE col record;
BEGIN
 FOR col IN SELECT table_name,column_name FROM information_schema.columns
   WHERE table_schema='public' AND table_name IN ('users','profiles')
 LOOP
   EXECUTE format('REVOKE INSERT (%I), UPDATE (%I), REFERENCES (%I) ON public.%I FROM PUBLIC,anon,authenticated',
     col.column_name,col.column_name,col.column_name,col.table_name);
 END LOOP;
END $$;

-- Normal own-profile editing survives. RLS still checks ownership.
-- Membership, identifiers, email, roles, status, forums and permissions stay server-owned.
GRANT UPDATE(name,phone,roll_number,branch,year,college,fcm_token,last_active,last_seen)
 ON public.profiles TO authenticated;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Do not inherit an unknown permissive UPDATE policy from an older deployment.
CREATE POLICY profile_update_owner_guard ON public.profiles AS RESTRICTIVE
 FOR UPDATE TO authenticated
 USING ((SELECT auth.uid())=id) WITH CHECK ((SELECT auth.uid())=id);

COMMIT;
