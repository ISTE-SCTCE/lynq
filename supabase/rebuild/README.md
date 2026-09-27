# IST Admin rebuild — isolated staged import

Updated 2026-09-27. **The additive unified_next schema is populated with a pending-review copy of IST Admin identity/membership data. No archive, cross-project transfer, or client cutover has been executed.**

## Completed: staged membership backfill

Applied migration: stage_membership_and_execom_backfill.
Exact SQL: membership-backfill.sql (already applied; do not rerun).

- 201 email-deduplicated user records, preserving all 195 profile IDs; 120 linked to matching existing Auth IDs.
- 337 source rows mapped across profiles, member registry, and verification. This is not an import of every Auth-only or cross-project account.
- 101 non-conflicting IST memberships. Primary key is membership_id; user_id remains unique and linked.
- duration_years supports 1–4: 99 annual memberships imported as 1, two unknown lengths left NULL.
- forum_memberships supports multiple SWAS, EXIS, TORQ, GENESIS, BITS memberships; 32 member records have known forums.
- 68 pending Execom assignments: tier 1 = 3, tier 2 = 5, tier 3 = 21, tier 4 = 39, tier 5 = 0.
- 222 pending permission settings, namespaced by source to avoid assuming differently named permissions are equivalent.
- Eight identities have conflicting membership IDs (14 source references); two Execom assignments withheld because membership is unresolved.
- All 68 imported Execom assignments need term/roster verification; tier 1 includes both legacy vice-chair records, not a claim that both are current.
- 69 legacy folder assignments and two global permission settings remain reference-only review items.
- Dates and approving actors were not invented. No imported assignment, membership, or permission is active.
- Original row counts AND whole-row fingerprints are unchanged for profiles, member registry, verification, folder membership and folder permissions.
- All new tables retain RLS and deny app-role schema access. Existing legacy security problems remain outside this import.
- No phone ciphertext was fabricated or plaintext phone data duplicated. Review items reference originals; they are not backups.

No app update is needed for this isolated import. Connecting apps to these tables will require a separately tested API/client rollout. Existing source updates do not automatically replicate into this staging copy.

## Earlier milestone: table creation

Applied migration: create_private_unified_user_foundation.
See unified-schema.applied.sql for the exact applied SQL.
Created 10 tables and the user_membership_flags view in unified_next.
The five tier definitions were populated; the subsequent staged backfill is described above.
All new tables have RLS enabled. Verified no schema usage or table SELECT access for anonymous or authenticated app roles; service-role schema access is also revoked.
Existing counts are unchanged: profiles 195, member registry 35, verification 107, Auth users 126, events 2.
Mentron was not changed.

Security advisor reports RLS without policies on the new tables; this is deliberate default-deny during staging, not a ready-to-use client API. Existing unrelated security warnings remain. Reference: https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy

## Fixed source and destination

- Source: iste-admin / vwxbgklgkcbwrvtwypfs (Postgres 17).
- Temporary archive destination: mentron / ysllolnoyezfdllqocgv (Postgres 17).
- Both projects are ACTIVE_HEALTHY.
- Source inventory: 37 public application tables, 8 identity tables, 27 Auth tables, 8 Storage tables, two public views, and additional platform/migration metadata.
- Mentron already has public.profiles, public.events, its own Auth users, and its own Storage metadata. Never restore the source dump into those live schemas.

## Files

- archive-container.sql: proposed private container for encrypted database archive chunks in Mentron. Stores an archive, NOT active imported source tables. Not yet applied.
- unified-schema.draft.sql: original design draft. Its structure is now applied; do not rerun.
- unified-schema.applied.sql: exact SQL applied to IST Admin; no client API exposure.
- preflight.sql: read-only object inventory and source counts; no personal records.
- release-gates.json: explicit incomplete recovery/cutover gates.

The SQL files are review drafts, not CLI-generated migrations. Before deployment, generate versioned migrations with the installed CLI and verify the target project. Do not run all files against one project.

## Why an archive, not a live clone inside Mentron?

A raw restore could overwrite Mentron's tables, execute triggers, mix Auth accounts, or connect foreign keys to the wrong users. Prefixing table names alone does not safely rewrite dependencies, functions, policies or managed Auth schemas.

The proposed alternative stores an **encrypted full database archive** in a private Mentron container. It must also be retained off-project. The archive can later be restored into a separate empty rehearsal database, NOT Mentron's live application schemas. This is a proposed implementation of the holding-copy request; it is not a claim that an isolated full clone has been created.

## Transfer prerequisites

1. Configure authenticated PostgreSQL connections for BOTH projects locally using a protected credential store or pg_service/pgpass configuration. Never put passwords in chat, source control, command output, or browser code.
2. Install compatible PostgreSQL backup/restore tools or the supported Supabase CLI toolchain. Inspect their actual --help before execution.
3. Select an encrypted backup location outside this OneDrive-synchronized repository and provide a recovery encryption recipient/key arrangement. A lost encryption key makes the backup unusable.
4. Supply a separate disposable restoration target. Neither live project may be the restore-test target. No paid project/branch is provisioned without cost approval.

The MCP connection permits SQL operations but does not expose a streaming pg_dump export. Local export credentials and tools are currently absent. Do not substitute a table-by-table JSON dump for a consistent, verified recovery archive.

## Copy, verify, build, then switch

1. Inventory the complete source and destination, including object dependencies, platform-managed schemas, custom roles, policies, functions, sequences, extensions, migration history and storage.
2. Export the source using a consistent snapshot. Capture platform configuration and Edge Function sources/dependencies separately. Do not activate source Auth sessions/accounts inside Mentron.
3. Encrypt the archive before upload; checksum it. Upload only encrypted chunks into the new private archive container. Deny anonymous, authenticated and service-role access to this container. Destination project owners/database administrators remain in its trust boundary.
4. Download the archive again, verify every chunk and the complete checksum, decrypt with the recovery key, and perform an isolated restore rehearsal. Compare row counts, identities, membership IDs, foreign keys, grants, RLS, function behavior, sequences, and representative data checksums.
5. Database backups contain Storage metadata, not object bytes. Preserve IST Admin's actual Storage objects separately. Mentron's Cloudflare files remain untouched.
6. Record the snapshot timestamp. Capture subsequent source changes or schedule a short coordinated write freeze before final cutover. A stale archive cannot justify deleting recent registrations.
7. Build the additive unified schema within IST Admin. Reconcile every source row, preserve the approved conflict queue, backfill only verified identity matches, and keep legacy interfaces operational.
8. Implement server-authorized admin writes and own-record reads before app connection. The private draft's default-deny policies deliberately provide no client write route. Tier numbers alone never authorize an operation.
9. Test M-Link, Lynq and the site in that order. Retain original tables during user review. UI remains Liquid Glass with the typography revision planned separately.
10. Only after user inspection and a fresh explicit cleanup confirmation may the exact archive objects created by this run be removed. Keep an independent verified recovery archive. No DROP/TRUNCATE/DELETE script is supplied.

## Limitations of the draft schema

- Staged transformations are complete for the documented subset; identity reconciliation, cross-project transfer, API rollout, encryption-key setup and restoration tests remain incomplete.
- Existing legacy Execom privileges may have been self-editable. Do not blindly treat current role flags as trusted authorization history.
- Subcommittee names are pending. No Tier 5 member is assigned.
- The website roster is for 2025–26; positions need confirmed terms, not automatic renewal.
- Multiple assignments may exist for one person. Permission resolution must consider scope, dates, suspension and explicit denials; do not union grants indiscriminately.
- Exact-match names alone are not sufficient to bind Auth accounts.

Official recovery guidance: https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore
