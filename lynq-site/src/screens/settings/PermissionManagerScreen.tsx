import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { ArrowLeft, Users, Shield, Folder, Search, Check, AlertCircle, Plus, Trash2, X } from 'lucide-react';
import { useAuth } from '../../core/auth-provider';
import { supabase } from '../../core/supabase-client';
import { GlassCard } from '../../shared/components/GlassCard';
import { PrimaryButton } from '../../shared/components/PrimaryButton';
import { FolderFeature, AppRole } from '../../core/constants';
import { NavBar } from '../../shared/components/NavBar';

export const PermissionManagerScreen: React.FC = () => {
  const navigate = useNavigate();
  const { currentUser, permissions } = useAuth();

  const [activeTab, setActiveTab] = useState<'members' | 'forums' | 'core'>('members');
  const [isLoading, setIsLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');

  // Data states
  const [users, setUsers] = useState<any[]>([]);
  const [folders, setFolders] = useState<any[]>([]);
  const [allPermissions, setAllPermissions] = useState<any[]>([]);
  const [authorizedCoreMembers, setAuthorizedCoreMembers] = useState<any[]>([]);

  // Add Core Member modal
  const [showAddMemberModal, setShowAddMemberModal] = useState(false);
  const [addSearchQuery, setAddSearchQuery] = useState('');

  const fetchAllData = async () => {
    setIsLoading(true);
    try {
      const [
        { data: usersData, error: usersError },
        { data: foldersData, error: foldersError },
        { data: permsData, error: permsError },
        { data: membersData, error: membersError }
      ] = await Promise.all([
        supabase.from('users').select().order('name'),
        supabase.from('folders').select().order('name'),
        supabase.from('folder_permissions').select('id, folder_id:execom_id, feature, allowed'),
        supabase.from('folder_members').select('id, folder_id:execom_id, folder_role:execom_role, user_id, joined_at, users!folder_members_user_id_fkey(*)').eq('execom_id', 0)
      ]);

      if (usersError) throw usersError;
      if (foldersError) throw foldersError;
      if (permsError) throw permsError;
      if (membersError) throw membersError;

      setUsers(usersData || []);
      setFolders(foldersData || []);
      setAllPermissions(permsData || []);
      
      const coreMembers = (membersData || [])
        .filter((m: any) => m.users)
        .map((m: any) => m.users);
      setAuthorizedCoreMembers(coreMembers);
    } catch (e: any) {
      console.error('Error fetching permission manager data:', e);
      alert('Failed to load permission details: ' + e.message);
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    fetchAllData();
  }, []);

  if (!currentUser || !permissions) return null;

  const isChairman = currentUser.role === 'chairman';

  if (!isChairman) {
    return (
      <div className="access-denied flex-center" style={{ height: '100vh', flexDirection: 'column', padding: '24px', textAlign: 'center' }}>
        <AlertCircle size={64} style={{ color: 'var(--accent-red)', marginBottom: '16px' }} />
        <h2 style={{ fontFamily: 'var(--font-space-grotesk)', fontWeight: '800' }}>Restricted Access</h2>
        <p style={{ color: 'var(--text-muted)', fontSize: '14px', maxWidth: '350px', margin: '8px 0 24px 0' }}>
          Only the Chairman holds high-level credentials to modify administrative permission tables.
        </p>
        <button onClick={() => navigate(-1)} className="back-btn-secondary">Go Back</button>
      </div>
    );
  }

  const handleUpdateUserRole = async (userId: string, newRole: string) => {
    try {
      const { error } = await supabase
        .from('users')
        .update({ role: newRole })
        .eq('id', userId);

      if (error) throw error;
      fetchAllData();
    } catch (e: any) {
      alert('Failed to update role: ' + e.message);
    }
  };

  const handleTogglePermission = async (folderId: number, feature: string, isCurrentlyAllowed: boolean) => {
    try {
      const existing = allPermissions.find(p => p.folder_id === folderId && p.feature === feature);
      
      if (existing) {
        const { error } = await supabase
          .from('folder_permissions')
          .update({ allowed: !isCurrentlyAllowed })
          .eq('id', existing.id);
        if (error) throw error;
      } else {
        const { error } = await supabase
          .from('folder_permissions')
          .insert({
            execom_id: folderId,
            feature: feature,
            allowed: !isCurrentlyAllowed
          });
        if (error) throw error;
      }

      fetchAllData();
    } catch (e: any) {
      alert('Failed to modify feature permission: ' + e.message);
    }
  };

  const handleAddCoreMember = async (userId: string) => {
    try {
      const { error } = await supabase.from('folder_members').insert({
        execom_id: 0,
        user_id: userId,
        execom_role: 'viewer'
      });

      if (error) throw error;
      setShowAddMemberModal(false);
      fetchAllData();
    } catch (e: any) {
      alert('Failed to add core authorization: ' + e.message);
    }
  };

  const handleRemoveCoreMember = async (userId: string) => {
    if (!window.confirm('Remove global authorization for this member?')) return;
    try {
      const { error } = await supabase
        .from('folder_members')
        .delete()
        .eq('execom_id', 0)
        .eq('user_id', userId);

      if (error) throw error;
      fetchAllData();
    } catch (e: any) {
      alert('Failed to remove core authorization: ' + e.message);
    }
  };

  const filteredUsers = searchQuery.trim() === ''
    ? users
    : users.filter(u => u.name?.toLowerCase().includes(searchQuery.toLowerCase()));

  const membersToAdd = addSearchQuery.trim() === ''
    ? users.filter(u => !authorizedCoreMembers.some(m => m.id === u.id))
    : users
        .filter(u => !authorizedCoreMembers.some(m => m.id === u.id))
        .filter(u => u.name?.toLowerCase().includes(addSearchQuery.toLowerCase()));

  return (
    <div className="perm-manager-container" style={{ paddingBottom: '80px' }}>
      <header className="page-header">
        <button onClick={() => navigate('/settings')} className="back-button">
          <ArrowLeft size={20} />
        </button>
        <h2 className="page-title">Permissions</h2>
        <div style={{ width: '20px' }}></div>
      </header>

      {/* Selector Tabs */}
      <div className="perm-tabs flex-center">
        <button 
          onClick={() => setActiveTab('members')}
          className={`perm-tab-btn flex-center ${activeTab === 'members' ? 'active' : ''}`}
        >
          <Users size={15} style={{ marginRight: '6px' }} />
          Members
        </button>
        <button 
          onClick={() => setActiveTab('forums')}
          className={`perm-tab-btn flex-center ${activeTab === 'forums' ? 'active' : ''}`}
        >
          <Folder size={15} style={{ marginRight: '6px' }} />
          Teams
        </button>
        <button 
          onClick={() => setActiveTab('core')}
          className={`perm-tab-btn flex-center ${activeTab === 'core' ? 'active' : ''}`}
        >
          <Shield size={15} style={{ marginRight: '6px' }} />
          Core
        </button>
      </div>

      {isLoading ? (
        <div className="perm-loading flex-center" style={{ height: '300px' }}>
          <div className="spinner"></div>
        </div>
      ) : activeTab === 'members' ? (
        // Tab 1: Members role assignment
        <div className="members-tab-flow">
          <div className="search-bar-wrapper flex-center" style={{ margin: '14px 0' }}>
            <Search size={16} className="search-icon" style={{ color: 'var(--text-muted)', marginRight: '10px' }} />
            <input 
              type="text" 
              placeholder="Search members..." 
              className="chat-search-input"
              value={searchQuery}
              onChange={e => setSearchQuery(e.target.value)}
            />
          </div>

          <div className="members-list">
            {filteredUsers.map((userObj: any) => (
              <GlassCard key={userObj.id} className="member-perm-card" padding="14px">
                <div className="flex-row-between">
                  <div className="member-details flex-center" style={{ gap: '12px', justifyContent: 'flex-start' }}>
                    <div className="avatar-holder flex-center">
                      {userObj.name?.[0]?.toUpperCase()}
                    </div>
                    <div className="text-meta">
                      <span className="name-lbl">{userObj.name}</span>
                      <span className="email-lbl">{userObj.email}</span>
                    </div>
                  </div>
                  
                  {/* Role drop selector */}
                  <select 
                    className="role-selector-input"
                    value={userObj.role}
                    onChange={e => handleUpdateUserRole(userObj.id, e.target.value)}
                  >
                    <option value="chairman">Chairman</option>
                    <option value="vice_chairman">Vice Chairman</option>
                    <option value="core_execcom">Core Execon</option>
                    <option value="execcom">Forum-Execom</option>
                    <option value="member">General Member</option>
                  </select>
                </div>
              </GlassCard>
            ))}
          </div>
        </div>
      ) : activeTab === 'forums' ? (
        // Tab 2: Team Permission configurations
        <div className="forums-tab-flow" style={{ marginTop: '16px' }}>
          {folders.map((forum: any) => (
            <GlassCard key={forum.id} className="forum-perm-card" padding="16px" style={{ marginBottom: '14px' }}>
              <h3 className="forum-title-lbl">{forum.name}</h3>
              <span className="forum-subtitle-lbl">Team Scoped Visibility Flags</span>
              
              <div className="divider-line"></div>

              <div className="toggles-list">
                {[
                  { feature: FolderFeature.viewBudget, label: 'Show Budget Bar' },
                  { feature: FolderFeature.requestBudget, label: 'Allow Budget Requests' },
                  { feature: FolderFeature.uploadReports, label: 'Allow Report Uploads' }
                ].map((featObj) => {
                  const isAllowed = allPermissions.some(p => p.folder_id === forum.id && p.feature === featObj.feature && p.allowed);
                  return (
                    <div key={featObj.feature} className="toggle-row flex-row-between">
                      <span className="toggle-label">{featObj.label}</span>
                      <label className="switch">
                        <input 
                          type="checkbox" 
                          checked={isAllowed}
                          onChange={() => handleTogglePermission(forum.id, featObj.feature, isAllowed)}
                        />
                        <span className="slider round"></span>
                      </label>
                    </div>
                  );
                })}
              </div>
            </GlassCard>
          ))}
        </div>
      ) : (
        // Tab 3: Core Settings and Global Toggles
        <div className="core-tab-flow" style={{ marginTop: '16px' }}>
          <GlassCard className="global-config-card" padding="20px">
            <h3 className="card-heading">Global Configuration</h3>
            <p className="card-desc">Control what administrative features Core members can see globally.</p>
            
            <div className="divider-line"></div>

            <div className="toggles-list">
              {[
                { feature: FolderFeature.viewTotalBudget, label: 'View Total Organization Budget' },
                { feature: FolderFeature.viewReports, label: 'View All Submitted Reports' },
                { feature: FolderFeature.manageAll, label: 'Global Management Access' }
              ].map((featObj) => {
                const isAllowed = allPermissions.some(p => p.folder_id === 0 && p.feature === featObj.feature && p.allowed);
                return (
                  <div key={featObj.feature} className="toggle-row flex-row-between">
                    <span className="toggle-label">{featObj.label}</span>
                    <label className="switch">
                      <input 
                        type="checkbox" 
                        checked={isAllowed}
                        onChange={() => handleTogglePermission(0, featObj.feature, isAllowed)}
                      />
                      <span className="slider round"></span>
                    </label>
                  </div>
                );
              })}
            </div>
          </GlassCard>

          {/* Core Authorized Members */}
          <div className="core-members-block" style={{ marginTop: '24px' }}>
            <h3 className="section-title">Authorized Core Organisers</h3>
            <p className="card-desc" style={{ marginLeft: '4px' }}>
              These members are granted the global system access options toggled above (requires Core Execcom role).
            </p>

            <div className="core-members-list" style={{ marginTop: '14px' }}>
              {authorizedCoreMembers.map((coreM: any) => (
                <GlassCard key={coreM.id} className="core-member-row" padding="12px" style={{ marginBottom: '8px' }}>
                  <div className="flex-row-between">
                    <div className="core-info flex-center" style={{ gap: '12px', justifyContent: 'flex-start' }}>
                      <div className="avatar-holder flex-center small">
                        {coreM.name?.[0]?.toUpperCase()}
                      </div>
                      <div className="text-meta">
                        <span className="core-name-lbl">{coreM.name}</span>
                        <span className="core-post-lbl">{coreM.post || 'Core Organizer'}</span>
                      </div>
                    </div>

                    <button 
                      onClick={() => handleRemoveCoreMember(coreM.id)}
                      className="remove-core-btn flex-center"
                    >
                      <Trash2 size={16} />
                    </button>
                  </div>
                </GlassCard>
              ))}
            </div>

            <button 
              onClick={() => setShowAddMemberModal(true)}
              className="add-core-trigger-btn flex-center"
              style={{ marginTop: '14px' }}
            >
              <Plus size={16} style={{ marginRight: '6px' }} />
              Add Authorized Core Member
            </button>
          </div>
        </div>
      )}

      {/* Add Member Core Modal */}
      {showAddMemberModal && (
        <div className="modal-overlay flex-center" onClick={() => setShowAddMemberModal(false)}>
          <GlassCard className="add-member-modal" padding="20px" onClick={e => e.stopPropagation()}>
            <div className="modal-header flex-center" style={{ justifyContent: 'space-between', marginBottom: '16px' }}>
              <h4 style={{ margin: 0, fontFamily: 'var(--font-space-grotesk)' }}>Authorize Core Member</h4>
              <button className="close-btn" onClick={() => setShowAddMemberModal(false)}>
                <X size={18} />
              </button>
            </div>

            <div className="search-bar-wrapper flex-center" style={{ marginBottom: '12px' }}>
              <Search size={16} className="search-icon" style={{ color: 'var(--text-muted)', marginRight: '10px' }} />
              <input 
                type="text" 
                placeholder="Search organizers..." 
                className="chat-search-input"
                value={addSearchQuery}
                onChange={e => setAddSearchQuery(e.target.value)}
              />
            </div>

            <div className="add-members-scroll-list">
              {membersToAdd.length === 0 ? (
                <div className="empty-results">No eligible members found.</div>
              ) : (
                membersToAdd.map(elM => (
                  <div 
                    key={elM.id} 
                    className="eligible-member-row flex-row-between"
                    onClick={() => handleAddCoreMember(elM.id)}
                  >
                    <div className="eligible-details">
                      <span className="eligible-name">{elM.name}</span>
                      <span className="eligible-sub">{elM.post || elM.role}</span>
                    </div>
                    <button className="add-action-btn flex-center">
                      <Plus size={14} />
                    </button>
                  </div>
                ))
              )}
            </div>
          </GlassCard>
        </div>
      )}

      <NavBar />

      <style>{`
        .perm-manager-container {
          padding: 16px 20px;
          width: 100%;
          max-width: 100%;
          margin: 0;
        }

        .page-header {
          display: flex;
          align-items: center;
          justify-content: space-between;
          height: 60px;
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

        /* Tabs styling */
        .perm-tabs {
          background: rgba(255,255,255,0.03);
          border: 1px solid var(--border-light);
          padding: 4px;
          border-radius: 12px;
          margin-top: 10px;
        }

        .perm-tab-btn {
          flex: 1;
          padding: 10px;
          border: none;
          background: transparent;
          border-radius: 8px;
          font-family: var(--font-space-grotesk);
          font-weight: 700;
          font-size: 13px;
          color: var(--text-muted);
          cursor: pointer;
          transition: all 0.2s ease;
        }

        .perm-tab-btn.active {
          background: rgba(22, 192, 122, 0.15);
          color: rgb(22, 192, 122);
        }

        /* Search input bar */
        .search-bar-wrapper {
          background: rgba(255,255,255,0.02);
          border: 1px solid var(--border-light);
          border-radius: 12px;
          padding: 10px 16px;
          width: 100%;
        }

        .chat-search-input {
          background: transparent;
          border: none;
          outline: none;
          color: var(--text-primary);
          font-family: var(--font-inter);
          font-size: 13.5px;
          width: 100%;
        }

        /* Members List Tab */
        .members-list {
          display: flex;
          flex-direction: column;
          gap: 10px;
          margin-top: 12px;
        }

        .avatar-holder {
          width: 36px;
          height: 36px;
          border-radius: 50%;
          background: rgba(22, 192, 122, 0.15);
          color: rgb(22, 192, 122);
          font-family: var(--font-space-grotesk);
          font-weight: 800;
          font-size: 14px;
          flex-shrink: 0;
        }

        .avatar-holder.small {
          width: 30px;
          height: 30px;
          font-size: 12px;
        }

        .text-meta {
          display: flex;
          flex-direction: column;
          gap: 2px;
          text-align: left;
        }

        .name-lbl {
          font-family: var(--font-space-grotesk);
          font-weight: 700;
          font-size: 14px;
          color: var(--text-primary);
        }

        .email-lbl {
          font-size: 11px;
          color: var(--text-muted);
        }

        .role-selector-input {
          background: rgba(255,255,255,0.02);
          border: 1px solid var(--border-light);
          border-radius: 8px;
          padding: 6px 10px;
          font-family: var(--font-inter);
          font-size: 11.5px;
          color: var(--text-primary);
          outline: none;
          width: 130px;
        }

        .role-selector-input option {
          background: #111;
          color: #fff;
        }

        /* Forums list tab */
        .forum-title-lbl {
          font-family: var(--font-space-grotesk);
          font-weight: 800;
          font-size: 16px;
          color: var(--text-primary);
          margin: 0 0 2px 0;
        }

        .forum-subtitle-lbl {
          font-size: 11px;
          color: var(--text-muted);
        }

        .divider-line {
          height: 1px;
          background: var(--border-light);
          margin: 12px 0;
          width: 100%;
        }

        .toggles-list {
          display: flex;
          flex-direction: column;
          gap: 12px;
        }

        .toggle-row {
          width: 100%;
        }

        .toggle-label {
          font-family: var(--font-inter);
          font-size: 13px;
          color: var(--text-secondary);
        }

        /* Toggles layout switch styling */
        .switch {
          position: relative;
          display: inline-block;
          width: 38px;
          height: 20px;
        }

        .switch input {
          opacity: 0;
          width: 0;
          height: 0;
        }

        .slider {
          position: absolute;
          cursor: pointer;
          top: 0;
          left: 0;
          right: 0;
          bottom: 0;
          background-color: rgba(255,255,255,0.08);
          transition: .3s;
          border: 1px solid var(--border-light);
        }

        .slider:before {
          position: absolute;
          content: "";
          height: 12px;
          width: 12px;
          left: 3px;
          bottom: 3px;
          background-color: var(--text-muted);
          transition: .3s;
        }

        input:checked + .slider {
          background-color: rgba(22, 192, 122, 0.2);
          border-color: rgb(22, 192, 122);
        }

        input:checked + .slider:before {
          transform: translateX(18px);
          background-color: rgb(22, 192, 122);
        }

        .slider.round {
          border-radius: 20px;
        }

        .slider.round:before {
          border-radius: 50%;
        }

        /* Core Settings Tab */
        .card-heading {
          font-family: var(--font-space-grotesk);
          font-weight: 800;
          font-size: 16px;
          color: var(--text-primary);
          margin: 0 0 4px 0;
        }

        .card-desc {
          font-size: 12px;
          color: var(--text-muted);
          margin: 0;
          line-height: 1.4;
          text-align: left;
        }

        .section-title {
          font-family: var(--font-space-grotesk);
          font-weight: 800;
          font-size: 16px;
          color: var(--text-primary);
          margin: 0 0 4px 0;
        }

        .core-members-list {
          display: flex;
          flex-direction: column;
          gap: 6px;
        }

        .core-name-lbl {
          font-family: var(--font-space-grotesk);
          font-weight: 700;
          font-size: 13.5px;
          color: var(--text-primary);
        }

        .core-post-lbl {
          font-size: 11px;
          color: var(--text-muted);
        }

        .remove-core-btn {
          color: #ef4444;
          cursor: pointer;
        }

        .add-core-trigger-btn {
          width: 100%;
          padding: 12px;
          background: transparent;
          border: 1px dashed var(--border-light);
          border-radius: 12px;
          color: rgb(22, 192, 122);
          font-family: var(--font-space-grotesk);
          font-weight: 700;
          font-size: 13px;
          cursor: pointer;
        }

        /* Modals and searching */
        .modal-overlay {
          position: fixed;
          top: 0;
          left: 0;
          right: 0;
          bottom: 0;
          background: rgba(0,0,0,0.6);
          backdrop-filter: blur(5px);
          z-index: 1000;
        }

        .add-member-modal {
          width: 90%;
          max-width: 400px;
        }

        .add-members-scroll-list {
          max-height: 250px;
          overflow-y: auto;
          display: flex;
          flex-direction: column;
          gap: 8px;
          padding-right: 4px;
        }

        .add-members-scroll-list::-webkit-scrollbar {
          width: 4px;
        }
        .add-members-scroll-list::-webkit-scrollbar-thumb {
          background: var(--border-light);
          border-radius: 2px;
        }

        .eligible-member-row {
          padding: 10px 12px;
          background: rgba(255,255,255,0.01);
          border: 1px solid var(--border-light);
          border-radius: 8px;
          cursor: pointer;
          transition: all 0.2s ease;
        }

        .eligible-member-row:hover {
          background: rgba(255,255,255,0.04);
        }

        .eligible-details {
          display: flex;
          flex-direction: column;
          gap: 2px;
          text-align: left;
        }

        .eligible-name {
          font-family: var(--font-space-grotesk);
          font-weight: 700;
          font-size: 13px;
          color: var(--text-primary);
        }

        .eligible-sub {
          font-size: 11px;
          color: var(--text-muted);
        }

        .add-action-btn {
          width: 24px;
          height: 24px;
          border-radius: 6px;
          background: rgba(22, 192, 122, 0.15);
          color: rgb(22, 192, 122);
        }

        .empty-results {
          text-align: center;
          padding: 30px;
          color: var(--text-muted);
          font-size: 13px;
        }

        .close-btn {
          color: var(--text-muted);
        }

        .back-btn-secondary {
          background: rgba(255,255,255,0.04);
          border: 1px solid var(--border-light);
          padding: 10px 20px;
          border-radius: 10px;
          font-family: var(--font-space-grotesk);
          font-weight: 700;
          font-size: 13px;
          color: var(--text-primary);
          cursor: pointer;
        }
      `}</style>
    </div>
  );
};
