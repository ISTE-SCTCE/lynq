import { useState, useEffect } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { useAuth } from '../contexts/AuthContext';
import { supabase } from '../lib/supabase';
import DashboardLayout from '../components/DashboardLayout';
import { Calendar, Award, Bell, ChevronRight, User, Clock, MapPin, Tag } from 'lucide-react';

const CATEGORY_PILLS = ['All', 'Announcements', 'Workshops', 'Tech Talks', 'Hackathons', 'Meetups', 'Seminars'];

const EVENT_COLORS = ['#D9E9F9', '#E8E2F5', '#FBE4D5'];

function getTypeColor(type) {
  const t = (type || '').toLowerCase();
  if (t.includes('workshop') || t.includes('basics')) return '#5F85A2';
  if (t.includes('tech') || t.includes('seminar') || t.includes('geometry')) return '#9B8FCA';
  if (t.includes('meetup') || t.includes('summit') || t.includes('hack')) return '#D97D55';
  return '#D97D55';
}

export default function HomePage() {
  const { user, name, membershipId, isMembershipValid } = useAuth();
  const navigate = useNavigate();
  const [events, setEvents] = useState([]);
  const [announcements, setAnnouncements] = useState([]);
  const [attendanceCount, setAttendanceCount] = useState(0);
  const [category, setCategory] = useState('All');
  const [isLoading, setIsLoading] = useState(true);

  const avatarUrl = name ? `https://api.dicebear.com/7.x/notionists/png?seed=${encodeURIComponent(name)}` : null;

  useEffect(() => {
    const load = async () => {
      setIsLoading(true);
      const [evRes, annRes, attRes] = await Promise.all([
        supabase.from('events').select('id,title,date,location,type,description,poster_url,is_paid,member_price,non_member_price,allowed_roles').order('date', { ascending: true }),
        supabase.from('announcements').select('id,title,content,visibility,created_at').order('created_at', { ascending: false }),
        supabase.from('attendance').select('id', { count: 'exact', head: true }).eq('user_id', user.id),
      ]);
      setEvents(evRes.data || []);
      setAnnouncements(annRes.data || []);
      setAttendanceCount(attRes.count || 0);
      setIsLoading(false);
    };
    load();
  }, [user]);

  const now = new Date();
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const ongoingEvents = events.filter(e => { const d = new Date(e.date); return d.toDateString() === today.toDateString(); });
  const upcomingEvents = events.filter(e => new Date(e.date) > today);
  const pastEvents = [...events.filter(e => new Date(e.date) < today)].reverse();

  const filteredItems = (() => {
    if (category === 'All') return [...announcements.map(a => ({ ...a, _type: 'announcement' })), ...events.map(e => ({ ...e, _type: 'event' }))];
    if (category === 'Announcements') return announcements.map(a => ({ ...a, _type: 'announcement' }));
    return events.filter(e => e.type?.toLowerCase() === category.slice(0, -1).toLowerCase() || e.type?.toLowerCase().includes(category.toLowerCase().slice(0, -1))).map(e => ({ ...e, _type: 'event' }));
  })();

  return (
    <DashboardLayout>
      <div style={{ maxWidth: 900, margin: '0 auto', padding: '32px 24px' }}>
        {/* Header */}
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 32, flexWrap: 'wrap', gap: 16 }}>
          <div>
            <h1 style={{ fontFamily: "'Space Grotesk',sans-serif", fontSize: 26, fontWeight: 700, color: '#111', lineHeight: 1.2 }}>
              Hi, {name?.split(' ')[0] || 'Member'} 👋
            </h1>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 6 }}>
              <div style={{ width: 8, height: 8, borderRadius: '50%', background: isMembershipValid ? '#48BB78' : '#E53E3E' }} />
              <span style={{ fontFamily: "'Inter',sans-serif", fontSize: 13, color: '#5F85A2', fontWeight: 500 }}>
                {isMembershipValid ? 'Active Member' : 'Guest Account'}
              </span>
            </div>
          </div>
          <Link to="/profile" style={{ display: 'flex', alignItems: 'center', gap: 3, textDecoration: 'none' }}>
            {avatarUrl ? (
              <img src={avatarUrl} alt="avatar" style={{ width: 48, height: 48, borderRadius: '50%', objectFit: 'cover', border: '3px solid #D3E3F0' }} />
            ) : (
              <div style={{ width: 48, height: 48, borderRadius: '50%', background: '#D3E3F0', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                <User size={22} color="#5F85A2" />
              </div>
            )}
          </Link>
        </div>

        {/* Quick stats */}
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit,minmax(160px,1fr))', gap: 14, marginBottom: 32 }}>
          {[
            { icon: <Calendar size={20} color="#5F85A2" />, value: upcomingEvents.length, label: 'Upcoming Events', bg: '#D9E9F9', to: '/events' },
            { icon: <Award size={20} color="#D97D55" />, value: attendanceCount, label: 'Events Attended', bg: '#FBE4D5', to: '/attendance' },
            { icon: <Bell size={20} color="#9B8FCA" />, value: announcements.length, label: 'Announcements', bg: '#E8E2F5', to: '/notifications' },
          ].map(s => (
            <Link key={s.label} to={s.to} style={{ textDecoration: 'none', background: s.bg, borderRadius: 20, padding: '18px 20px', border: '2px solid rgba(95,133,162,0.15)', display: 'flex', alignItems: 'center', gap: 14 }}>
              <div style={{ width: 42, height: 42, borderRadius: 12, background: '#fff', display: 'flex', alignItems: 'center', justifyContent: 'center', boxShadow: '0 2px 8px rgba(0,0,0,0.06)' }}>
                {s.icon}
              </div>
              <div>
                <div style={{ fontFamily: "'Space Grotesk',sans-serif", fontSize: 22, fontWeight: 700, color: '#111', lineHeight: 1 }}>{s.value}</div>
                <div style={{ fontFamily: "'Inter',sans-serif", fontSize: 12, color: '#5F85A2', fontWeight: 500, marginTop: 3 }}>{s.label}</div>
              </div>
            </Link>
          ))}
        </div>

        {/* Category pills */}
        <div style={{ display: 'flex', gap: 8, overflowX: 'auto', paddingBottom: 4, marginBottom: 24, scrollbarWidth: 'none' }}>
          {CATEGORY_PILLS.map(c => (
            <button key={c} onClick={() => setCategory(c)} style={{ flexShrink: 0, padding: '8px 16px', borderRadius: 20, border: '2px solid', borderColor: category === c ? '#111' : '#D3E3F0', background: category === c ? '#111' : '#fff', color: category === c ? '#fff' : '#5F85A2', fontSize: 13, fontWeight: 600, cursor: 'pointer', fontFamily: "'Space Grotesk',sans-serif", transition: 'all 0.15s', whiteSpace: 'nowrap' }}>
              {c}
            </button>
          ))}
        </div>

        {/* Content */}
        {isLoading ? (
          <div style={{ textAlign: 'center', padding: 60 }}>
            <div style={{ width: 36, height: 36, border: '4px solid #D3E3F0', borderTopColor: '#5F85A2', borderRadius: '50%', animation: 'spin 1s linear infinite', margin: '0 auto' }} />
          </div>
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
            {filteredItems.length === 0 && (
              <div style={{ textAlign: 'center', padding: 60, color: '#5F85A2', fontFamily: "'Inter',sans-serif" }}>No items found</div>
            )}
            {filteredItems.map((item, i) => {
              if (item._type === 'announcement') return (
                <Link key={`ann-${item.id}`} to="/notifications" style={{ textDecoration: 'none', background: '#fff', borderRadius: 20, padding: '20px 22px', border: '2px solid #D3E3F0', display: 'flex', alignItems: 'flex-start', gap: 14 }}>
                  <div style={{ width: 42, height: 42, borderRadius: 12, background: '#E8E2F5', flexShrink: 0, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                    <Bell size={20} color="#9B8FCA" />
                  </div>
                  <div style={{ flex: 1 }}>
                    <div style={{ fontFamily: "'Space Grotesk',sans-serif", fontWeight: 600, color: '#111', fontSize: 15, marginBottom: 4 }}>{item.title}</div>
                    <div style={{ fontFamily: "'Inter',sans-serif", fontSize: 13, color: '#5F85A2', overflow: 'hidden', textOverflow: 'ellipsis', display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical' }}>{item.content}</div>
                  </div>
                  <ChevronRight size={18} color="#D3E3F0" style={{ flexShrink: 0, marginTop: 2 }} />
                </Link>
              );
              const color = EVENT_COLORS[i % 3];
              const typeColor = getTypeColor(item.type);
              return (
                <div key={`ev-${item.id}`} style={{ background: color, borderRadius: 20, padding: '20px 22px', border: '2px solid rgba(95,133,162,0.15)' }}>
                  <div style={{ display: 'flex', alignItems: 'flex-start', gap: 14 }}>
                    <div style={{ flex: 1 }}>
                      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 8, flexWrap: 'wrap' }}>
                        <span style={{ fontFamily: "'Space Grotesk',sans-serif", fontWeight: 700, color: '#111', fontSize: 16 }}>{item.title}</span>
                        {item.type && (
                          <span style={{ fontSize: 11, fontWeight: 600, color: typeColor, background: 'rgba(255,255,255,0.7)', borderRadius: 10, padding: '2px 8px', border: `1px solid ${typeColor}30` }}>{item.type}</span>
                        )}
                      </div>
                      <div style={{ display: 'flex', gap: 16, flexWrap: 'wrap' }}>
                        {item.date && (
                          <span style={{ display: 'flex', alignItems: 'center', gap: 5, fontFamily: "'Inter',sans-serif", fontSize: 12, color: '#5F85A2', fontWeight: 500 }}>
                            <Clock size={13} />{new Date(item.date).toLocaleDateString('en-IN', { day: 'numeric', month: 'short', year: 'numeric' })}
                          </span>
                        )}
                        {item.location && (
                          <span style={{ display: 'flex', alignItems: 'center', gap: 5, fontFamily: "'Inter',sans-serif", fontSize: 12, color: '#5F85A2', fontWeight: 500 }}>
                            <MapPin size={13} />{item.location}
                          </span>
                        )}
                      </div>
                      {item.description && (
                        <p style={{ fontFamily: "'Inter',sans-serif", fontSize: 13, color: '#5F85A2', marginTop: 8, overflow: 'hidden', textOverflow: 'ellipsis', display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical' }}>{item.description}</p>
                      )}
                    </div>
                  </div>
                  <div style={{ display: 'flex', gap: 10, marginTop: 14 }}>
                    <Link to={`/events/${item.id}`} style={{ padding: '8px 18px', background: '#111', color: '#fff', borderRadius: 20, textDecoration: 'none', fontSize: 13, fontWeight: 600, fontFamily: "'Space Grotesk',sans-serif" }}>
                      More Details
                    </Link>
                    <Link to={`/events/${item.id}`} style={{ padding: '8px 18px', background: 'rgba(95,133,162,0.15)', color: '#5F85A2', borderRadius: 20, textDecoration: 'none', fontSize: 13, fontWeight: 600, fontFamily: "'Space Grotesk',sans-serif", border: '1.5px solid rgba(95,133,162,0.25)' }}>
                      Register Now
                    </Link>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>
    </DashboardLayout>
  );
}
