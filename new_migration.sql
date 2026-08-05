-- ============================================================
-- Migration: m-lynq Fixes — QR Atomicity, Events RLS, Attendance Constraint
-- Run this against your Supabase project via the SQL Editor.
-- Review each section before applying. Sections are idempotent.
-- ============================================================


-- ── 1. Unique constraint on attendance(event_id, user_id) ──────────────────
-- Prevents duplicate attendance at the DB level (last line of defence).

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.attendance'::regclass
      AND conname  = 'attendance_event_user_unique'
  ) THEN
    ALTER TABLE public.attendance
      ADD CONSTRAINT attendance_event_user_unique UNIQUE (event_id, user_id);
  END IF;
END
$$;


-- ── 2. Atomic attendance mark RPC ─────────────────────────────────────────
-- Called by qr_scanner_screen.dart instead of separate INSERT + UPDATE.
-- Atomically:
--   a) marks the qr_token as used (only if is_used=false AND not expired)
--   b) inserts the attendance row
-- Returns JSONB: {success: true} or {success: false, error: '<reason>'}

CREATE OR REPLACE FUNCTION public.mark_attendance_atomic(
  p_event_id   INT,
  p_user_id    UUID,
  p_token_id   INT,
  p_scanned_by UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_token_rows_updated INT;
BEGIN
  -- Atomically mark token as used. Only succeeds if the token is still valid
  -- (is_used=false AND expires_at > NOW()). This is the primary race-condition guard.
  UPDATE public.qr_tokens
  SET    is_used = true
  WHERE  id         = p_token_id
    AND  is_used    = false
    AND  expires_at > NOW();

  GET DIAGNOSTICS v_token_rows_updated = ROW_COUNT;

  IF v_token_rows_updated = 0 THEN
    -- Token was already used or expired — concurrent scan lost the race
    RETURN jsonb_build_object('success', false, 'error', 'token_invalid_or_race');
  END IF;

  -- Insert attendance row. The UNIQUE constraint handles the unlikely case
  -- where two separate valid tokens are used for the same user/event.
  BEGIN
    INSERT INTO public.attendance (event_id, user_id, scanned_by, qr_token_id)
    VALUES (p_event_id, p_user_id, p_scanned_by, p_token_id);
  EXCEPTION
    WHEN unique_violation THEN
      RETURN jsonb_build_object('success', false, 'error', 'already_attended');
  END;

  RETURN jsonb_build_object('success', true);
END;
$$;

-- Grant execute to authenticated users (execom scanners are authenticated)
GRANT EXECUTE ON FUNCTION public.mark_attendance_atomic(INT, UUID, INT, UUID)
  TO authenticated;


-- ── 3. RLS on events table ────────────────────────────────────────────────
-- Enforces allowed_roles server-side so even direct API calls are filtered.

-- Step 3a: Enable RLS (idempotent)
ALTER TABLE public.events ENABLE ROW LEVEL SECURITY;

-- Step 3b: Allow execom to see all events
CREATE POLICY "Execom sees all events"
  ON public.events
  FOR SELECT
  TO authenticated
  USING (
    (SELECT role FROM public.users WHERE id = auth.uid())
    IN ('core_execcom', 'vice_chairman', 'chairman', 'forum_execcom', 'panel')
  );

-- Step 3c: Allow members to see only events their role is in.
-- If allowed_roles is NULL or empty the event is visible to all (backwards compat).
CREATE POLICY "Members see permitted events"
  ON public.events
  FOR SELECT
  TO authenticated
  USING (
    (SELECT role FROM public.users WHERE id = auth.uid())
      IN ('core_execcom', 'vice_chairman', 'chairman', 'forum_execcom', 'panel')
    OR
    (
      allowed_roles IS NULL
      OR array_length(allowed_roles, 1) IS NULL
      OR (SELECT role FROM public.users WHERE id = auth.uid()) = ANY(allowed_roles)
    )
  );

-- Step 3d: Allow execom to INSERT/UPDATE/DELETE events
CREATE POLICY "Execom manages events"
  ON public.events
  FOR ALL
  TO authenticated
  USING (
    (SELECT role FROM public.users WHERE id = auth.uid())
    IN ('core_execcom', 'vice_chairman', 'chairman', 'forum_execcom', 'panel')
  )
  WITH CHECK (
    (SELECT role FROM public.users WHERE id = auth.uid())
    IN ('core_execcom', 'vice_chairman', 'chairman', 'forum_execcom', 'panel')
  );


-- ── 4. qr_tokens cleanup indexes ──────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_qr_tokens_expires_at
  ON public.qr_tokens (expires_at);

CREATE INDEX IF NOT EXISTS idx_qr_tokens_is_used_expires
  ON public.qr_tokens (is_used, expires_at);


-- ── 5. Optional: scheduled token cleanup (requires pg_cron on Pro plan) ───
-- SELECT cron.schedule(
--   'cleanup-expired-qr-tokens',
--   '*/30 * * * *',
--   $$DELETE FROM public.qr_tokens WHERE expires_at < NOW() - INTERVAL '1 hour'$$
-- );
--
-- Alternative: Supabase Edge Function cron (free plan compatible):
--   supabase.from('qr_tokens').delete().lt('expires_at', new Date(Date.now() - 3600000).toISOString())
