import React, { useState, useEffect } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { ArrowLeft, Settings, Calendar, Wallet, FileText, Users, Plus, ShieldAlert } from 'lucide-react';
import { useAuth } from '../../core/auth-provider';
import { supabase } from '../../core/supabase-client';
import { GlassCard } from '../../shared/components/GlassCard';
import { NavBar } from '../../shared/components/NavBar';

export const FolderDetailScreen: React.FC = () => {
  const { id } = useParams<{ id: string }>();
  const folderId = parseInt(id || '0');
  const navigate = useNavigate();
  const { permissions, currentUser } = useAuth();
  const [folder, setFolder] = useState<any>(null);
  const [members, setMembers] = useState<any[]>([]);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    if (!folderId || !currentUser) return;
    
    const fetchFolderDetails = async () => {
      setIsLoading(true);
      try {
        // 1. Fetch folder info
        const { data: folderData, error: fError } = await supabase
          .from('folders')
          .select('*')
          .eq('id', folderId)
          .single();

        if (fError) throw fError;
        setFolder(folderData);

        // 2. Fetch folder members joined with users
        const { data: membersData, error: mError } = await supabase
          .from('folder_members')
          .select('*, users:users(id, name, email, role, post)')
          .eq('folder_id', folderId);

        if (mError) throw mError;
        setMembers(membersData || []);
      } catch (e) {
        console.error('Error fetching details:', e);
        navigate('/folders');
      } finally {
        setIsLoading(false);
      }
    };

    fetchFolderDetails();
  }, [folderId, currentUser, navigate]);

  if (!currentUser || !permissions || isLoading) {
    return <div className="folders-loading">Loading folder details...</div>;
  }

  if (!folder) return null;

  const canManageFolderPermissions = permissions.canManageFolderPermissions;
  const canManageMembers = permissions.canManageMembersInFolder(folderId);

  return (
    <div className="folder-detail-container">
      <header className="page-header">
        <button onClick={() => navigate('/folders')} className="back-button">
          <ArrowLeft size={20} />
        </button>
        <h2 className="page-title">{folder.name}</h2>
        {canManageFolderPermissions ? (
          <button 
            onClick={() => navigate(`/folders/${folderId}/permissions`)} 
            className="config-permissions-btn"
          >
            <ShieldAlert size={20} />
          </button>
        ) : (
          <div style={{ width: '20px' }}></div>
        )}
      </header>

      {/* Scoped Actions Grid */}
      <section className="detail-actions-block">
        <h3 className="section-title">FORUM RESOURCES</h3>
        <div className="resources-grid">
          {permissions.canDoInFolder(folderId, 'view_events') && (
            <GlassCard 
              className="resource-card" 
              padding="16px" 
              onClick={() => navigate(`/events?folder=${folderId}`)}
            >
              <Calendar size={22} style={{ color: '#16c07a', marginBottom: '10px' }} />
              <span className="resource-name">Events</span>
            </GlassCard>
          )}

          {permissions.canViewBudgetInFolder(folderId) && (
            <GlassCard 
              className="resource-card" 
              padding="16px" 
              onClick={() => navigate(`/budget?folder=${folderId}`)}
            >
              <Wallet size={22} style={{ color: '#6a8b54', marginBottom: '10px' }} />
              <span className="resource-name">Budget</span>
            </GlassCard>
          )}

          {permissions.canDoInFolder(folderId, 'view_reports') && (
            <GlassCard 
              className="resource-card" 
              padding="16px" 
              onClick={() => navigate(`/reports?folder=${folderId}`)}
            >
              <FileText size={22} style={{ color: '#4a7c6e', marginBottom: '10px' }} />
              <span className="resource-name">Reports</span>
            </GlassCard>
          )}
        </div>
      </section>

      {/* Folder Members Section */}
      <section className="members-section-block" style={{ marginBottom: '40px' }}>
        <div className="section-title-row">
          <h3 className="section-title">FORUM MEMBERS ({members.length})</h3>
          {canManageMembers && (
            <button 
              onClick={() => navigate(`/members-enroll?folder=${folderId}`)} 
              className="add-member-pill flex-center"
            >
              <Plus size={14} style={{ marginRight: '4px' }} /> Add
            </button>
          )}
        </div>

        <div className="members-list">
          {members.map((member) => {
            const u = member.users;
            if (!u) return null;
            return (
              <div key={member.id} className="member-row-card">
                <div className="member-avatar">
                  {u.name[0].toUpperCase()}
                </div>
                <div className="member-info">
                  <span className="member-name">{u.name}</span>
                  <span className="member-post">{member.folder_role || u.post || 'Executive Member'}</span>
                </div>
                <span className="member-role-badge">
                  {u.role.replace('_', ' ')}
                </span>
              </div>
            );
          })}
        </div>
      </section>

      <NavBar />

      <style>{`
        .folder-detail-container {
          padding: 16px 20px;
        }

        .page-header {
          display: flex;
          align-items: center;
          justify-content: space-between;
          height: 60px;
          margin-bottom: 24px;
        }

        .back-button, .config-permissions-btn {
          color: var(--text-primary);
          display: flex;
          align-items: center;
          justify-content: center;
        }

        .page-title {
          font-family: var(--font-space-grotesk);
          font-weight: 800;
          font-size: 20px;
          color: var(--text-primary);
        }

        .detail-actions-block, .members-section-block {
          display: flex;
          flex-direction: column;
          gap: 12px;
          margin-bottom: 28px;
        }

        .section-title-row {
          display: flex;
          align-items: center;
          justify-content: space-between;
        }

        .section-title {
          font-family: var(--font-space-grotesk);
          font-size: 12px;
          font-weight: 800;
          letter-spacing: 1.5px;
          color: var(--text-secondary);
          text-transform: uppercase;
        }

        .resources-grid {
          display: grid;
          grid-template-columns: repeat(3, 1fr);
          gap: 12px;
        }

        .resource-card {
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          text-align: center;
        }

        .resource-name {
          font-family: var(--font-space-grotesk);
          font-size: 14px;
          font-weight: 700;
          color: var(--text-primary);
        }

        .add-member-pill {
          background: rgba(22, 192, 122, 0.1);
          color: rgb(22, 192, 122);
          border-radius: 20px;
          padding: 6px 12px;
          font-family: var(--font-space-grotesk);
          font-weight: 700;
          font-size: 12px;
        }

        .members-list {
          display: flex;
          flex-direction: column;
          gap: 10px;
        }

        .member-row-card {
          display: flex;
          align-items: center;
          padding: 12px 14px;
          background: rgba(255, 255, 255, 0.02);
          border: 1px solid var(--border-light);
          border-radius: 16px;
        }

        .member-avatar {
          width: 40px;
          height: 40px;
          border-radius: 50%;
          background: rgb(15, 117, 73);
          color: #ffffff;
          display: flex;
          align-items: center;
          justify-content: center;
          font-family: var(--font-space-grotesk);
          font-weight: 700;
          margin-right: 14px;
        }

        .member-info {
          flex-grow: 1;
          display: flex;
          flex-direction: column;
        }

        .member-name {
          font-size: 14px;
          font-weight: 600;
          color: var(--text-primary);
        }

        .member-post {
          font-size: 12px;
          color: var(--text-muted);
        }

        .member-role-badge {
          font-family: var(--font-space-grotesk);
          font-size: 10px;
          font-weight: 800;
          color: rgb(22, 192, 122);
          background: rgba(22, 192, 122, 0.08);
          border-radius: 8px;
          padding: 4px 8px;
          text-transform: uppercase;
          letter-spacing: 0.5px;
        }
      `}</style>
    </div>
  );
};
