-- Target: IST Admin vwxbgklgkcbwrvtwypfs. Additive foundation approved 2026-09-27.
-- Additive, private and deny-by-default. Does not replace public.users.
-- Does not grant app access, migrate rows, or create Auth accounts.
BEGIN;
SET LOCAL lock_timeout = '5s';
CREATE SCHEMA unified_next;
REVOKE ALL ON SCHEMA unified_next FROM PUBLIC, anon, authenticated, service_role;

CREATE TABLE unified_next.users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  auth_user_id uuid UNIQUE REFERENCES auth.users(id) ON DELETE RESTRICT,
  email text,
  full_name text NOT NULL CHECK (btrim(full_name) <> ''),
  account_status text NOT NULL DEFAULT 'pending_review'
    CHECK (account_status IN ('pending_review', 'active', 'suspended', 'archived')),
  college text,
  branch text,
  academic_year text,
  roll_number text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (email IS NULL OR (email = lower(btrim(email)) AND email <> ''))
);
CREATE UNIQUE INDEX users_email_unique ON unified_next.users(email) WHERE email IS NOT NULL;

CREATE TABLE unified_next.user_private_details (
  user_id uuid PRIMARY KEY REFERENCES unified_next.users(id) ON DELETE RESTRICT,
  phone_ciphertext bytea,
  encryption_key_version text,
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK ((phone_ciphertext IS NULL) = (encryption_key_version IS NULL))
);

CREATE TABLE unified_next.iste_members (
  user_id uuid PRIMARY KEY REFERENCES unified_next.users(id) ON DELETE RESTRICT,
  membership_id text NOT NULL UNIQUE CHECK (membership_id = upper(btrim(membership_id)) AND membership_id <> ''),
  membership_plan text,
  status text NOT NULL DEFAULT 'pending_review'
    CHECK (status IN ('pending_review', 'active', 'suspended', 'expired', 'cancelled')),
  starts_on date,
  expires_on date,
  verified_at timestamptz,
  verified_by uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  CHECK (expires_on IS NULL OR starts_on IS NULL OR expires_on >= starts_on)
);
CREATE INDEX iste_members_verified_by_idx ON unified_next.iste_members(verified_by);

CREATE TABLE unified_next.execom_tiers (
  tier smallint PRIMARY KEY CHECK (tier BETWEEN 1 AND 5),
  label text NOT NULL
);
INSERT INTO unified_next.execom_tiers VALUES
 (1, 'Chairperson and Vice-chairperson'),
 (2, 'Core: Secretary, Joint Secretary, Treasurer, Sub Treasurer, Creative Lead'),
 (3, 'Other Execom excluding forum and panel'),
 (4, 'Forum and Panel'),
 (5, 'Subcommittee');

CREATE TABLE unified_next.execom_members (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES unified_next.iste_members(user_id) ON DELETE RESTRICT,
  tier smallint NOT NULL REFERENCES unified_next.execom_tiers(tier) ON DELETE RESTRICT,
  position text NOT NULL CHECK (btrim(position) <> ''),
  scope_code text NOT NULL CHECK (btrim(scope_code) <> ''),
  term_label text NOT NULL,
  starts_on date NOT NULL,
  ends_on date NOT NULL CHECK (ends_on >= starts_on),
  status text NOT NULL DEFAULT 'pending_review'
    CHECK (status IN ('pending_review', 'active', 'suspended', 'ended')),
  approved_by uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  approved_at timestamptz,
  UNIQUE (user_id, position, scope_code, term_label),
  CHECK (status <> 'active' OR (approved_by IS NOT NULL AND approved_at IS NOT NULL))
);
CREATE INDEX execom_members_user_idx ON unified_next.execom_members(user_id);
CREATE INDEX execom_members_tier_idx ON unified_next.execom_members(tier);
CREATE INDEX execom_members_approved_by_idx ON unified_next.execom_members(approved_by);

CREATE TABLE unified_next.permission_definitions (
  code text PRIMARY KEY,
  description text NOT NULL
);
CREATE TABLE unified_next.execom_permissions (
  assignment_id uuid NOT NULL REFERENCES unified_next.execom_members(id) ON DELETE RESTRICT,
  permission_code text NOT NULL REFERENCES unified_next.permission_definitions(code) ON DELETE RESTRICT,
  scope_code text NOT NULL,
  allowed boolean NOT NULL DEFAULT false,
  changed_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  changed_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (assignment_id, permission_code, scope_code)
);
CREATE INDEX execom_permissions_code_idx ON unified_next.execom_permissions(permission_code);
CREATE INDEX execom_permissions_actor_idx ON unified_next.execom_permissions(changed_by);

CREATE TABLE unified_next.source_identity_map (
  source_project text NOT NULL,
  source_table text NOT NULL,
  source_key text NOT NULL,
  user_id uuid NOT NULL REFERENCES unified_next.users(id) ON DELETE RESTRICT,
  match_basis text NOT NULL,
  reviewed_at timestamptz NOT NULL,
  reviewed_by uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  PRIMARY KEY (source_project, source_table, source_key)
);
CREATE INDEX source_identity_user_idx ON unified_next.source_identity_map(user_id);
CREATE INDEX source_identity_reviewer_idx ON unified_next.source_identity_map(reviewed_by);

CREATE TABLE unified_next.review_queue (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source_project text NOT NULL,
  source_table text NOT NULL,
  source_key text NOT NULL,
  issue_code text NOT NULL,
  original_values_ciphertext bytea NOT NULL,
  encryption_key_version text NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'resolved')),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (source_project, source_table, source_key, issue_code)
);
CREATE TABLE unified_next.user_change_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES unified_next.users(id) ON DELETE RESTRICT,
  actor_auth_id uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  action text NOT NULL,
  changed_fields text[] NOT NULL,
  changed_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX user_change_log_user_idx ON unified_next.user_change_log(user_id);
CREATE INDEX user_change_log_actor_idx ON unified_next.user_change_log(actor_auth_id);

-- Flags describe current eligibility; no user-controlled flag columns.
CREATE VIEW unified_next.user_membership_flags WITH (security_invoker = true) AS
SELECT u.id AS user_id,
  EXISTS (
    SELECT 1 FROM unified_next.iste_members m
    WHERE m.user_id = u.id AND m.status = 'active' AND u.account_status = 'active'
      AND (m.starts_on IS NULL OR m.starts_on <= current_date)
      AND (m.expires_on IS NULL OR m.expires_on >= current_date)
  ) AS is_iste_member,
  EXISTS (
    SELECT 1 FROM unified_next.execom_members e
    JOIN unified_next.iste_members m ON m.user_id = e.user_id
    WHERE e.user_id = u.id AND u.account_status = 'active'
      AND m.status = 'active' AND e.status = 'active'
      AND (m.starts_on IS NULL OR m.starts_on <= current_date)
      AND (m.expires_on IS NULL OR m.expires_on >= current_date)
      AND current_date BETWEEN e.starts_on AND e.ends_on
  ) AS is_execom_member
FROM unified_next.users u;

-- No client policies until own-record reads and server admin writes are tested.
DO $block$
DECLARE t record;
BEGIN
  FOR t IN SELECT tablename FROM pg_tables WHERE schemaname = 'unified_next'
  LOOP
    EXECUTE format('ALTER TABLE unified_next.%I ENABLE ROW LEVEL SECURITY', t.tablename);
  END LOOP;
END
$block$;
REVOKE ALL ON ALL TABLES IN SCHEMA unified_next FROM PUBLIC, anon, authenticated, service_role;
COMMIT;
