import { Link } from 'react-router-dom';
import { useAuth } from '../contexts/AuthContext';
import { 
  GraduationCap, Calendar, Award, Bell, Users, 
  ArrowRight, CheckCircle, Zap, Shield, BookOpen
} from 'lucide-react';

export default function LandingPage() {
  const { isAuthenticated } = useAuth();

  return (
    <div style={{ fontFamily: "'Space Grotesk', sans-serif", minHeight: '100vh', background: '#0a0a0f', color: '#fff' }}>
      {/* NAV */}
      <nav style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '20px 40px', borderBottom: '1px solid rgba(255,255,255,0.08)', position: 'sticky', top: 0, backdropFilter: 'blur(12px)', background: 'rgba(10,10,15,0.8)', zIndex: 50 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          <div style={{ width: 36, height: 36, borderRadius: 10, background: 'linear-gradient(135deg,#5F85A2,#3a5c7a)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <GraduationCap size={20} color="#fff" />
          </div>
          <span style={{ fontWeight: 700, fontSize: 20, letterSpacing: '-0.5px' }}>M-Lynq</span>
          <span style={{ fontSize: 11, color: '#5F85A2', fontWeight: 500, background: 'rgba(95,133,162,0.15)', padding: '2px 8px', borderRadius: 20, marginLeft: 4 }}>ISTE</span>
        </div>
        <div style={{ display: 'flex', gap: 8 }}>
          {isAuthenticated ? (
            <Link to="/home" style={{ padding: '9px 20px', background: '#5F85A2', color: '#fff', borderRadius: 28, textDecoration: 'none', fontWeight: 600, fontSize: 14 }}>
              Go to Dashboard
            </Link>
          ) : (
            <>
              <Link to="/login" style={{ padding: '9px 20px', background: 'transparent', color: '#D3E3F0', border: '1px solid rgba(211,227,240,0.2)', borderRadius: 28, textDecoration: 'none', fontWeight: 500, fontSize: 14 }}>
                Sign In
              </Link>
              <Link to="/login" style={{ padding: '9px 20px', background: 'linear-gradient(135deg,#5F85A2,#3a5c7a)', color: '#fff', borderRadius: 28, textDecoration: 'none', fontWeight: 600, fontSize: 14 }}>
                Join Now
              </Link>
            </>
          )}
        </div>
      </nav>

      {/* HERO */}
      <section style={{ textAlign: 'center', padding: '100px 24px 80px', position: 'relative', overflow: 'hidden' }}>
        {/* Glow halos */}
        <div style={{ position: 'absolute', top: -80, left: '20%', width: 500, height: 500, borderRadius: '50%', background: 'radial-gradient(circle, rgba(95,133,162,0.25) 0%, transparent 70%)', filter: 'blur(40px)', pointerEvents: 'none' }} />
        <div style={{ position: 'absolute', bottom: -80, right: '10%', width: 400, height: 400, borderRadius: '50%', background: 'radial-gradient(circle, rgba(217,125,85,0.2) 0%, transparent 70%)', filter: 'blur(40px)', pointerEvents: 'none' }} />
        
        <div style={{ display: 'inline-flex', alignItems: 'center', gap: 8, background: 'rgba(95,133,162,0.15)', border: '1px solid rgba(95,133,162,0.3)', borderRadius: 20, padding: '6px 16px', marginBottom: 28 }}>
          <div style={{ width: 8, height: 8, borderRadius: '50%', background: '#5F85A2', animation: 'ping 1.5s infinite' }} />
          <span style={{ fontSize: 13, color: '#D3E3F0', fontWeight: 500 }}>ISTE Student Chapter — Member Portal</span>
        </div>

        <h1 style={{ fontSize: 'clamp(36px,6vw,72px)', fontWeight: 700, lineHeight: 1.1, letterSpacing: '-2px', marginBottom: 24, maxWidth: 800, margin: '0 auto 24px' }}>
          Learn Something<br />
          <span style={{ background: 'linear-gradient(135deg,#5F85A2,#D3E3F0,#D97D55)', WebkitBackgroundClip: 'text', WebkitTextFillColor: 'transparent', backgroundClip: 'text' }}>
            New Today
          </span>
        </h1>

        <p style={{ fontSize: 18, color: 'rgba(211,227,240,0.7)', maxWidth: 520, margin: '0 auto 40px', lineHeight: 1.6, fontFamily: "'Inter', sans-serif", fontWeight: 400 }}>
          Your all-in-one member portal for the ISTE Student Chapter. Track attendance, download certificates, and stay connected with club events.
        </p>

        <div style={{ display: 'flex', gap: 12, justifyContent: 'center', flexWrap: 'wrap' }}>
          <Link to="/login" style={{ display: 'inline-flex', alignItems: 'center', gap: 8, padding: '14px 28px', background: 'linear-gradient(135deg,#5F85A2,#3a5c7a)', color: '#fff', borderRadius: 28, textDecoration: 'none', fontWeight: 600, fontSize: 16, boxShadow: '0 8px 32px rgba(95,133,162,0.4)' }}>
            Get Started <ArrowRight size={18} />
          </Link>
          <a href="#features" style={{ display: 'inline-flex', alignItems: 'center', gap: 8, padding: '14px 28px', background: 'rgba(255,255,255,0.05)', color: '#D3E3F0', border: '1px solid rgba(211,227,240,0.15)', borderRadius: 28, textDecoration: 'none', fontWeight: 500, fontSize: 16 }}>
            Learn More
          </a>
        </div>

        {/* Stats */}
        <div style={{ display: 'flex', gap: 40, justifyContent: 'center', marginTop: 72, flexWrap: 'wrap' }}>
          {[['Events', 'Hosted yearly'], ['Members', 'Active & growing'], ['Certificates', 'Issued to members']].map(([num, label]) => (
            <div key={label} style={{ textAlign: 'center' }}>
              <div style={{ fontSize: 28, fontWeight: 700, color: '#D3E3F0' }}>🎓</div>
              <div style={{ fontSize: 13, color: 'rgba(211,227,240,0.5)', marginTop: 4, fontFamily: "'Inter', sans-serif" }}>{label}</div>
            </div>
          ))}
        </div>
      </section>

      {/* FEATURES */}
      <section id="features" style={{ padding: '80px 24px', maxWidth: 1100, margin: '0 auto' }}>
        <h2 style={{ textAlign: 'center', fontSize: 36, fontWeight: 700, marginBottom: 12, letterSpacing: '-1px' }}>Everything you need</h2>
        <p style={{ textAlign: 'center', color: 'rgba(211,227,240,0.6)', marginBottom: 60, fontFamily: "'Inter',sans-serif" }}>All your ISTE chapter activities, in one place.</p>
        
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(280px,1fr))', gap: 20 }}>
          {[
            { icon: <Calendar size={24} />, color: '#5F85A2', bg: 'rgba(95,133,162,0.12)', title: 'Attendance Tracking', desc: 'View your full attendance history with a beautiful heatmap visualization. Know exactly when you attended each event.' },
            { icon: <Award size={24} />, color: '#D97D55', bg: 'rgba(217,125,85,0.12)', title: 'Digital Certificates', desc: 'Download and share your earned certificates directly from the portal. Same certificates as on your mobile app.' },
            { icon: <BookOpen size={24} />, color: '#3AAFA9', bg: 'rgba(58,175,169,0.12)', title: 'Event Calendar', desc: 'Browse upcoming workshops, hackathons, seminars, and more. Filter by category and register directly.' },
            { icon: <Bell size={24} />, color: '#F5C842', bg: 'rgba(245,200,66,0.12)', title: 'Notifications', desc: 'Stay up to date with club announcements and important updates from the ISTE executive committee.' },
            { icon: <Users size={24} />, color: '#E8E2F5', bg: 'rgba(232,226,245,0.12)', title: 'Member Profile', desc: 'Your complete member profile — ISTE ID, membership validity, branch, and all your club details.' },
            { icon: <Shield size={24} />, color: '#D3E3F0', bg: 'rgba(211,227,240,0.08)', title: 'Secure Auth', desc: 'Same Supabase authentication as the mobile app. Your data, your account — seamlessly synced across devices.' },
          ].map(f => (
            <div key={f.title} style={{ background: 'rgba(255,255,255,0.04)', border: '1px solid rgba(255,255,255,0.08)', borderRadius: 20, padding: 28 }}>
              <div style={{ width: 48, height: 48, borderRadius: 14, background: f.bg, display: 'flex', alignItems: 'center', justifyContent: 'center', color: f.color, marginBottom: 16 }}>
                {f.icon}
              </div>
              <h3 style={{ fontSize: 18, fontWeight: 600, marginBottom: 10 }}>{f.title}</h3>
              <p style={{ color: 'rgba(211,227,240,0.6)', fontSize: 14, lineHeight: 1.6, fontFamily: "'Inter',sans-serif" }}>{f.desc}</p>
            </div>
          ))}
        </div>
      </section>

      {/* CTA */}
      <section style={{ textAlign: 'center', padding: '80px 24px', background: 'rgba(95,133,162,0.08)', margin: '0 24px 80px', borderRadius: 28, border: '1px solid rgba(95,133,162,0.2)' }}>
        <div style={{ maxWidth: 500, margin: '0 auto' }}>
          <Zap size={40} color="#5F85A2" style={{ marginBottom: 20 }} />
          <h2 style={{ fontSize: 36, fontWeight: 700, letterSpacing: '-1px', marginBottom: 16 }}>Ready to dive in?</h2>
          <p style={{ color: 'rgba(211,227,240,0.6)', marginBottom: 32, fontFamily: "'Inter',sans-serif", fontSize: 16 }}>Sign in with your ISTE member credentials or join as a guest.</p>
          <Link to="/login" style={{ display: 'inline-flex', alignItems: 'center', gap: 8, padding: '14px 32px', background: 'linear-gradient(135deg,#5F85A2,#3a5c7a)', color: '#fff', borderRadius: 28, textDecoration: 'none', fontWeight: 600, fontSize: 16, boxShadow: '0 8px 32px rgba(95,133,162,0.4)' }}>
            Get Started Free <ArrowRight size={18} />
          </Link>
        </div>
      </section>

      {/* FOOTER */}
      <footer style={{ textAlign: 'center', padding: '32px 24px', borderTop: '1px solid rgba(255,255,255,0.08)', color: 'rgba(211,227,240,0.4)', fontFamily: "'Inter',sans-serif", fontSize: 13 }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8, marginBottom: 8 }}>
          <GraduationCap size={16} color="#5F85A2" />
          <span style={{ fontWeight: 600, color: '#5F85A2' }}>ISTE Student Chapter</span>
        </div>
        <p>© {new Date().getFullYear()} M-Lynq Member Portal. All rights reserved.</p>
      </footer>
    </div>
  );
}
