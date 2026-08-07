import { useState, useEffect, useRef } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '../contexts/AuthContext';
import { supabase } from '../lib/supabase';
import DashboardLayout from '../components/DashboardLayout';
import { Award, Calendar, Download, Eye, AlertCircle } from 'lucide-react';

// ── Design tokens ──────────────────────────────────────────────────────────────
const T = {
  bg:         '#FAF6EC',
  navy:       '#1B2A4A',
  gold:       '#C9A227',
  teal:       '#2F6F6E',
  lavender:   '#6B4E9E',
  muted:      '#6b6558',
  caption:    '#8a8371',
  cardSurf:   '#FFFDF8',
  cardBorder: '#E7DFC9',
  divider:    '#EFE9D8',
};

const FILTERS = ['All', 'Hackathon', 'Workshop', 'Seminar'];

function sealColor(cat) {
  const c = (cat || '').toLowerCase();
  if (c === 'hackathon') return T.gold;
  if (c === 'workshop')  return T.teal;
  if (c === 'seminar')   return T.lavender;
  return T.navy;
}

function formatDate(dateStr) {
  if (!dateStr) return '';
  const d = new Date(dateStr);
  return d.toLocaleDateString('en-IN', { day: 'numeric', month: 'short', year: 'numeric' });
}

// ── Circuit-trace SVG ornament (top-right corner) ─────────────────────────────
function CircuitOrnament() {
  return (
    <svg width="80" height="80" viewBox="0 0 80 80" fill="none"
      style={{ position: 'absolute', top: 0, right: 0, opacity: 0.13, pointerEvents: 'none' }}>
      {/* Horizontal traces */}
      <polyline points="80,10 50,10 50,26 32,26" stroke={T.gold} strokeWidth="1.5" strokeLinecap="round" fill="none"/>
      <polyline points="80,28 64,28 64,50 48,50" stroke={T.gold} strokeWidth="1.5" strokeLinecap="round" fill="none"/>
      <polyline points="30,0 30,20 18,20" stroke={T.gold} strokeWidth="1.5" strokeLinecap="round" fill="none"/>
      {/* Contact dots */}
      <circle cx="50" cy="10" r="2.5" fill={T.gold}/>
      <circle cx="50" cy="26" r="2.5" fill={T.gold}/>
      <circle cx="64" cy="28" r="2.5" fill={T.gold}/>
      <circle cx="30" cy="20" r="2.5" fill={T.gold}/>
    </svg>
  );
}

// ── Seal badge ─────────────────────────────────────────────────────────────────
function SealBadge({ color }) {
  return (
    <div style={{
      width: 54, height: 54, borderRadius: '50%', flexShrink: 0,
      background: `${color}14`,
      border: `1.5px solid ${color}80`,
      display: 'flex', alignItems: 'center', justifyContent: 'center',
    }}>
      <Award size={26} color={color} />
    </div>
  );
}

// ── Skeleton card ──────────────────────────────────────────────────────────────
function SkeletonCard() {
  return (
    <div style={{
      background: T.cardSurf, border: `1px solid ${T.cardBorder}`, borderRadius: 16,
      padding: 16, display: 'flex', gap: 14, alignItems: 'center',
      animation: 'shimmer 1.5s ease-in-out infinite',
    }}>
      <div style={{ width: 54, height: 54, borderRadius: '50%', background: T.cardBorder, flexShrink: 0 }} />
      <div style={{ flex: 1 }}>
        <div style={{ height: 10, width: 60, background: T.cardBorder, borderRadius: 6, marginBottom: 10 }} />
        <div style={{ height: 14, width: '80%', background: T.cardBorder, borderRadius: 6, marginBottom: 8 }} />
        <div style={{ height: 10, width: 100, background: T.cardBorder, borderRadius: 6 }} />
      </div>
      <style>{`
        @keyframes shimmer {
          0%   { opacity: 1; }
          50%  { opacity: 0.55; }
          100% { opacity: 1; }
        }
      `}</style>
    </div>
  );
}

