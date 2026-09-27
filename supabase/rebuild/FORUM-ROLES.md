# Forum and society leadership normalization

Applied migration: normalize_forum_and_society_leadership (IST Admin, unified_next only).
Exact SQL: forum-role-normalization.sql. Do not rerun.

execom_members now has separate forum_code, forum_role and organization_role columns.
Forum codes: SWAS, EXIS, TORQ, GENESIS, BITS.
Forum roles: chairperson, vice_chairperson, secretary, joint_secretary, media.
Chair/chairman/chairperson and vice-chair variants use one canonical role each.
Social Media maps to media. Original position strings remain intact as legacy information.
Forum appointments remain Tier 4. Panel rows have no forum fields.
Society leadership tags are society_chairperson and society_vice_chairperson (Tier 1).
AADITHYAN R S is the imported society_chairperson; the tag does not activate privileges.
The two legacy vice-chair records remain pending review, not confirmed current appointments.

Checks enforce known values, forum/scope agreement, and separation from society leadership.
A unique index prevents duplicate user/forum/role/term assignments.
24 forum appointments were populated. TORQ has four staged appointments; its missing vice-chair was not invented.
All existing approval/status gates, permissions and RLS remain unchanged.
Applications must use the canonical fields in a future tested rollout; no UI was deployed.
