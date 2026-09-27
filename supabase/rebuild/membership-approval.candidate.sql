-- LOCAL REVIEW CANDIDATE ONLY. Not applied to production.
-- Depends on the existing unified_next foundation/backfill.
-- No legacy profile/Auth UUID changes; clients must not be switched by this file.
BEGIN;
ALTER TABLE public.membership_registrations
 ADD COLUMN approved_user_id uuid REFERENCES unified_next.users(id) ON DELETE RESTRICT,
 ADD COLUMN approved_membership_id text REFERENCES unified_next.iste_members(membership_id) ON DELETE RESTRICT;
CREATE INDEX membership_registrations_approved_user_idx ON public.membership_registrations(approved_user_id);
CREATE INDEX membership_registrations_approved_membership_idx ON public.membership_registrations(approved_membership_id);

INSERT INTO unified_next.permission_definitions(code,description)
VALUES('membership.approve','Review membership intake and allocate an official membership ID')
ON CONFLICT(code) DO NOTHING;
-- No person receives a permission from this migration.
CREATE OR REPLACE FUNCTION public.can_approve_membership(p_reviewer_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=''
AS $$
 SELECT current_user='service_role' AND coalesce(bool_or(p.allowed),false)
   AND NOT coalesce(bool_or(NOT p.allowed),false)
 FROM unified_next.users u
 JOIN unified_next.iste_members m ON m.user_id=u.id
 JOIN unified_next.execom_members e ON e.user_id=u.id
 JOIN unified_next.execom_permissions p ON p.assignment_id=e.id
 WHERE u.auth_user_id=p_reviewer_id AND u.account_status='active'
 AND m.status='active' AND (m.starts_on IS NULL OR m.starts_on<=current_date)
 AND (m.expires_on IS NULL OR m.expires_on>=current_date)
 AND e.status='active' AND e.approved_by IS NOT NULL AND e.approved_at IS NOT NULL
 AND current_date BETWEEN e.starts_on AND e.ends_on
 AND e.scope_code='organization'
 AND p.permission_code='membership.approve' AND p.scope_code='organization'
 AND p.status='approved' AND p.changed_by IS NOT NULL
$$;

CREATE OR REPLACE FUNCTION public.approve_membership_registration(
 p_registration_id uuid,p_membership_id text,p_reviewer_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=''
AS $$
DECLARE
 r public.membership_registrations%ROWTYPE;
 v_id text:=upper(btrim(p_membership_id));
 v_user uuid;
 v_user_status text;
 v_email text;
 v_years smallint;
 v_forums text[];
 v_total integer;
BEGIN
 IF current_user<>'service_role' OR NOT public.can_approve_membership(p_reviewer_id) THEN
   RAISE EXCEPTION 'Not authorized to approve memberships' USING ERRCODE='42501';
 END IF;
 IF v_id IS NULL OR v_id !~ '^KE104[0-9]{3}$' THEN
   RAISE EXCEPTION 'Official KE104xxx ID required' USING ERRCODE='22023';
 END IF;
 SELECT * INTO r FROM public.membership_registrations WHERE id=p_registration_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Registration not found' USING ERRCODE='P0002'; END IF;
 IF r.status='approved' AND r.approved_membership_id=v_id AND r.approved_user_id IS NOT NULL THEN
   IF NOT EXISTS(SELECT 1 FROM unified_next.iste_members WHERE membership_id=v_id AND user_id=r.approved_user_id) THEN
     RAISE EXCEPTION 'Approved membership identity requires review' USING ERRCODE='23505';
   END IF;
   RETURN jsonb_build_object('id',r.id,'membership_id',v_id,'status','approved');
 END IF;
 IF r.status<>'pending' THEN RAISE EXCEPTION 'Registration already reviewed' USING ERRCODE='23505'; END IF;
 v_email:=lower(btrim(r.email));
 v_years:=CASE r.membership_fee WHEN 649 THEN 1 WHEN 1199 THEN 2 WHEN 1499 THEN 3 WHEN 1799 THEN 4 END;
 IF length(btrim(r.full_name)) NOT BETWEEN 2 AND 120
   OR v_email !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$'
   OR r.date_of_birth>current_date OR r.academic_year NOT IN ('1','2','3','4')
   OR btrim(r.branch)='' OR r.phone !~ '^[0-9]{10}$'
   OR btrim(r.transaction_id)='' OR btrim(r.receipt_path)='' OR v_years IS NULL
   OR jsonb_typeof(r.forums)<>'array' THEN
   RAISE EXCEPTION 'Incomplete registration details' USING ERRCODE='22023';
 END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(r.forums) f
   WHERE jsonb_typeof(f)<>'string' OR f#>>'{}' NOT IN
   ('SWaS Forum (299)','EXIS Forum (149)','TORQ Forum (129)','BITS Forum (129)','Genesis Forum (129)'))
   OR (SELECT count(*)<>count(DISTINCT f) FROM jsonb_array_elements(r.forums) f) THEN
   RAISE EXCEPTION 'Invalid or duplicate forums' USING ERRCODE='22023';
 END IF;
 SELECT coalesce(array_agg(code ORDER BY code),'{}'::text[]) INTO v_forums FROM (
 SELECT CASE f WHEN 'SWaS Forum (299)' THEN 'SWAS' WHEN 'EXIS Forum (149)' THEN 'EXIS'
 WHEN 'TORQ Forum (129)' THEN 'TORQ' WHEN 'BITS Forum (129)' THEN 'BITS'
 WHEN 'Genesis Forum (129)' THEN 'GENESIS' END code FROM jsonb_array_elements_text(r.forums) f) codes;
 SELECT r.membership_fee+coalesce(sum(price),0) INTO v_total FROM (
 SELECT CASE f WHEN 'SWaS Forum (299)' THEN 299 WHEN 'EXIS Forum (149)' THEN 149 ELSE 129 END price
 FROM jsonb_array_elements_text(r.forums) f ORDER BY price DESC
 OFFSET CASE WHEN v_years>=3 THEN 2 WHEN v_years=2 THEN 1 ELSE 0 END) payable;
 IF r.total_amount<>v_total THEN RAISE EXCEPTION 'Payment total does not match selections' USING ERRCODE='22023'; END IF;

 -- Serialize allocations for the same email across different intake rows.
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_email,0));
 SELECT id,account_status INTO v_user,v_user_status FROM unified_next.users WHERE email=v_email FOR UPDATE;
 IF v_user IS NOT NULL AND v_user_status IN ('suspended','archived') THEN
   RAISE EXCEPTION 'Account requires review before membership approval' USING ERRCODE='42501';
 END IF;
 IF v_user IS NOT NULL AND EXISTS(
   SELECT 1 FROM unified_next.source_identity_map s JOIN unified_next.review_queue q
   USING(source_project,source_table,source_key)
   WHERE s.user_id=v_user AND q.status='pending' AND q.issue_code='membership_identity_conflict'
 ) THEN RAISE EXCEPTION 'Identity conflict requires review' USING ERRCODE='23505'; END IF;
 IF EXISTS(SELECT 1 FROM unified_next.iste_members WHERE membership_id=v_id OR user_id=v_user) THEN
   RAISE EXCEPTION 'Membership ID or member already allocated; review or renewal required' USING ERRCODE='23505';
 END IF;
 IF v_user IS NULL THEN
   INSERT INTO unified_next.users(email,full_name,branch,academic_year)
   VALUES(v_email,btrim(r.full_name),r.branch,r.academic_year) RETURNING id INTO v_user;
 END IF;
 -- New membership starts on approval date; original submission remains unchanged.
 INSERT INTO unified_next.iste_members(user_id,membership_id,membership_plan,duration_years,
 forum_memberships,status,starts_on,expires_on,verified_at,verified_by)
 VALUES(v_user,v_id,v_years||' year',v_years,v_forums,'active',current_date,
 (current_date+pg_catalog.make_interval(years=>v_years))::date-1,now(),p_reviewer_id);
 INSERT INTO unified_next.source_identity_map(source_project,source_table,source_key,user_id,match_basis,reviewed_at,reviewed_by)
 VALUES('vwxbgklgkcbwrvtwypfs','public.membership_registrations',r.id::text,v_user,
 'admin_reviewed_exact_email',now(),p_reviewer_id);
 UPDATE public.membership_registrations SET status='approved',reviewed_by=p_reviewer_id,
 reviewed_at=now(),updated_at=now(),approved_user_id=v_user,approved_membership_id=v_id WHERE id=r.id;
 INSERT INTO unified_next.user_change_log(user_id,actor_auth_id,action,changed_fields)
 VALUES(v_user,p_reviewer_id,'membership_registration_approved',ARRAY['iste_members','membership_registrations']);
 RETURN jsonb_build_object('id',r.id,'membership_id',v_id,'status','approved');