// ── Certificate card ───────────────────────────────────────────────────────────
function CertCard({ cert, navigate }) {
  const category   = cert._category;
  const eventTitle = cert._eventTitle;
  const eventDate  = cert._eventDate;
  const eventId    = cert._eventId;
  const url        = cert._url;
  const color      = sealColor(category);
  const issuedAt   = cert.issued_at ? formatDate(cert.issued_at) : '';
  const dateLabel  = eventDate ? formatDate(eventDate) : issuedAt;

  const [shareMsg, setShareMsg] = useState('');

  const handleShare = () => {
    if (!url) return;
    if (navigator.share) {
      navigator.share({ title: `My ISTE Certificate — ${eventTitle}`, url }).catch(() => {});
    } else {
      navigator.clipboard.writeText(url).then(() => {
        setShareMsg('Link copied!');
        setTimeout(() => setShareMsg(''), 2000);
      }).catch(() => {});
    }
  };

  return (
    <div style={{
      background: T.cardSurf, border: `1px solid ${T.cardBorder}`, borderRadius: 16,
      overflow: 'hidden', position: 'relative',
      cursor: eventId ? 'pointer' : 'default',
      transition: 'box-shadow 0.18s, transform 0.18s',
    }}
      onMouseEnter={e => { e.currentTarget.style.boxShadow = '0 4px 20px rgba(27,42,74,0.10)'; e.currentTarget.style.transform = 'translateY(-1px)'; }}
      onMouseLeave={e => { e.currentTarget.style.boxShadow = 'none'; e.currentTarget.style.transform = 'none'; }}
      onClick={() => eventId && navigate(`/events/${eventId}`)}
    >
      <CircuitOrnament />

      {/* Card body */}
      <div style={{ padding: '14px 14px 10px', display: 'flex', gap: 14, alignItems: 'flex-start' }}>
        <SealBadge color={color} />
        <div style={{ flex: 1, minWidth: 0 }}>
          {category && (
            <div style={{
              fontSize: 10, fontFamily: 'monospace', fontWeight: 700,
              letterSpacing: '1.4px', color, textTransform: 'uppercase', marginBottom: 3,
            }}>
              {category}
            </div>
          )}
          <div style={{
            fontFamily: "'Cormorant Garamond', 'Georgia', serif", fontSize: 16,
            fontWeight: 700, color: T.navy, lineHeight: 1.3,
            whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
          }}>
            {eventTitle}
          </div>
          <div style={{ fontSize: 12, color: T.muted, fontFamily: "'Inter',sans-serif", marginTop: 2 }}>
            Certificate of Participation
          </div>
          {dateLabel && (
            <div style={{ display: 'flex', alignItems: 'center', gap: 5, marginTop: 6 }}>
              <Calendar size={11} color={T.caption} />
              <span style={{ fontSize: 11, color: T.caption, fontFamily: "'Inter',sans-serif" }}>{dateLabel}</span>
            </div>
          )}
        </div>
      </div>

      {/* Action bar */}
      {url && (
        <>
          <div style={{ height: 1, background: T.divider }} />
          <div style={{ display: 'flex', onClick: e => e.stopPropagation() }}
            onClick={e => e.stopPropagation()}>
            <button
              onClick={e => { e.stopPropagation(); window.open(url, '_blank'); }}
              style={{
                flex: 1, padding: '10px 0', background: 'none', border: 'none', cursor: 'pointer',
                display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6,
                fontFamily: "'Inter',sans-serif", fontSize: 13, fontWeight: 600, color: T.navy,
                transition: 'background 0.15s',
              }}
              onMouseEnter={e => e.currentTarget.style.background = `${T.navy}08`}
              onMouseLeave={e => e.currentTarget.style.background = 'none'}
            >
              <Eye size={14} /> View
            </button>
            <div style={{ width: 1, background: T.divider }} />
            <button
              onClick={e => { e.stopPropagation(); window.open(url, '_blank'); }}
              style={{
                flex: 1, padding: '10px 0', background: 'none', border: 'none', cursor: 'pointer',
                display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6,
                fontFamily: "'Inter',sans-serif", fontSize: 13, fontWeight: 600, color: T.teal,
                transition: 'background 0.15s',
              }}
              onMouseEnter={e => e.currentTarget.style.background = `${T.teal}08`}
              onMouseLeave={e => e.currentTarget.style.background = 'none'}
            >
              <Download size={14} /> Download
            </button>
          </div>
        </>
      )}
    </div>
  );
}

