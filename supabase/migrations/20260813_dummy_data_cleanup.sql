-- ============================================================================
-- Dummy Data Cleanup: Events & Announcements Audit & Cleanup
-- File: supabase/migrations/20260813_dummy_data_cleanup.sql
-- ============================================================================
-- NOT a blind delete-all — that risks wiping real data if any exists mixed in.
-- Run the SELECT queries first, review the results, THEN uncomment and
-- run the matching DELETE once you've confirmed which rows are actually junk.
-- ============================================================================

-- ── STEP 1: Find likely dummy events ───────────────────────────────────────
SELECT id, title, date, category, created_by, created_at
FROM public.events
WHERE
  title ILIKE '%test%'
  OR title ILIKE '%dummy%'
  OR title ILIKE '%sample%'
  OR title ILIKE '%demo%'
  OR title ILIKE '%lorem%'
  OR title ILIKE '%placeholder%'
ORDER BY created_at DESC;

-- Also check for events all created within the same minute (bulk seed insert):
SELECT created_at::date, created_at::time(0), COUNT(*) AS events_created_together
FROM public.events
GROUP BY created_at::date, created_at::time(0)
HAVING COUNT(*) > 1
ORDER BY events_created_together DESC;

-- ── STEP 2: Find likely dummy announcements ────────────────────────────────
SELECT id, title, content, created_by, created_at
FROM public.announcements
WHERE
  title ILIKE '%test%'
  OR title ILIKE '%dummy%'
  OR title ILIKE '%sample%'
  OR title ILIKE '%demo%'
  OR title ILIKE '%lorem%'
  OR title ILIKE '%placeholder%'
  OR content ILIKE '%lorem ipsum%'
ORDER BY created_at DESC;

-- ── STEP 3: Delete targeted dummy rows after review ───────────────────────
-- Example:
-- DELETE FROM public.events WHERE id IN (101, 102, 103);
-- DELETE FROM public.announcements WHERE id IN (11, 12);
