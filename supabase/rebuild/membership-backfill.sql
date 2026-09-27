-- IST Admin only. Isolated, pending-review import; never changes public/Auth rows.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM unified_next.users) THEN RAISE EXCEPTION 'Target must be empty; reconcile instead of overwriting'; END IF;
END $$;

-- Preserve the one-user/one-membership relationship while changing its primary key.
ALTER TABLE unified_next.execom_members DROP CONSTRAINT execom_members_user_id_fkey;
ALTER TABLE unified_next.iste_members ADD CONSTRAINT iste_members_user_id_key UNIQUE(user_id);
ALTER TABLE unified_next.iste_members DROP CONSTRAINT iste_members_pkey;
ALTER TABLE unified_next.iste_members ADD CONSTRAINT iste_members_pkey PRIMARY KEY(membership_id);
ALTER TABLE unified_next.execom_members ADD CONSTRAINT execom_members_user_id_fkey FOREIGN KEY(user_id) REFERENCES unified_next.iste_members(user_id) ON DELETE RESTRICT;
ALTER TABLE unified_next.iste_members
 ADD COLUMN duration_years smallint CHECK(duration_years BETWEEN 1 AND 4),
 ADD COLUMN forum_memberships text[] NOT NULL DEFAULT '{}' CHECK(forum_memberships <@ ARRAY['SWAS','EXIS','TORQ','GENESIS','BITS']::text[] AND array_position(forum_memberships,NULL) IS NULL);
COMMENT ON COLUMN unified_next.iste_members.duration_years IS 'Purchased term length; NULL means unknown, never inferred from registration time.';
COMMENT ON COLUMN unified_next.iste_members.forum_memberships IS 'Distinct known forum memberships copied from source records; empty means none recorded, not verified absence.';

-- Unknown historical terms and actors must not be fabricated.
ALTER TABLE unified_next.execom_members ALTER COLUMN starts_on DROP NOT NULL, ALTER COLUMN ends_on DROP NOT NULL;
ALTER TABLE unified_next.execom_members ADD CONSTRAINT execom_active_dates CHECK(status <> 'active' OR (starts_on IS NOT NULL AND ends_on IS NOT NULL));
ALTER TABLE unified_next.execom_members ADD COLUMN source_table text, ADD COLUMN source_key text;
ALTER TABLE unified_next.execom_permissions ALTER COLUMN changed_by DROP NOT NULL;
ALTER TABLE unified_next.execom_permissions ADD COLUMN status text NOT NULL DEFAULT 'pending_review' CHECK(status IN ('pending_review','approved','rejected')),
 ADD COLUMN source_table text, ADD COLUMN source_key text,
 ADD CONSTRAINT approved_permission_actor CHECK(status <> 'approved' OR changed_by IS NOT NULL);
COMMENT ON COLUMN unified_next.execom_permissions.allowed IS 'Imported requested setting, not an effective grant. Requires approved permission and active approved assignment before use.';

-- Reference-only review items avoid duplicating sensitive source data without an encryption key.
ALTER TABLE unified_next.review_queue ALTER COLUMN original_values_ciphertext DROP NOT NULL, ALTER COLUMN encryption_key_version DROP NOT NULL;
ALTER TABLE unified_next.review_queue ADD CONSTRAINT review_encryption_pair CHECK((original_values_ciphertext IS NULL) = (encryption_key_version IS NULL));
COMMENT ON TABLE unified_next.review_queue IS 'Unresolved source references. NULL ciphertext means original remains in source_table/source_key, not an encrypted snapshot or backup.';


CREATE TEMP TABLE import_sources ON COMMIT DROP AS
SELECT 'public.profiles'::text source_table,id::text source_key,lower(btrim(email)) email,btrim(name) full_name, nullif(upper(btrim(iste_membership_id)),'') membership_id,membership_plan,forum,1 priority FROM public.profiles
UNION ALL SELECT 'public.iste_members',id::text,lower(btrim(email)),btrim(name),nullif(upper(btrim(iste_membership_id)),''),membership_plan,forum,2 FROM public.iste_members
UNION ALL SELECT 'public.users_iste_verification',id::text,lower(btrim(email)),btrim(full_name),nullif(upper(btrim(iste_id)),''),null,null,3 FROM public.users_iste_verification;
CREATE TEMP TABLE import_conflicts ON COMMIT DROP AS
SELECT DISTINCT email FROM import_sources WHERE email IS NULL OR email='' OR email IN (SELECT email FROM import_sources GROUP BY email HAVING count(DISTINCT membership_id)>1)
OR membership_id IN (SELECT membership_id FROM import_sources WHERE membership_id IS NOT NULL GROUP BY membership_id HAVING count(DISTINCT email)>1);


INSERT INTO unified_next.users(id,auth_user_id,email,full_name,college,branch,academic_year,roll_number,created_at,updated_at)
SELECT p.id,a.id,lower(btrim(p.email)),btrim(p.name),p.college,p.branch,p.year,p.roll_number,coalesce(p.created_at,now()),coalesce(p.updated_at,now())
FROM public.profiles p LEFT JOIN auth.users a ON a.id=p.id AND lower(btrim(a.email))=lower(btrim(p.email));

INSERT INTO unified_next.users(email,full_name)
SELECT DISTINCT ON(s.email) s.email,s.full_name FROM import_sources s
WHERE nullif(s.email,'') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM unified_next.users u WHERE u.email=s.email)
ORDER BY s.email,s.priority,s.source_key;

INSERT INTO unified_next.source_identity_map(source_project,source_table,source_key,user_id,match_basis,reviewed_at)
SELECT 'vwxbgklgkcbwrvtwypfs',s.source_table,s.source_key,u.id,
 CASE WHEN s.source_table='public.profiles' THEN 'preserved_profile_id_pending_review' ELSE 'normalized_email_pending_review' END,now()
FROM import_sources s JOIN unified_next.users u ON u.email=s.email;

INSERT INTO unified_next.review_queue(source_project,source_table,source_key,issue_code)
SELECT 'vwxbgklgkcbwrvtwypfs',s.source_table,s.source_key,'membership_identity_conflict'
FROM import_sources s JOIN import_conflicts c ON c.email=s.email;

INSERT INTO unified_next.iste_members(user_id,membership_id,membership_plan,duration_years,forum_memberships,starts_on,expires_on)
SELECT u.id,min(s.membership_id),
 (array_agg(s.membership_plan ORDER BY s.priority,s.source_key) FILTER(WHERE s.membership_plan IS NOT NULL))[1],
 CASE WHEN bool_or(lower(btrim(s.membership_plan)) IN ('annual','1 year')) THEN 1 ELSE NULL END,
 coalesce(array_agg(DISTINCT upper(btrim(s.forum))) FILTER(WHERE upper(btrim(s.forum)) IN ('SWAS','EXIS','TORQ','GENESIS','BITS')),'{}'::text[]),
 p.membership_date,p.expiry_date
FROM import_sources s JOIN unified_next.users u ON u.email=s.email
LEFT JOIN public.profiles p ON p.id=u.id
WHERE NOT EXISTS(SELECT 1 FROM import_conflicts c WHERE c.email=s.email)
GROUP BY u.id,p.membership_date,p.expiry_date
HAVING count(s.membership_id)>0;

INSERT INTO unified_next.execom_members(user_id,tier,position,scope_code,term_label,source_table,source_key)
SELECT p.id,
 CASE WHEN p.role::text IN ('chairman','vice_chairman') THEN 1
 WHEN p.role::text IN ('forum_execcom','panel') THEN 4
 WHEN lower(regexp_replace(coalesce(p.post,''),'[^a-zA-Z]','','g')) IN ('secretary','jointsecretary','treasurer','subtreasurer','creativelead') THEN 2 ELSE 3 END,
 coalesce(nullif(btrim(p.post),''),p.role::text),
 CASE WHEN p.role::text='forum_execcom' THEN 'forum:'||lower(coalesce(nullif(btrim(p.forum),''),'unconfirmed'))
 WHEN p.role::text='panel' THEN 'panel' ELSE 'organization' END,
 'legacy-unconfirmed','public.profiles',p.id::text
