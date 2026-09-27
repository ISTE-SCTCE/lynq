-- LOCAL CANDIDATE ONLY. No approvals, event scope mappings, or client cutover seeded.
-- Requires the unified foundation/backfill. Server endpoints must verify the caller
-- token/session and pass its Auth ID, never a request-body actor ID. No legacy ID rewrite.
BEGIN;
CREATE TABLE unified_next.attendance_event_config (
 event_id bigint PRIMARY KEY REFERENCES public.events(id) ON DELETE RESTRICT,
 scope_code text NOT NULL CHECK (length(btrim(scope_code))>0),
 eligibility_mode text NOT NULL CHECK (eligibility_mode IN ('active_users','approved_attendees')),
 enabled boolean NOT NULL DEFAULT false,
 approved_by uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
 approved_at timestamptz,
 CHECK (NOT enabled OR (approved_by IS NOT NULL AND approved_at IS NOT NULL))
);
CREATE TABLE unified_next.attendance_eligible_users (
 event_id bigint REFERENCES unified_next.attendance_event_config(event_id) ON DELETE RESTRICT,
 user_id uuid REFERENCES unified_next.users(id) ON DELETE RESTRICT,
 approved_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 approved_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(event_id,user_id)
);
CREATE INDEX attendance_event_approver_idx ON unified_next.attendance_event_config(approved_by);
CREATE INDEX attendance_eligible_user_idx ON unified_next.attendance_eligible_users(user_id);
CREATE INDEX attendance_eligible_approver_idx ON unified_next.attendance_eligible_users(approved_by);
CREATE TABLE unified_next.attendance_credentials (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 credential_digest bytea NOT NULL UNIQUE,
 user_id uuid NOT NULL REFERENCES unified_next.users(id) ON DELETE RESTRICT,
 event_id bigint NOT NULL REFERENCES unified_next.attendance_event_config(event_id) ON DELETE RESTRICT,
 day_number integer NOT NULL CHECK(day_number>0),
 expires_at timestamptz NOT NULL,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 attendance_id bigint UNIQUE REFERENCES public.attendance(id) ON DELETE RESTRICT,
 consumed_at timestamptz,
 CHECK((attendance_id IS NULL)=(consumed_at IS NULL))
);
CREATE INDEX attendance_credentials_user_idx ON unified_next.attendance_credentials(user_id);
CREATE INDEX attendance_credentials_event_idx ON unified_next.attendance_credentials(event_id);
ALTER TABLE unified_next.attendance_event_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE unified_next.attendance_eligible_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE unified_next.attendance_credentials ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON unified_next.attendance_event_config,unified_next.attendance_eligible_users,
 unified_next.attendance_credentials FROM PUBLIC,anon,authenticated;
INSERT INTO unified_next.permission_definitions(code,description)
VALUES('attendance.record','Record attendance in an explicitly approved event scope')
ON CONFLICT(code) DO NOTHING;

CREATE FUNCTION unified_next.assert_attendance_cutover_ready()
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
 IF current_user<>'service_role' THEN RAISE EXCEPTION 'Server authentication required' USING ERRCODE='42501'; END IF;
 -- Do not silently turn on a secure path while known bypasses still write its data.
 IF EXISTS(SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='mark_attendance_atomic'
   AND (has_function_privilege('anon',p.oid,'EXECUTE') OR has_function_privilege('authenticated',p.oid,'EXECUTE')))
 OR has_table_privilege('anon','public.attendance','INSERT,UPDATE,DELETE')
 OR has_table_privilege('authenticated','public.attendance','INSERT,UPDATE,DELETE')
 OR has_any_column_privilege('anon','public.attendance','INSERT,UPDATE')
 OR has_any_column_privilege('authenticated','public.attendance','INSERT,UPDATE')
 OR has_column_privilege('authenticated','public.profiles','id','UPDATE')
 OR has_column_privilege('anon','public.profiles','id','UPDATE')
 OR coalesce(has_table_privilege('authenticated',to_regclass('public.users'),'INSERT,UPDATE,DELETE'),false)
 OR coalesce(has_table_privilege('anon',to_regclass('public.users'),'INSERT,UPDATE,DELETE'),false) THEN
   RAISE EXCEPTION 'Attendance cutover blocked: retire legacy write bypasses first' USING ERRCODE='42501';
 END IF;
END $$;

