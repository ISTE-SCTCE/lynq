# Unreleased backend candidates

These files are local, NOT live migrations. No new Supabase project is needed.

- membership-approval.candidate.sql: service-only, invoker-rights transactional
  registration approval. Requires an explicitly approved organization-scoped
  membership.approve permission on an active, date-valid Execom appointment.
  No permissions are automatically assigned by tier or title.
- profile-provisioning.candidate.sql: service-only verified Auth identity and
  required profile details; creates ordinary account details, never Execom or
  membership authority. Existing email/UUID conflicts are blocked, not rewritten.
- Desktop/mlynq/supabase/functions/provision-member: local Edge entry point obtains
  Auth user from a verified bearer token, not a client-supplied UUID or email.
- backend-tests: pinned PGlite PostgreSQL runtime with synthetic data only.
  Run npm ci then npm test. No production database/credentials are used.

## Current evidence

11 PostgreSQL integration tests pass: successful/idempotent approval, official-ID
conflicts, unauthorized access, pending/revoked permission, expired term, invalid
forums/totals, mid-transaction failure rollback, verified signup, unverified/banned
signup rejection, privilege injection, and stable identity handling.
These are not multi-connection race tests, full Supabase API tests, or a recovery test.

The Edge provisioning handler also passes nine local tests, including rejecting
incomplete or mismatched database results. Registration totals now use a gated
canonical membership-count function rather than legacy profile flags.

Verified Auth rows are locked while provisioning. The candidate requires narrowly
scoped Auth-column SELECT and UPDATE grants for service_role (PostgreSQL row locks
require an UPDATE privilege); no Auth UPDATE is performed. These new grants need
hosted security review before deployment. Basic verified account activation does
not activate ISTE membership, Execom appointments, or their permissions.

## Term decision recorded on 2026-09-27

The user confirmed the current Execom term starts in March 2026 and ends in
February 2027. Proposed inclusive date boundaries are 2026-03-01 to 2027-02-28;
the exact days were not specified. This decision has not been written to the
live database and does not approve imported appointments.

## Registration approval decision recorded on 2026-09-27

The user authorizes organization-level Tier 1 and Tier 2 members, plus all three
Tier 3 Membership Drive Coordinators, to approve registrations. Other Tier 3,
Tier 4 and Tier 5 appointments do not qualify. This is membership.approve only,
not a grant of unrelated administration privileges. Use explicit approved
permissions on verified, current appointments; expiry, suspension and explicit
denial must continue to block approval. Do not use editable client role fields.

Read-only roster verification found five Tier 2 appointments and three Tier 1
appointments (including two vice-chair records needing current-roster review).
The user subsequently identified MAHADEVAN AL and SADHIKA SUNIL B as the other
two Membership Drive Coordinators alongside Nayana Salil. Their existing
appointments were matched read-only by stable IDs in reviewer-roster.json;
legacy job titles are preserved. No live access was changed.

New approvals start on their approval date and expire the day before the same date
after the purchased 1–4-year duration. Confirm this policy before deployment.
Phone/DOB remain in existing intake/legacy fields; no new encryption claim is made.
Provisioning does not synchronize legacy membership flags; the controlled compatibility
writer and canonical reads must be completed before a client cutover.

## Not deployable as a complete system yet

1. Restore/verify recovery backup. Review migration with the CLI (not installed here).
2. Replace the unsafe Auth ID-rewriting trigger and restrict editable legacy privilege
   fields / SECURITY DEFINER view writes. These candidates do not fix those older paths.
3. Apply the recorded term and reviewer rule to verified appointments, resolve the
   imported vice-chair records, then approve
   the exact canonical assignments and scoped permissions; currently none are active.
4. Validate actual hosted role grants, RLS, Edge routes, browser CORS, and rollback.
5. Wire complete required signup fields into both web and Flutter clients.
6. Implement verified legacy/canonical membership compatibility and synchronization.
7. Run cross-device sign-in, approval, attendance/certificate and failure-path tests.

Never deploy manage-membership-registrations alone: its new authorization and approval
RPC dependencies are not installed in production and would deny current review access.
The original live functions and clients have not been changed this turn.
