import { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { useAuth } from '../contexts/AuthContext';
import { supabase } from '../lib/supabase';
import DashboardLayout from '../components/DashboardLayout';
import { ArrowLeft, Calendar, Clock, MapPin, Star, CheckCircle, Lock, DollarSign } from 'lucide-react';

function getTypeColor(type) {
  const t = (type || '').toLowerCase();
  if (t.includes('workshop') || t.includes('basics')) return '#5F85A2';
  if (t.includes('tech') || t.includes('seminar')) return '#9B8FCA';
  if (t.includes('hackathon') || t.includes('meetup')) return '#D97D55';
  return '#D97D55';
}

export default function EventDetailPage() {
  const { id } = useParams();
  const { user, role, membershipId } = useAuth();
  const navigate = useNavigate();
  const [event, setEvent] = useState(null);
  const [isAttended, setIsAttended] = useState(false);
  const [isAllowed, setIsAllowed] = useState(true);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    const load = async () => {
      setIsLoading(true);
      const [evRes, attRes] = await Promise.all([
        supabase.from('events').select().eq('id', parseInt(id)).maybeSingle(),
        supabase.from('attendance').select('id').eq('event_id', parseInt(id)).eq('user_id', user.id).limit(1),
      ]);
      const ev = evRes.data;
      setEvent(ev);
      setIsAttended((attRes.data || []).length > 0);
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

  const typeColor = getTypeColor(event.type);
  const eventDate = event.date ? new Date(event.date) : null;
  const today = new Date();
  const daysAway = eventDate ? Math.ceil((eventDate - today) / (1000*60*60*24)) : null;

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

        {/* Register CTA */}
        <button onClick={() => alert('Registration flow not connected yet.')} style={{ width: '100%', padding: '16px', background: typeColor, color: '#fff', border: 'none', borderRadius: 28, fontSize: 16, fontWeight: 700, fontFamily: "'Space Grotesk',sans-serif", cursor: 'pointer', boxShadow: `0 8px 24px ${typeColor}40` }}>
          Register Now
        </button>
      </div>
    </DashboardLayout>
  );
}
