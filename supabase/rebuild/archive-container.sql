-- REVIEW DRAFT ONLY. Destination: Mentron ysllolnoyezfdllqocgv.
-- Contains encrypted archive bytes only, never active Auth/Storage source tables.
-- Do not apply until export access, encryption and recovery target are configured.
BEGIN;
SET LOCAL lock_timeout = '5s';
CREATE SCHEMA iste_recovery_20260927;
REVOKE ALL ON SCHEMA iste_recovery_20260927 FROM PUBLIC, anon, authenticated, service_role;

CREATE TABLE iste_recovery_20260927.archives (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source_project text NOT NULL CHECK (source_project = 'vwxbgklgkcbwrvtwypfs'),
  source_snapshot_at timestamptz NOT NULL,
  format text NOT NULL,
  encryption_format text NOT NULL,
  encrypted_archive_sha256 text NOT NULL CHECK (encrypted_archive_sha256 ~ '^[0-9a-f]{64}$'),
  expected_bytes bigint NOT NULL CHECK (expected_bytes > 0),
  expected_chunks integer NOT NULL CHECK (expected_chunks > 0),
  status text NOT NULL DEFAULT 'uploading' CHECK (status IN ('uploading', 'uploaded', 'download_verified', 'restore_verified')),
  created_at timestamptz NOT NULL DEFAULT now(),
  restore_verified_at timestamptz,
  CHECK ((status = 'restore_verified') = (restore_verified_at IS NOT NULL))
);
CREATE TABLE iste_recovery_20260927.archive_chunks (
  archive_id uuid NOT NULL REFERENCES iste_recovery_20260927.archives(id) ON DELETE RESTRICT,
  ordinal integer NOT NULL CHECK (ordinal >= 0),
  ciphertext bytea NOT NULL CHECK (octet_length(ciphertext) > 0),
  ciphertext_sha256 text NOT NULL CHECK (ciphertext_sha256 ~ '^[0-9a-f]{64}$'),
  PRIMARY KEY (archive_id, ordinal)
);
ALTER TABLE iste_recovery_20260927.archives ENABLE ROW LEVEL SECURITY;
ALTER TABLE iste_recovery_20260927.archive_chunks ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA iste_recovery_20260927 FROM PUBLIC, anon, authenticated, service_role;
-- No client policies. Restricted database administrator operation only.
-- Verification status must be set by the transfer controller after actual checks,
-- never merely because the number of chunks happens to match.
COMMIT;
