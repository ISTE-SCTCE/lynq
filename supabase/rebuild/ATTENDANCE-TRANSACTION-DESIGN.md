# Attendance transaction: blocked from production activation

Read-only audit: 2026-09-27, IST Admin (`vwxbgklgkcbwrvtwypfs`).
No live schema, policies, data, grants, or functions were changed by this audit.
This is a design, not an applied migration. `attendance.candidate.sql` now implements
a local-only candidate with seven passing synthetic PGlite tests in
`backend-tests/attendance.test.mjs`. It has not been deployed or tested against
live callers, concurrent PostgreSQL connections, or mobile devices.

## Local candidate and deliberate activation gates

The candidate is server-only SECURITY INVOKER. A future endpoint must validate the
caller session and derive the passed Auth ID, rate-limit issuance, and not log QR
credential material. It creates private, RLS-enabled, unseeded event configuration,
explicit attendee eligibility, and credential tables. It does not assign anyone a
permission or infer an event's scope/eligibility from editable legacy roles.

Each call fails closed while either old attendance overload is client-executable,
client attendance DML privileges remain, profile ID rewriting is permitted, or the
legacy users view remains writable. The candidate does not retire those bypasses
itself. Other privileged legacy functions still require comprehensive audit.

Approved configuration selects either `active_users` or `approved_attendees` for
each event. These are deliberate new modes, not automatic interpretations of
legacy `allowed_roles`. Explicit event configuration and an approved
`attendance.record` scoped permission are required before using the candidate.
Credentials are random, last 30 seconds, and bind canonical user/event/day. Only
their SHA-256 digests persist. Attendance retains legacy profile/Auth FK IDs through
a verified identity bridge; the credential retains the canonical ID and attendance
reference. Existing public attendance and QR token records are never migrated or
deleted by this file. New candidate writes do not use client-minted `qr_tokens`.

## Verified blockers

- Both public `mark_attendance_atomic` overloads are SECURITY DEFINER, executable
  by `anon` and `authenticated`, with no fixed search path. Neither verifies
  `auth.uid()`, scanner authorization, token ownership, day bounds, finalized
  attendance, or attendee eligibility. Both trust caller-supplied `scanned_by`.
- The five-argument function consumes a token before a duplicate insert and omits
  `qr_token_id` in the attendance record. The four-argument function also leaves
  a token consumed when it catches a duplicate.
- Authenticated users can insert attendance under an unconditional INSERT policy
  and read all attendance under an unconditional SELECT policy. Adding a narrower
  policy does not override these permissive policies.
- `profiles.role` and `profiles.permissions` are writable by authenticated users
  on their own row. The only non-internal profile trigger updates a timestamp.
  The writable `users` view has a SECURITY DEFINER DML trigger. Existing rank
  helpers read these mutable roles and cannot be the new authorization authority.
- `unified_next` has zero active Execom assignments. All 222 imported permissions
  are pending review, even the 41 with `allowed=true`. No dedicated attendance
  permission definition exists. Importing a flag is not approval to activate it.
- Event scopes currently use `events.execom_id` (a folder ID), while unified
  assignments use `organization`, `panel`, or `forum:<code>`. There is no verified
  folder-to-authoritative-scope mapping in this audit.
- `qr_tokens` does not bind tokens to an event/day. Token insertion permits the
  owner to supply values, including expiry. Server issuance must set bounded expiry
  and unpredictable token material; browser encryption secrets cannot provide this.

## Contract to implement after authorization is established

Use one versioned endpoint shared by website and APK:

`record_event_attendance(event_id: bigint, day_number: integer, qr_credential: text)`

Do not accept `scanned_by`, claimed attendee UUID, or a bare sequential token ID
as authoritative input. Derive the scanner from the validated session and the
attendee from the verified token. Authenticate server-side; derive canonical user
identity from `auth_user_id`, never assume canonical UUID equals Auth UUID.

The permission decision must require an active canonical user, valid approved
Execom appointment, and approved `attendance.record` permission for the exact
event scope. An organization-wide permission can be a separately approved scope.
The society-chair tag alone, legacy tier number, editable profile, or pending
permission must not silently confer access. Do not invent the initial approvals.

