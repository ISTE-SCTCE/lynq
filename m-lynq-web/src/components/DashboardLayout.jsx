import { Link, useNavigate, useLocation } from 'react-router-dom';
import { useAuth } from '../contexts/AuthContext';
import { GraduationCap, Home, Calendar, Award, Bell, User, LogOut, Menu, X } from 'lucide-react';
import { useState } from 'react';

const navItems = [
  { path: '/home', icon: <Home size={18} />, label: 'Home' },
  { path: '/events', icon: <Calendar size={18} />, label: 'Events' },
  { path: '/attendance', icon: <GraduationCap size={18} />, label: 'Attendance' },
  { path: '/certificates', icon: <Award size={18} />, label: 'Certificates' },
  { path: '/notifications', icon: <Bell size={18} />, label: 'Notifications' },
  { path: '/profile', icon: <User size={18} />, label: 'Profile' },
];

export default function DashboardLayout({ children }) {
  const { name, membershipId, signOut } = useAuth();
  const location = useLocation();
  const navigate = useNavigate();
  const [mobileOpen, setMobileOpen] = useState(false);

  const avatarUrl = name ? `https://api.dicebear.com/7.x/notionists/png?seed=${encodeURIComponent(name)}` : null;

  const handleSignOut = async () => { await signOut(); navigate('/login'); };

  const SidebarContent = () => (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%', padding: '24px 16px' }}>
      {/* Logo */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 36, paddingLeft: 8 }}>
        <div style={{ width: 36, height: 36, borderRadius: 10, background: 'linear-gradient(135deg,#5F85A2,#3a5c7a)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <GraduationCap size={20} color="#fff" />
        </div>
        <div>
          <div style={{ fontFamily: "'Space Grotesk',sans-serif", fontWeight: 700, fontSize: 17, color: '#111', lineHeight: 1.2 }}>M-Lynq</div>
          <div style={{ fontSize: 11, color: '#5F85A2', fontWeight: 500 }}>ISTE Portal</div>
        </div>
      </div>

      {/* Nav */}
      <nav style={{ flex: 1 }}>
        {navItems.map(item => {
          const active = location.pathname === item.path;
          return (
            <Link key={item.path} to={item.path} onClick={() => setMobileOpen(false)}
              style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '11px 14px', borderRadius: 14, marginBottom: 4, textDecoration: 'none', transition: 'all 0.15s', color: active ? '#111' : '#5F85A2', background: active ? '#D3E3F0' : 'transparent', fontWeight: active ? 600 : 500, fontSize: 14, fontFamily: "'Inter',sans-serif" }}>
              {item.icon}
              {item.label}
            </Link>
          );
        })}
      </nav>

      {/* User card */}
      <div style={{ borderTop: '1.5px solid #D3E3F0', paddingTop: 16, marginTop: 16 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 12 }}>
          {avatarUrl ? (
            <img src={avatarUrl} alt="avatar" style={{ width: 38, height: 38, borderRadius: '50%', objectFit: 'cover', border: '2px solid #D3E3F0' }} />
          ) : (
            <div style={{ width: 38, height: 38, borderRadius: '50%', background: '#D3E3F0', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <User size={18} color="#5F85A2" />
            </div>
          )}
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontWeight: 600, fontSize: 13, color: '#111', fontFamily: "'Space Grotesk',sans-serif", overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{name || 'Member'}</div>
            <div style={{ fontSize: 11, color: '#5F85A2', fontFamily: "'Inter',sans-serif" }}>{membershipId ? `ID: ${membershipId}` : 'Guest'}</div>
          </div>
        </div>
        <button onClick={handleSignOut} style={{ display: 'flex', alignItems: 'center', gap: 8, width: '100%', padding: '9px 14px', background: 'rgba(217,125,85,0.1)', border: '1px solid rgba(217,125,85,0.2)', borderRadius: 12, color: '#D97D55', cursor: 'pointer', fontSize: 13, fontWeight: 600, fontFamily: "'Inter',sans-serif" }}>
          <LogOut size={16} /> Sign Out
        </button>
      </div>
    </div>
  );

  return (
    <div style={{ display: 'flex', minHeight: '100vh', background: '#EBF3FC' }}>
      {/* Desktop Sidebar */}
      <aside style={{ width: 240, background: '#fff', borderRight: '1.5px solid #D3E3F0', position: 'fixed', top: 0, left: 0, height: '100vh', overflowY: 'auto', zIndex: 40, display: 'none' }} className="desktop-sidebar">
        <SidebarContent />
      </aside>

      {/* Mobile overlay sidebar */}
      {mobileOpen && (
        <div style={{ position: 'fixed', inset: 0, zIndex: 60 }}>
          <div style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,0,0.3)' }} onClick={() => setMobileOpen(false)} />
          <aside style={{ position: 'absolute', left: 0, top: 0, width: 260, height: '100%', background: '#fff', overflowY: 'auto' }}>
            <SidebarContent />
          </aside>
        </div>
      )}

      {/* Mobile header */}
      <div style={{ position: 'fixed', top: 0, left: 0, right: 0, height: 60, background: '#fff', borderBottom: '1.5px solid #D3E3F0', display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '0 20px', zIndex: 30 }} className="mobile-header">
        <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          <div style={{ width: 32, height: 32, borderRadius: 8, background: 'linear-gradient(135deg,#5F85A2,#3a5c7a)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <GraduationCap size={18} color="#fff" />
          </div>
          <span style={{ fontFamily: "'Space Grotesk',sans-serif", fontWeight: 700, fontSize: 16, color: '#111' }}>M-Lynq</span>
        </div>
        <button onClick={() => setMobileOpen(!mobileOpen)} style={{ background: 'none', border: 'none', cursor: 'pointer', color: '#5F85A2', padding: 6 }}>
          {mobileOpen ? <X size={22} /> : <Menu size={22} />}
        </button>
      </div>

      {/* Main content */}
      <main className="dashboard-main" style={{ flex: 1, paddingTop: 0 }}>
        {children}
      </main>

      <style>{`
        @media (min-width: 768px) {
          .desktop-sidebar { display: block !important; }
          .mobile-header { display: none !important; }
          .dashboard-main { margin-left: 240px; }
        }
        @media (max-width: 767px) {
          .dashboard-main { padding-top: 60px; }
        }
      `}</style>
    </div>
  );
}