END
$$;

REVOKE ALL ON FUNCTION public.can_approve_membership(uuid) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.count_approved_iste_members(p_reviewer_id uuid)
RETURNS bigint LANGUAGE plpgsql SECURITY INVOKER SET search_path=''
AS $$
BEGIN
 IF current_user<>'service_role' OR NOT public.can_approve_membership(p_reviewer_id) THEN
   RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501';
 END IF;
 RETURN (SELECT count(*) FROM unified_next.iste_members WHERE status='active'
   AND (starts_on IS NULL OR starts_on<=current_date)
   AND (expires_on IS NULL OR expires_on>=current_date));
END
$$;
REVOKE ALL ON FUNCTION public.count_approved_iste_members(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.count_approved_iste_members(uuid) TO service_role;
REVOKE ALL ON FUNCTION public.approve_membership_registration(uuid,text,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.can_approve_membership(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.approve_membership_registration(uuid,text,uuid) TO service_role;
GRANT USAGE ON SCHEMA unified_next TO service_role;
GRANT SELECT ON unified_next.users,unified_next.iste_members,unified_next.execom_members,
 unified_next.execom_permissions,unified_next.source_identity_map,unified_next.review_queue TO service_role;
GRANT INSERT ON unified_next.users,unified_next.iste_members,unified_next.source_identity_map,
 unified_next.user_change_log TO service_role;
-- SELECT FOR UPDATE requires UPDATE privilege, but only the function performs writes.
-- service_role is a server secret; never expose it to clients.
GRANT UPDATE ON unified_next.users TO service_role;
GRANT SELECT,UPDATE ON public.membership_registrations TO service_role;
COMMIT;

