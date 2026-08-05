import { useState, useEffect, useMemo } from 'react';
import { useAuth } from '../contexts/AuthContext';
import { supabase } from '../lib/supabase';
import DashboardLayout from '../components/DashboardLayout';
import { CalendarDays, List } from 'lucide-react';

const WEEKDAYS_SHORT = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const MONTHS_SHORT = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];

function getWeekKey(date) {
  // Get the Monday of the week
  const d = new Date(date);
  const day = (d.getDay() + 6) % 7; // Mon=0
  d.setDate(d.getDate() - day);
  return d.toISOString().slice(0, 10);
}

export default function AttendancePage() {
  const { user } = useAuth();
  const [records, setRecords] = useState([]);
  const [isLoading, setIsLoading] = useState(true);
  const [view, setView] = useState('heatmap'); // 'heatmap' | 'list'

  useEffect(() => {
    const load = async () => {
      setIsLoading(true);
      const { data } = await supabase
        .from('attendance')
        .select('id, event_id, day_number, scan_time, events(title, date, type)')
        .eq('user_id', user.id)
        .order('scan_time', { ascending: false });
      setRecords(data || []);
      setIsLoading(false);
    };
    load();
  }, [user]);

  // Build heatmap data — 52 weeks
  const heatmapData = useMemo(() => {
    const countsByDay = {};
    records.forEach(r => {
      const dateStr = r.scan_time ? r.scan_time.slice(0, 10) : (r.events?.date ? r.events.date.slice(0, 10) : null);
      if (dateStr) countsByDay[dateStr] = (countsByDay[dateStr] || 0) + 1;
    });

    // Build 52-week grid (most recent 52 weeks)
    const today = new Date();
    const startDate = new Date(today);
    const dow = (startDate.getDay() + 6) % 7; // Mon=0
    startDate.setDate(startDate.getDate() - dow - 7 * 51); // 52 weeks back to Monday

    const weeks = [];
    let cur = new Date(startDate);
    for (let w = 0; w < 53; w++) {
      const week = [];
      for (let d = 0; d < 7; d++) {
        const dateStr = cur.toISOString().slice(0, 10);
        const count = countsByDay[dateStr] || 0;
        const isFuture = cur > today;
        week.push({ date: new Date(cur), dateStr, count, isFuture });
        cur.setDate(cur.getDate() + 1);
      }
      weeks.push(week);
    }
    return { weeks, countsByDay };
  }, [records]);

  const totalAttendance = records.length;
  const thisYear = new Date().getFullYear();
  const thisYearCount = records.filter(r => {
    const d = r.scan_time || r.events?.date;
    return d && new Date(d).getFullYear() === thisYear;
  }).length;

  function getLevel(count) {
    if (count === 0) return 0;
    if (count === 1) return 1;
    if (count === 2) return 2;
    if (count <= 4) return 3;
    return 4;
  }

  return (
    <DashboardLayout>
      <div style={{ maxWidth: 900, margin: '0 auto', padding: '32px 24px' }}>
        {/* Header */}
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 28, flexWrap: 'wrap', gap: 16 }}>
          <div>
            <h1 style={{ fontFamily: "'Space Grotesk',sans-serif", fontSize: 26, fontWeight: 700, color: '#111', marginBottom: 4 }}>Attendance</h1>
            <p style={{ fontFamily: "'Inter',sans-serif", fontSize: 14, color: '#5F85A2' }}>Your event attendance history</p>
          </div>
          <div style={{ display: 'flex', background: '#fff', borderRadius: 14, border: '1.5px solid #D3E3F0', overflow: 'hidden' }}>
            {[{ key: 'heatmap', icon: <CalendarDays size={16} />, label: 'Heatmap' }, { key: 'list', icon: <List size={16} />, label: 'List' }].map(v => (
              <button key={v.key} onClick={() => setView(v.key)} style={{ display: 'flex', alignItems: 'center', gap: 6, padding: '9px 16px', background: view === v.key ? '#111' : 'transparent', color: view === v.key ? '#fff' : '#5F85A2', border: 'none', cursor: 'pointer', fontFamily: "'Inter',sans-serif", fontSize: 13, fontWeight: 600, transition: 'all 0.15s' }}>
                {v.icon} {v.label}
              </button>
            ))}
          </div>
        </div>

        {/* Stats row */}
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit,minmax(150px,1fr))', gap: 14, marginBottom: 28 }}>
          {[
            { value: totalAttendance, label: 'Total Events Attended', color: '#5F85A2', bg: '#D9E9F9' },
            { value: thisYearCount, label: `Events in ${thisYear}`, color: '#D97D55', bg: '#FBE4D5' },
            { value: new Set(records.map(r => r.event_id)).size, label: 'Unique Events', color: '#3AAFA9', bg: '#E1F3E2' },
          ].map(s => (
            <div key={s.label} style={{ background: s.bg, borderRadius: 18, padding: '18px 20px', border: '2px solid rgba(95,133,162,0.12)' }}>
              <div style={{ fontFamily: "'Space Grotesk',sans-serif", fontSize: 28, fontWeight: 700, color: '#111', lineHeight: 1 }}>{s.value}</div>
              <div style={{ fontFamily: "'Inter',sans-serif", fontSize: 12, color: s.color, fontWeight: 500, marginTop: 6 }}>{s.label}</div>
            </div>
          ))}
        </div>

        {isLoading ? (
          <div style={{ display: 'flex', justifyContent: 'center', padding: 80 }}>
            <div style={{ width: 36, height: 36, border: '4px solid #D3E3F0', borderTopColor: '#5F85A2', borderRadius: '50%', animation: 'spin 1s linear infinite' }} />
          </div>
        ) : view === 'heatmap' ? (
          /* HEATMAP VIEW */
          <div style={{ background: '#fff', borderRadius: 24, border: '2px solid #D3E3F0', padding: '28px' }}>
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 20 }}>
              <h2 style={{ fontFamily: "'Space Grotesk',sans-serif", fontSize: 16, fontWeight: 700, color: '#111' }}>
                {totalAttendance} event{totalAttendance !== 1 ? 's' : ''} attended in the last year
              </h2>
              <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                <span style={{ fontFamily: "'Inter',sans-serif", fontSize: 11, color: '#5F85A2' }}>Less</span>
                {[0, 1, 2, 3, 4].map(level => (
                  <div key={level} className={`heatmap-cell level-${level}`} />
                ))}
                <span style={{ fontFamily: "'Inter',sans-serif", fontSize: 11, color: '#5F85A2' }}>More</span>
              </div>
            </div>

            <div style={{ overflowX: 'auto' }}>
              <div style={{ display: 'flex', gap: 3, minWidth: 'max-content' }}>
                {/* Weekday labels */}
                <div style={{ display: 'flex', flexDirection: 'column', gap: 3, marginRight: 4 }}>
                  {WEEKDAYS_SHORT.map((d, i) => (
                    <div key={d} style={{ height: 14, display: 'flex', alignItems: 'center', fontFamily: "'Inter',sans-serif", fontSize: 10, color: '#5F85A2', opacity: i % 2 === 0 ? 1 : 0 }}>
                      {d}
                    </div>
                  ))}
                </div>

                {/* Month labels + cells */}
                <div>
                  {/* Month labels */}
                  <div style={{ display: 'flex', marginBottom: 4 }}>
                    {heatmapData.weeks.map((week, wi) => {
                      const firstOfMonth = week.find(d => d.date.getDate() === 1);
                      return (
                        <div key={wi} style={{ width: 14, marginRight: 3, fontFamily: "'Inter',sans-serif", fontSize: 10, color: '#5F85A2', flexShrink: 0 }}>
                          {firstOfMonth ? MONTHS_SHORT[firstOfMonth.date.getMonth()] : ''}
                        </div>
                      );
                    })}
                  </div>

                  {/* Grid */}
                  <div style={{ display: 'flex', gap: 3 }}>
                    {heatmapData.weeks.map((week, wi) => (
                      <div key={wi} style={{ display: 'flex', flexDirection: 'column', gap: 3 }}>
                        {week.map(day => (
                          <div
                            key={day.dateStr}
                            className={`heatmap-cell level-${day.isFuture ? 0 : getLevel(day.count)}`}
                            title={`${day.dateStr}: ${day.count} event${day.count !== 1 ? 's' : ''}`}
                            style={{ opacity: day.isFuture ? 0.3 : 1 }}
                          />
                        ))}
                      </div>
                    ))}
                  </div>
                </div>
              </div>
            </div>

            {totalAttendance === 0 && (
              <div style={{ textAlign: 'center', paddingTop: 24, borderTop: '1px solid #D3E3F0', marginTop: 20 }}>
                <p style={{ fontFamily: "'Inter',sans-serif", fontSize: 13, color: '#5F85A2' }}>No attendance recorded yet. Start attending events!</p>
              </div>
            )}
          </div>
        ) : (
          /* LIST VIEW */
          <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
            {records.length === 0 ? (
              <div style={{ background: '#fff', borderRadius: 20, border: '2px solid #D3E3F0', padding: '60px 24px', textAlign: 'center' }}>
                <div style={{ fontSize: 40, marginBottom: 14 }}>📋</div>
                <p style={{ fontFamily: "'Space Grotesk',sans-serif", fontWeight: 600, fontSize: 16, color: '#111', marginBottom: 6 }}>No attendance records</p>
                <p style={{ fontFamily: "'Inter',sans-serif", fontSize: 13, color: '#5F85A2' }}>Attend events with your QR code to build your record</p>
              </div>
            ) : records.map((rec, i) => {
              const eventTitle = rec.events?.title || `Event #${rec.event_id}`;
              const eventType = rec.events?.type || '';
              const scanDate = rec.scan_time ? new Date(rec.scan_time) : (rec.events?.date ? new Date(rec.events.date) : null);
              return (
                <div key={rec.id} style={{ background: '#fff', borderRadius: 18, border: '2px solid #D3E3F0', padding: '16px 20px', display: 'flex', alignItems: 'center', gap: 16 }} className="fade-in">
                  <div style={{ width: 42, height: 42, borderRadius: 12, background: '#D9E9F9', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0, fontFamily: "'Space Grotesk',sans-serif", fontWeight: 700, fontSize: 16, color: '#5F85A2' }}>
                    {i + 1}
                  </div>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ fontFamily: "'Space Grotesk',sans-serif", fontWeight: 700, color: '#111', fontSize: 15, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{eventTitle}</div>
                    <div style={{ display: 'flex', gap: 10, marginTop: 4, flexWrap: 'wrap' }}>
                      {eventType && <span style={{ fontFamily: "'Inter',sans-serif", fontSize: 11, color: '#5F85A2', background: '#EBF3FC', borderRadius: 8, padding: '2px 8px', fontWeight: 600 }}>{eventType}</span>}
                      {rec.day_number > 1 && <span style={{ fontFamily: "'Inter',sans-serif", fontSize: 11, color: '#D97D55', fontWeight: 600 }}>Day {rec.day_number}</span>}
                    </div>
                  </div>
                  <div style={{ textAlign: 'right', flexShrink: 0 }}>
                    {scanDate && (
                      <>
                        <div style={{ fontFamily: "'Inter',sans-serif", fontSize: 12, color: '#5F85A2', fontWeight: 500 }}>{scanDate.toLocaleDateString('en-IN', { day: 'numeric', month: 'short', year: 'numeric' })}</div>
                        <div style={{ fontFamily: "'Inter',sans-serif", fontSize: 11, color: '#aaa' }}>{scanDate.toLocaleTimeString('en-IN', { hour: '2-digit', minute: '2-digit' })}</div>
                      </>
                    )}
                    <div style={{ display: 'flex', alignItems: 'center', gap: 4, justifyContent: 'flex-end', marginTop: 4 }}>
                      <div style={{ width: 8, height: 8, borderRadius: '50%', background: '#48BB78' }} />
                      <span style={{ fontFamily: "'Inter',sans-serif", fontSize: 11, color: '#48BB78', fontWeight: 600 }}>Attended</span>
                    </div>
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
