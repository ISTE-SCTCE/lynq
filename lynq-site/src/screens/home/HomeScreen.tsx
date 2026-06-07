import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { 
  Bell, 
  Calendar, 
  Upload, 
  FileText, 
  Users, 
  Wallet, 
  MessageSquare, 
  FolderOpen, 
  ShieldAlert, 
  CheckSquare, 
  QrCode, 
  UserCheck, 
  ChevronRight, 
  BookOpen,
  BarChart2
} from 'lucide-react';
import { useAuth } from '../../core/auth-provider';
import { supabase } from '../../core/supabase-client';
import { GlassCard } from '../../shared/components/GlassCard';
import { NavBar } from '../../shared/components/NavBar';

export const HomeScreen: React.FC = () => {
  const navigate = useNavigate();
  const { currentUser, permissions } = useAuth();
  const [upcomingEvents, setUpcomingEvents] = useState<any[]>([]);
  const [pendingTasks, setPendingTasks] = useState<any[]>([]);
  const [isUpcomingLoading, setIsUpcomingLoading] = useState(true);
  const [activeForums, setActiveForums] = useState<any[]>([]);
  const [isForumsLoading, setIsForumsLoading] = useState(true);
  const [stats, setStats] = useState<{ members: number; execom: number; events: number; forums: number } | null>(null);

  useEffect(() => {
    if (!currentUser || !permissions) return;
    
    const fetchDashboardData = async () => {
      try {
        const today = new Date().toISOString().split('T')[0];
        
        // 1. Fetch upcoming events
        const { data: events } = await supabase
          .from('events')
          .select('id, title, date')
          .gte('date', today)
          .order('date', { ascending: true })
          .limit(3);

        setUpcomingEvents(events || []);

        // 2. Fetch pending tasks assigned to current user
        const { data: tasks } = await supabase
          .from('tasks')
          .select('id, title, deadline, status')
          .neq('status', 'completed')
          .contains('assigned_to', [currentUser.id])
          .order('deadline', { ascending: true })
          .limit(3);

        setPendingTasks(tasks || []);

        // 3. Fetch exact counts from database dynamically to align with mobile app & backend
        try {
          const [membersRes, execomRes, eventsRes, foldersRes] = await Promise.all([
            supabase.from('members').select('id', { count: 'exact', head: true }).not('iste_id', 'is', null).neq('iste_id', ''),
            supabase.from('folder_members').select('user_id'),
            supabase.from('events').select('id', { count: 'exact', head: true }),
            supabase.from('folders').select('id', { count: 'exact', head: true })
          ]);
          
          const uniqueExecomUsers = new Set((execomRes.data || []).map((m: any) => m.user_id)).size;

          setStats({
            members: membersRes.count ?? 73,
            execom: uniqueExecomUsers,
            events: eventsRes.count ?? 1,
            forums: foldersRes.count ?? 5
          });
        } catch (err) {
          console.error('Error loading dynamic dashboard stats:', err);
        }

        // 4. Fetch active folders (forums) user has access to
        try {
          let hasAccess = true;
          let folderIds: number[] = [];
          if (!permissions.isAtLeastTier2) {
            const { data: memberFolders } = await supabase
              .from('folder_members')
              .select('folder_id:execom_id')
              .eq('user_id', currentUser.id);
            
            folderIds = (memberFolders || []).map((m: any) => m.folder_id);
            if (folderIds.length === 0) {
              hasAccess = false;
            }
          }

          if (hasAccess) {
            let query = supabase.from('folders').select('*');
            if (folderIds.length > 0) {
              query = query.in('id', folderIds);
            }
            const { data: forumsData } = await query.order('name').limit(4);
            setActiveForums(forumsData || []);
          } else {
            setActiveForums([]);
          }
        } catch (err) {
          console.error('Error fetching dashboard forums:', err);
        } finally {
          setIsForumsLoading(false);
        }

      } catch (e) {
        console.error('Error fetching dashboard feeds:', e);
      } finally {
        setIsUpcomingLoading(false);
      }
    };

    fetchDashboardData();
  // Use currentUser?.id (primitive) as dep — permissions is a new object ref on every
  // background auth refresh, which would cause fetchDashboardData to loop endlessly.
  }, [currentUser?.id]); // eslint-disable-line react-hooks/exhaustive-deps

  if (!currentUser || !permissions) return null;

  const firstName = currentUser.name.split(' ')[0] || 'Member';

  // Build quick actions list based on permissions
  const quickActions: Array<{
    icon: React.ComponentType<any>;
    label: string;
    route: string;
    color: string;
  }> = [];

  quickActions.push({ icon: Calendar, label: 'Events', route: '/events', color: '#16c07a' });

  if (permissions.canUploadReports) {
    quickActions.push({ icon: Upload, label: 'Upload', route: '/reports/upload', color: '#5277b8' });
  }

  quickActions.push({ icon: FileText, label: 'Reports', route: '/reports', color: '#4a7c6e' });
  quickActions.push({ icon: Users, label: 'Members', route: '/members', color: '#0f7549' });

  if (permissions.canRequestBudget || permissions.canManageBudget) {
    quickActions.push({ icon: Wallet, label: 'Budget', route: '/budget', color: '#6a8b54' });
  }

  if (permissions.canAccessChat) {
    quickActions.push({ icon: MessageSquare, label: 'Chat', route: '/chat', color: '#2e8a77' });
  }

  quickActions.push({ icon: FolderOpen, label: 'Teams', route: '/folders', color: '#e4a252' });

  if (permissions.canManagePermissions) {
    quickActions.push({ icon: ShieldAlert, label: 'Permissions', route: '/settings/permissions', color: '#8b546a' });
  }

  quickActions.push({ icon: CheckSquare, label: 'Tasks', route: '/tasks', color: '#d97d55' });
  quickActions.push({ icon: QrCode, label: 'Scanner', route: '/scan', color: '#6fa4af' });
  quickActions.push({ icon: BarChart2, label: 'Mentron', route: '/mentron', color: '#8B5CF6' });

  if (permissions.isAtLeastTier1) {
    quickActions.push({ icon: UserCheck, label: 'Registrations', route: '/registrations', color: '#b8c4a9' });
  }

  return (
    <div className="home-screen-container">
      {/* Top Header Panel */}
      <header className="home-header">
        <div className="header-branding">
          <img src="/logo.png" className="branding-logo" alt="LYNQ Logo" />
          <span className="branding-title">LYNQ</span>
        </div>
        <div className="header-actions">
          <button onClick={() => navigate('/announcements')} className="notification-button">
            <Bell size={22} />
          </button>
          <div className="user-avatar" onClick={() => navigate('/settings')}>
            {currentUser.name[0].toUpperCase()}
          </div>
        </div>
      </header>

      {/* Greeting and Welcome */}
      <section className="welcome-section">
        <span className="welcome-tagline">Good Day,</span>
        <h2 className="welcome-name">{firstName}!</h2>
      </section>

      {/* Responsive Two-Column Dashboard Grid */}
      <div className="dashboard-grid">
        <div className="dashboard-main">
          {/* Network Overview Stats */}
          <section className="section-block">
            <h3 className="section-title">NETWORK OVERVIEW</h3>
            <div className="overview-stats-row">
              <GlassCard className="stat-card" padding="16px" onClick={() => navigate('/members')}>
                <div className="stat-icon-wrapper">
                  <Users size={18} />
                </div>
                <div className="stat-value">{stats?.members ?? '—'}</div>
                <div className="stat-label">MEMBERS</div>
              </GlassCard>

              <GlassCard className="stat-card" padding="16px" onClick={() => navigate('/execom_list')}>
                <div className="stat-icon-wrapper">
                  <ShieldAlert size={18} />
                </div>
                <div className="stat-value">{stats?.execom ?? '—'}</div>
                <div className="stat-label">EXECOM</div>
              </GlassCard>
              
              <GlassCard className="stat-card" padding="16px" onClick={() => navigate('/events')}>
                <div className="stat-icon-wrapper">
                  <Calendar size={18} />
                </div>
                <div className="stat-value">{stats?.events ?? '—'}</div>
                <div className="stat-label">EVENTS</div>
              </GlassCard>

              <GlassCard className="stat-card" padding="16px" onClick={() => navigate('/folders')}>
                <div className="stat-icon-wrapper">
                  <FolderOpen size={18} />
                </div>
                <div className="stat-value">{stats?.forums ?? '—'}</div>
                <div className="stat-label">TEAMS</div>
              </GlassCard>
            </div>
          </section>

          {/* Quick Actions Grid */}
          <section className="section-block">
            <h3 className="section-title">ACTIONS</h3>
            <div className="actions-grid">
              {quickActions.map((action, i) => {
                const Icon = action.icon;
                return (
                  <div
                    key={`act-${i}`}
                    className="action-grid-item"
                    onClick={() => navigate(action.route)}
                  >
                    <div 
                      className="action-icon-circle"
                      style={{ backgroundColor: `${action.color}18`, color: action.color }}
                    >
                      <Icon size={22} />
                    </div>
                    <span className="action-grid-label">{action.label}</span>
                  </div>
                );
              })}
            </div>
          </section>
        </div>

        <div className="dashboard-sidebar">
          {/* Upcoming Board Section */}
          <section className="section-block">
            <h3 className="section-title">UPCOMING BOARD</h3>
            {isUpcomingLoading ? (
              <div className="upcoming-loading">Loading board updates...</div>
            ) : upcomingEvents.length === 0 && pendingTasks.length === 0 ? (
              <div className="upcoming-empty-card">
                No upcoming events or tasks. All caught up!
              </div>
            ) : (
              <div className="upcoming-list">
                {upcomingEvents.map((evt) => (
                  <div key={`evt-${evt.id}`} className="upcoming-item-row" onClick={() => navigate('/events')}>
                    <div className="item-icon-wrapper" style={{ backgroundColor: 'rgba(22, 192, 122, 0.1)' }}>
                      <Calendar size={18} style={{ color: '#16c07a' }} />
                    </div>
                    <div className="item-text-details">
                      <div className="item-text-title">{evt.title}</div>
                      <div className="item-text-subtitle">{evt.date}</div>
                    </div>
                    <ChevronRight size={18} className="item-chevron" />
                  </div>
                ))}
                {pendingTasks.map((tsk) => (
                  <div key={`tsk-${tsk.id}`} className="upcoming-item-row" onClick={() => navigate('/tasks')}>
                    <div className="item-icon-wrapper" style={{ backgroundColor: 'rgba(217, 125, 85, 0.1)' }}>
                      <CheckSquare size={18} style={{ color: '#d97d55' }} />
                    </div>
                    <div className="item-text-details">
                      <div className="item-text-title">{tsk.title}</div>
                      <div className="item-text-subtitle">Due: {tsk.deadline || 'No deadline'}</div>
                    </div>
                    <ChevronRight size={18} className="item-chevron" />
                  </div>
                ))}
              </div>
            )}
          </section>

          {/* Active Teams Cards */}
          <section className="section-block" style={{ marginBottom: '40px' }}>
            <div className="section-title-row">
              <h3 className="section-title">ACTIVE TEAMS</h3>
              <button onClick={() => navigate('/folders')} className="see-all-button">
                See All
              </button>
            </div>
            <div className="forums-row-scroll">
              {isForumsLoading ? (
                <div style={{ color: 'var(--text-secondary)', fontSize: '14px', padding: '10px' }}>Loading teams...</div>
              ) : activeForums.length === 0 ? (
                <div style={{ color: 'var(--text-secondary)', fontSize: '14px', padding: '10px' }}>No teams available</div>
              ) : (
                activeForums.map((forum) => (
                  <GlassCard key={forum.id} className="forum-item-card" padding="14px" onClick={() => navigate(`/folders/${forum.id}`)}>
                    <div className="forum-card-content">
                      <BookOpen size={24} style={{ color: 'rgb(22, 192, 122)', marginBottom: '8px' }} />
                      <span className="forum-card-name">{forum.name}</span>
                      <span className="forum-card-role">Interactive Hub</span>
                    </div>
                  </GlassCard>
                ))
              )}
            </div>
          </section>
        </div>
      </div>

      <NavBar />

      <style>{`
        .home-screen-container {
          padding: 16px 20px;
          display: flex;
          flex-direction: column;
          gap: 24px;
        }

        @media (min-width: 768px) {
          .home-screen-container {
            padding: 24px 0;
          }
        }

        .home-header {
          display: flex;
          align-items: center;
          justify-content: space-between;
          height: 60px;
        }

        .header-branding {
          display: flex;
          align-items: center;
          gap: 10px;
        }

        .branding-logo {
          width: 32px;
          height: 32px;
          background: linear-gradient(135deg, rgb(var(--primary-emerald)) 0%, rgb(var(--secondary-neon)) 100%);
          border-radius: 10px;
          display: block;
          object-fit: contain;
          padding: 4px;
        }

        .branding-title {
          font-family: var(--font-space-grotesk);
          font-weight: 800;
          font-size: 20px;
          letter-spacing: 0.5px;
          color: var(--text-primary);
        }

        .header-actions {
          display: flex;
          align-items: center;
          gap: 16px;
        }

        .notification-button {
          color: var(--text-primary);
          opacity: 0.85;
          display: flex;
          align-items: center;
          justify-content: center;
        }

        .user-avatar {
          width: 38px;
          height: 38px;
          border-radius: 50%;
          background-color: rgb(22, 192, 122);
          color: #ffffff;
          font-family: var(--font-space-grotesk);
          font-weight: 700;
          font-size: 15px;
          display: flex;
          align-items: center;
          justify-content: center;
          cursor: pointer;
          box-shadow: 0 4px 10px rgba(22, 192, 122, 0.25);
        }

        .welcome-section {
          display: flex;
          flex-direction: column;
        }

        .welcome-tagline {
          font-size: 16px;
          color: var(--text-secondary);
          font-weight: 500;
        }

        .welcome-name {
          font-size: 34px;
          font-weight: 800;
          color: var(--text-primary);
          letter-spacing: -1px;
          height: 38px;
          line-height: 38px;
        }

        /* Two-Column Grid Setup */
        .dashboard-grid {
          display: flex;
          flex-direction: column;
          gap: 24px;
        }

        @media (min-width: 1024px) {
          .dashboard-grid {
            display: grid;
            grid-template-columns: 2.2fr 1fr;
            gap: 32px;
            align-items: start;
          }
        }

        .section-block {
          display: flex;
          flex-direction: column;
          gap: 14px;
          margin-bottom: 8px;
        }

        .section-title-row {
          display: flex;
          align-items: center;
          justify-content: space-between;
        }

        .section-title {
          font-family: var(--font-space-grotesk);
          font-size: 12.5px;
          font-weight: 800;
          letter-spacing: 1.5px;
          color: var(--text-muted);
          text-transform: uppercase;
        }

        .see-all-button {
          font-family: var(--font-space-grotesk);
          font-size: 12.5px;
          font-weight: 700;
          color: rgb(22, 192, 122);
        }

        .upcoming-empty-card, .upcoming-loading {
          background: rgba(255, 255, 255, 0.02);
          border: 1px dashed var(--border-light);
          border-radius: 16px;
          padding: 24px;
          text-align: center;
          font-size: 14px;
          color: var(--text-secondary);
        }

        .upcoming-list {
          display: flex;
          flex-direction: column;
          gap: 10px;
        }

        .upcoming-item-row {
          display: flex;
          align-items: center;
          padding: 14px 16px;
          background: rgba(255, 255, 255, 0.015);
          border: 1px solid var(--border-light);
          border-radius: 16px;
          cursor: pointer;
          transition: all 0.2s cubic-bezier(0.4, 0, 0.2, 1);
        }

        .upcoming-item-row:hover {
          background: rgba(255, 255, 255, 0.04);
          transform: translateX(3px);
          box-shadow: 0 4px 15px rgba(0,0,0,0.05);
        }

        .item-icon-wrapper {
          width: 38px;
          height: 38px;
          border-radius: 50%;
          display: flex;
          align-items: center;
          justify-content: center;
          margin-right: 14px;
          flex-shrink: 0;
        }

        .item-text-details {
          flex-grow: 1;
          display: flex;
          flex-direction: column;
          gap: 2px;
        }

        .item-text-title {
          font-size: 14.5px;
          font-weight: 600;
          color: var(--text-primary);
        }

        .item-text-subtitle {
          font-size: 12px;
          color: var(--text-muted);
        }

        .item-chevron {
          color: var(--text-muted);
          opacity: 0.6;
        }

        /* Actions Grid Styling */
        .actions-grid {
          display: grid;
          grid-template-columns: repeat(4, 1fr);
          column-gap: 12px;
          row-gap: 24px;
          padding: 8px 0;
        }

        @media (min-width: 1024px) {
          .actions-grid {
            grid-template-columns: repeat(auto-fill, minmax(90px, 1fr));
            column-gap: 20px;
            row-gap: 24px;
          }
        }

        .action-grid-item {
          display: flex;
          flex-direction: column;
          align-items: center;
          cursor: pointer;
          transition: transform 0.2s cubic-bezier(0.175, 0.885, 0.32, 1.275);
        }

        .action-grid-item:hover {
          transform: translateY(-4px);
        }

        .action-icon-circle {
          width: 54px;
          height: 54px;
          border-radius: 18px;
          display: flex;
          align-items: center;
          justify-content: center;
          margin-bottom: 8px;
          box-shadow: 0 4px 15px rgba(0, 0, 0, 0.05);
          transition: all 0.2s ease;
        }

        .action-grid-item:hover .action-icon-circle {
          box-shadow: 0 8px 25px rgba(0,0,0,0.1);
        }

        .action-grid-label {
          font-size: 12px;
          font-weight: 700;
          color: var(--text-primary);
          text-align: center;
          max-width: 90px;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }

        .overview-stats-row {
          display: flex;
          gap: 16px;
        }

        .stat-card {
          flex: 1;
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          transition: all 0.2s ease;
        }

        .stat-card:hover {
          transform: translateY(-2px);
        }

        .stat-icon-wrapper {
          width: 40px;
          height: 40px;
          background: rgba(15, 117, 73, 0.06);
          border-radius: 12px;
          display: flex;
          align-items: center;
          justify-content: center;
          color: rgb(15, 117, 73);
          margin-bottom: 12px;
        }

        [data-theme='dark'] .stat-icon-wrapper {
          background: rgba(22, 192, 122, 0.1);
          color: rgb(22, 192, 122);
        }

        .stat-value {
          font-family: var(--font-space-grotesk);
          font-size: 24px;
          font-weight: 800;
          color: var(--text-primary);
          line-height: 1;
          margin-bottom: 4px;
        }

        .stat-label {
          font-size: 9.5px;
          font-weight: 800;
          letter-spacing: 1.5px;
          color: var(--text-muted);
        }

        .forums-row-scroll {
          display: flex;
          gap: 12px;
          overflow-x: auto;
          padding-bottom: 8px;
          scroll-snap-type: x mandatory;
        }

        .forum-item-card {
          flex: 1 0 110px;
          scroll-snap-align: start;
          transition: all 0.2s ease;
        }

        .forum-item-card:hover {
          transform: translateY(-2px);
        }

        .forum-card-content {
          display: flex;
          flex-direction: column;
        }

        .forum-card-name {
          font-family: var(--font-space-grotesk);
          font-size: 15.5px;
          font-weight: 700;
          color: var(--text-primary);
        }

        .forum-card-role {
          font-size: 10px;
          color: var(--text-muted);
        }
      `}</style>
    </div>
  );
};
