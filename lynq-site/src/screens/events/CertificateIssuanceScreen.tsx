import React, { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { ArrowLeft, RefreshCw, Upload, Check, AlertTriangle, Play, Sparkles, Loader } from 'lucide-react';
import { supabase } from '../../core/supabase-client';
import { useAuth } from '../../core/auth-provider';
import { GlassCard } from '../../shared/components/GlassCard';
import { NavBar } from '../../shared/components/NavBar';
import { EventModel } from '../../models/types';

export const CertificateIssuanceScreen: React.FC = () => {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { currentUser } = useAuth();
  
  const [event, setEvent] = useState<EventModel | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isProcessing, setIsProcessing] = useState(false);
  const [attendees, setAttendees] = useState<{ user_id: string; name: string }[]>([]);
  const [alreadyIssuedIds, setAlreadyIssuedIds] = useState<Set<string>>(new Set());

  const [pickedFile, setPickedFile] = useState<File | null>(null);
  const [uploadedTemplateUrl, setUploadedTemplateUrl] = useState<string | null>(null);
  const [isCompleted, setIsCompleted] = useState(false);

  const [processedCount, setProcessedCount] = useState(0);
  const [progressMessage, setProgressMessage] = useState('');
  const [lastSuccessCount, setLastSuccessCount] = useState<number | null>(null);

  const attendeeCount = attendees.length;
  const issuedCount = alreadyIssuedIds.size;
  const pendingCount = attendeeCount - issuedCount;

  const loadStats = async () => {
    if (!id) return;
    setIsLoading(true);
    setLastSuccessCount(null);
    try {
      // 1. Fetch Event Template
      const { data: eventRow, error: eErr } = await supabase
        .from('events')
        .select('*')
        .eq('id', parseInt(id))
        .maybeSingle();

      if (eErr) throw eErr;
      if (eventRow) {
        setEvent(eventRow as EventModel);
        setUploadedTemplateUrl(eventRow.template_url);
        setIsCompleted(eventRow.attendance_finalized || false);
      }

      // 2. Fetch Attendance Rows
      const { data: attendanceRows, error: aErr } = await supabase
        .from('attendance')
        .select('user_id')
        .eq('event_id', parseInt(id));

      if (aErr) throw aErr;
      const rows = attendanceRows || [];

      // 3. Fetch user info for unique user ids
      const userIds = Array.from(new Set(rows.map(r => r.user_id)));
      let uniqueAttendees: { user_id: string; name: string }[] = [];
      
      if (userIds.length > 0) {
        const { data: usersRows, error: uErr } = await supabase
          .from('users')
          .select('id, name')
          .in('id', userIds);

        if (uErr) throw uErr;
        const usersMap = new Map((usersRows || []).map(u => [u.id, u.name]));
        uniqueAttendees = userIds.map(uid => ({
          user_id: uid,
          name: usersMap.get(uid) || 'Member'
        }));
      }
      setAttendees(uniqueAttendees);

      // 4. Fetch already issued certificates
      const { data: issuedRows, error: cErr } = await supabase
        .from('certificates')
        .select('user_id')
        .eq('event_id', parseInt(id));

      if (cErr) throw cErr;
      const issuedSet = new Set((issuedRows || []).map(r => r.user_id));
      setAlreadyIssuedIds(issuedSet);
    } catch (e) {
      console.error('Error loading event stats:', e);
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    loadStats();
  }, [id]);

  const handleUploadTemplate = async () => {
    if (!pickedFile || !id) return;
    setIsProcessing(true);
    setProgressMessage('Uploading HTML template...');
    try {
      const ext = pickedFile.name.split('.').pop() || 'html';
      const fileName = `template_event_${id}_${Date.now()}.${ext}`;
      const path = `templates/${fileName}`;

      const { data, error } = await supabase.storage
        .from('event_posters')
        .upload(path, pickedFile, {
          contentType: 'text/html'
        });

      if (error) throw error;

      const { data: { publicUrl } } = supabase.storage
        .from('event_posters')
        .getPublicUrl(path);

      const { error: updateErr } = await supabase
        .from('events')
        .update({ template_url: publicUrl })
        .eq('id', parseInt(id));

      if (updateErr) throw updateErr;

      setUploadedTemplateUrl(publicUrl);
      setPickedFile(null);
      alert('HTML template uploaded and configured successfully!');
    } catch (e: any) {
      console.error(e);
      alert('Upload failed: ' + e.message);
    } finally {
      setIsProcessing(false);
      setProgressMessage('');
    }
  };

  const handleFinalizeEvent = async () => {
    if (!id) return;
    setIsProcessing(true);
    setProgressMessage('Finalizing event...');
    try {
      const { error } = await supabase
        .from('events')
        .update({ attendance_finalized: true })
        .eq('id', parseInt(id));

      if (error) throw error;
      setIsCompleted(true);
      alert('Event marked as Completed successfully!');
    } catch (e: any) {
      alert('Failed to finalize event: ' + e.message);
    } finally {
      setIsProcessing(false);
      setProgressMessage('');
      loadStats();
    }
  };

  const handlePublishCertificates = async () => {
    if (!uploadedTemplateUrl) {
      alert('Please upload an HTML template first.');
      return;
    }
    if (attendees.length === 0) {
      alert('No attendees found for this event.');
      return;
    }

    const eligible = attendees.filter(a => !alreadyIssuedIds.has(a.user_id));
    if (eligible.length === 0) {
      alert('All attendees already have certificates.');
      return;
    }

    const confirmed = window.confirm(
      `This will generate certificates for ${eligible.length} attendee(s) of "${event?.title}". Proceed?`
    );
    if (!confirmed) return;

    setIsProcessing(true);
    setProcessedCount(0);
    setLastSuccessCount(null);

    let successCount = 0;
    const total = eligible.length;

    for (let i = 0; i < eligible.length; i++) {
      const attendee = eligible[i];
      setProgressMessage(`Publishing for ${attendee.name} (${i + 1}/${total})...`);
      
      try {
        const finalCertUrl = `template:${uploadedTemplateUrl}`;
        const { error } = await supabase.from('certificates').upsert({
          user_id: attendee.user_id,
          event_id: parseInt(id!),
          student_name: attendee.name,
          title: `Certificate of Participation — ${event?.title}`,
          description: `Awarded for attending ${event?.title} on ${event?.date || ''}`,
          file_url: finalCertUrl,
          issued_by: currentUser?.id,
          issued_at: new Date().toISOString()
        }, { onConflict: 'user_id,event_id' });

        if (error) throw error;
        successCount++;
        setProcessedCount(i + 1);
      } catch (err) {
        console.error(`Error issuing cert for ${attendee.user_id}:`, err);
      }
    }

    await loadStats();
    setIsProcessing(false);
    setProgressMessage('');
    setLastSuccessCount(successCount);
    alert(`Successfully published ${successCount} certificate(s).`);
  };

  if (!currentUser) return null;

  return (
    <div className="publish-certs-container" style={{ padding: '16px 20px', minHeight: '100vh', display: 'flex', flexDirection: 'column' }}>
      <header className="page-header" style={{ display: 'flex', alignItems: 'center', height: '60px', marginBottom: '20px' }}>
        <button onClick={() => navigate('/events')} className="back-button" style={{ background: 'none', border: 'none', color: 'var(--text-primary)', cursor: 'pointer', marginRight: '16px' }}>
          <ArrowLeft size={20} />
        </button>
        <h2 className="page-title" style={{ fontFamily: 'var(--font-space-grotesk)', fontWeight: 800, fontSize: '20px', margin: 0 }}>
          Publish Certificates
        </h2>
        <div style={{ marginLeft: 'auto' }}>
          {!isLoading && !isProcessing && (
            <button onClick={loadStats} className="role-filter-chip" style={{ display: 'flex', alignItems: 'center', gap: '6px', background: 'none', border: '1px solid var(--border-light)', cursor: 'pointer' }}>
              <RefreshCw size={14} /> Refresh
            </button>
          )}
        </div>
      </header>

      {isLoading ? (
        <div className="flex-center" style={{ height: '300px', flexDirection: 'column', gap: '12px' }}>
          <Loader size={32} className="spinner" />
          <span>Loading stats...</span>
        </div>
      ) : (
        <div className="publish-content" style={{ display: 'flex', flexDirection: 'column', gap: '20px', marginBottom: '80px' }}>
          {/* Event info card */}
          <GlassCard padding="20px">
            <h3 style={{ fontFamily: 'var(--font-space-grotesk)', fontWeight: 700, fontSize: '18px', margin: '0 0 8px 0' }}>
              {event?.title}
            </h3>
            <p style={{ color: 'var(--text-secondary)', fontSize: '14px', margin: 0 }}>
              Date: {event?.date} | Location: {event?.location || 'N/A'}
            </p>
          </GlassCard>

          {/* Completion banner */}
          {!isCompleted ? (
            <div style={{ padding: '16px', borderRadius: '12px', border: '1px dashed rgba(239, 68, 68, 0.4)', background: 'rgba(239, 68, 68, 0.05)', display: 'flex', alignItems: 'center', gap: '12px' }}>
              <AlertTriangle size={20} style={{ color: 'rgb(239, 68, 68)' }} />
              <div style={{ flex: 1 }}>
                <h4 style={{ margin: '0 0 4px 0', fontSize: '14px', color: 'white' }}>Event Attendance Not Finalized</h4>
                <p style={{ margin: 0, fontSize: '12px', color: 'var(--text-muted)' }}>You must finalize the attendance before issuing certificates.</p>
              </div>
              <button onClick={handleFinalizeEvent} className="role-filter-chip active" style={{ cursor: 'pointer', background: 'rgb(239, 68, 68)', border: 'none', color: 'white', padding: '8px 16px' }}>
                Finalize Now
              </button>
            </div>
          ) : (
            <div style={{ padding: '16px', borderRadius: '12px', border: '1px solid rgba(22, 192, 122, 0.4)', background: 'rgba(22, 192, 122, 0.05)', display: 'flex', alignItems: 'center', gap: '12px' }}>
              <Check size={20} style={{ color: 'rgb(22, 192, 122)' }} />
              <div>
                <h4 style={{ margin: '0 0 4px 0', fontSize: '14px', color: 'white' }}>Attendance Finalized</h4>
                <p style={{ margin: 0, fontSize: '12px', color: 'var(--text-muted)' }}>Event marked as completed. You can issue certificates now.</p>
              </div>
            </div>
          )}

          {/* Stats grid */}
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: '12px' }}>
            <GlassCard padding="16px" style={{ textAlign: 'center' }}>
              <div style={{ fontSize: '24px', fontWeight: 800, color: 'var(--text-primary)' }}>{attendeeCount}</div>
              <div style={{ fontSize: '12px', color: 'var(--text-muted)' }}>Total Attendees</div>
            </GlassCard>
            <GlassCard padding="16px" style={{ textAlign: 'center' }}>
              <div style={{ fontSize: '24px', fontWeight: 800, color: 'rgb(22, 192, 122)' }}>{issuedCount}</div>
              <div style={{ fontSize: '12px', color: 'var(--text-muted)' }}>Already Issued</div>
            </GlassCard>
            <GlassCard padding="16px" style={{ textAlign: 'center' }}>
              <div style={{ fontSize: '24px', fontWeight: 800, color: '#f59e0b' }}>{pendingCount}</div>
              <div style={{ fontSize: '12px', color: 'var(--text-muted)' }}>Pending</div>
            </GlassCard>
          </div>

          {/* HTML Template upload card */}
          <GlassCard padding="20px">
            <h3 style={{ fontFamily: 'var(--font-space-grotesk)', fontWeight: 700, fontSize: '16px', margin: '0 0 12px 0', display: 'flex', alignItems: 'center', gap: '8px' }}>
              <Upload size={18} /> HTML Certificate Template
            </h3>
            {uploadedTemplateUrl ? (
              <div style={{ marginBottom: '16px' }}>
                <span style={{ fontSize: '12px', color: 'var(--text-muted)', display: 'block', marginBottom: '4px' }}>Active Template URL:</span>
                <a href={uploadedTemplateUrl} target="_blank" rel="noopener noreferrer" style={{ fontSize: '13px', color: 'rgb(22, 192, 122)', wordBreak: 'break-all', textDecoration: 'underline' }}>
                  {uploadedTemplateUrl}
                </a>
              </div>
            ) : (
              <div style={{ fontSize: '13px', color: '#ef4444', marginBottom: '16px' }}>
                No template uploaded yet. You must upload one to publish certificates.
              </div>
            )}

            <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
              <input
                type="file"
                accept=".html"
                id="picked-template-file"
                style={{ display: 'none' }}
                onChange={(e) => {
                  const file = e.target.files?.[0];
                  if (file) setPickedFile(file);
                }}
              />
              <button
                onClick={() => document.getElementById('picked-template-file')?.click()}
                className="role-filter-chip"
                style={{ cursor: 'pointer', display: 'flex', alignItems: 'center', gap: '6px' }}
              >
                Choose HTML File
              </button>
              <span style={{ fontSize: '13px', color: 'var(--text-secondary)' }}>
                {pickedFile ? pickedFile.name : 'No file picked'}
              </span>
              {pickedFile && (
                <button
                  onClick={handleUploadTemplate}
                  className="role-filter-chip active"
                  style={{ cursor: 'pointer', background: 'rgb(22, 192, 122)', border: 'none', color: 'white' }}
                >
                  Upload
                </button>
              )}
            </div>
          </GlassCard>

          {/* Action layout */}
          {isProcessing && (
            <div style={{ padding: '16px', borderRadius: '12px', background: 'rgba(255,255,255,0.03)', border: '1px solid var(--border-light)', display: 'flex', flexDirection: 'column', gap: '8px' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                <Loader size={16} className="spinner" />
                <span style={{ fontSize: '14px', color: 'white', fontWeight: 600 }}>{progressMessage}</span>
              </div>
              {processedCount > 0 && pendingCount > 0 && (
                <div style={{ width: '100%', height: '6px', borderRadius: '3px', background: 'rgba(255,255,255,0.1)', overflow: 'hidden' }}>
                  <div style={{ height: '100%', background: 'rgb(22, 192, 122)', width: `${(processedCount / pendingCount) * 100}%` }}></div>
                </div>
              )}
            </div>
          )}

          {lastSuccessCount !== null && (
            <div style={{ padding: '16px', borderRadius: '12px', background: 'rgba(22, 192, 122, 0.05)', border: '1px solid rgba(22, 192, 122, 0.3)', display: 'flex', alignItems: 'center', gap: '10px' }}>
              <Sparkles size={18} style={{ color: 'rgb(22, 192, 122)' }} />
              <span style={{ fontSize: '14px', color: 'white' }}>Published {lastSuccessCount} certificate(s) successfully!</span>
            </div>
          )}

          <div style={{ marginTop: '12px' }}>
            <button
              onClick={handlePublishCertificates}
              disabled={!isCompleted || !uploadedTemplateUrl || pendingCount === 0 || isProcessing}
              style={{
                width: '100%',
                padding: '16px',
                borderRadius: '14px',
                background: (isCompleted && uploadedTemplateUrl && pendingCount > 0 && !isProcessing) ? '#f59e0b' : 'rgba(255,255,255,0.05)',
                color: (isCompleted && uploadedTemplateUrl && pendingCount > 0 && !isProcessing) ? 'white' : 'var(--text-muted)',
                fontFamily: 'var(--font-space-grotesk)',
                fontWeight: 700,
                fontSize: '15px',
                border: 'none',
                cursor: (isCompleted && uploadedTemplateUrl && pendingCount > 0 && !isProcessing) ? 'pointer' : 'not-allowed',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                gap: '8px'
              }}
            >
              <Play size={18} /> Publish {pendingCount} Pending Certificates
            </button>
          </div>
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
