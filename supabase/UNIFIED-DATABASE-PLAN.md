# ISTE Admin: database-first migration

Status: audited 2026-09-26; migration and client cutover NOT completed.

## Verified live state

Project: vwxbgklgkcbwrvtwypfs.

| Source | Rows / finding |
| --- | --- |
| public.profiles | 195 people; 103 marked ISTE |
| auth.users | 126 sign-in accounts |
| public.iste_members | 35 registry rows |
| public.users_iste_verification | 107 verification rows |
| public.events | 2 event records, not necessarily 2 completed events |
| identity.users | 0 |
| Profiles without an Auth UUID match | 75; none match another Auth account by normalized email |
| Auth accounts without profiles | 6 |
| Registry emails absent from profiles | 4 |
| Verification emails absent from profiles | 6 |
| Membership ID disagreements between verification and profiles | 2 |

Counts overlap and must NOT be summed to infer unique people. No duplicate normalized profile email groups or profile membership ID groups were found. Zero current same-UUID profile/Auth email disagreements.

The existing public.users is a VIEW over profiles, not a canonical users table. The private identity.users foundation requires every ID to exist in auth.users, so it cannot currently represent all registered people. Prior preview screenshots used synthetic data; their counts are not live measurements.

## Target model

users (one person, stable ID; optional unique auth_user_id)
  -> iste_members (unique user_id, unique normalized membership ID)
     -> execom_members (unique current user_id, title, tier, term, status)
        -> execom_permissions (feature, scope, allowed boolean, audit actor/time)

Use the existing identity schema for the canonical domain. Preserve public interfaces until every client is migrated; do not replace or rename public.users/public.iste_members in place during the first rollout.

- users holds the shared identity consumed by M-Link and the site. A person may exist before creating a sign-in account. Do not manufacture Auth accounts, passwords, or fake emails.
- is_iste_member and is_execom_member are server-maintained/derived flags backed by the linked records, not self-editable claims. Historical membership, active membership, and application access are separate concepts.
- Execom requires a valid linked ISTE membership. Expired/suspended memberships and ended Execom terms cannot grant Lynq access.
- Execom permissions are normalized rows, exposed as a yes/no map to clients. Missing permission means denied. Explicit denials and suspension take precedence. No arbitrary JSON supplied by the client may grant privileges.
- Lynq membership eligibility does not grant every action. Enforce feature and team scope on the server for each operation.
- Keep account identity IDs stable; maintain an auditable source-to-canonical mapping. Do not reassign existing Auth UUIDs by email.
- Preserve all existing profile fields and source provenance, including contact and academic details. Never put plaintext phone numbers into the misleadingly named phone_encrypted field.

## Migration order and release gates

1. Confirm a usable full database backup/PITR and test restoration in an isolated environment. Include Auth, schema, functions, policies, and constraints. Storage objects require their own backup. A second table in the same database is not a disaster-recovery backup.
2. Contain current authorization issues. profiles has an own-row UPDATE policy and authenticated UPDATE privileges on role, is_sudo, membership flags and permissions. Its only current trigger updates timestamps. users_view_dml is SECURITY DEFINER and supports privileged writes including ID changes. Audit all callers and secure both direct and view writes together; a fix to only one path is insufficient.
3. Approve the two conflicting membership IDs and five-tier mapping. Preserve unresolved identities in a private review queue, with all original values intact; never choose a winner from LIMIT 1 or overwrite either value.
4. Prepare an additive, versioned schema migration. Decouple person identity from optional Auth identity; establish uniqueness, foreign keys, indexed join keys, audit history, default-deny access, and a restricted sensitive-data store. Validate original values before normalization and record transformations.
5. Dry-run reconciliation across profiles, Auth, registry, and verification. Assert every source row is mapped or explicitly pending review; verify membership uniqueness, counts, field preservation, and rollback. Do not combine the source counts above.
6. Backfill only approved mappings. Keep old records and interfaces. Implement a controlled, transactional write path so changes during transition cannot cause old and new tables to diverge.
7. Test anonymous denial, cross-user denial, self-promotion denial, server-authorized administration, all five tiers, member/guest sign-in, website registration, mobile/web synchronization, and revoked access. Compare database permissions with client routing.
8. Release M-Link and Lynq separately behind a reversible configuration switch. Verify each one before proceeding. Only switch the IST site after registration/event tests. Mentron/Cloudflare migration remains deferred.
9. Restore Liquid Glass styling and replace the previous editorial/serif dashboard style after the database gate. Use consistent frosted surfaces, depth, contrast, a refined sans-serif type family, accessibility, reduced motion and small-screen fallbacks. Clearly label all mock previews.
10. Remove obsolete tables or interfaces only with a separate explicit deletion approval, a dependency audit, and a demonstrated restore path.

## Decisions confirmed — 2026-09-27

- User approved preserving membership-ID conflicts in a private review queue without overwriting either original value.
- Tier 1: organization chairperson and vice-chairperson.
- Tier 2: core Execom — secretary, joint secretary, treasurer, sub-treasurer, creative lead.
- Tier 3: other Execom members, excluding forum Execom and panel.
- Tier 4: forum members/Execom and panel. A forum chair/secretary is not an organization-wide Tier 1/2 office.
- Tier 5: subcommittee; named list to be supplied later. Do not infer or assign members yet.
- Ordinary users and ordinary ISTE members have no Execom tier; do not carry forward the old tier-6 interpretation.
- Multiple positions belong to one identity. Record each assignment and its scope; do not duplicate people or automatically union all permissions from a person's job titles.
- User reports NO backup. Production data migration and cutover remain blocked pending a verified recovery path.
- Public roster reference retrieved on 2026-09-27: https://istesctce.in/execom.html and its https://istesctce.in/JS/data.js. It explicitly identifies the 2025–26 term. See EXECOM-ROSTER-MAPPING.md for proposed assignments.

## Remaining decisions and gates

- Review the two conflicting membership IDs individually. Queueing them is approved; choosing replacement values is not.
- Match website entries against stable database identities, using corroborating email/membership identifiers. Name-only candidates are not enough to automatically grant access.
- Preserve existing access until the new five-tier mapping and feature-by-feature permissions have passed server-side tests. Rank alone does not specify every permitted action.
- Establish a verified recovery point and isolated restoration target before data migration. No backup restore has been verified in this task.

## Security boundaries

No claim of complete security or encryption compliance is made. Require TLS, server-side authorization, least-privilege APIs, private receipt storage, secrets outside clients, server-managed encryption keys for chosen sensitive fields, access logging, retention rules, and monitored backups. Do not use user_metadata for permissions.

Relevant documentation:
- https://supabase.com/docs/guides/database/postgres/row-level-security
- https://supabase.com/docs/guides/database/views
- https://supabase.com/docs/guides/platform/backups

This audit made no production data or schema changes. Earlier privacy restrictions remain separate from this incomplete unification.
