import React, { useEffect, useState } from 'react';
import { createClient } from '@supabase/supabase-js';
import { useNavigate } from 'react-router-dom';
import { motion, useSpring, useTransform } from 'framer-motion';
import PageTransition from '../../shared/components/PageTransition';

// Initialize a separate client for Mentron DB
const mentronClient = createClient(
  'https://ysllolnoyezfdllqocgv.supabase.co',
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlzbGxvbG5veWV6ZmRsbHFvY2d2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE1MjA0NTcsImV4cCI6MjA4NzA5NjQ1N30.0bQMBFKaQuXEQ3sh1_gfQWgWkcd70SDfy_zMwIQ8myk'
);

// Micro-animation component for numbers
const RollingNumber: React.FC<{ value: number }> = ({ value }) => {
  const spring = useSpring(value, { mass: 0.8, stiffness: 75, damping: 15 });
  const display = useTransform(spring, (current) => Math.round(current).toString());

  useEffect(() => {
    spring.set(value);
  }, [value, spring]);

  return <motion.span>{display}</motion.span>;
};

const MentronDashboardScreen: React.FC = () => {
  const navigate = useNavigate();
  const [registeredStudents, setRegisteredStudents] = useState<number>(0);
  const [activeAdmins, setActiveAdmins] = useState<number>(0);
  const [totalNotes, setTotalNotes] = useState<number>(0);
  const [totalViews, setTotalViews] = useState<number>(0);
  const [loading, setLoading] = useState<boolean>(true);

  useEffect(() => {
    fetchMentronMetrics();

    // Subscribe to realtime updates for Mentron platform
    const channel = mentronClient
      .channel('mentron_public_profiles')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'profiles' }, (payload) => {
        // Trigger a fresh fetch when anything changes to keep it perfectly synced
        fetchMentronMetrics(false);
      })
      .subscribe();

    return () => {
      mentronClient.removeChannel(channel);
    };
  }, []);

  const fetchMentronMetrics = async (showLoading = true) => {
    try {
      if (showLoading) setLoading(true);
      
      // Profiles
      const { data: profilesData } = await mentronClient.from('profiles').select('id, role');
      let students = 0;
      let admins = 0;
      if (profilesData) {
        for (const profile of profilesData) {
          if (profile.role === 'exec' || profile.role === 'core') {
            admins++;
          } else {
            students++;
          }
        }
      }
      
      // Notes
      const { data: notesData } = await mentronClient.from('notes').select('id');
      const notesCount = notesData ? notesData.length : 0;
      
      // Note Views
      const { data: viewsData } = await mentronClient.from('note_views').select('views_count');
      let viewsSum = 0;
      if (viewsData) {
        for (const row of viewsData) {
          viewsSum += parseInt(row.views_count, 10) || 0;
        }
      }
      
      setRegisteredStudents(students);
      setActiveAdmins(admins);
      setTotalNotes(notesCount);
      setTotalViews(viewsSum);
    } catch (error) {
      console.error('Error fetching Mentron metrics:', error);
    } finally {
      if (showLoading) setLoading(false);
    }
  };

  return (
    <PageTransition>
      <div className="mentron-dashboard flex-col">
        {/* Header */}
        <header className="home-header">
          <div className="header-top flex-center">
            <button className="icon-btn" onClick={() => navigate(-1)}>
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <path strokeLinecap="round" strokeLinejoin="round" d="M15 19l-7-7 7-7" />
              </svg>
            </button>
            <div className="flex-col" style={{ marginLeft: '12px' }}>
              <h1 className="header-title">Mentron Analytics</h1>
              <span className="header-subtitle" style={{ color: 'var(--text-muted)' }}>Key metrics directly pulled from the platform</span>
            </div>
          </div>
        </header>

        {loading ? (
          <div className="flex-center" style={{ flex: 1, height: '300px' }}>
            <div className="loader"></div>
          </div>
        ) : (
          <div className="mentron-content" style={{ padding: '24px 20px', gap: '16px', display: 'flex', flexDirection: 'column' }}>
            <MetricCard 
              title="Registered Students" 
              value={registeredStudents} 
              color="#3B82F6" 
              icon={
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                  <path d="M12 14l9-5-9-5-9 5 9 5z" />
                  <path d="M12 14l6.16-3.422a12.083 12.083 0 01.665 6.479A11.952 11.952 0 0012 20.055a11.952 11.952 0 00-6.824-2.998 12.078 12.078 0 01.665-6.479L12 14z" />
                </svg>
              }
            />
            
            <MetricCard 
              title="Active Administrators" 
              value={activeAdmins} 
              color="#F59E0B" 
              icon={
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                  <path d="M12 11c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z" />
                </svg>
              }
            />

            <MetricCard 
              title="Total Student Notes" 
              value={totalNotes} 
              color="#10B981" 
              icon={
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                  <path d="M19 3H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zm-2 14H7v-2h10v2zm0-4H7v-2h10v2zm0-4H7V7h10v2z" />
                </svg>
              }
            />

            <MetricCard 
              title="Total Note Views" 
              value={totalViews} 
              color="#8B5CF6" 
              icon={
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                  <path d="M12 4.5C7 4.5 2.73 7.61 1 12c1.73 4.39 6 7.5 11 7.5s9.27-3.11 11-7.5c-1.73-4.39-6-7.5-11-7.5zM12 17c-2.76 0-5-2.24-5-5s2.24-5 5-5 5 2.24 5 5-2.24 5-5 5zm0-8c-1.66 0-3 1.34-3 3s1.34 3 3 3 3-1.34 3-3-1.34-3-3-3z" />
                </svg>
              }
            />
          </div>
        )}
      </div>
    </PageTransition>
  );
};

const MetricCard: React.FC<{title: string, value: number, icon: React.ReactNode, color: string}> = ({ title, value, icon, color }) => {
  return (
    <div className="glass-card" style={{ padding: '20px', display: 'flex', alignItems: 'center', gap: '20px' }}>
      <div style={{
        width: '56px', height: '56px', borderRadius: '50%',
        backgroundColor: `${color}1A`, color: color,
        display: 'flex', alignItems: 'center', justifyContent: 'center'
      }}>
        <div style={{ width: '28px', height: '28px' }}>
          {icon}
        </div>
      </div>
      <div className="flex-col">
        <span style={{ fontSize: '14px', fontWeight: '500', color: 'var(--text-muted)' }}>{title}</span>
        <span style={{ fontSize: '32px', fontWeight: '800', fontFamily: 'var(--font-space-grotesk)', color: 'var(--text-primary)' }}>
          <RollingNumber value={value} />
        </span>
      </div>
    </div>
  );
};

export default MentronDashboardScreen;