Legacy `allowed_roles` requires an explicit mapping to protected canonical roles
or replacement eligibility rules before restricted events are enabled. Unknown
scope/eligibility must deny, not fall back to permissive legacy helpers.

## Transaction algorithm

1. Reject anonymous/expired/revoked sessions. Resolve scanner and approved scope.
2. Acquire event row `FOR SHARE` so concurrent event finalization waits; verify
   event exists, attendance is open, day is 1..num_days, and eligibility rules.
3. Lock the server-issued token row `FOR UPDATE`. Recheck expiry using database
   clock after acquiring the lock, unused state, credential digest, intended
   attendee, event and day bindings. Store only a digest of credential material.
4. Insert attendance with `(event_id, user_id, day_number, scanned_by,
   qr_token_id)` and `ON CONFLICT (event_id,user_id,day_number) DO NOTHING
   RETURNING id`. Derive scanner ID server-side, resolve legacy FK identity through
   the verified source map during compatibility, and never mutate profile IDs.
5. On duplicate, return `already_attended` without consuming the new token.
   On successful insert, consume the locked token in the same transaction.
6. Any failure after insertion must raise and roll back the full operation;
   never catch an error and return success or commit a half-completed operation.
7. Return only attendance ID, outcome, event ID and day; authorized reports resolve
   attendee details separately. Client retry after a lost response must display the
   persisted duplicate as already recorded, not attempt a second check-in.

Lock order is event then token everywhere. Keep the transaction short: no network
calls or certificate generation inside it. Existing unique triple already provides
the concurrency boundary. Add a unique token-use constraint only after auditing
historical data; do not delete historical rows to make a constraint pass.

## Privilege and rollout requirements

Prefer a SECURITY INVOKER entry point with correctly scoped grants/RLS. If internal
token verification requires privileged code, isolate a narrowly granted internal
function in a non-exposed schema, with explicit identity/scope checks and fixed
empty search path. A definer helper is not a workaround for failed RLS.

Before enabling it, remove alternative direct-write bypasses and revoke execution
on BOTH unsafe legacy overloads atomically with tested client compatibility.
Retain narrow self-read attendance access plus approved scoped reporting access.
Do not broadly grant access to `unified_next` to make the UI work.

Both apps must switch to this same contract. Realtime attendance/certificate
publication requires reviewed SELECT policies first, then publication/subscriptions;
Realtime alone is not an authorization mechanism. Reports also need pagination.

## Isolated test matrix (not yet executed)

Use a local/test database and synthetic scanner/member/event/token fixtures. Never
run mutation fixtures against production. Run each test under its real caller role,
not just `postgres`; concurrency tests need two separate connections.

| Test | Required outcome |
|---|---|
| Anonymous or expired/revoked session | Denied; no attendance/token mutation |
| Member self-edits legacy role to chairman | Still denied |
| Active appointment but pending permission | Denied |
| Approved forum scanner, different forum event | Denied |
| Approved scope and eligible attendee | One row; token consumed; scanner derived |
| Token belongs to another attendee/event/day | Denied |
| Missing, expired, already-used or forged token | Denied |
| Null, zero, negative or beyond-limit day | Denied |
| Finalized event | Denied |
| Two simultaneous uses of same token | At most one successful check-in |
| Two tokens for same attendee/event/day | One row; duplicate token unconsumed |
| Same attendee on different valid event day | Separate valid attendance row |
| Failure while consuming token | Insert rolls back too |
| Finalize concurrently with scan | Serialized, never write after finalized state |
| Client loses response and retries | No duplicate; shows persisted attendance |
| Direct table insert and old RPC calls | Denied for client roles |
| Unauthorized reporting/subscription | No other-user attendance disclosure |

## Verification performed

Live read-only catalog checks verified the blockers above, columns, unique triple,
foreign keys, function definitions, policies, grants, and pending permission counts.
No replacement RPC was installed or exercised in production. The accompanying preflight SQL is
read-only and reports gates, not a claim of successful end-to-end attendance.

Reference: https://supabase.com/docs/guides/database/functions