// ── Empty state ────────────────────────────────────────────────────────────────
function EmptyState({ filter, navigate }) {
  const hasFilter = filter !== 'All';
  return (
    <div style={{ textAlign: 'center', padding: '80px 24px' }}>
      <div style={{
        width: 72, height: 72, borderRadius: '50%', margin: '0 auto 20px',
        border: `2px solid ${T.navy}30`,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
      }}>
        <Award size={36} color={`${T.navy}40`} />
      </div>
      <h2 style={{
        fontFamily: "'Cormorant Garamond','Georgia',serif", fontSize: 20,
        fontWeight: 700, color: T.navy, marginBottom: 10,
      }}>
        {hasFilter ? `No ${filter} certificates` : 'No certificates yet'}
      </h2>
      <p style={{ fontFamily: "'Inter',sans-serif", fontSize: 13, color: T.muted, lineHeight: 1.6, marginBottom: 28 }}>
        {hasFilter
          ? `You haven't earned any ${filter} certificates yet.`
          : 'Attend events and mark your attendance to start earning certificates.'}
      </p>
      {!hasFilter && (
        <button
          onClick={() => navigate('/events')}
          style={{
            padding: '12px 28px', background: T.navy, color: '#fff',
            border: 'none', borderRadius: 40, cursor: 'pointer',
            fontFamily: "'Inter',sans-serif", fontSize: 14, fontWeight: 700,
            transition: 'opacity 0.15s',
          }}
          onMouseEnter={e => e.currentTarget.style.opacity = '0.85'}
          onMouseLeave={e => e.currentTarget.style.opacity = '1'}
        >
          Browse Events
        </button>
      )}
    </div>
  );
}

// ── Main page ──────────────────────────────────────────────────────────────────
export default function CertificatesPage() {
  const { user } = useAuth();
  const navigate = useNavigate();
  const [all, setAll] = useState([]);
  const [isLoading, setIsLoading] = useState(true);
  const [activeFilter, setActiveFilter] = useState('All');

  useEffect(() => {
    if (!user?.id) return;
    (async () => {
      setIsLoading(true);
      const { data } = await supabase
        .from('certificates')
        .select('id, event_id, student_name, certificate_url, file_url, issued_at, events(id, title, date, category, type)')
        .eq('user_id', user.id)
        .order('issued_at', { ascending: false });

      const normalised = (data || []).map(item => ({
        ...item,
        _url: item.certificate_url || item.file_url || '',
        _category: item.events?.category || item.events?.type || null,
        _eventTitle: item.events?.title || 'Event',
        _eventDate: item.events?.date || '',
        _eventId: item.events?.id || item.event_id,
      }));
      setAll(normalised);
      setIsLoading(false);
    })();
  }, [user]);

  const filtered = activeFilter === 'All'
    ? all
    : all.filter(c => (c._category || '').toLowerCase() === activeFilter.toLowerCase());

  return (
    <DashboardLayout>
      <div style={{ background: T.bg, minHeight: '100vh' }}>
        {/* Header */}
        <div style={{
          background: T.bg, borderBottom: `1px solid ${T.cardBorder}`,
          padding: '28px 28px 20px', position: 'sticky', top: 0, zIndex: 10,
        }}>
          <h1 style={{
            fontFamily: "'Cormorant Garamond','Georgia',serif",
            fontSize: 24, fontWeight: 700, color: T.navy, marginBottom: 2,
          }}>
            My Certificates
          </h1>
          {!isLoading && (
            <p style={{ fontFamily: "'Inter',sans-serif", fontSize: 12, color: T.muted }}>
              {all.length} {all.length === 1 ? 'certificate' : 'certificates'} earned
            </p>
          )}

          {/* Filter chips */}
          <div style={{ display: 'flex', gap: 10, marginTop: 16, flexWrap: 'wrap' }}>
            {FILTERS.map(f => {
              const active = f === activeFilter;
              return (
                <button
                  key={f}
                  onClick={() => setActiveFilter(f)}
                  style={{
                    padding: '6px 18px', borderRadius: 40, border: `1px solid ${active ? T.navy : T.cardBorder}`,
                    background: active ? T.navy : 'transparent', color: active ? '#fff' : T.navy,
                    fontFamily: "'Inter',sans-serif", fontSize: 13, fontWeight: 600,
                    cursor: 'pointer', transition: 'all 0.18s',
                  }}
                  onMouseEnter={e => { if (!active) e.currentTarget.style.borderColor = T.navy; }}
                  onMouseLeave={e => { if (!active) e.currentTarget.style.borderColor = T.cardBorder; }}
                >
                  {f}
                </button>
              );
            })}
          </div>
        </div>

        {/* Content */}
        <div style={{ maxWidth: 760, margin: '0 auto', padding: '20px 24px 48px' }}>
          {isLoading ? (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
              {[0, 1, 2].map(i => <SkeletonCard key={i} />)}
            </div>
          ) : filtered.length === 0 ? (
            <EmptyState filter={activeFilter} navigate={navigate} />
          ) : (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
              {filtered.map(cert => (
                <CertCard key={cert.id} cert={cert} navigate={navigate} />
              ))}
            </div>
          )}
        </div>
      </div>

      <style>{`
        @import url('https://fonts.googleapis.com/css2?family=Cormorant+Garamond:wght@600;700&display=swap');
      `}</style>
    </DashboardLayout>
  );
}
