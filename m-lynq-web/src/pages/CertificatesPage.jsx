import { useState, useEffect, useRef } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '../contexts/AuthContext';
import { supabase } from '../lib/supabase';
import DashboardLayout from '../components/DashboardLayout';
import { Award, Calendar, Download, Eye, AlertCircle, Loader } from 'lucide-react';
import jsPDF from 'jspdf';
import html2canvas from 'html2canvas';

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
  const auth = useAuth();
  const category   = cert._category;
  const eventTitle = cert._eventTitle;
  const eventDate  = cert._eventDate;
  const eventId    = cert._eventId;
  const url        = cert._url;
  const color      = sealColor(category);
  const issuedAt   = cert.issued_at ? formatDate(cert.issued_at) : '';
  const dateLabel  = eventDate ? formatDate(eventDate) : issuedAt;

  const [shareMsg, setShareMsg] = useState('');
  const [isDownloading, setIsDownloading] = useState(false);

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

  const handleDownload = async (e) => {
    e.stopPropagation();
    if (!url) return;
    if (url.startsWith('template:')) {
      if (isDownloading) return;
      setIsDownloading(true);
      try {
        const templatePath = url.replace('template:', '');
        
        // Ensure template is treated as a URL (it might already be a public URL if generated locally)
        let templateHtmlUrl = templatePath;
        if (!templatePath.startsWith('http')) {
          const { data } = await supabase.storage.from('event_posters').createSignedUrl(templatePath, 60);
          templateHtmlUrl = data?.signedUrl || templatePath;
        }

        const res = await fetch(templateHtmlUrl);
        let html = await res.text();
        
        const certId = `ISTE-${eventId}-${(cert.user_id || '').replace(/-/g, '').substring(0,6).toUpperCase()}`;

        // ── Resolve live student name from DB/Context ────────────────────
        let resolvedName = '';
        const userId = cert.user_id;

        // Priority 1: live fetch from users table
        if (userId) {
          try {
            const { data: userRow } = await supabase
              .from('users')
              .select('name')
              .eq('id', userId)
              .maybeSingle();
            if (userRow?.name && userRow.name.trim() !== '') {
              resolvedName = userRow.name.trim();
            }
          } catch (e) {
            console.error('Error fetching live name:', e);
          }
        }

        // Priority 2: stored student_name
        if (!resolvedName && cert.student_name && cert.student_name !== 'Member') {
          resolvedName = cert.student_name.trim();
        }

        // Priority 3: fallback to auth profile name
        if (!resolvedName && auth?.name) {
          resolvedName = auth.name.trim();
        }

        if (!resolvedName) resolvedName = 'Member';
        // ─────────────────────────────────────────────────────────────────

        const coordinatorName = cert.events?.coordinator_name || '';
        const chairName = cert.events?.chair_name || '';

        // Replace placeholders
        html = html.replaceAll('{{student_name}}', resolvedName);
        html = html.replaceAll('{{STUDENT_NAME}}', resolvedName);
        html = html.replaceAll('{{event_name}}', eventTitle);
        html = html.replaceAll('{{EVENT_NAME}}', eventTitle);
        html = html.replaceAll('{{date}}', dateLabel);
        html = html.replaceAll('{{DATE}}', dateLabel);
        html = html.replaceAll('{{event_date}}', dateLabel);
        html = html.replaceAll('{{EVENT_DATE}}', dateLabel);
        html = html.replaceAll('{{certificate_id}}', certId);
        html = html.replaceAll('{{CERTIFICATE_ID}}', certId);
        html = html.replaceAll('{{coordinator_name}}', coordinatorName);
        html = html.replaceAll('{{COORDINATOR_NAME}}', coordinatorName);
        html = html.replaceAll('{{chair_name}}', chairName);
        html = html.replaceAll('{{CHAIR_NAME}}', chairName);

        const container = document.createElement('div');
        container.innerHTML = html;
        container.style.position = 'absolute';
        container.style.left = '-9999px';
        container.style.top = '-9999px';
        container.style.width = '1122px'; // A4 landscape at 96 DPI
        container.style.height = '793px';
        document.body.appendChild(container);

        // Allow layout to settle and remote fonts/images to load
        await new Promise(r => setTimeout(r, 1000));

        const canvas = await html2canvas(container, { scale: 2, useCORS: true });
        const imgData = canvas.toDataURL('image/png');
        
        const pdf = new jsPDF({
          orientation: 'landscape',
          unit: 'px',
          format: [1122, 793]
        });
        pdf.addImage(imgData, 'PNG', 0, 0, 1122, 793);
        pdf.save(`Certificate_${eventTitle.replace(/[^a-zA-Z0-9]/g, '_')}.pdf`);
        
        document.body.removeChild(container);
      } catch (err) {
        console.error('PDF Generation error:', err);
        alert('Failed to generate PDF from template.');
      } finally {
        setIsDownloading(false);
      }
    } else {
      window.open(url, '_blank');
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
              onClick={handleDownload}
              disabled={isDownloading}
              style={{
                flex: 1, padding: '10px 0', background: 'none', border: 'none', cursor: isDownloading ? 'wait' : 'pointer',
                display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6,
                fontFamily: "'Inter',sans-serif", fontSize: 13, fontWeight: 600, color: T.teal,
                transition: 'background 0.15s',
                opacity: isDownloading ? 0.6 : 1,
              }}
              onMouseEnter={e => !isDownloading && (e.currentTarget.style.background = `${T.teal}08`)}
              onMouseLeave={e => e.currentTarget.style.background = 'none'}
            >
              {isDownloading ? <Loader size={14} className="animate-spin" /> : <Download size={14} />} {isDownloading ? 'Downloading...' : 'Download'}
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
      try {
        // 1. Fetch certificates for current user
        const { data: certData, error: certErr } = await supabase
          .from('certificates')
          .select('id, event_id, student_name, user_id, certificate_url, file_url, issued_at')
          .eq('user_id', user.id)
          .order('issued_at', { ascending: false });

        if (certErr) throw certErr;

        const certList = certData || [];

        // 2. Fetch event details for unique event_ids
        const eventIds = [...new Set(certList.map(c => c.event_id).filter(Boolean))];
        const eventsMap = {};

        if (eventIds.length > 0) {
          const { data: eventRows, error: evErr } = await supabase
            .from('events')
            .select('id, title, date, category, type, coordinator_name, chair_name')
            .in('id', eventIds);

          if (evErr) throw evErr;

          (eventRows || []).forEach(ev => {
            eventsMap[ev.id] = ev;
          });
        }

        // 3. Normalise and merge data
        const normalised = certList.map(item => {
          const ev = eventsMap[item.event_id];
          return {
            ...item,
            events: ev || null,
            _url: item.certificate_url || item.file_url || '',
            _category: ev?.category || ev?.type || null,
            _eventTitle: ev?.title || 'Event',
            _eventDate: ev?.date || '',
            _eventId: ev?.id || item.event_id,
          };
        });

        setAll(normalised);
      } catch (err) {
        console.error('Error fetching certificates:', err);
      } finally {
        setIsLoading(false);
      }
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