-- Requires a currently verified, unbanned Auth identity and a stable legacy FK bridge.
CREATE FUNCTION unified_next.attendance_identity(p_auth_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE v_user uuid;
BEGIN
 IF current_user<>'service_role' THEN RAISE EXCEPTION 'Server authentication required' USING ERRCODE='42501'; END IF;
 SELECT u.id INTO v_user FROM auth.users a
 JOIN unified_next.users u ON u.auth_user_id=a.id
 JOIN public.profiles p ON p.id=a.id AND lower(btrim(p.email))=u.email
 WHERE a.id=p_auth_id AND a.email_confirmed_at IS NOT NULL AND a.deleted_at IS NULL
 AND (a.banned_until IS NULL OR a.banned_until<=clock_timestamp())
 AND lower(btrim(a.email))=u.email AND u.account_status='active'
 FOR SHARE OF a,u,p;
 IF v_user IS NULL THEN RAISE EXCEPTION 'Verified active identity required' USING ERRCODE='42501'; END IF;
 RETURN v_user;
END $$;

CREATE FUNCTION public.issue_attendance_credential(p_auth_id uuid,p_event_id bigint,p_day_number integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE v_user uuid; v_secret text; v_expires timestamptz; c record;
BEGIN
 PERFORM unified_next.assert_attendance_cutover_ready();
 v_user:=unified_next.attendance_identity(p_auth_id);
 SELECT ec.*,e.num_days,e.attendance_finalized INTO c FROM unified_next.attendance_event_config ec
 JOIN public.events e ON e.id=ec.event_id WHERE ec.event_id=p_event_id FOR SHARE OF ec,e;
 IF NOT FOUND OR NOT c.enabled OR c.attendance_finalized IS DISTINCT FROM false
 OR p_day_number IS NULL OR p_day_number<1 OR p_day_number>c.num_days THEN
   RAISE EXCEPTION 'Event or day unavailable' USING ERRCODE='22023';
 END IF;
 IF c.eligibility_mode='approved_attendees' AND NOT EXISTS(
 SELECT 1 FROM unified_next.attendance_eligible_users WHERE event_id=p_event_id AND user_id=v_user) THEN
   RAISE EXCEPTION 'Not eligible for this event' USING ERRCODE='42501';
 END IF;
 -- 244 random bits; only the digest persists. No client-provided lifetime/owner.
 v_secret:=gen_random_uuid()::text||gen_random_uuid()::text;
 v_expires:=clock_timestamp()+interval '30 seconds';
 INSERT INTO unified_next.attendance_credentials(credential_digest,user_id,event_id,day_number,expires_at)
 VALUES(sha256(convert_to(v_secret,'UTF8')),v_user,p_event_id,p_day_number,v_expires);
 RETURN jsonb_build_object('credential',v_secret,'event_id',p_event_id,'day_number',p_day_number,'expires_at',v_expires);
END $$;

CREATE FUNCTION public.record_event_attendance(p_scanner_auth_id uuid,p_event_id bigint,p_day_number integer,p_credential text)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE v_scanner uuid; v_attendee_auth uuid; v_id bigint; c record; t unified_next.attendance_credentials%ROWTYPE; v_allowed boolean;
BEGIN
 PERFORM unified_next.assert_attendance_cutover_ready();
 v_scanner:=unified_next.attendance_identity(p_scanner_auth_id);
 SELECT ec.*,e.num_days,e.attendance_finalized INTO c FROM unified_next.attendance_event_config ec
 JOIN public.events e ON e.id=ec.event_id WHERE ec.event_id=p_event_id FOR SHARE OF ec,e;
 IF NOT FOUND OR NOT c.enabled OR c.attendance_finalized IS DISTINCT FROM false
 OR p_day_number IS NULL OR p_day_number<1 OR p_day_number>c.num_days THEN
   RAISE EXCEPTION 'Event or day unavailable' USING ERRCODE='22023';
 END IF;
 SELECT coalesce(bool_or(p.allowed),false) AND NOT coalesce(bool_or(NOT p.allowed),false) INTO v_allowed
 FROM unified_next.execom_members e JOIN unified_next.execom_permissions p ON p.assignment_id=e.id
 JOIN unified_next.iste_members m ON m.user_id=e.user_id
 WHERE e.user_id=v_scanner AND e.status='active' AND e.approved_by IS NOT NULL AND e.approved_at IS NOT NULL
 AND current_date BETWEEN e.starts_on AND e.ends_on
 AND m.status='active' AND (m.starts_on IS NULL OR m.starts_on<=current_date) AND (m.expires_on IS NULL OR m.expires_on>=current_date)
 AND e.scope_code IN ('organization',c.scope_code) AND p.scope_code IN ('organization',c.scope_code)
 AND (p.scope_code<>'organization' OR e.scope_code='organization')
 AND p.permission_code='attendance.record' AND p.status='approved' AND p.changed_by IS NOT NULL;
 IF NOT v_allowed THEN RAISE EXCEPTION 'Not authorized for event attendance' USING ERRCODE='42501'; END IF;
 IF p_credential IS NULL OR length(p_credential)<>72 THEN RAISE EXCEPTION 'Invalid credential' USING ERRCODE='22023'; END IF;
 SELECT * INTO t FROM unified_next.attendance_credentials
 WHERE credential_digest=sha256(convert_to(p_credential,'UTF8')) FOR UPDATE;
 IF NOT FOUND OR t.event_id<>p_event_id OR t.day_number<>p_day_number THEN
   RAISE EXCEPTION 'Invalid credential' USING ERRCODE='22023';
 END IF;
 SELECT auth_user_id INTO v_attendee_auth FROM unified_next.users WHERE id=t.user_id;
 PERFORM unified_next.attendance_identity(v_attendee_auth);
 IF c.eligibility_mode='approved_attendees' AND NOT EXISTS(
 SELECT 1 FROM unified_next.attendance_eligible_users WHERE event_id=p_event_id AND user_id=t.user_id) THEN
   RAISE EXCEPTION 'Not eligible for this event' USING ERRCODE='42501';
 END IF;
 IF t.attendance_id IS NOT NULL THEN
   RETURN jsonb_build_object('status','already_recorded','attendance_id',t.attendance_id,'event_id',p_event_id,'day_number',p_day_number);
 END IF;
 IF t.expires_at<=clock_timestamp() THEN RAISE EXCEPTION 'Credential expired' USING ERRCODE='22023'; END IF;
 INSERT INTO public.attendance(event_id,user_id,scanned_by,day_number)
 VALUES(p_event_id,v_attendee_auth,p_scanner_auth_id,p_day_number)
 ON CONFLICT(event_id,user_id,day_number) DO NOTHING RETURNING id INTO v_id;
 IF v_id IS NULL THEN
   SELECT id INTO v_id FROM public.attendance WHERE event_id=p_event_id AND user_id=v_attendee_auth AND day_number=p_day_number;
   RETURN jsonb_build_object('status','already_recorded','attendance_id',v_id,'event_id',p_event_id,'day_number',p_day_number);
 END IF;
 UPDATE unified_next.attendance_credentials SET attendance_id=v_id,consumed_at=clock_timestamp() WHERE id=t.id;
 RETURN jsonb_build_object('status','recorded','attendance_id',v_id,'event_id',p_event_id,'day_number',p_day_number);
END $$;
REVOKE ALL ON FUNCTION unified_next.assert_attendance_cutover_ready(),unified_next.attendance_identity(uuid),
 public.issue_attendance_credential(uuid,bigint,integer),public.record_event_attendance(uuid,bigint,integer,text)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION unified_next.assert_attendance_cutover_ready(),unified_next.attendance_identity(uuid),
 public.issue_attendance_credential(uuid,bigint,integer),public.record_event_attendance(uuid,bigint,integer,text) TO service_role;
GRANT USAGE ON SCHEMA unified_next,auth TO service_role;
GRANT SELECT ON unified_next.users,unified_next.iste_members,unified_next.execom_members,
 unified_next.execom_permissions,unified_next.attendance_event_config,unified_next.attendance_eligible_users TO service_role;
-- Row locks require UPDATE privilege. A trusted server secret is required throughout.
GRANT UPDATE ON unified_next.users,unified_next.attendance_event_config TO service_role;
GRANT SELECT(id,email,email_confirmed_at,deleted_at,banned_until),UPDATE(id) ON auth.users TO service_role;
GRANT SELECT,UPDATE ON public.profiles,public.events TO service_role;
GRANT SELECT,INSERT,UPDATE ON unified_next.attendance_credentials TO service_role;
GRANT SELECT,INSERT ON public.attendance TO service_role;
GRANT USAGE ON SEQUENCE public.attendance_id_seq TO service_role;
COMMIT;
