import { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { useAuth } from '../contexts/AuthContext';
import { supabase } from '../lib/supabase';
import DashboardLayout from '../components/DashboardLayout';
import { ArrowLeft, Calendar, Clock, MapPin, Star, CheckCircle, Lock, DollarSign, Award, Download, Eye, Loader2 } from 'lucide-react';
import jsPDF from 'jspdf';
import html2canvas from 'html2canvas';

function getTypeColor(type) {
  const t = (type || '').toLowerCase();
  if (t.includes('workshop') || t.includes('basics')) return '#5F85A2';
  if (t.includes('tech') || t.includes('seminar')) return '#9B8FCA';
  if (t.includes('hackathon') || t.includes('meetup')) return '#D97D55';
  return '#D97D55';
}

// ── Certificate section (past + attended events) ───────────────────────────────
function CertificateSection({ certificate, finalized, eventTitle, eventId }) {
  const auth = useAuth();
  const url = certificate?.certificate_url || certificate?.file_url || '';
  const issuedAt = certificate?.issued_at
    ? new Date(certificate.issued_at).toLocaleDateString('en-IN', { day: 'numeric', month: 'long', year: 'numeric' })
    : '';

  const [isDownloading, setIsDownloading] = useState(false);

  const handleDownload = async (e) => {
    if (e) e.stopPropagation();
    if (!url) return;

    if (url.startsWith('template:') || url.toLowerCase().endsWith('.html') || url.toLowerCase().includes('.html?')) {
      if (isDownloading) return;
      setIsDownloading(true);
      try {
        const templatePath = url.replace('template:', '');
        
        let templateHtmlUrl = templatePath;
        if (!templatePath.startsWith('http')) {
          const { data } = await supabase.storage.from('event_posters').createSignedUrl(templatePath, 60);
          templateHtmlUrl = data?.signedUrl || templatePath;
        }

        const res = await fetch(templateHtmlUrl);
        let html = await res.text();
        
        const certId = `ISTE-${eventId}-${(certificate.user_id || '').replace(/-/g, '').substring(0,6).toUpperCase()}`;

        // ── Resolve live student name from DB/Context ────────────────────
        let resolvedName = '';
        const userId = certificate.user_id || auth.user?.id;

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
          } catch (err) {
            console.error('Error fetching live name:', err);
          }
        }

        // Priority 2: stored student_name
        if (!resolvedName && certificate.student_name && certificate.student_name !== 'Member') {
          resolvedName = certificate.student_name.trim();
        }

        // Priority 3: fallback to auth profile name
        if (!resolvedName && auth?.name) {
          resolvedName = auth.name.trim();
        }

        if (!resolvedName) resolvedName = 'Member';
        // ─────────────────────────────────────────────────────────────────

        // Replace placeholders
        html = html.replaceAll('{{student_name}}', resolvedName);
        html = html.replaceAll('{{event_name}}', eventTitle || 'Event');
        html = html.replaceAll('{{date}}', issuedAt || '');
        html = html.replaceAll('{{certificate_id}}', certId);

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
        pdf.save(`Certificate_${(eventTitle || 'Event').replace(/[^a-zA-Z0-9]/g, '_')}.pdf`);
        
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

  if (certificate && url) {
    const isTemplateUrl = url.startsWith('template:') || url.toLowerCase().endsWith('.html') || url.toLowerCase().includes('.html?');

    return (
      <div style={{
        borderRadius: 18, marginBottom: 20, overflow: 'hidden',
        border: '1.5px solid rgba(201,162,39,0.4)',
        background: 'linear-gradient(135deg, rgba(201,162,39,0.10) 0%, #FFFDF8 80%)',
      }}>
        {/* Header row */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 14, padding: '16px 18px 12px' }}>
          <div style={{
            width: 46, height: 46, borderRadius: '50%', flexShrink: 0,
            background: 'radial-gradient(circle, rgba(201,162,39,0.25), rgba(201,162,39,0.06))',
            border: '1.5px solid rgba(201,162,39,0.55)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>
            <Award size={22} color="#C9A227" />
          </div>
          <div>
            <div style={{
              fontFamily: "'Space Grotesk',sans-serif", fontSize: 15, fontWeight: 700, color: '#1B2A4A',
            }}>
              Your Certificate is Ready
            </div>
            {issuedAt && (
              <div style={{ fontFamily: "'Inter',sans-serif", fontSize: 11, color: '#8a8371' }}>
                Issued {issuedAt}
              </div>
            )}
          </div>
        </div>

        {/* Divider */}
        <div style={{ height: 1, background: '#EFE9D8' }} />

        {/* Action buttons */}
        <div style={{ display: 'flex' }}>
          <button
            onClick={handleDownload}
            disabled={isDownloading}
            style={{
              flex: 1, padding: '11px 0', background: 'none', border: 'none', cursor: isDownloading ? 'wait' : 'pointer',
              display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6,
              fontFamily: "'Inter',sans-serif", fontSize: 13, fontWeight: 600, color: '#1B2A4A',
              transition: 'background 0.15s',
              opacity: isDownloading ? 0.6 : 1,
            }}
            onMouseEnter={e => !isDownloading && (e.currentTarget.style.background = 'rgba(27,42,74,0.06)')}
            onMouseLeave={e => e.currentTarget.style.background = 'none'}
          >
            <Eye size={15} /> {isDownloading ? 'Loading...' : 'View'}
          </button>
          <div style={{ width: 1, background: '#EFE9D8' }} />
          <button
            onClick={handleDownload}
            disabled={isDownloading}
            style={{
              flex: 1, padding: '11px 0', background: 'none', border: 'none', cursor: isDownloading ? 'wait' : 'pointer',
              display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6,
              fontFamily: "'Inter',sans-serif", fontSize: 13, fontWeight: 600, color: '#2F6F6E',
              transition: 'background 0.15s',
              opacity: isDownloading ? 0.6 : 1,
            }}
            onMouseEnter={e => !isDownloading && (e.currentTarget.style.background = 'rgba(47,111,110,0.06)')}
            onMouseLeave={e => e.currentTarget.style.background = 'none'}
          >
            <Download size={15} /> {isDownloading ? 'Downloading...' : 'Download PDF'}
          </button>
        </div>
      </div>
    );
  }

  if (finalized) {
    return (
      <div style={{
        display: 'flex', alignItems: 'center', gap: 12,
        background: 'rgba(245,197,62,0.08)', border: '1px solid rgba(245,197,62,0.3)',
        borderRadius: 14, padding: '12px 16px', marginBottom: 20,
      }}>
        <Loader2 size={18} color="#C9A227" style={{ animation: 'spin 1s linear infinite', flexShrink: 0 }} />
        <span style={{ fontFamily: "'Inter',sans-serif", fontSize: 13, fontWeight: 500, color: '#9a7c10' }}>
          Your certificate is being generated…
        </span>
        <style>{`@keyframes spin { from { transform: rotate(0deg); } to { transform: rotate(360deg); } }`}</style>
      </div>
    );
  }

  return null;
}

export default function EventDetailPage() {
  const { id } = useParams();
  const { user, role, membershipId } = useAuth();
  const navigate = useNavigate();
  const [event, setEvent] = useState(null);
  const [isAttended, setIsAttended] = useState(false);
  const [isAllowed, setIsAllowed] = useState(true);
  const [isLoading, setIsLoading] = useState(true);
  const [certificate, setCertificate] = useState(null);
  const [finalized, setFinalized] = useState(false);

  useEffect(() => {
    const load = async () => {
      setIsLoading(true);
      const [evRes, attRes, certRes] = await Promise.all([
        supabase.from('events').select().eq('id', parseInt(id)).maybeSingle(),
        supabase.from('attendance').select('id').eq('event_id', parseInt(id)).eq('user_id', user.id).limit(1),
        supabase.from('certificates')
          .select('id, certificate_url, file_url, issued_at, student_name, user_id')
          .eq('event_id', parseInt(id))
          .eq('user_id', user.id)
          .maybeSingle(),
      ]);
      const ev = evRes.data;
      setEvent(ev);
      setIsAttended((attRes.data || []).length > 0);
      setCertificate(certRes.data || null);
      setFinalized(ev?.attendance_finalized ?? false);
      if (ev?.allowed_roles?.length > 0) {
        setIsAllowed(ev.allowed_roles.includes(role));
      }
      setIsLoading(false);
    };
    load();
  }, [id, user, role]);

  if (isLoading) return (
    <DashboardLayout>
      <div style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', height: '60vh' }}>
        <div style={{ width: 36, height: 36, border: '4px solid #D3E3F0', borderTopColor: '#5F85A2', borderRadius: '50%', animation: 'spin 1s linear infinite' }} />
        <style>{`@keyframes spin { from { transform: rotate(0deg); } to { transform: rotate(360deg); } }`}</style>
      </div>
    </DashboardLayout>
  );

  if (!event) return (
    <DashboardLayout>
      <div style={{ textAlign: 'center', padding: 80 }}>
        <p style={{ fontFamily: "'Space Grotesk',sans-serif", fontSize: 18, color: '#5F85A2' }}>Event not found.</p>
        <button onClick={() => navigate('/events')} style={{ marginTop: 16, padding: '10px 20px', background: '#111', color: '#fff', borderRadius: 20, border: 'none', cursor: 'pointer', fontFamily: "'Inter',sans-serif", fontWeight: 600 }}>Back to Events</button>
      </div>
    </DashboardLayout>
  );

  if (!isAllowed) return (
    <DashboardLayout>
      <div style={{ textAlign: 'center', padding: 80 }}>
        <Lock size={56} color="#D3E3F0" style={{ marginBottom: 20 }} />
        <h2 style={{ fontFamily: "'Space Grotesk',sans-serif", fontSize: 22, fontWeight: 700, color: '#111', marginBottom: 10 }}>Event Not Available</h2>
        <p style={{ fontFamily: "'Inter',sans-serif", fontSize: 14, color: '#5F85A2' }}>This event is not available for your membership role.</p>
        <button onClick={() => navigate('/events')} style={{ marginTop: 20, padding: '10px 20px', background: '#111', color: '#fff', borderRadius: 20, border: 'none', cursor: 'pointer', fontFamily: "'Inter',sans-serif", fontWeight: 600 }}>Back to Events</button>
      </div>
    </DashboardLayout>
  );

  const typeColor = getTypeColor(event.type || event.category);
  const eventDate = event.date ? new Date(event.date) : null;
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const isPast = eventDate ? eventDate < today : false;
  const daysAway = eventDate ? Math.ceil((eventDate - today) / (1000 * 60 * 60 * 24)) : null;

  const perks = Array.isArray(event.perks) ? event.perks : (typeof event.perks === 'string' ? [event.perks] : []);
  const posters = Array.isArray(event.posters) ? event.posters : (event.poster_url ? [event.poster_url] : []);

  const priceLabel = !event.is_paid ? 'Free' : membershipId ? `₹${event.member_price} (Member)` : `₹${event.non_member_price} (Non-member)`;

  return (
    <DashboardLayout>
      <div style={{ maxWidth: 720, margin: '0 auto', padding: '24px' }}>
        {/* Back */}
        <button onClick={() => navigate('/events')} style={{ display: 'flex', alignItems: 'center', gap: 8, background: '#111', border: 'none', color: '#fff', padding: '9px 16px', borderRadius: 20, cursor: 'pointer', fontFamily: "'Space Grotesk',sans-serif", fontWeight: 600, fontSize: 14, marginBottom: 24 }}>
          <ArrowLeft size={16} /> Back
        </button>

        {/* Hero poster */}
        {posters.length > 0 ? (
          <div style={{ borderRadius: 24, overflow: 'hidden', marginBottom: 24, aspectRatio: '16/7', position: 'relative' }}>
            <img src={posters[0]} alt={event.title} style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
            <div style={{ position: 'absolute', inset: 0, background: 'linear-gradient(to top, rgba(0,0,0,0.6) 0%, transparent 50%)' }} />
            <div style={{ position: 'absolute', bottom: 20, left: 20, right: 20 }}>
              {daysAway !== null && (
                <span style={{ background: daysAway <= 0 ? '#D97D55' : 'rgba(0,0,0,0.6)', color: '#fff', borderRadius: 20, padding: '4px 12px', fontSize: 12, fontWeight: 700, fontFamily: "'Space Grotesk',sans-serif", marginBottom: 8, display: 'inline-block' }}>
                  {daysAway <= 0 ? '🔥 Today!' : `${daysAway} days away`}
                </span>
              )}
              <h1 style={{ fontFamily: "'Space Grotesk',sans-serif", fontSize: 24, fontWeight: 700, color: '#fff', textShadow: '0 2px 8px rgba(0,0,0,0.5)' }}>{event.title}</h1>
            </div>
          </div>
        ) : (
          <div style={{ background: `${typeColor}20`, borderRadius: 24, padding: '40px 24px', marginBottom: 24, textAlign: 'center', border: `2px solid ${typeColor}40` }}>
            {daysAway !== null && (
              <div style={{ marginBottom: 12 }}>
                <span style={{ background: typeColor, color: '#fff', borderRadius: 20, padding: '4px 14px', fontSize: 12, fontWeight: 700, fontFamily: "'Space Grotesk',sans-serif" }}>
                  {daysAway <= 0 ? '🔥 Today!' : `${daysAway} days away`}
                </span>
              </div>
            )}
            <h1 style={{ fontFamily: "'Space Grotesk',sans-serif", fontSize: 26, fontWeight: 700, color: '#111' }}>{event.title}</h1>
            {event.type && <p style={{ color: typeColor, fontWeight: 600, fontFamily: "'Inter',sans-serif", marginTop: 6 }}>{event.type}</p>}
          </div>
        )}

        {/* Attendance status */}
        {isAttended && (
          <div style={{ display: 'flex', alignItems: 'center', gap: 10, background: '#F0FFF4', border: '1.5px solid #9AE6B4', borderRadius: 16, padding: '14px 18px', marginBottom: 20 }}>
            <CheckCircle size={20} color="#38A169" />
            <span style={{ fontFamily: "'Space Grotesk',sans-serif", fontWeight: 600, color: '#276749', fontSize: 14 }}>You attended this event ✓</span>
          </div>
        )}

        {/* ── Certificate section (past + attended only) ─────────────────── */}
        {isPast && isAttended && (
          <CertificateSection certificate={certificate} finalized={finalized} eventTitle={event.title} eventId={event.id} />
        )}

        {/* Info cards */}
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit,minmax(200px,1fr))', gap: 14, marginBottom: 24 }}>
          {[
            { icon: <Calendar size={18} color={typeColor} />, label: 'Date', value: eventDate ? eventDate.toLocaleDateString('en-IN', { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' }) : 'TBA' },
            event.time && { icon: <Clock size={18} color={typeColor} />, label: 'Time', value: event.time },
            (event.venue || event.location) && { icon: <MapPin size={18} color={typeColor} />, label: 'Venue', value: event.venue || event.location },
            { icon: <DollarSign size={18} color={typeColor} />, label: 'Price', value: priceLabel },
          ].filter(Boolean).map(info => (
            <div key={info.label} style={{ background: '#111', borderRadius: 16, padding: '16px 18px', display: 'flex', alignItems: 'flex-start', gap: 12 }}>
              <div style={{ marginTop: 2 }}>{info.icon}</div>
              <div>
                <div style={{ fontFamily: "'Inter',sans-serif", fontSize: 11, color: 'rgba(255,255,255,0.5)', fontWeight: 600, marginBottom: 4 }}>{info.label.toUpperCase()}</div>
                <div style={{ fontFamily: "'Inter',sans-serif", fontSize: 14, color: '#fff', fontWeight: 500 }}>{info.value}</div>
              </div>
            </div>
          ))}
        </div>

        {/* About */}
        {event.description && (
          <div style={{ background: '#fff', borderRadius: 20, border: '2px solid #D3E3F0', padding: '22px', marginBottom: 16 }}>
            <h2 style={{ fontFamily: "'Space Grotesk',sans-serif", fontSize: 17, fontWeight: 700, color: '#111', marginBottom: 12 }}>About</h2>
            <p style={{ fontFamily: "'Inter',sans-serif", fontSize: 14, color: '#5F85A2', lineHeight: 1.7 }}>{event.description}</p>
          </div>
        )}

        {/* Details */}
        {event.details && (
          <div style={{ background: '#fff', borderRadius: 20, border: '2px solid #D3E3F0', padding: '22px', marginBottom: 16 }}>
            <h2 style={{ fontFamily: "'Space Grotesk',sans-serif", fontSize: 17, fontWeight: 700, color: '#111', marginBottom: 12 }}>Event Details</h2>
            <p style={{ fontFamily: "'Inter',sans-serif", fontSize: 14, color: '#5F85A2', lineHeight: 1.7, whiteSpace: 'pre-wrap' }}>{event.details}</p>
          </div>
        )}

        {/* Perks */}
        {perks.length > 0 && (
          <div style={{ background: '#fff', borderRadius: 20, border: '2px solid #D3E3F0', padding: '22px', marginBottom: 24 }}>
            <h2 style={{ fontFamily: "'Space Grotesk',sans-serif", fontSize: 17, fontWeight: 700, color: '#111', marginBottom: 14 }}>Perks & Highlights</h2>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
              {perks.map((perk, i) => (
                <div key={i} style={{ display: 'flex', alignItems: 'flex-start', gap: 10 }}>
                  <Star size={16} color="#F5C842" style={{ flexShrink: 0, marginTop: 2 }} />
                  <span style={{ fontFamily: "'Inter',sans-serif", fontSize: 14, color: '#5F85A2' }}>{perk}</span>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Register CTA (only for upcoming/ongoing events) */}
        {!isPast && (
          <button onClick={() => alert('Registration flow not connected yet.')} style={{ width: '100%', padding: '16px', background: typeColor, color: '#fff', border: 'none', borderRadius: 28, fontSize: 16, fontWeight: 700, fontFamily: "'Space Grotesk',sans-serif", cursor: 'pointer', boxShadow: `0 8px 24px ${typeColor}40` }}>
            Register Now
          </button>
        )}
      </div>

      <style>{`@keyframes spin { from { transform: rotate(0deg); } to { transform: rotate(360deg); } }`}</style>
    </DashboardLayout>
  );
}
