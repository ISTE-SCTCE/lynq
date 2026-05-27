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
