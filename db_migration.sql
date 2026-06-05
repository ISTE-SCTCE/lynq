-- 1. Migrate old 'execcom' role to 'forum_execcom' in your profiles/users table
UPDATE member_profiles 
SET role = 'forum_execcom' 
WHERE role = 'execcom';

UPDATE users -- if you have a separate users table
SET role = 'forum_execcom'
WHERE role = 'execcom';

-- 2. Add is_sudo and is_budget_activated boolean flags
ALTER TABLE member_profiles
ADD COLUMN IF NOT EXISTS is_sudo BOOLEAN DEFAULT false;

ALTER TABLE member_profiles
ADD COLUMN IF NOT EXISTS is_budget_activated BOOLEAN DEFAULT false;

-- If you have a separate users table that stores these instead:
ALTER TABLE users
ADD COLUMN IF NOT EXISTS is_sudo BOOLEAN DEFAULT false;

ALTER TABLE users
ADD COLUMN IF NOT EXISTS is_budget_activated BOOLEAN DEFAULT false;

-- 3. Create access_control_logs table for logging sudo grants
CREATE TABLE IF NOT EXISTS access_control_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    granted_by UUID REFERENCES auth.users(id),
    granted_to UUID REFERENCES auth.users(id),
    action VARCHAR(255) NOT NULL, -- e.g., 'GRANT_SUDO', 'REVOKE_SUDO'
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Note: Ensure you apply RLS policies to access_control_logs if needed.

-- 4. Fixed sync_user_with_members trigger function (replaces 'IF m_record IS NOT NULL' gotcha with 'IF FOUND')
CREATE OR REPLACE FUNCTION public.sync_user_with_members()
RETURNS TRIGGER AS $$
DECLARE
    m_record RECORD;
BEGIN
    -- Find a matching member by email (case-insensitive)
    SELECT * INTO m_record 
    FROM public.members 
    WHERE LOWER(TRIM(email)) = LOWER(TRIM(NEW.email))
    LIMIT 1;

    -- FIXED: In PL/pgSQL, 'record IS NOT NULL' returns false if ANY field in the record is NULL.
    -- Changed to 'IF FOUND THEN' to correctly detect if the matching row was found.
    IF FOUND THEN
        -- Pre-populate users fields from members foundation
        NEW.name := COALESCE(NEW.name, m_record.name);
        NEW.phone := COALESCE(NEW.phone, m_record.phone);
        NEW.branch := COALESCE(NEW.branch, m_record.department);
        NEW.membership_plan := COALESCE(NEW.membership_plan, m_record.plan);
        NEW.forum := COALESCE(NEW.forum, m_record.forum);
        NEW.membership_date := COALESCE(NEW.membership_date, m_record.joined_date);
        NEW.expiry_date := COALESCE(NEW.expiry_date, m_record.membership_expiry, m_record.expiry_date);
        
        -- Map role from members table (lower-cased for app compatibility)
        IF m_record.role IS NOT NULL THEN
            NEW.role := LOWER(TRIM(m_record.role));
        END IF;
        
        -- Also update the user_id in the members table to link them
        UPDATE public.members 
        SET user_id = NEW.id 
        WHERE id = m_record.id;
        
        -- Also populate or update member_profiles for member_app integration
        INSERT INTO public.member_profiles (
            user_id, membership_id, membership_type, validity_start, validity_end
        ) VALUES (
            NEW.id, 
            COALESCE(m_record.iste_id, m_record.ui_id), 
            COALESCE(m_record.plan, 'Annual'), 
            COALESCE(m_record.joined_date, CURRENT_DATE), 
            COALESCE(m_record.membership_expiry, m_record.expiry_date)
        ) ON CONFLICT (user_id) DO UPDATE SET
            membership_id = EXCLUDED.membership_id,
            membership_type = EXCLUDED.membership_type,
            validity_start = EXCLUDED.validity_start,
            validity_end = EXCLUDED.validity_end;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

