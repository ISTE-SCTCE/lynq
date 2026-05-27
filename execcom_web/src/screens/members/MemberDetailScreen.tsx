import React, { useState, useEffect } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
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
  Shield
} from 'lucide-react';
import { useAuth } from '../../core/auth-provider';
import { supabase } from '../../core/supabase-client';
import { AppRole, AppRoleLabels } from '../../core/constants';
import { UserModel, ExecomMemberModel, ExecomModel } from '../../models/types';
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
  
  const [showExecomModal, setShowExecomModal] = useState(false);
  const [execoms, setExecoms] = useState<ExecomModel[]>([]);
  const [selectedExecom, setSelectedExecom] = useState<number | ''>('');
  const [selectedExecomRole, setSelectedExecomRole] = useState('member');
  
  const [showTagModal, setShowTagModal] = useState(false);
  const [newExecomTag, setNewExecomTag] = useState('');

  const [isUpdating, setIsUpdating] = useState(false);

  const loadUserData = async () => {
    if (!id) return;
    setIsLoading(true);
    try {
      // 1. Fetch main profile
      const { data: profile, error: pError } = await supabase
        .from('users')
        .select('*')
        .eq('id', id)
        .single();
      
      if (pError) throw pError;
      setUser(profile as UserModel);
      setSelectedRole(profile.role);
      setNewExecomTag(profile.execom_tag || '');

      // 2. Fetch memberships joined with execom
      const { data: memberData, error: mError } = await supabase
        .from('execom_members')
        .select('*, execom:execom(id, name)')
        .eq('user_id', id);

      if (mError) throw mError;
      setMemberships(memberData || []);
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

  const loadExecoms = async () => {
    try {
      const { data, error } = await supabase
        .from('execom')
        .select('*')
        .order('name');

      if (error) throw error;
      
      const allExecoms = (data || []) as ExecomModel[];
      const joinedIds = new Set(memberships.map((m) => m.execom_id));
      const available = allExecoms.filter((f) => !joinedIds.has(f.id));
      
      setExecoms(available);
      if (available.length > 0) {
        setSelectedExecom(available[0].id);
      } else {
        setSelectedExecom('');
      }
    } catch (e) {
      console.error('Error loading execom list:', e);
    }
  };

  const handleOpenExecomModal = () => {
    loadExecoms();
    setShowExecomModal(true);
  };

  const handleUpdateRole = async () => {
    if (!user || !currentUser) return;
    
    // Restriction: Only Chair/Vice-Chair can promote to Execcom+
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
      const { error } = await supabase
        .from('users')
        .update({ role: selectedRole })
        .eq('id', user.id);

      if (error) throw error;
      
      setShowRoleModal(false);
      loadUserData();
      alert('Role updated successfully!');
    } catch (e) {
      console.error('Error saving role change:', e);
      alert('Failed to update role');
    } finally {
      setIsUpdating(false);
    }
  };

  const handleUpdateTag = async () => {
    if (!user) return;
    setIsUpdating(true);
    try {
      const { error } = await supabase
        .from('users')
        .update({ execom_tag: newExecomTag.trim() || null })
        .eq('id', user.id);

      if (error) throw error;
      
      setShowTagModal(false);
      loadUserData();
      alert('Execom Tag updated successfully!');
    } catch (e) {
      console.error('Error saving execom tag change:', e);
      alert('Failed to update Execom Tag');
    } finally {
      setIsUpdating(false);
    }
  };

  const handleAddToExecom = async () => {
    if (!user || selectedExecom === '') return;
    setIsUpdating(true);
    try {
      const { error } = await supabase
        .from('execom_members')
        .insert({
          execom_id: selectedExecom,
          user_id: user.id,
          execom_role: selectedExecomRole,
        });

      if (error) throw error;

      setShowExecomModal(false);
      loadUserData();
      alert('Added to Execom team successfully!');
    } catch (e) {
      console.error('Execom insertion error:', e);
      alert('Failed to add to Execom team');
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
      case 'faculty_advisor': return 'Faculty Advisor';
      case 'core_execcom': return 'Core Execcom';
      case 'forum_execcom':
      case 'execcom': return 'Execcom';
      case 'member': return 'Member';
      default: return role;
    }
  };

  const isUserExecom = user && user.role !== 'member' && user.role !== 'restricted';

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
        
        {/* Render Execom tag as requested */}
        {isUserExecom && user.execom_tag && (
          <span className="profile-card-execom-tag">
            Team: {user.execom_tag}
          </span>
        )}
        
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

      {/* Execom Memberships */}
      <section className="details-section-block">
        <h3 className="section-title">EXECOM MEMBERSHIPS</h3>
        <div className="memberships-list">
          {user.forum && (
            <GlassCard className="membership-row-card" padding="12px 16px">
              <Shield size={18} style={{ marginRight: '12px', color: 'rgb(22, 192, 122)' }} />
              <span className="membership-name">Primary: {user.forum}</span>
              <span className="membership-badge">Primary</span>
            </GlassCard>
          )}

          {memberships.map((m) => (
            <GlassCard key={m.id} className="membership-row-card" padding="12px 16px">
              <Shield size={18} style={{ marginRight: '12px' }} />
              <span className="membership-name">{m.execom?.name || `Team #${m.execom_id}`}</span>
              <span className="membership-badge">{m.execom_role.toUpperCase()}</span>
            </GlassCard>
          ))}

          {memberships.length === 0 && !user.forum && (
            <div className="memberships-empty-msg">No Execom memberships.</div>
          )}
        </div>
      </section>

      {/* Actions (Chairman / Vice Chairman / Core Lead guards) */}
      {permissions.canEditMembers && (
        <section className="details-section-block" style={{ marginBottom: '40px' }}>
          <h3 className="section-title">ACTIONS</h3>
          <div className="actions-button-wrap">
            <button onClick={handleOpenExecomModal} className="action-pill-btn flex-center">
              <Plus size={16} style={{ marginRight: '4px' }} /> Add to Team
            </button>
            {permissions.canAssignRoles && (
              <button onClick={() => setShowRoleModal(true)} className="action-pill-btn flex-center">
                Change Role
              </button>
            )}
            {isUserExecom && (
              <button onClick={() => setShowTagModal(true)} className="action-pill-btn flex-center">
                Set Execom Tag
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
      {showRoleModal && (
        <div className="modal-overlay">
          <GlassCard className="modal-card" padding="24px">
            <h3 className="modal-title">Change User Role</h3>
            <select
              value={selectedRole}
              onChange={(e) => setSelectedRole(e.target.value)}
              className="modal-select-field"
            >
              {Object.keys(AppRoleLabels).map((levelStr) => {
                const level = parseInt(levelStr);
                if (level === AppRole.restricted) return null;
                const dbStr = level === AppRole.chairman ? 'chairman' :
                              level === AppRole.viceChairman ? 'vice_chairman' :
                              level === AppRole.facultyAdvisor ? 'faculty_advisor' :
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
        </div>
      )}

      {/* Execom Tag Modal */}
      {showTagModal && (
        <div className="modal-overlay">
          <GlassCard className="modal-card" padding="24px">
            <h3 className="modal-title">Set Execom Team Tag</h3>
            <input
              type="text"
              placeholder="e.g. Technical, Marketing"
              value={newExecomTag}
              onChange={(e) => setNewExecomTag(e.target.value)}
              className="modal-select-field"
              style={{ background: 'rgba(255, 255, 255, 0.05)', color: '#fff', border: '1px solid var(--border-light)' }}
            />
            
            <div className="modal-actions-row" style={{ marginTop: '16px' }}>
              <button onClick={() => setShowTagModal(false)} className="modal-cancel-btn" disabled={isUpdating}>
                Cancel
              </button>
              <button onClick={handleUpdateTag} className="modal-submit-btn" disabled={isUpdating}>
                {isUpdating ? 'Saving...' : 'Save Tag'}
              </button>
            </div>
          </GlassCard>
        </div>
      )}

      {/* Add To Execom Modal */}
      {showExecomModal && (
        <div className="modal-overlay">
          <GlassCard className="modal-card" padding="24px">
            <h3 className="modal-title">Add to Execom Team</h3>
            
            <div style={{ marginBottom: '16px' }}>
              <label className="modal-input-label">Select Team</label>
              <select
                value={selectedExecom}
                onChange={(e) => setSelectedExecom(parseInt(e.target.value))}
                className="modal-select-field"
                disabled={execoms.length === 0}
              >
                {execoms.map((f) => (
                  <option key={f.id} value={f.id}>
                    {f.name}
                  </option>
                ))}
              </select>
            </div>

            <div style={{ marginBottom: '24px' }}>
              <label className="modal-input-label">Role in Team</label>
              <select
                value={selectedExecomRole}
                onChange={(e) => setSelectedExecomRole(e.target.value)}
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
              <button onClick={() => setShowExecomModal(false)} className="modal-cancel-btn" disabled={isUpdating}>
                Cancel
              </button>
              <button 
                onClick={handleAddToExecom} 
                className="modal-submit-btn" 
                disabled={isUpdating || selectedExecom === ''}
              >
                {isUpdating ? 'Adding...' : 'Add'}
              </button>
            </div>
          </GlassCard>
        </div>
      )}

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
          background: none;
          border: none;
          cursor: pointer;
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

        .profile-card-execom-tag {
          font-size: 12px;
          font-weight: 700;
          color: #ffffff;
          background: linear-gradient(135deg, rgb(15, 117, 73) 0%, rgb(22, 192, 122) 100%);
          border-radius: 8px;
          padding: 3px 10px;
          margin-bottom: 8px;
          text-transform: uppercase;
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
          cursor: pointer;
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
          background: none;
          border: none;
          cursor: pointer;
        }

        .modal-submit-btn {
          padding: 10px 16px;
          background: linear-gradient(135deg, rgb(15, 117, 73) 0%, rgb(22, 192, 122) 100%);
          color: #ffffff;
          border-radius: 10px;
          font-size: 14px;
          font-weight: 700;
          border: none;
          cursor: pointer;
        }
      `}</style>
    </div>
  );
};
