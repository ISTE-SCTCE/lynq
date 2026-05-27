import React from 'react';
import { useNavigate } from 'react-router-dom';
import { Users, Folder, FileText, Wallet, Shield, LogOut, ChevronRight } from 'lucide-react';
import { useAuth } from '../../core/auth-provider';
import { GlassCard } from '../../shared/components/GlassCard';
import { NavBar } from '../../shared/components/NavBar';

export const MoreScreen: React.FC = () => {
  const navigate = useNavigate();
  const { currentUser, permissions, signOut } = useAuth();

  if (!currentUser || !permissions) return null;

  const moreItems = [
    {
      icon: Users,
      title: 'Members Directory',
      subtitle: 'View and manage committee organisers',
      route: '/members',
      color: '#16c07a',
      visible: true
    },
    {
      icon: Shield,
      title: 'Execom Teams',
      subtitle: 'Manage Execom-based teams',
      route: '/execom',
      color: '#268aff',
      visible: true
    },
    {
      icon: FileText,
      title: 'Activity Reports',
      subtitle: permissions.canUploadReports ? 'Upload activity reports' : 'View uploaded reports',
      route: permissions.canUploadReports ? '/reports/upload' : '/reports',
      color: '#f59e0b',
      visible: true
    },
    {
      icon: Wallet,
      title: 'Financial Ledger & Budget',
      subtitle: 'Financial overview and proposals',
      route: '/budget',
      color: '#8b5cf6',
      visible: permissions.canAccessScopedBudget || permissions.canViewTotalBudget
    },
    {
      icon: Shield,
      title: 'Global Permission Manager',
      subtitle: 'Control administrative level flags',
      route: '/settings/permissions',
      color: '#ef4444',
      visible: permissions.canManageGlobalPermissions
    }
  ];

  return (
    <div className="more-screen-container" style={{ paddingBottom: '80px' }}>
      <header className="page-header">
        <h2 className="page-title">More Control Panel</h2>
      </header>

      <div className="more-items-list" style={{ marginTop: '10px' }}>
        {moreItems
          .filter(item => item.visible)
          .map((item, idx) => {
            const IconComp = item.icon;
            return (
              <div 
                key={idx} 
                className="more-item-tile"
                onClick={() => navigate(item.route)}
              >
                <GlassCard className="tile-glass-card" padding="16px">
                  <div className="flex-row-between" style={{ justifyContent: 'flex-start' }}>
                    <div 
                      className="item-icon-holder flex-center"
                      style={{ backgroundColor: `${item.color}15`, color: item.color }}
                    >
                      <IconComp size={22} />
                    </div>
                    <div className="item-details" style={{ flex: 1, marginLeft: '16px', textAlign: 'left' }}>
                      <span className="item-title">{item.title}</span>
                      <span className="item-subtitle">{item.subtitle}</span>
                    </div>
                    <ChevronRight size={16} className="arrow-icon" style={{ color: 'var(--text-muted)' }} />
                  </div>
                </GlassCard>
              </div>
            );
          })}

        <div className="more-item-tile" onClick={signOut} style={{ marginTop: '20px' }}>
          <GlassCard className="tile-glass-card border-danger" padding="16px" style={{ border: '1px solid rgba(239, 68, 68, 0.15)' }}>
            <div className="flex-row-between" style={{ justifyContent: 'flex-start' }}>
              <div 
                className="item-icon-holder flex-center"
                style={{ backgroundColor: 'rgba(239, 68, 68, 0.15)', color: '#ef4444' }}
              >
                <LogOut size={22} />
              </div>
              <div className="item-details" style={{ flex: 1, marginLeft: '16px', textAlign: 'left' }}>
                <span className="item-title" style={{ color: '#ef4444' }}>Sign Out</span>
                <span className="item-subtitle">Log out of this executive session</span>
              </div>
              <ChevronRight size={16} className="arrow-icon" style={{ color: 'var(--text-muted)' }} />
            </div>
          </GlassCard>
        </div>
      </div>

      <NavBar />

      <style>{`
        .more-screen-container {
          padding: 16px 20px;
          max-width: 680px;
          margin: 0 auto;
        }

        .page-header {
          display: flex;
          align-items: center;
          height: 60px;
          margin-bottom: 10px;
        }

        .page-title {
          font-family: var(--font-space-grotesk);
          font-weight: 800;
          font-size: 20px;
          color: var(--text-primary);
        }

        .more-items-list {
          display: flex;
          flex-direction: column;
          gap: 12px;
        }

        .more-item-tile {
          cursor: pointer;
          transition: transform 0.2s ease;
        }

        .more-item-tile:hover {
          transform: translateY(-1.5px);
        }

        .item-icon-holder {
          width: 44px;
          height: 44px;
          border-radius: 12px;
          flex-shrink: 0;
        }

        .item-title {
          font-family: var(--font-space-grotesk);
          font-weight: 700;
          font-size: 15px;
          color: var(--text-primary);
          display: block;
        }

        .item-subtitle {
          font-size: 12px;
          color: var(--text-muted);
          margin-top: 2px;
          display: block;
        }

        .arrow-icon {
          flex-shrink: 0;
        }

        .flex-row-between {
          display: flex;
          justify-content: space-between;
          align-items: center;
        }
      `}</style>
    </div>
  );
};
