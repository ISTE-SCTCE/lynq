import React, { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { ArrowLeft, RefreshCw, Download, Loader, Users } from 'lucide-react';
import { supabase } from '../../core/supabase-client';
import { useAuth } from '../../core/auth-provider';
import { GlassCard } from '../../shared/components/GlassCard';
import { NavBar } from '../../shared/components/NavBar';
import { EventModel } from '../../models/types';

interface AttendeeLog {
  user_id: string;
  name: string;
  roll_number: string;
  branch: string;
  year: string;
  email: string;
  time: string | null;
  day_number: number;
}

export const AttendanceReportScreen: React.FC = () => {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { currentUser } = useAuth();

  const [event, setEvent] = useState<EventModel | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [attendanceByDay, setAttendanceByDay] = useState<Record<number, AttendeeLog[]>>({});
  const [activeTabDay, setActiveTabDay] = useState<number>(1);
  const numDays = event?.num_days || 1;

  const loadAttendance = async () => {
    if (!id) return;
    setIsLoading(true);
    try {
      // 1. Fetch Event Info
      const { data: eventRow, error: eErr } = await supabase
        .from('events')
        .select('*')
        .eq('id', parseInt(id))
        .maybeSingle();

      if (eErr) throw eErr;
      if (eventRow) {
        setEvent(eventRow as EventModel);
      }

      // 2. Fetch Attendance Rows
      const { data: attendanceRows, error: aErr } = await supabase
        .from('attendance')
        .select('user_id, day_number, scan_time')
        .eq('event_id', parseInt(id))
        .order('day_number', { ascending: true })
        .order('scan_time', { ascending: true });

      if (aErr) throw aErr;
      const rows = attendanceRows || [];

      // 3. Fetch User Details
      const userIds = Array.from(new Set(rows.map(r => r.user_id)));
      const usersMap = new Map<string, any>();
      
      if (userIds.length > 0) {
        const { data: usersRows, error: uErr } = await supabase
          .from('users')
          .select('id, name, roll_number, branch, year, email')
          .in('id', userIds);

        if (uErr) throw uErr;
        (usersRows || []).forEach(u => {
          usersMap.set(u.id, u);
        });
      }

      // 4. Group by day_number
      const grouped: Record<number, AttendeeLog[]> = {};
      rows.forEach(r => {
        const day = r.day_number || 1;
        const user = usersMap.get(r.user_id);
        if (!grouped[day]) {
          grouped[day] = [];
        }
        grouped[day].push({
          user_id: r.user_id,
          name: user?.name || 'Unknown',
          roll_number: user?.roll_number || '-',
          branch: user?.branch || '-',
          year: user?.year?.toString() || '-',
          email: user?.email || '-',
          time: r.scan_time,
          day_number: day
        });
      });

      setAttendanceByDay(grouped);
    } catch (e) {
      console.error('Error loading attendance report:', e);
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    loadAttendance();
  }, [id]);

  const handleExportCSV = () => {
    const list = attendanceByDay[activeTabDay] || [];
    if (list.length === 0) {
      alert(`No attendance logs to export for Day ${activeTabDay}`);
      return;
    }

    // Generate CSV Content
    const headers = ['#', 'Name', 'Roll Number', 'Branch', 'Year', 'Email', 'Scan Time'];
    const csvRows = [headers.join(',')];

    list.forEach((row, index) => {
      const formattedTime = row.time ? new Date(row.time).toLocaleString() : '-';
      const line = [
        index + 1,
        `"${row.name.replace(/"/g, '""')}"`,
        `"${row.roll_number.replace(/"/g, '""')}"`,
        `"${row.branch.replace(/"/g, '""')}"`,
        `"${row.year.replace(/"/g, '""')}"`,
        `"${row.email.replace(/"/g, '""')}"`,
        `"${formattedTime}"`
      ];
      csvRows.push(line.join(','));
    });

    const csvContent = 'data:text/csv;charset=utf-8,' + csvRows.join('\n');
    const encodedUri = encodeURI(csvContent);
    const link = document.createElement('a');
    
    const safeTitle = (event?.title || 'event')
      .replace(/[^\w\s-]/g, '')
      .trim()
      .replace(/\s+/g, '_');

    link.setAttribute('href', encodedUri);
    link.setAttribute('download', `${safeTitle}_Day_${activeTabDay}_Attendance.csv`);
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
  };

  if (!currentUser) return null;

  const currentList = attendanceByDay[activeTabDay] || [];

  return (
    <div className="attendance-report-container" style={{ padding: '16px 20px', minHeight: '100vh', display: 'flex', flexDirection: 'column' }}>
      <header className="page-header" style={{ display: 'flex', alignItems: 'center', height: '60px', marginBottom: '20px' }}>
        <button onClick={() => navigate('/events')} className="back-button" style={{ background: 'none', border: 'none', color: 'var(--text-primary)', cursor: 'pointer', marginRight: '16px' }}>
          <ArrowLeft size={20} />
        </button>
        <h2 className="page-title" style={{ fontFamily: 'var(--font-space-grotesk)', fontWeight: 800, fontSize: '20px', margin: 0 }}>
          Attendance Report
        </h2>
        <div style={{ marginLeft: 'auto', display: 'flex', gap: '8px' }}>
          <button onClick={handleExportCSV} className="role-filter-chip active" style={{ display: 'flex', alignItems: 'center', gap: '6px', cursor: 'pointer', background: 'rgb(22, 192, 122)', border: 'none', color: 'white', padding: '8px 16px' }}>
            <Download size={14} /> Export CSV
          </button>
          {!isLoading && (
            <button onClick={loadAttendance} className="role-filter-chip" style={{ display: 'flex', alignItems: 'center', gap: '6px', background: 'none', border: '1px solid var(--border-light)', cursor: 'pointer' }}>
              <RefreshCw size={14} /> Refresh
            </button>
          )}
        </div>
      </header>

      {isLoading ? (
        <div className="flex-center" style={{ height: '300px', flexDirection: 'column', gap: '12px' }}>
          <Loader size={32} className="spinner" />
          <span>Loading attendance data...</span>
        </div>
      ) : (
        <div className="report-content" style={{ display: 'flex', flexDirection: 'column', gap: '20px', marginBottom: '80px' }}>
          {/* Event Header info */}
          <GlassCard padding="20px">
            <h3 style={{ fontFamily: 'var(--font-space-grotesk)', fontWeight: 700, fontSize: '18px', margin: '0 0 8px 0' }}>
              {event?.title}
            </h3>
            <p style={{ color: 'var(--text-secondary)', fontSize: '14px', margin: 0 }}>
              Category: {event?.category || 'General'} | Duration: {numDays} day(s)
            </p>
          </GlassCard>

          {/* Days Tabs (only render if numDays > 1) */}
          {numDays > 1 && (
            <div className="days-tabs" style={{ display: 'flex', gap: '8px', overflowX: 'auto', paddingBottom: '4px' }}>
              {Array.from({ length: numDays }, (_, i) => i + 1).map((day) => (
                <button
                  key={day}
                  onClick={() => setActiveTabDay(day)}
                  className={`role-filter-chip ${activeTabDay === day ? 'active' : ''}`}
                  style={{ cursor: 'pointer' }}
                >
                  Day {day}
                </button>
              ))}
            </div>
          )}

          {/* Attendee count for active day */}
          <div style={{ fontSize: '14px', color: 'var(--text-secondary)', fontWeight: 600 }}>
            Total check-ins on Day {activeTabDay}: <span style={{ color: 'rgb(22, 192, 122)', fontWeight: 800 }}>{currentList.length}</span>
          </div>

          {/* Table list */}
          {currentList.length === 0 ? (
            <div className="flex-center" style={{ height: '200px', flexDirection: 'column', color: 'var(--text-muted)' }}>
              <Users size={36} style={{ marginBottom: '12px' }} />
              <span>No check-ins recorded for Day {activeTabDay}.</span>
            </div>
          ) : (
            <GlassCard padding="0" style={{ overflow: 'hidden' }}>
              <div style={{ overflowX: 'auto' }}>
                <table style={{ width: '100%', borderCollapse: 'collapse', textAlign: 'left', fontSize: '13px' }}>
                  <thead>
                    <tr style={{ borderBottom: '1px solid var(--border-light)', background: 'rgba(255,255,255,0.02)' }}>
                      <th style={{ padding: '12px 16px', color: 'var(--text-muted)', fontWeight: 600 }}>#</th>
                      <th style={{ padding: '12px 16px', color: 'var(--text-muted)', fontWeight: 600 }}>Name</th>
                      <th style={{ padding: '12px 16px', color: 'var(--text-muted)', fontWeight: 600 }}>Roll Number</th>
                      <th style={{ padding: '12px 16px', color: 'var(--text-muted)', fontWeight: 600 }}>Branch</th>
                      <th style={{ padding: '12px 16px', color: 'var(--text-muted)', fontWeight: 600 }}>Year</th>
                      <th style={{ padding: '12px 16px', color: 'var(--text-muted)', fontWeight: 600 }}>Email</th>
                      <th style={{ padding: '12px 16px', color: 'var(--text-muted)', fontWeight: 600 }}>Time Checked-In</th>
                    </tr>
                  </thead>
                  <tbody>
                    {currentList.map((log, index) => (
                      <tr key={log.user_id} style={{ borderBottom: '1px solid var(--border-light)' }}>
                        <td style={{ padding: '12px 16px', color: 'var(--text-muted)' }}>{index + 1}</td>
                        <td style={{ padding: '12px 16px', fontWeight: 600, color: 'var(--text-primary)' }}>{log.name}</td>
                        <td style={{ padding: '12px 16px', color: 'var(--text-secondary)' }}>{log.roll_number}</td>
                        <td style={{ padding: '12px 16px', color: 'var(--text-secondary)' }}>{log.branch}</td>
                        <td style={{ padding: '12px 16px', color: 'var(--text-secondary)' }}>{log.year}</td>
                        <td style={{ padding: '12px 16px', color: 'var(--text-secondary)' }}>{log.email}</td>
                        <td style={{ padding: '12px 16px', color: 'var(--text-muted)' }}>
                          {log.time ? new Date(log.time).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) : '-'}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </GlassCard>
          )}
        </div>
      )}

      <NavBar />

      <style>{`
        .spinner {
          animation: spin 1s linear infinite;
        }
        @keyframes spin {
          to { transform: rotate(360deg); }
        }
      `}</style>
    </div>
  );
};
