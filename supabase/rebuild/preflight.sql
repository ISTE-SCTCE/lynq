-- READ ONLY: run separately on the verified source and destination.
-- Output is metadata, not user rows or authentication secrets.
SELECT n.nspname AS schema_name, c.relname AS object_name, c.relkind AS object_kind,
       c.relrowsecurity AS rls_enabled, pg_total_relation_size(c.oid) AS relation_bytes
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
  AND n.nspname NOT LIKE 'pg_toast%'
  AND c.relkind IN ('r', 'p', 'v', 'm', 'S')
ORDER BY 1, 2;

SELECT n.nspname AS schema_name, p.proname, p.prosecdef AS security_definer
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname IN ('public', 'identity')
ORDER BY 1, 2;

SELECT schemaname, tablename, policyname, roles, cmd
FROM pg_policies
WHERE schemaname IN ('public', 'identity')
ORDER BY 1, 2, 3;
