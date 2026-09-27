-- LOCAL CANDIDATE ONLY: verified basic-profile provisioning.
-- Before deployment replace the old Auth ID-rewriting trigger and harden legacy
-- profile/view writes. This file alone does NOT make the legacy backend safe.
BEGIN;
CREATE OR REPLACE FUNCTION public.provision_verified_member(p_auth_id uuid,p_details jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=''
AS $$
DECLARE
 a record;
 u unified_next.users%ROWTYPE;
 p public.profiles%ROWTYPE;
 v_name text:=btrim(p_details->>'name');
 v_phone text:=regexp_replace(p_details->>'phone','[^0-9+]','','g');
 v_email text;
 k text;
BEGIN
 IF current_user<>'service_role' THEN RAISE EXCEPTION 'Server authentication required' USING ERRCODE='42501'; END IF;
 -- Hold the verified email/ban state stable until profile writes commit.
 SELECT id,email,email_confirmed_at,deleted_at,banned_until INTO a FROM auth.users WHERE id=p_auth_id FOR SHARE;
 IF NOT FOUND OR a.email_confirmed_at IS NULL OR a.email IS NULL
   OR a.deleted_at IS NOT NULL OR a.banned_until>now() THEN
   RAISE EXCEPTION 'Verified active email account required' USING ERRCODE='42501';
 END IF;
 IF p_details IS NULL OR jsonb_typeof(p_details)<>'object' THEN
   RAISE EXCEPTION 'Profile details required' USING ERRCODE='22023';
 END IF;
 FOR k IN SELECT jsonb_object_keys(p_details) LOOP
   IF k NOT IN ('name','phone','roll_number','college','branch','academic_year')
     OR jsonb_typeof(p_details->k)<>'string' THEN
     RAISE EXCEPTION 'Unsupported profile field' USING ERRCODE='22023';
   END IF;
 END LOOP;
 IF v_name IS NULL OR length(v_name) NOT BETWEEN 2 AND 120
 OR v_phone IS NULL OR v_phone !~ '^[+]?[0-9]{10,15}$'
 OR nullif(btrim(p_details->>'roll_number'),'') IS NULL
 OR length(p_details->>'roll_number')>60
 OR nullif(btrim(p_details->>'college'),'') IS NULL OR length(p_details->>'college')>160
 OR nullif(btrim(p_details->>'branch'),'') IS NULL OR length(p_details->>'branch')>120
 OR coalesce(p_details->>'academic_year','') NOT IN ('1','2','3','4') THEN
   RAISE EXCEPTION 'Complete valid profile details required' USING ERRCODE='22023';
 END IF;
 v_email:=lower(btrim(a.email));
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_email,0));
 IF EXISTS(SELECT 1 FROM public.profiles WHERE lower(btrim(email))=v_email AND id<>p_auth_id) THEN
   RAISE EXCEPTION 'Existing identity needs administrator reconciliation' USING ERRCODE='23505';
 END IF;
 SELECT * INTO p FROM public.profiles WHERE id=p_auth_id FOR UPDATE;
 IF FOUND AND (lower(btrim(p.email))<>v_email OR p.status::text<>'active' OR p.suspended_until>now()) THEN
   RAISE EXCEPTION 'Existing profile requires administrator review' USING ERRCODE='42501';
 END IF;
 IF EXISTS(SELECT 1 FROM unified_next.users WHERE auth_user_id=p_auth_id AND email IS DISTINCT FROM v_email) THEN
   RAISE EXCEPTION 'Identity email changed; administrator review required' USING ERRCODE='23505';
 END IF;
 SELECT * INTO u FROM unified_next.users WHERE email=v_email FOR UPDATE;
 IF FOUND THEN
   IF u.account_status IN ('suspended','archived') OR (u.auth_user_id IS NOT NULL AND u.auth_user_id<>p_auth_id) THEN
     RAISE EXCEPTION 'Existing identity cannot be claimed' USING ERRCODE='42501';
   END IF;
   IF EXISTS(SELECT 1 FROM unified_next.source_identity_map s JOIN unified_next.review_queue q
      USING(source_project,source_table,source_key)
      WHERE s.user_id=u.id AND q.status='pending' AND q.issue_code='membership_identity_conflict') THEN
     RAISE EXCEPTION 'Membership identity conflict needs review' USING ERRCODE='23505';
   END IF;
   UPDATE unified_next.users SET auth_user_id=p_auth_id,account_status='active',
    full_name=v_name,college=btrim(p_details->>'college'),branch=btrim(p_details->>'branch'),
    academic_year=p_details->>'academic_year',roll_number=btrim(p_details->>'roll_number'),updated_at=now()
   WHERE id=u.id;
 ELSE
   INSERT INTO unified_next.users(id,auth_user_id,email,full_name,account_status,college,branch,academic_year,roll_number)
   VALUES(p_auth_id,p_auth_id,v_email,v_name,'active',btrim(p_details->>'college'),
    btrim(p_details->>'branch'),p_details->>'academic_year',btrim(p_details->>'roll_number')) RETURNING * INTO u;
 END IF;
 -- Compatibility profile: explicit ordinary-member defaults, never caller role/flags.
 INSERT INTO public.profiles(id,email,name,phone,roll_number,college,branch,year,
 role,status,is_registered,is_iste_member,is_sudo,is_primary_chairman,is_budget_activated,permissions)
 VALUES(p_auth_id,v_email,v_name,v_phone,btrim(p_details->>'roll_number'),btrim(p_details->>'college'),
 btrim(p_details->>'branch'),p_details->>'academic_year','member','active',true,false,false,false,false,'{}')
 ON CONFLICT(id) DO UPDATE SET name=excluded.name,phone=excluded.phone,
 roll_number=excluded.roll_number,college=excluded.college,branch=excluded.branch,
 year=excluded.year,is_registered=true,updated_at=now();
 -- Membership records and Execom records are deliberately untouched.
 INSERT INTO unified_next.user_change_log(user_id,actor_auth_id,action,changed_fields)
 VALUES(u.id,p_auth_id,'verified_basic_profile_saved',ARRAY['profile_details','auth_user_id']);
 RETURN jsonb_build_object('user_id',u.id,'auth_user_id',p_auth_id,'status','active');
END
$$;
REVOKE ALL ON FUNCTION public.provision_verified_member(uuid,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.provision_verified_member(uuid,jsonb) TO service_role;
GRANT USAGE ON SCHEMA unified_next,auth TO service_role;
GRANT SELECT(id,email,email_confirmed_at,deleted_at,banned_until) ON auth.users TO service_role;
-- PostgreSQL row locking needs UPDATE on at least one column. This server-only
-- privilege must be reviewed before deployment; no Auth UPDATE is issued here.
GRANT UPDATE(email_confirmed_at) ON auth.users TO service_role;
GRANT SELECT,INSERT,UPDATE ON unified_next.users,public.profiles TO service_role;
GRANT SELECT ON unified_next.source_identity_map,unified_next.review_queue TO service_role;
GRANT INSERT ON unified_next.user_change_log TO service_role;
COMMIT;

