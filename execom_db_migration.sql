-- 1. Rename tables
ALTER TABLE IF EXISTS folders RENAME TO execom;
ALTER TABLE IF EXISTS folder_members RENAME TO execom_members;
ALTER TABLE IF EXISTS folder_permissions RENAME TO execom_permissions;

-- 2. Rename columns/foreign keys in the renamed tables themselves
ALTER TABLE IF EXISTS execom_members RENAME COLUMN folder_id TO execom_id;
ALTER TABLE IF EXISTS execom_members RENAME COLUMN folder_role TO execom_role;
ALTER TABLE IF EXISTS execom_permissions RENAME COLUMN folder_id TO execom_id;

-- 3. Rename folder_id to execom_id in other tables
ALTER TABLE IF EXISTS events RENAME COLUMN folder_id TO execom_id;
ALTER TABLE IF EXISTS budget_requests RENAME COLUMN folder_id TO execom_id;
ALTER TABLE IF EXISTS messages RENAME COLUMN folder_id TO execom_id;
ALTER TABLE IF EXISTS conversations RENAME COLUMN folder_id TO execom_id;
ALTER TABLE IF EXISTS reports RENAME COLUMN folder_id TO execom_id;
ALTER TABLE IF EXISTS tasks RENAME COLUMN folder_id TO execom_id;
ALTER TABLE IF EXISTS financial_income RENAME COLUMN folder_id TO execom_id;
ALTER TABLE IF EXISTS financial_ledger RENAME COLUMN folder_id TO execom_id;

-- 4. Add execom_tag to member_profiles and users tables
ALTER TABLE IF EXISTS member_profiles ADD COLUMN IF NOT EXISTS execom_tag VARCHAR(255);
ALTER TABLE IF EXISTS users ADD COLUMN IF NOT EXISTS execom_tag VARCHAR(255);

-- 5. Seeding initial Execom teams
INSERT INTO execom (name) VALUES
('Core Execcom'),
('Activity Coordination Team'),
('Technical Team'),
('MD Team'),
('Marketing'),
('Design'),
('Media'),
('SWAS'),
('EXIS'),
('TORQ'),
('Genesis'),
('Panel')
ON CONFLICT DO NOTHING;
