import React, { useState, useEffect } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import confetti from 'canvas-confetti';
import { motion, AnimatePresence } from 'framer-motion';
import { 
  ArrowLeft, 
  Mail, 
  Phone, 
  Calendar, 
  Plus, 
  Trash, 
  Users, 
  Tag, 
  GraduationCap, 
  AlertTriangle,
  FolderOpen
} from 'lucide-react';
import { useAuth } from '../../core/auth-provider';
import { supabase } from '../../core/supabase-client';
import { AppRole, AppRoleLabels } from '../../core/constants';
import { UserModel, FolderMemberModel, FolderModel } from '../../models/types';
import { GlassCard } from '../../shared/components/GlassCard';
import { NavBar } from '../../shared/components/NavBar';

export const MemberDetailScreen: React.FC = () => {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { permissions, currentUser } = useAuth();
  
  const [user, setUser] = useState<UserModel | null>(null);
  const [memberships, setMemberships] = useState<any[]>([]);
  const [isLoading, setIsLoading] = useState(true);

  // Dialog States
  const [showRoleModal, setShowRoleModal] = useState(false);
  const [selectedRole, setSelectedRole] = useState('member');
  
  const [showForumModal, setShowForumModal] = useState(false);
  const [forums, setForums] = useState<FolderModel[]>([]);
  const [selectedForum, setSelectedForum] = useState<number | ''>('');
  const [selectedForumRole, setSelectedForumRole] = useState('member');

  const [isUpdating, setIsUpdating] = useState(false);

  const loadUserData = async () => {
    if (!id) return;
    setIsLoading(true);
    try {
      // Parallelise both fetches
      const [profileRes, memberRes] = await Promise.all([
        supabase
          .from('users')
          .select('id, email, name, role, post, phone, roll_number, branch, forum, membership_date, expiry_date, is_sudo')
          .eq('id', id)
          .single(),
        supabase
          .from('folder_members')
          .select('id, folder_id:execom_id, folder_role:execom_role, user_id, joined_at, folders:folders(id, name)')
          .eq('user_id', id),
      ]);

      if (profileRes.error) throw profileRes.error;
      setUser(profileRes.data as UserModel);
      setSelectedRole(profileRes.data.role);
      setMemberships(memberRes.data || []);
    } catch (e) {
      console.error('Error fetching member profile:', e);
      navigate('/members');
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    loadUserData();
  }, [id]);

  const loadForums = async () => {
    try {
      const { data, error } = await supabase
        .from('folders')
        .select('*')
        .order('name');

      if (error) throw error;
      
      const allForums = (data || []) as FolderModel[];
      const joinedIds = new Set(memberships.map((m) => m.folder_id));
      const available = allForums.filter((f) => !joinedIds.has(f.id));
      
      setForums(available);
      if (available.length > 0) {
        setSelectedForum(available[0].id);
      } else {
        setSelectedForum('');
      }
    } catch (e) {
      console.error('Error loading forums list:', e);
    }
  };

  const handleOpenForumModal = () => {
    loadForums();
    setShowForumModal(true);
  };

  const handleUpdateRole = async () => {
    if (!user || !currentUser) return;

    const targetRoleLevel = AppRole[selectedRole as keyof typeof AppRole] || AppRole.member;
    if (targetRoleLevel >= AppRole.forumExeccom) {
      const curRoleLevel = AppRole[currentUser.role as keyof typeof AppRole] || AppRole.member;
      if (curRoleLevel < AppRole.viceChairman) {
        alert('Only Chairman/Vice Chairman can promote members to Execcom roles.');
        return;
      }
    }

    setIsUpdating(true);
    try {
      // Sync role to BOTH users and members tables (keep consistent with Flutter app)
      const [usersRes] = await Promise.all([
        supabase.from('users').update({ role: selectedRole }).eq('id', user.id),
        supabase.from('members').update({ role: selectedRole }).eq('user_id', user.id),
      ]);

      if (usersRes.error) throw usersRes.error;

      setShowRoleModal(false);
      loadUserData();
      // Trigger gorgeous success confetti
      confetti({
        particleCount: 100,
        spread: 70,
        origin: { y: 0.8 },
        colors: ['#0f7549', '#16c07a', '#ffffff', '#3b82f6']
      });
      alert('Role updated successfully!');
    } catch (e) {
      console.error('Error saving role change:', e);
      alert('Failed to update role');
    } finally {
      setIsUpdating(false);
    }
  };

  const handleAddToForum = async () => {
    if (!user || selectedForum === '') return;
    setIsUpdating(true);
    try {
      const { error } = await supabase
        .from('folder_members')
        .insert({
          execom_id: selectedForum,
          user_id: user.id,
          execom_role: selectedForumRole,
        });

      if (error) throw error;

      setShowForumModal(false);
      loadUserData();
      // Trigger gorgeous success confetti
      confetti({
        particleCount: 80,
        spread: 60,
        origin: { y: 0.8 },
        colors: ['#0f7549', '#16c07a', '#ffffff', '#3b82f6']
      });
      alert('Added to team successfully!');
    } catch (e) {
      console.error('Forum insertion error:', e);
      alert('Failed to add to forum');
    } finally {
      setIsUpdating(false);
    }
  };

  const handleRemoveMember = async () => {
    if (!user) return;
    if (!window.confirm(`Are you sure you want to remove ${user.name}? This action cannot be undone.`)) return;

    setIsUpdating(true);
    try {
      const { error } = await supabase
        .from('users')
        .delete()
        .eq('id', user.id);

      if (error) throw error;
      alert('Member removed successfully!');
      navigate('/members');
    } catch (e) {
      console.error('Error removing member:', e);
      alert('Failed to remove member');
      setIsUpdating(false);
    }
  };

  const getRoleLabel = (role: string) => {
    switch (role) {
      case 'chairman': return 'Chairman';
      case 'vice_chairman': return 'Vice Chair';
      case 'core_execcom': return 'Core Execcom';
      case 'forum_execcom':
      case 'execcom': return 'Execcom';
      case 'member': return 'Member';
      default: return role;
    }
  };

  if (!currentUser || !permissions || isLoading) {
    return <div className="members-loading">Loading profile details...</div>;
  }

  if (!user) return null;

  return (
    <div className="member-detail-container">
      <header className="page-header">
        <button onClick={() => navigate('/members')} className="back-button">
          <ArrowLeft size={20} />
        </button>
        <h2 className="page-title">{user.name}</h2>
        <div style={{ width: '20px' }}></div>
      </header>

      {/* Main Profile glass card */}
      <GlassCard className="profile-header-card" padding="24px">
        <div className="avatar-circle-large">
          {user.name.length > 0 ? user.name[0].toUpperCase() : '?'}
        </div>
        <h3 className="profile-card-name">{user.name}</h3>
        {user.post && <span className="profile-card-post">{user.post}</span>}
        <span className="profile-card-role">{getRoleLabel(user.role)}</span>
        <span className="profile-card-email">{user.email}</span>
      </GlassCard>

      {/* Member Details */}
      <section className="details-section-block">
        <h3 className="section-title">MEMBER DETAILS</h3>
        <GlassCard className="details-fields-card" padding="16px">
          <div className="detail-data-row">
            <Tag size={16} className="detail-icon" />
            <span className="detail-label">Roll Number</span>
            <span className="detail-value">{user.roll_number || 'Not set'}</span>
          </div>
          <div className="detail-data-row">
            <GraduationCap size={16} className="detail-icon" />
            <span className="detail-label">Branch</span>
            <span className="detail-value">{user.branch || 'Not set'}</span>
          </div>
          <div className="detail-data-row">
            <Phone size={16} className="detail-icon" />
            <span className="detail-label">Phone</span>
            <span className="detail-value">{user.phone || 'Not set'}</span>
          </div>
          <div className="detail-data-row">
            <Calendar size={16} className="detail-icon" />
            <span className="detail-label">Joined</span>
            <span className="detail-value">
              {user.membership_date ? new Date(user.membership_date).toLocaleDateString() : 'Not set'}
            </span>
          </div>
          <div className="detail-data-row">
            <Calendar size={16} className="detail-icon" style={{ color: 'var(--accent-red)' }} />
            <span className="detail-label">Expires</span>
            <span className="detail-value">
              {user.expiry_date ? new Date(user.expiry_date).toLocaleDateString() : 'Not set'}
            </span>
          </div>
        </GlassCard>
      </section>

      {/* Team Memberships */}
      <section className="details-section-block">
        <h3 className="section-title">TEAM MEMBERSHIPS</h3>
        <div className="memberships-list">
          {user.forum && (
            <GlassCard className="membership-row-card" padding="12px 16px">
              <FolderOpen size={18} style={{ marginRight: '12px', color: 'rgb(22, 192, 122)' }} />
              <span className="membership-name">Primary: {user.forum}</span>
              <span className="membership-badge">Primary</span>
            </GlassCard>
          )}

          {memberships.map((m) => (
            <GlassCard key={m.id} className="membership-row-card" padding="12px 16px">
              <FolderOpen size={18} style={{ marginRight: '12px' }} />
              <span className="membership-name">{m.folders?.name || `Team #${m.folder_id}`}</span>
              <span className="membership-badge">{m.folder_role.toUpperCase()}</span>
            </GlassCard>
          ))}

          {memberships.length === 0 && !user.forum && (
            <div className="memberships-empty-msg">No team memberships.</div>
          )}
        </div>
      </section>

      {/* Actions (Chairman / Vice Chairman / Core Lead guards) */}
      {permissions.canEditMembers && (
        <section className="details-section-block" style={{ marginBottom: '40px' }}>
          <h3 className="section-title">ACTIONS</h3>
          <div className="actions-button-wrap">
            <button onClick={handleOpenForumModal} className="action-pill-btn flex-center">
              <Plus size={16} style={{ marginRight: '4px' }} /> Add to Team
            </button>
            {permissions.canAssignRoles && (
              <button onClick={() => setShowRoleModal(true)} className="action-pill-btn flex-center">
                Change Role
              </button>
            )}
            {permissions.canRemoveMembers && (
              <button 
                onClick={handleRemoveMember} 
                className="action-pill-btn flex-center destructive"
              >
                <Trash size={16} style={{ marginRight: '4px' }} /> Remove Member
              </button>
            )}
          </div>
        </section>
      )}

      {/* Role Picker Modal */}
      <AnimatePresence>
        {showRoleModal && (
          <motion.div 
            className="modal-overlay"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            transition={{ duration: 0.2 }}
          >
            <motion.div
              initial={{ scale: 0.9, opacity: 0, y: 20 }}
              animate={{ scale: 1, opacity: 1, y: 0 }}
              exit={{ scale: 0.9, opacity: 0, y: 20 }}
              transition={{ type: 'spring', stiffness: 400, damping: 28 }}
              style={{ width: '100%', maxWidth: '360px' }}
            >
              <GlassCard className="modal-card" padding="24px">
                <h3 className="modal-title">Change User Role</h3>
                <select
                  value={selectedRole}
                  onChange={(e) => setSelectedRole(e.target.value)}
                  className="modal-select-field"
                >
                  {Object.keys(AppRoleLabels).map((levelStr) => {
                    const level = parseInt(levelStr);
                    // Exclude restricted as per Flutter code: values.where(r != AppRole.restricted)
                    if (level === AppRole.restricted) return null;
                    const dbStr = level === AppRole.chairman ? 'chairman' :
                                  level === AppRole.viceChairman ? 'vice_chairman' :
                                  level === AppRole.coreExeccom ? 'core_execcom' :
                                  level === AppRole.forumExeccom ? 'forum_execcom' :
                                  level === AppRole.panel ? 'panel' : 'member';
                    return (
                      <option key={level} value={dbStr}>
                        {AppRoleLabels[level as keyof typeof AppRoleLabels]}
                      </option>
                    );
                  })}
                </select>
                
                <div className="modal-actions-row">
                  <button onClick={() => setShowRoleModal(false)} className="modal-cancel-btn" disabled={isUpdating}>
                    Cancel
                  </button>
                  <button onClick={handleUpdateRole} className="modal-submit-btn" disabled={isUpdating}>
                    {isUpdating ? 'Saving...' : 'Update'}
                  </button>
                </div>
              </GlassCard>
            </motion.div>
          </motion.div>
        )}
      </AnimatePresence>

      {/* Add To Forum Modal */}
      <AnimatePresence>
        {showForumModal && (
          <motion.div 
            className="modal-overlay"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            transition={{ duration: 0.2 }}
          >
            <motion.div
              initial={{ scale: 0.9, opacity: 0, y: 20 }}
              animate={{ scale: 1, opacity: 1, y: 0 }}
              exit={{ scale: 0.9, opacity: 0, y: 20 }}
              transition={{ type: 'spring', stiffness: 400, damping: 28 }}
              style={{ width: '100%', maxWidth: '360px' }}
            >
              <GlassCard className="modal-card" padding="24px">
                <h3 className="modal-title">Add to Team</h3>
                
                <div style={{ marginBottom: '16px' }}>
                  <label className="modal-input-label">Select Team</label>
                  <select
                    value={selectedForum}
                    onChange={(e) => setSelectedForum(parseInt(e.target.value))}
                    className="modal-select-field"
                    disabled={forums.length === 0}
                  >
                    {forums.map((f) => (
                      <option key={f.id} value={f.id}>
                        {f.name}
                      </option>
                    ))}
                  </select>
                </div>

                <div style={{ marginBottom: '24px' }}>
                  <label className="modal-input-label">Role in Team</label>
                  <select
                    value={selectedForumRole}
                    onChange={(e) => setSelectedForumRole(e.target.value)}
                    className="modal-select-field"
                  >
                    {['chair', 'vice_chair', 'head', 'secretary', 'joint_secretary', 'member'].map((r) => (
                      <option key={r} value={r}>
                        {r.replace('_', ' ').toUpperCase()}
                      </option>
                    ))}
                  </select>
                </div>

                <div className="modal-actions-row">
                  <button onClick={() => setShowForumModal(false)} className="modal-cancel-btn" disabled={isUpdating}>
                    Cancel
                  </button>
                  <button 
                    onClick={handleAddToForum} 
                    className="modal-submit-btn" 
                    disabled={isUpdating || selectedForum === ''}
                  >
                    {isUpdating ? 'Adding...' : 'Add'}
                  </button>
                </div>
              </GlassCard>
            </motion.div>
          </motion.div>
        )}
      </AnimatePresence>

      <NavBar />

      <style>{`
        .member-detail-container {
          padding: 16px 20px;
        }

        .page-header {
          display: flex;
          align-items: center;
          justify-content: space-between;
          height: 60px;
          margin-bottom: 20px;
        }

        .back-button {
          color: var(--text-primary);
        }

        .page-title {
          font-family: var(--font-space-grotesk);
          font-weight: 800;
          font-size: 20px;
          color: var(--text-primary);
        }

        .profile-header-card {
          width: 100%;
          display: flex;
          flex-direction: column;
          align-items: center;
          text-align: center;
          margin-bottom: 24px;
        }

        .avatar-circle-large {
          width: 72px;
          height: 72px;
          border-radius: 50%;
          background: rgba(22, 192, 122, 0.15);
          color: rgb(22, 192, 122);
          display: flex;
          align-items: center;
          justify-content: center;
          font-family: var(--font-space-grotesk);
          font-weight: 700;
          font-size: 28px;
          margin-bottom: 12px;
        }

        .profile-card-name {
          font-size: 20px;
          font-weight: 700;
          color: var(--text-primary);
          margin-bottom: 6px;
        }

        .profile-card-post {
          font-size: 13px;
          font-weight: 600;
          color: #ffffff;
          background: rgba(22, 192, 122, 0.15);
          border-radius: 12px;
          padding: 4px 12px;
          margin-bottom: 6px;
        }

        .profile-card-role {
          font-size: 13px;
          color: var(--text-secondary);
          margin-bottom: 4px;
        }

        .profile-card-email {
          font-size: 12px;
          color: var(--text-muted);
        }

        .details-section-block {
          display: flex;
          flex-direction: column;
          gap: 12px;
          margin-bottom: 24px;
        }

        .section-title {
          font-family: var(--font-space-grotesk);
          font-size: 12px;
          font-weight: 800;
          letter-spacing: 1.5px;
          color: var(--text-secondary);
          text-transform: uppercase;
        }

        .details-fields-card {
          width: 100%;
          display: flex;
          flex-direction: column;
          gap: 16px;
        }

        .detail-data-row {
          display: flex;
          align-items: center;
          width: 100%;
        }

        .detail-icon {
          color: var(--text-muted);
          margin-right: 12px;
          flex-shrink: 0;
        }

        .detail-label {
          font-size: 13px;
          color: var(--text-secondary);
          width: 110px;
        }

        .detail-value {
          font-size: 14px;
          font-weight: 600;
          color: var(--text-primary);
          flex-grow: 1;
        }

        .memberships-list {
          display: flex;
          flex-direction: column;
          gap: 8px;
        }

        .membership-row-card {
          display: flex;
          align-items: center;
          width: 100%;
        }

        .membership-name {
          flex-grow: 1;
          font-size: 14px;
          font-weight: 600;
          color: var(--text-primary);
        }

        .membership-badge {
          font-family: var(--font-space-grotesk);
          font-size: 10px;
          font-weight: 700;
          color: rgb(22, 192, 122);
          background: rgba(22, 192, 122, 0.12);
          border-radius: 8px;
          padding: 4px 8px;
          text-transform: uppercase;
        }

        .memberships-empty-msg {
          font-size: 13px;
          color: var(--text-muted);
          text-align: center;
          padding: 12px;
        }

        .actions-button-wrap {
          display: flex;
          flex-wrap: wrap;
          gap: 8px;
        }

        .action-pill-btn {
          padding: 10px 14px;
          border-radius: 12px;
          font-size: 12px;
          font-weight: 600;
          border: 1px solid rgba(22, 192, 122, 0.3);
          color: rgb(22, 192, 122);
          background: rgba(22, 192, 122, 0.08);
          transition: all 0.2s ease;
        }

        .action-pill-btn:hover {
          background: rgba(22, 192, 122, 0.18);
        }

        .action-pill-btn.destructive {
          border-color: rgba(239, 68, 68, 0.3);
          color: rgb(239, 68, 68);
          background: rgba(239, 68, 68, 0.08);
        }

        .action-pill-btn.destructive:hover {
          background: rgba(239, 68, 68, 0.18);
        }

        /* Modal styling */
        .modal-overlay {
          position: fixed;
          top: 0;
          left: 0;
          right: 0;
          bottom: 0;
          background: rgba(0, 0, 0, 0.5);
          backdrop-filter: blur(5px);
          display: flex;
          align-items: center;
          justify-content: center;
          z-index: 1001;
          padding: 20px;
        }

        .modal-card {
          width: 100%;
          max-width: 360px;
          background: var(--bg-secondary);
        }

        .modal-title {
          font-size: 18px;
          color: var(--text-primary);
          margin-bottom: 16px;
        }

        .modal-input-label {
          display: block;
          font-size: 12px;
          font-weight: 600;
          color: var(--text-secondary);
          margin-bottom: 6px;
        }

        .modal-select-field {
          width: 100%;
          padding: 12px;
          background: rgba(255, 255, 255, 0.05);
          border: 1px solid var(--border-light);
          border-radius: 12px;
          color: var(--text-primary);
          outline: none;
        }

        .modal-actions-row {
          display: flex;
          justify-content: flex-end;
          gap: 12px;
          margin-top: 24px;
        }

        .modal-cancel-btn {
          padding: 10px 16px;
          font-size: 14px;
          font-weight: 600;
          color: var(--text-secondary);
        }

        .modal-submit-btn {
          padding: 10px 16px;
          background: linear-gradient(135deg, rgb(15, 117, 73) 0%, rgb(22, 192, 122) 100%);
          color: #ffffff;
          border-radius: 10px;
          font-size: 14px;
          font-weight: 700;
        }
      `}</style>
    </div>
  );
};
