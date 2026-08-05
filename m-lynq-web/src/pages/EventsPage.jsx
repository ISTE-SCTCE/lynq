import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '../contexts/AuthContext';
import { supabase } from '../lib/supabase';
import DashboardLayout from '../components/DashboardLayout';
import { ChevronLeft, ChevronRight, MapPin, Clock } from 'lucide-react';

const WEEKDAYS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const MONTHS = ['January','February','March','April','May','June','July','August','September','October','November','December'];

function getTypeColor(type) {
  const t = (type || '').toLowerCase();
  if (t.includes('workshop') || t.includes('basics')) return '#5F85A2';
  if (t.includes('tech') || t.includes('seminar')) return '#9B8FCA';
  if (t.includes('hackathon') || t.includes('meetup')) return '#D97D55';
  return '#3AAFA9';
}

function isSameDay(a, b) {
  return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
}

export default function EventsPage() {
  const { role, membershipId } = useAuth();
  const navigate = useNavigate();
  const [events, setEvents] = useState([]);
  const [isLoading, setIsLoading] = useState(true);
  const [currentDate, setCurrentDate] = useState(new Date());
  const [selectedDate, setSelectedDate] = useState(new Date());

  useEffect(() => {
    const load = async () => {
      setIsLoading(true);
      const { data } = await supabase.from('events').select().order('date', { ascending: true });
      const effectiveRole = role === 'user' ? 'restricted' : role;
      const filtered = (data || []).filter(e => {
        if (!e.allowed_roles || e.allowed_roles.length === 0) return true;
        return e.allowed_roles.includes(effectiveRole);
      });
      setEvents(filtered);
      setIsLoading(false);
    };
    load();
  }, [role]);

  const year = currentDate.getFullYear();
  const month = currentDate.getMonth();
  const firstDay = new Date(year, month, 1);
  const startDow = (firstDay.getDay() + 6) % 7; // Monday=0
  const daysInMonth = new Date(year, month + 1, 0).getDate();

  // Build calendar cells
  const cells = [];
  for (let i = 0; i < startDow; i++) cells.push(null);
  for (let d = 1; d <= daysInMonth; d++) cells.push(new Date(year, month, d));

  const eventDates = events.map(e => new Date(e.date));
  const selectedEvents = events.filter(e => isSameDay(new Date(e.date), selectedDate));

  const getPriceLabel = (e) => {
    if (!e.is_paid) return 'Free';
    if (membershipId) return `₹${e.member_price}`;
    return `₹${e.non_member_price}`;
  };

  return (
    <DashboardLayout>
      <div style={{ maxWidth: 900, margin: '0 auto', padding: '32px 24px' }}>
        <h1 style={{ fontFamily: "'Space Grotesk',sans-serif", fontSize: 26, fontWeight: 700, color: '#111', marginBottom: 6 }}>Course Schedule</h1>
        <p style={{ fontFamily: "'Inter',sans-serif", fontSize: 14, color: '#5F85A2', marginBottom: 28 }}>Browse and plan your event attendance</p>

        {/* Calendar card */}
        <div style={{ background: '#fff', borderRadius: 24, border: '2px solid #D3E3F0', padding: '24px', marginBottom: 24 }}>
          {/* Month navigation */}
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 20 }}>
            <button onClick={() => setCurrentDate(new Date(year, month - 1, 1))} style={chevBtn}>
              <ChevronLeft size={20} />
            </button>
            <h2 style={{ fontFamily: "'Space Grotesk',sans-serif", fontSize: 18, fontWeight: 700, color: '#111' }}>
              {MONTHS[month]} {year}
            </h2>
            <button onClick={() => setCurrentDate(new Date(year, month + 1, 1))} style={chevBtn}>
              <ChevronRight size={20} />
            </button>
          </div>

          {/* Day headers */}
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7,1fr)', gap: 4, marginBottom: 8 }}>
            {WEEKDAYS.map(d => (
              <div key={d} style={{ textAlign: 'center', fontFamily: "'Inter',sans-serif", fontSize: 11, fontWeight: 700, color: '#5F85A2', padding: '4px 0' }}>{d}</div>
            ))}
          </div>

          {/* Calendar grid */}
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7,1fr)', gap: 4 }}>
            {cells.map((date, i) => {
              if (!date) return <div key={`e-${i}`} />;
              const isToday = isSameDay(date, new Date());
              const isSelected = isSameDay(date, selectedDate);
              const hasEvent = eventDates.some(d => isSameDay(d, date));
              const isCurrentMonth = date.getMonth() === month;
              return (
                <button key={date.toISOString()} onClick={() => setSelectedDate(date)} style={{
                  width: '100%', aspectRatio: '1', borderRadius: '50%', border: isToday && !isSelected ? '2px solid #111' : 'none',
                  background: isSelected ? '#111' : hasEvent ? '#D3E3F0' : 'transparent',
                  color: isSelected ? '#fff' : isCurrentMonth ? '#111' : '#ccc',
                  fontFamily: "'Inter',sans-serif", fontSize: 13, fontWeight: isSelected || hasEvent ? 600 : 400,
                  cursor: 'pointer', transition: 'all 0.15s', display: 'flex', alignItems: 'center', justifyContent: 'center',
                  position: 'relative',
                }}>
                  {date.getDate()}
                  {hasEvent && !isSelected && (
                    <span style={{ position: 'absolute', bottom: 3, left: '50%', transform: 'translateX(-50%)', width: 4, height: 4, borderRadius: '50%', background: '#5F85A2' }} />
                  )}
                </button>
              );
            })}
          </div>
        </div>

        {/* Selected date events */}
        <div>
          <h3 style={{ fontFamily: "'Space Grotesk',sans-serif", fontSize: 16, fontWeight: 700, color: '#111', marginBottom: 14 }}>
            {isSameDay(selectedDate, new Date()) ? "Today's Events" : `Events on ${selectedDate.toLocaleDateString('en-IN', { day: 'numeric', month: 'long' })}`}
          </h3>

          {isLoading ? (
            <div style={{ textAlign: 'center', padding: 40 }}>
              <div style={{ width: 32, height: 32, border: '4px solid #D3E3F0', borderTopColor: '#5F85A2', borderRadius: '50%', animation: 'spin 1s linear infinite', margin: '0 auto' }} />
            </div>
          ) : selectedEvents.length === 0 ? (
            <div style={{ background: '#fff', borderRadius: 20, border: '2px solid #D3E3F0', padding: '40px 24px', textAlign: 'center' }}>
              <div style={{ fontSize: 36, marginBottom: 10 }}>📅</div>
              <p style={{ fontFamily: "'Space Grotesk',sans-serif", fontWeight: 600, color: '#111', marginBottom: 6 }}>No events this day</p>
              <p style={{ fontFamily: "'Inter',sans-serif", fontSize: 13, color: '#5F85A2' }}>Select another date or check upcoming events</p>
            </div>
          ) : (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
              {selectedEvents.map(ev => (
                <div key={ev.id} onClick={() => navigate(`/events/${ev.id}`)} style={{ background: '#fff', borderRadius: 20, border: '2px solid #D3E3F0', padding: '18px 20px', cursor: 'pointer', transition: 'border-color 0.15s', display: 'flex', gap: 16, alignItems: 'center' }}
                  onMouseEnter={e => e.currentTarget.style.borderColor = '#5F85A2'}
                  onMouseLeave={e => e.currentTarget.style.borderColor = '#D3E3F0'}>
                  <div style={{ width: 48, height: 48, borderRadius: 14, background: `${getTypeColor(ev.type)}20`, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
                    <span style={{ fontSize: 22 }}>📚</span>
                  </div>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ fontFamily: "'Space Grotesk',sans-serif", fontWeight: 700, color: '#111', fontSize: 15, marginBottom: 6 }}>{ev.title}</div>
                    <div style={{ display: 'flex', gap: 14, flexWrap: 'wrap' }}>
                      {ev.location && <span style={{ display: 'flex', alignItems: 'center', gap: 4, fontFamily: "'Inter',sans-serif", fontSize: 12, color: '#5F85A2' }}><MapPin size={13} />{ev.location}</span>}
                      <span style={{ fontFamily: "'Inter',sans-serif", fontSize: 12, color: '#D97D55', fontWeight: 600 }}>{getPriceLabel(ev)}</span>
                    </div>
                  </div>
                  <ChevronRight size={20} color="#D3E3F0" />
                </div>
              ))}
            </div>
          )}

          {/* All upcoming events list */}
          {selectedEvents.length === 0 && (
            <>
              <h3 style={{ fontFamily: "'Space Grotesk',sans-serif", fontSize: 16, fontWeight: 700, color: '#111', margin: '28px 0 14px' }}>All Upcoming Events</h3>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
                {events.filter(e => new Date(e.date) >= new Date()).slice(0, 10).map(ev => (
                  <div key={ev.id} onClick={() => navigate(`/events/${ev.id}`)} style={{ background: '#fff', borderRadius: 20, border: '2px solid #D3E3F0', padding: '18px 20px', cursor: 'pointer', display: 'flex', gap: 16, alignItems: 'center' }}
                    onMouseEnter={e => e.currentTarget.style.borderColor = '#5F85A2'}
                    onMouseLeave={e => e.currentTarget.style.borderColor = '#D3E3F0'}>
                    <div style={{ width: 48, height: 48, borderRadius: 14, background: `${getTypeColor(ev.type)}20`, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
                      <Clock size={20} color={getTypeColor(ev.type)} />
                    </div>
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <div style={{ fontFamily: "'Space Grotesk',sans-serif", fontWeight: 700, color: '#111', fontSize: 15, marginBottom: 4 }}>{ev.title}</div>
                      <div style={{ display: 'flex', gap: 12, flexWrap: 'wrap', alignItems: 'center' }}>
                        <span style={{ fontFamily: "'Inter',sans-serif", fontSize: 12, color: '#5F85A2' }}>{new Date(ev.date).toLocaleDateString('en-IN', { day: 'numeric', month: 'short', year: 'numeric' })}</span>
                        {ev.location && <span style={{ display: 'flex', alignItems: 'center', gap: 3, fontFamily: "'Inter',sans-serif", fontSize: 12, color: '#5F85A2' }}><MapPin size={12} />{ev.location}</span>}
                        <span style={{ fontFamily: "'Inter',sans-serif", fontSize: 12, color: '#D97D55', fontWeight: 600 }}>{getPriceLabel(ev)}</span>
                      </div>
                    </div>
                    <ChevronRight size={20} color="#D3E3F0" />
                  </div>
                ))}
              </div>
            </>
          )}
        </div>
      </div>
    </DashboardLayout>
  );
}

const chevBtn = {
  width: 36, height: 36, borderRadius: 10, background: '#EBF3FC', border: '1.5px solid #D3E3F0',
  display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer', color: '#5F85A2',
};
