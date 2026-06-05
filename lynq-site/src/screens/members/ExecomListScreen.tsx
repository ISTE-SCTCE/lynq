import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { ArrowLeft, ShieldAlert, Users } from 'lucide-react';
import { useAuth } from '../../core/auth-provider';
import { supabase } from '../../core/supabase-client';
import { GlassCard } from '../../shared/components/GlassCard';
import { NavBar } from '../../shared/components/NavBar';

export const ExecomListScreen: React.FC = () => {
  const navigate = useNavigate();
  const { permissions, currentUser } = useAuth();
  const [teams, setTeams] = useState<{ [key: string]: any[] }>({});
  const [isLoading, setIsLoading] = useState(true);
  const [totalExecomCount, setTotalExecomCount] = useState(0);

  const loadExecomMembers = async () => {
    setIsLoading(true);
    try {
      const { data, error } = await supabase
        .from('folder_members')
        .select(`
          execom_role,
          folders!inner(name),
          users!inner(id, name, email, phone, role, post)
        `);

      if (error) throw error;

      const grouped: { [key: string]: any[] } = {};
      const uniqueUsers = new Set();

      (data || []).forEach((row: any) => {
        const folderName = row.folders?.name || 'Unknown Team';
        const user = row.users;
        if (!user) return;
        
        uniqueUsers.add(user.id);
        
        if (!grouped[folderName]) {
          grouped[folderName] = [];
        }
        
        grouped[folderName].push({
          ...user,
          execom_role: row.execom_role
        });
      });

      setTeams(grouped);
      setTotalExecomCount(uniqueUsers.size);
    } catch (e) {
      console.error('Error fetching execom members:', e);
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    loadExecomMembers();
  }, []);

  const getRoleColor = (role: string) => {
    switch (role?.toLowerCase()) {
      case 'chairman':
      case 'chair':
        return '#fbbf24'; // Amber
      case 'vice_chairman':
      case 'vice-chair':
      case 'vice chair':
        return '#f97316'; // Orange
      case 'core_execcom':
      case 'secretary':
      case 'treasurer':
      case 'sub-treasurer':
      case 'joint secretary':
        return '#16c07a'; // Emerald
      case 'forum_execcom':
      case 'execom':
      case 'technical head':
      case 'media head':
      case 'marketing head':
      case 'design head':
        return '#0d9488'; // Teal
      case 'panel':
        return '#64748b'; // BlueGrey
      case 'restricted':
        return '#a855f7'; // Purple
      default:
        return '#9ca3af'; // Grey
    }
  };

  const getRoleLabel = (role: string) => {
    switch (role?.toLowerCase()) {
      case 'chairman': return 'Chairman';
      case 'vice_chairman': return 'Vice Chair';
      case 'core_execcom': return 'Core Execcom';
      case 'forum_execcom':
      case 'execcom': return 'Execcom';
      case 'member': return 'Member';
      default: return role || 'Member';
    }
  };

  if (!currentUser || !permissions) return null;

  return (
    <div className="execom-list-container">
      <header className="page-header">
        <button onClick={() => navigate('/home')} className="back-button">
          <ArrowLeft size={20} />
        </button>
        <h2 className="page-title">Execom Teams</h2>
        <div style={{ width: '20px' }}></div>
      </header>

      {/* Main Content Area */}
      {isLoading ? (
        <div className="members-loading">Loading execom directory...</div>
      ) : Object.keys(teams).length === 0 ? (
        <div className="members-empty flex-center" style={{ flexDirection: 'column' }}>
          <Users size={48} style={{ color: 'var(--text-muted)', marginBottom: '16px' }} />
          <span>No Execom members found.</span>
        </div>
      ) : (
        <div className="teams-flow" style={{ marginBottom: '80px' }}>
          
          <div className="total-count-header">
            <span className="total-label">Total Execom Members</span>
            <span className="total-value">{totalExecomCount}</span>
          </div>

          {Object.entries(teams).map(([teamName, members]) => (
            <div key={teamName} className="team-section">
              <h3 className="team-name-title">{teamName}</h3>
              
              <div className="members-list-flow">
                {members.map((user, idx) => {
                  const role = user.role || 'member';
                  const roleColor = getRoleColor(role);
                  return (
                    <div 
                      key={`${user.id}-${idx}`} 
                      className="member-row-card-interactive"
                      onClick={() => navigate(`/members/${user.id}`)}
                    >
                      <GlassCard className="member-card-wrapper" padding="12px 16px">
                        <div className="card-inner-row">
                          <div 
                            className="avatar-circle"
                            style={{ backgroundColor: `${roleColor}1a`, color: roleColor }}
                          >
                            {user.name && user.name.length > 0 ? user.name[0].toUpperCase() : '?'}
                          </div>

                          <div className="member-meta-block">
                            <span className="member-name-text">{user.name || 'Unknown'}</span>
                            <span className="member-post-text">
                              {user.execom_role || user.post || getRoleLabel(role)}
                            </span>
                          </div>

                          <div className="member-badge-block">
                            <span 
                              className="role-badge"
                              style={{ backgroundColor: `${roleColor}16`, color: roleColor }}
                            >
                              {getRoleLabel(role)}
                            </span>
                          </div>
                        </div>
                      </GlassCard>
                    </div>
                  );
                })}
              </div>
            </div>
          ))}
        </div>
      )}

      <NavBar />

      <style>{`
        .execom-list-container {
          padding: 16px 20px;
        }

        @media (min-width: 768px) {
          .execom-list-container {
            padding: 24px 0;
          }
        }

        .page-header {
          display: flex;
          align-items: center;
          justify-content: space-between;
          height: 60px;
          margin-bottom: 16px;
        }

        .back-button {
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

        .total-count-header {
          display: flex;
          justify-content: space-between;
          align-items: center;
          margin-bottom: 24px;
          padding: 0 4px;
        }

        .total-label {
          font-size: 14px;
          font-weight: 600;
          color: var(--text-secondary);
        }

        .total-value {
          font-family: var(--font-space-grotesk);
          font-size: 20px;
          font-weight: 800;
          color: rgb(22, 192, 122);
        }

        .team-section {
          margin-bottom: 32px;
        }

        .team-name-title {
          font-family: var(--font-space-grotesk);
          font-size: 18px;
          font-weight: 700;
          color: rgb(22, 192, 122);
          margin-bottom: 16px;
          padding-left: 4px;
        }

        .members-loading, .members-empty {
          text-align: center;
          padding: 40px;
          font-size: 15px;
          color: var(--text-secondary);
        }

        .members-list-flow {
          display: grid;
          grid-template-columns: 1fr;
          gap: 12px;
        }

        @media (min-width: 768px) {
          .members-list-flow {
            grid-template-columns: repeat(2, 1fr);
            gap: 20px;
          }
        }

        @media (min-width: 1200px) {
          .members-list-flow {
            grid-template-columns: repeat(3, 1fr);
            gap: 24px;
          }
        }

        .member-row-card-interactive {
          cursor: pointer;
          transition: transform 0.2s cubic-bezier(0.4, 0, 0.2, 1);
        }

        .member-row-card-interactive:hover {
          transform: translateY(-3px);
        }

        .card-inner-row {
          display: flex;
          align-items: center;
          width: 100%;
        }

        .avatar-circle {
          width: 44px;
          height: 44px;
          border-radius: 50%;
          display: flex;
          align-items: center;
          justify-content: center;
          font-family: var(--font-space-grotesk);
          font-weight: 700;
          font-size: 16px;
          margin-right: 14px;
          flex-shrink: 0;
        }

        .member-meta-block {
          flex-grow: 1;
          display: flex;
          flex-direction: column;
        }

        .member-name-text {
          font-size: 14px;
          font-weight: 600;
          color: var(--text-primary);
        }

        .member-post-text {
          font-size: 12px;
          color: var(--text-muted);
          margin-bottom: 2px;
        }

        .member-badge-block {
          display: flex;
          flex-direction: column;
          align-items: flex-end;
          gap: 4px;
          flex-shrink: 0;
        }

        .role-badge {
          font-family: var(--font-space-grotesk);
          font-size: 10px;
          font-weight: 700;
          border-radius: 8px;
          padding: 4px 8px;
          text-transform: uppercase;
          letter-spacing: 0.5px;
        }
      `}</style>
    </div>
  );
};
