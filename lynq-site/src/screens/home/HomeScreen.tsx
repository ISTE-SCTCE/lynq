import { ArrowUpRight, Bell, Calendar, CheckSquare, FileText, FolderOpen, MessageSquare, QrCode, RefreshCw, Shield, Upload, UserCheck, Users, Wallet, BarChart2 } from 'lucide-react';
import { Link } from 'react-router-dom';
import { useAuth } from '../../core/auth-provider';
import { AppRole } from '../../core/constants';
import { NavBar } from '../../shared/components/NavBar';
import { useDashboard } from './useDashboard';
import './home.css';

export function HomeScreen() {
  const { currentUser, permissions } = useAuth();
  const { data, loading, error, updated, refresh } = useDashboard(currentUser?.id, permissions?.isAtLeastTier2 ?? false);
  if (!currentUser || !permissions) return null;
  const actions = [
    { title: 'Events', text: 'Plan what brings us together', icon: Calendar, path: '/events', show: true },
    { title: 'Tasks', text: 'Move the next idea forward', icon: CheckSquare, path: '/tasks', show: true },
    { title: 'Teams', text: 'Find your people and projects', icon: FolderOpen, path: '/folders', show: true },
    { title: 'Members', text: 'Your community directory', icon: Users, path: '/members', show: permissions.role >= AppRole.forumExeccom },
    { title: 'Reports', text: 'Keep the work documented', icon: FileText, path: '/reports', show: true },
    { title: 'Upload report', text: 'Share your latest progress', icon: Upload, path: '/reports/upload', show: permissions.canUploadReports },
    { title: 'Budget', text: 'Requests and allocations', icon: Wallet, path: '/budget', show: permissions.canRequestBudget || permissions.canManageBudget },
    { title: 'Conversations', text: 'Stay in the loop', icon: MessageSquare, path: '/chat', show: permissions.canAccessChat },
    { title: 'Registrations', text: 'Review incoming applications', icon: UserCheck, path: '/registrations', show: permissions.isAtLeastTier1 },
    { title: 'Scanner', text: 'Check in with a QR code', icon: QrCode, path: '/scan', show: true },
    { title: 'Permissions', text: 'Manage workspace access', icon: Shield, path: '/settings/permissions', show: permissions.canManagePermissions },
    { title: 'Mentron', text: 'Open the existing dashboard', icon: BarChart2, path: '/mentron', show: true },
  ].filter(action => action.show);
  const dateLabel = (date: string | null) => {
    if (!date) return 'No deadline';
    const value = new Date(date.length === 10 ? date + 'T12:00:00' : date);
    return Number.isNaN(value.getTime()) ? 'Date unavailable' : value.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
  };
  return <main className="lynq-workspace">
    <header className="workspace-header">
      <Link to="/home" className="workspace-brand" aria-label="Lynq home">lynq<span>ISTE / SCTCE</span></Link>
      <div className="workspace-header-actions">
        <Link to="/announcements" className="workspace-icon" aria-label="Announcements"><Bell size={20}/></Link>
        <Link to="/settings" className="workspace-avatar" aria-label="Your profile">{(currentUser.name || 'M')[0].toUpperCase()}</Link>
      </div>
    </header>
    <section className="workspace-welcome">
      <div><p className="workspace-eyebrow">YOUR COMMUNITY. IN MOTION.</p>
        <h1>A little clarity.<br/>A lot of possibility.</h1>
        <p>Welcome back, {currentUser.name?.split(' ')[0] || 'member'}. Here’s where we move things forward.</p>
      </div>
      <div className="workspace-today"><span>{new Date().toLocaleDateString(undefined, { weekday: 'long' })}</span>
        <strong>{new Date().toLocaleDateString(undefined, { day: '2-digit', month: 'short' })}</strong>
        <Link to="/tasks">Find your next task <ArrowUpRight size={16}/></Link>
      </div>
    </section>
    <div className="workspace-sync">
      <span role="status">{loading ? 'Updating workspace…' : error ? 'Some data is unavailable' : updated ? `Last checked ${updated.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}` : 'Waiting for data'}</span>
      <button onClick={refresh} disabled={loading}><RefreshCw size={14} className={loading ? 'workspace-spin' : ''}/> Refresh</button>
    </div>
    {error && <div role="alert" className="workspace-error">{error} Unavailable counts are shown as —, not zero.</div>}
    <section className="workspace-stats" aria-label="Workspace overview">
      {[['Members', data?.counts.members, 'Registered ISTE members'], ['Events', data?.counts.events, 'Across your accessible workspace'], ['Your open tasks', data?.counts.tasks, 'Assigned to you, not completed']].map(([label, count, note]) =>
        <div className="workspace-stat" key={String(label)}><span>{label}</span><strong>{count ?? '—'}</strong><small>{note}</small></div>)}
    </section>
    <div className="workspace-columns">
      <section><div className="workspace-section-heading"><h2>Your workspace</h2><span>Make something happen</span></div>
        <div className="workspace-actions">{actions.map(({ title, text, icon: Icon, path }) =>
          <Link key={path} to={path} className="workspace-action"><Icon size={22}/><ArrowUpRight className="workspace-action-arrow" size={16}/><h3>{title}</h3><p>{text}</p></Link>)}</div>
      </section>
      <aside className="workspace-agenda">
        <div className="workspace-section-heading"><h2>On the horizon</h2><Calendar size={18}/></div>
        <h3>Upcoming events</h3>
        {data?.errors.includes('Upcoming events') ? <p className="workspace-empty">Events are temporarily unavailable.</p> : data?.events.length ? data.events.map(event =>
          <Link className="workspace-agenda-row" key={event.id} to="/events"><span className="workspace-date">{dateLabel(event.date)}</span><strong>{event.title}</strong><ArrowUpRight size={15}/></Link>) :
          <p className="workspace-empty">{loading ? 'Loading events…' : 'No upcoming events. Room for your next idea.'}</p>}
        <h3>On your list</h3>
        {data?.errors.includes('Your tasks') ? <p className="workspace-empty">Tasks are temporarily unavailable.</p> : data?.tasks.length ? data.tasks.map(task =>
          <Link className="workspace-agenda-row" key={task.id} to="/tasks"><CheckSquare size={17}/><div><strong>{task.title}</strong><small>Due {dateLabel(task.deadline)}</small></div><ArrowUpRight size={15}/></Link>) :
          <p className="workspace-empty">{loading ? 'Loading tasks…' : 'You’re all caught up. Nicely done.'}</p>}
        <div className="workspace-section-heading"><h2>Your teams</h2><Link to="/folders">View all ↗</Link></div>
        {data?.teams.map(team => <Link className="workspace-team" key={team.id} to={`/folders/${team.id}`}><FolderOpen size={18}/>{team.name}<ArrowUpRight size={15}/></Link>)}
        {!data?.teams.length && <p className="workspace-empty">{loading ? 'Loading teams…' : data?.errors.includes('Teams') ? 'Teams are temporarily unavailable.' : 'No teams available for your account.'}</p>}
      </aside>
    </div>
    <footer className="workspace-footer">Built around people. Connected through lynq.<span>Refreshes every minute while visible.</span></footer>
    <NavBar/>
  </main>;
}
