-- Read-only release gates. No personal records, token material, or writes.
-- Evaluate policy/function definitions too: absence of one named policy is not proof.
select jsonb_build_object(
  'legacy_rpc_exposure', (
    select coalesce(jsonb_agg(jsonb_build_object(
      'signature', p.oid::regprocedure::text,
      'security_definer', p.prosecdef,
      'anon_execute', has_function_privilege('anon', p.oid, 'EXECUTE'),
      'authenticated_execute', has_function_privilege('authenticated', p.oid, 'EXECUTE'),
      'configuration', p.proconfig
    )), '[]'::jsonb)
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'mark_attendance_atomic'
  ),
  'mutable_profile_authority', jsonb_build_object(
    'role_update', has_column_privilege('authenticated', 'public.profiles', 'role', 'UPDATE'),
    'permissions_update', has_column_privilege('authenticated', 'public.profiles', 'permissions', 'UPDATE'),
    'users_view_insert', has_table_privilege('authenticated', 'public.users', 'INSERT')
  ),
  'approved_active_assignments', (
    select count(*) from unified_next.execom_members
    where status = 'active' and approved_at is not null and approved_by is not null
      and current_date between starts_on and ends_on
  ),
  'permissions_by_state', (
    select jsonb_agg(s) from (
      select status, allowed, count(*) from unified_next.execom_permissions
      group by status, allowed
    ) s
  ),
  'attendance_and_token_policies', (
    select jsonb_agg(p) from (
      select tablename, policyname, roles, cmd, qual, with_check
      from pg_policies where schemaname = 'public'
        and tablename in ('attendance', 'qr_tokens')
    ) p
  ),
  'attendance_constraints', (
    select jsonb_agg(pg_get_constraintdef(oid)) from pg_constraint
    where conrelid = 'public.attendance'::regclass
  ),
  'realtime_tables', (
    select jsonb_agg(tablename) from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public'
      and tablename in ('events', 'attendance', 'certificates')
  )
) as attendance_release_evidence;