FROM public.profiles p JOIN unified_next.iste_members m ON m.user_id=p.id
WHERE p.role::text IN ('chairman','vice_chairman','core_execcom','forum_execcom','panel');

-- Term/roster verification is required for every imported assignment.
INSERT INTO unified_next.review_queue(source_project,source_table,source_key,issue_code)
SELECT 'vwxbgklgkcbwrvtwypfs',source_table,source_key,'execom_term_and_roster_unconfirmed'
FROM unified_next.execom_members;
INSERT INTO unified_next.review_queue(source_project,source_table,source_key,issue_code)
SELECT 'vwxbgklgkcbwrvtwypfs','public.profiles',p.id::text,'execom_membership_unresolved'
FROM public.profiles p WHERE p.role::text<>'member' AND NOT EXISTS(SELECT 1 FROM unified_next.execom_members e WHERE e.user_id=p.id);

INSERT INTO unified_next.permission_definitions(code,description)
SELECT DISTINCT 'legacy.profile.'||k.key,'Legacy profile permission: '||k.key FROM public.profiles p CROSS JOIN LATERAL jsonb_each(p.permissions) k
UNION
SELECT DISTINCT 'legacy.folder.'||feature,'Legacy folder permission: '||feature FROM public.folder_permissions;

INSERT INTO unified_next.execom_permissions(assignment_id,permission_code,scope_code,allowed,source_table,source_key)
SELECT e.id,'legacy.profile.'||k.key,'legacy:profile',k.value::text::boolean,'public.profiles',p.id::text
FROM public.profiles p JOIN unified_next.execom_members e ON e.user_id=p.id CROSS JOIN LATERAL jsonb_each(p.permissions) k
WHERE jsonb_typeof(k.value)='boolean';

INSERT INTO unified_next.execom_permissions(assignment_id,permission_code,scope_code,allowed,source_table,source_key)
SELECT DISTINCT e.id,'legacy.folder.'||fp.feature,'legacy:folder:'||fp.execom_id,fp.allowed,'public.folder_permissions',fp.id::text
FROM public.folder_permissions fp JOIN public.folder_members fm ON fm.execom_id=fp.execom_id JOIN unified_next.execom_members e ON e.user_id=fm.user_id;

-- Keep unmatched scope memberships visible for later reconciliation; no invented assignments.
INSERT INTO unified_next.review_queue(source_project,source_table,source_key,issue_code)
SELECT 'vwxbgklgkcbwrvtwypfs','public.folder_members',id::text,'folder_scope_assignment_needs_reconciliation' FROM public.folder_members;
INSERT INTO unified_next.review_queue(source_project,source_table,source_key,issue_code)
SELECT 'vwxbgklgkcbwrvtwypfs','public.global_feature_permissions',feature,'global_policy_not_an_individual_grant' FROM public.global_feature_permissions;
INSERT INTO unified_next.review_queue(source_project,source_table,source_key,issue_code)
SELECT 'vwxbgklgkcbwrvtwypfs','public.profiles',p.id::text,'profile_permissions_without_execom_assignment'
FROM public.profiles p WHERE p.permissions<>'{}'::jsonb AND NOT EXISTS(SELECT 1 FROM unified_next.execom_members e WHERE e.user_id=p.id);
INSERT INTO unified_next.user_change_log(user_id,action,changed_fields)
SELECT id,'staged_legacy_import',ARRAY['identity','membership','execom_if_present'] FROM unified_next.users;
REVOKE ALL ON ALL TABLES IN SCHEMA unified_next FROM PUBLIC,anon,authenticated,service_role;
COMMIT;

