-- Applied to IST Admin staging only. No grants, activation or legacy writes.
BEGIN;
SET LOCAL lock_timeout = '5s';
ALTER TABLE unified_next.execom_members
 ADD COLUMN forum_code text,
 ADD COLUMN forum_role text,
 ADD COLUMN organization_role text;
COMMENT ON COLUMN unified_next.execom_members.forum_code IS 'Canonical forum: SWAS, EXIS, TORQ, GENESIS or BITS. One forum per appointment.';
COMMENT ON COLUMN unified_next.execom_members.forum_role IS 'Canonical forum role; does not grant organization-wide permissions. Use instead of parsing legacy position.';
COMMENT ON COLUMN unified_next.execom_members.organization_role IS 'Society-wide leadership tag, distinct from forum leadership; not an automatic permission grant.';

UPDATE unified_next.execom_members
SET forum_code=upper(split_part(scope_code,':',2)),
 forum_role=CASE lower(regexp_replace(position,'^[^ ]+ +','',''))
 WHEN 'chair' THEN 'chairperson' WHEN 'chairman' THEN 'chairperson' WHEN 'chairperson' THEN 'chairperson'
 WHEN 'vice chair' THEN 'vice_chairperson' WHEN 'vice chairman' THEN 'vice_chairperson' WHEN 'vice chairperson' THEN 'vice_chairperson'
 WHEN 'secretary' THEN 'secretary' WHEN 'joint secretary' THEN 'joint_secretary'
 WHEN 'social media' THEN 'media' WHEN 'media' THEN 'media' END
WHERE scope_code LIKE 'forum:%';

UPDATE unified_next.execom_members SET organization_role=
 CASE lower(regexp_replace(position,'[^a-zA-Z]','','g'))
 WHEN 'chairman' THEN 'society_chairperson'
 WHEN 'chairperson' THEN 'society_chairperson'
 WHEN 'vicechairman' THEN 'society_vice_chairperson'
 WHEN 'vicechairperson' THEN 'society_vice_chairperson' END
WHERE scope_code='organization' AND tier=1;

ALTER TABLE unified_next.execom_members
 ADD CONSTRAINT execom_forum_code_valid CHECK(forum_code IN ('SWAS','EXIS','TORQ','GENESIS','BITS')),
 ADD CONSTRAINT execom_forum_role_valid CHECK(forum_role IN ('chairperson','vice_chairperson','secretary','joint_secretary','media')),
 ADD CONSTRAINT execom_forum_scope_consistent CHECK(
 (scope_code LIKE 'forum:%' AND tier=4 AND forum_code IS NOT NULL AND forum_role IS NOT NULL AND scope_code='forum:'||lower(forum_code) AND organization_role IS NULL)
 OR (scope_code NOT LIKE 'forum:%' AND forum_code IS NULL AND forum_role IS NULL)),
 ADD CONSTRAINT execom_organization_role_valid CHECK(organization_role IN ('society_chairperson','society_vice_chairperson')),
 ADD CONSTRAINT execom_organization_scope_consistent CHECK(organization_role IS NULL OR (scope_code='organization' AND tier=1 AND forum_code IS NULL AND forum_role IS NULL));
CREATE UNIQUE INDEX execom_forum_assignment_unique ON unified_next.execom_members(user_id,forum_code,forum_role,term_label) WHERE forum_code IS NOT NULL;
CREATE INDEX execom_forum_role_lookup ON unified_next.execom_members(forum_code,forum_role) WHERE forum_code IS NOT NULL;
INSERT INTO unified_next.user_change_log(user_id,action,changed_fields)
SELECT user_id,'normalize_forum_and_society_leadership',ARRAY['forum_code','forum_role','organization_role']
FROM unified_next.execom_members WHERE forum_code IS NOT NULL OR organization_role IS NOT NULL;
COMMIT;

