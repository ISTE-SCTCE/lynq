import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { ArrowLeft, UserPlus, Search, UserMinus, ShieldAlert } from 'lucide-react';
import { useAuth } from '../../core/auth-provider';
import { supabase } from '../../core/supabase-client';
import { AppRole, AppRoleLabels } from '../../core/constants';
import { UserModel } from '../../models/types';
import { GlassCard } from '../../shared/components/GlassCard';
import { NavBar } from '../../shared/components/NavBar';

export const MemberListScreen: React.FC = () => {
  const navigate = useNavigate();
  const { permissions, currentUser } = useAuth();
  const [allUsers, setAllUsers] = useState<UserModel[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [filter, setFilter] = useState('all');
  const [searchQuery, setSearchQuery] = useState('');

  const loadUsers = async () => {
    setIsLoading(true);
    try {
      const { data, error } = await supabase
        .from('profiles')
        .select('*')
        .order('name');

      if (error) throw error;
      setAllUsers((data || []) as UserModel[]);
    } catch (e) {
      console.error('Error fetching members list:', e);
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    loadUsers();
  }, []);

  const getFilteredUsers = () => {
    let list = allUsers;
    const now = new Date();

    if (filter === 'expired') {
      list = list.filter((u) => {
        if (u.role.includes('expired')) return true;
        if (u.expiry_date) {
          const exp = new Date(u.expiry_date);
          return exp < now;
        }
        return false;
      });
    } else if (filter !== 'all') {
      list = list.filter((u) => u.role === filter);
    }

    if (searchQuery.trim().length > 0) {
      const query = searchQuery.toLowerCase();
      list = list.filter((u) => 
        u.name.toLowerCase().includes(query) ||
        u.email.toLowerCase().includes(query) ||
        (u.post || '').toLowerCase().includes(query) ||
        (u.roll_number || '').toLowerCase().includes(query) ||
        (u.branch || '').toLowerCase().includes(query)
      );
    }

    return list;
  };

  const getRoleColor = (role: string) => {
    switch (role) {
      case 'chairman':
        return '#fbbf24'; // Amber
      case 'vice_chairman':
        return '#f97316'; // Orange
      case 'core_execcom':
        return '#16c07a'; // Emerald
      case 'forum_execcom':
      case 'execcom':
        return '#0d9488'; // Teal
      case 'member':
        return '#9ca3af'; // Grey
      default:
        return '#9ca3af';
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

  if (!currentUser || !permissions) return null;

  const filtered = getFilteredUsers();
  const canAdd = permissions.canAddMembers;

  const chips = [
    { label: 'All', value: 'all' },
    { label: 'Chairman', value: 'chairman' },
    { label: 'Vice Chair', value: 'vice_chairman' },
    { label: 'Core Execcom', value: 'core_execcom' },
    { label: 'Execcom', value: 'execcom' },
    { label: 'Member', value: 'member' },
    { label: 'Expired', value: 'expired' },
  ];

  return (
    <div className="member-list-container">
      <header className="page-header">
        <button onClick={() => navigate('/home')} className="back-button">
          <ArrowLeft size={20} />
        </button>
        <h2 className="page-title">Members</h2>
        {canAdd ? (
          <button onClick={() => navigate('/members-enroll')} className="add-member-pill-btn">
            <UserPlus size={20} />
          </button>
        ) : (
          <div style={{ width: '20px' }}></div>
        )}
      </header>

      {/* Search Input Box */}
      <div className="search-bar-wrapper">
        <Search size={18} className="search-bar-icon" />
        <input 
          type="text" 
          placeholder="Search by name, email, or post..."
          value={searchQuery}
          onChange={(e) => setSearchQuery(e.target.value)}
          className="search-bar-input"
        />
      </div>

      {/* Horizontally scrollable chips row */}
      <div className="filters-row-scroll">
        {chips.map((c) => {
          const isActive = filter === c.value;
          return (
            <button
              key={c.value}
              onClick={() => setFilter(c.value)}
              className={`filter-chip ${isActive ? 'active' : ''}`}
            >
              {c.label}
            </button>
          );
        })}
      </div>

      {/* Members Listing Area */}
      {isLoading ? (
        <div className="members-loading">Loading members directory...</div>
      ) : filtered.length === 0 ? (
        <div className="members-empty flex-center" style={{ flexDirection: 'column' }}>
          <UserMinus size={48} style={{ color: 'var(--text-muted)', marginBottom: '16px' }} />
          <span>No members found matching your filters.</span>
        </div>
      ) : (
        <div className="members-list-flow" style={{ marginBottom: '40px' }}>
          {filtered.map((user) => {
            const roleColor = getRoleColor(user.role);
            const isExpired = user.expiry_date && new Date(user.expiry_date) < new Date();
            return (
              <div 
                key={user.id} 
                className="member-row-card-interactive"
                onClick={() => navigate(`/members/${user.id}`)}
              >
                <GlassCard className="member-card-wrapper" padding="12px 16px">
                  <div className="card-inner-row">
                    <div 
                      className="avatar-circle"
                      style={{ backgroundColor: `${roleColor}1a`, color: roleColor }}
                    >
                      {user.name.length > 0 ? user.name[0].toUpperCase() : '?'}
                    </div>

                    <div className="member-meta-block">
                      <span className="member-name-text">{user.name}</span>
                      <span className="member-post-text">
                        {user.post || getRoleLabel(user.role)}
                      </span>
                      {user.membership_date && (
                        <span className="member-date-span">
                          {new Date(user.membership_date).getFullYear()} - {user.expiry_date ? new Date(user.expiry_date).getFullYear() : 'Present'}
                        </span>
                      )}
                    </div>

                    <div className="member-badge-block">
                      <span 
                        className="role-badge"
                        style={{ backgroundColor: `${roleColor}16`, color: roleColor }}
                      >
                        {getRoleLabel(user.role)}
                      </span>
                      {isExpired && (
                        <span className="expired-badge">Expired</span>
                      )}
                    </div>
                  </div>
                </GlassCard>
              </div>
            );
          })}
        </div>
      )}

      <NavBar />

      <style>{`
        .member-list-container {
          padding: 16px 20px;
        }

        @media (min-width: 768px) {
          .member-list-container {
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

        .back-button, .add-member-pill-btn {
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

        .search-bar-wrapper {
          position: relative;
          display: flex;
          align-items: center;
          width: 100%;
          margin-bottom: 16px;
        }

        .search-bar-icon {
          position: absolute;
          left: 14px;
          color: var(--text-muted);
          pointer-events: none;
        }

        .search-bar-input {
          width: 100%;
          padding: 12px 14px 12px 42px;
          background: rgba(255, 255, 255, 0.03);
          border: 1px solid var(--border-light);
          border-radius: 12px;
          color: var(--text-primary);
          font-size: 14px;
          outline: none;
        }

        .search-bar-input:focus {
          border-color: rgb(22, 192, 122);
          box-shadow: 0 0 8px rgba(22, 192, 122, 0.15);
        }

        .filters-row-scroll {
          display: flex;
          gap: 8px;
          overflow-x: auto;
          padding-bottom: 12px;
          margin-bottom: 12px;
        }

        .filter-chip {
          flex-shrink: 0;
          padding: 6px 12px;
          border-radius: 20px;
          background: rgba(255, 255, 255, 0.03);
          border: 1px solid var(--border-light);
          color: var(--text-secondary);
          font-size: 12px;
          font-weight: 500;
          transition: all 0.2s ease;
        }

        .filter-chip.active {
          background: rgba(22, 192, 122, 0.15);
          border-color: rgba(22, 192, 122, 0.3);
          color: rgb(22, 192, 122);
          font-weight: 700;
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

        .member-date-span {
          font-size: 10px;
          color: var(--text-muted);
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

        .expired-badge {
          font-family: var(--font-space-grotesk);
          font-size: 9px;
          font-weight: 700;
          background: rgba(239, 68, 68, 0.12);
          color: rgb(239, 68, 68);
          border-radius: 4px;
          padding: 2px 6px;
          text-transform: uppercase;
        }
      `}</style>
    </div>
  );
};
