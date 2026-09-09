import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { ArrowLeft, Megaphone, Lock, Plus, Loader, Calendar } from 'lucide-react';
import { useAuth } from '../../core/auth-provider';
import { supabase } from '../../core/supabase-client';
import { AnnouncementModel } from '../../models/types';
import { GlassCard } from '../../shared/components/GlassCard';
import { NavBar } from '../../shared/components/NavBar';

export const AnnouncementScreen: React.FC = () => {
  const navigate = useNavigate();
  const { currentUser, permissions } = useAuth();
  
  const [announcements, setAnnouncements] = useState<AnnouncementModel[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [showModal, setShowModal] = useState(false);
  const [isCreating, setIsCreating] = useState(false);

  // Form States
  const [title, setTitle] = useState('');
  const [content, setContent] = useState('');
  const [visibility, setVisibility] = useState<'public' | 'internal'>('public');

  const loadAnnouncements = async () => {
    setIsLoading(true);
    try {
      const { data, error } = await supabase
        .from('announcements')
        .select('*')
        .order('created_at', { ascending: false });

      if (error) throw error;
      setAnnouncements((data || []) as AnnouncementModel[]);
    } catch (e) {
      console.error('Error fetching announcements:', e);
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    loadAnnouncements();

    // Setup WebSocket real-time subscription
    const channel = supabase
      .channel('public:announcements')
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'announcements' },
        (payload) => {
          const eventType = payload.eventType;
          if (eventType === 'INSERT') {
            const newAnn = payload.new as AnnouncementModel;
            setAnnouncements((prev) => [newAnn, ...prev]);
          } else if (eventType === 'UPDATE') {
            const updatedAnn = payload.new as AnnouncementModel;
            setAnnouncements((prev) =>
              prev.map((a) => (a.id === updatedAnn.id ? updatedAnn : a))
            );
          } else if (eventType === 'DELETE') {
            const deletedId = payload.old.id as number;
            setAnnouncements((prev) => prev.filter((a) => a.id !== deletedId));
          }
        }
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, []);

  const handleCreateAnnouncement = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!title.trim() || !currentUser) return;

    setIsCreating(true);
    try {
      const { error } = await supabase.from('announcements').insert({
        title: title.trim(),
        content: content.trim(),
        visibility,
        created_by: currentUser.id,
      });

      if (error) throw error;

      setTitle('');
      setContent('');
      setVisibility('public');
      setShowModal(false);
      // Let real-time subscription load the new card natively
    } catch (err) {
      console.error('Error creating announcement:', err);
      alert('Failed to post announcement');
    } finally {
      setIsCreating(false);
    }
  };

  if (!currentUser || !permissions) return null;

  return (
    <div className="announcements-container">
      <header className="page-header">
        <button onClick={() => navigate('/home')} className="back-button">
          <ArrowLeft size={20} />
        </button>
        <h2 className="page-title">Announcements</h2>
        {permissions.canManageAnnouncements ? (
          <button onClick={() => setShowModal(true)} className="create-announcement-btn">
            <Plus size={20} />
          </button>
        ) : (
          <div style={{ width: '20px' }}></div>
        )}
      </header>

      {isLoading ? (
        <div className="announcements-loading flex-center" style={{ height: '200px' }}>
          <Loader size={24} className="spinner" />
        </div>
      ) : announcements.length === 0 ? (
        <div className="announcements-empty flex-center" style={{ flexDirection: 'column', height: '200px' }}>
          <Megaphone size={44} style={{ color: 'var(--text-muted)', marginBottom: '12px' }} />
          <span>No announcements posted yet.</span>
        </div>
      ) : (
        <div className="announcements-list-flow" style={{ marginBottom: '40px' }}>
          {announcements.map((ann) => {
            const isInternal = ann.visibility === 'internal';
            return (
              <GlassCard key={ann.id} className="announcement-item-card" padding="20px">
                <div className="announcement-card-header">
                  <div className="header-left flex-center" style={{ gap: '8px' }}>
                    {isInternal ? (
                      <Lock size={16} style={{ color: '#f97316' }} />
                    ) : (
                      <Megaphone size={16} style={{ color: 'rgb(22, 192, 122)' }} />
                    )}
                    <h3 className="announcement-card-title">{ann.title}</h3>
                  </div>
                  <span className={`visibility-badge ${ann.visibility}`}>
                    {ann.visibility.toUpperCase()}
                  </span>
                </div>

                {ann.content && <p className="announcement-content-text">{ann.content}</p>}

                {ann.created_at && (
                  <div className="announcement-date flex-center" style={{ justifyContent: 'flex-start', gap: '6px', marginTop: '14px' }}>
                    <Calendar size={13} style={{ color: 'var(--text-muted)' }} />
                    <span>{new Date(ann.created_at).toLocaleDateString()}</span>
                  </div>
                )}
              </GlassCard>
            );
          })}
        </div>
      )}

      {/* Creation Modal */}
      {showModal && (
        <div className="modal-overlay">
          <GlassCard className="modal-card" padding="24px">
            <h3 className="modal-title">New Announcement</h3>
            <form onSubmit={handleCreateAnnouncement}>
              
              <div style={{ marginBottom: '12px' }}>
                <label className="modal-input-label">Title</label>
                <input
                  type="text"
                  placeholder="Title of announcement"
                  value={title}
                  onChange={(e) => setTitle(e.target.value)}
                  className="modal-input"
                  required
                />
              </div>

              <div style={{ marginBottom: '12px' }}>
                <label className="modal-input-label">Content</label>
                <textarea
                  placeholder="Enter details"
                  value={content}
                  onChange={(e) => setContent(e.target.value)}
                  className="modal-input"
                  rows={4}
                  style={{ resize: 'none' }}
                />
              </div>

              <div style={{ marginBottom: '24px' }}>
                <label className="modal-input-label">Visibility</label>
                <select
                  value={visibility}
                  onChange={(e) => setVisibility(e.target.value as any)}
                  className="modal-select-field"
                >
                  <option value="public">Public (All General Members)</option>
                  <option value="internal">Internal (Execcom+ Access Only)</option>
                </select>
              </div>

              <div className="modal-actions-row">
                <button type="button" onClick={() => setShowModal(false)} className="modal-cancel-btn" disabled={isCreating}>
                  Cancel
                </button>
                <button type="submit" className="modal-submit-btn" disabled={isCreating || !title.trim()}>
                  {isCreating ? 'Posting...' : 'Post'}
                </button>
              </div>
            </form>
          </GlassCard>
        </div>
      )}

      <NavBar />

      <style>{`
        .announcements-container {
          padding: 16px 20px;
        }

        .page-header {
          display: flex;
          align-items: center;
          justify-content: space-between;
          height: 60px;
          margin-bottom: 20px;
        }

        .back-button, .create-announcement-btn {
          color: var(--text-primary);
        }

        .page-title {
          font-family: var(--font-space-grotesk);
          font-weight: 800;
          font-size: 20px;
          color: var(--text-primary);
        }

        .announcements-loading, .announcements-empty {
          text-align: center;
          color: var(--text-secondary);
        }

        .announcements-list-flow {
          display: flex;
          flex-direction: column;
          gap: 12px;
        }

        .announcement-item-card {
          width: 100%;
        }

        .announcement-card-header {
          display: flex;
          align-items: center;
          justify-content: space-between;
          width: 100%;
          margin-bottom: 10px;
        }

        .announcement-card-title {
          font-size: 16px;
          font-weight: 700;
          color: var(--text-primary);
        }

        .visibility-badge {
          font-family: var(--font-space-grotesk);
          font-size: 10px;
          font-weight: 700;
          border-radius: 6px;
          padding: 3px 8px;
        }

        .visibility-badge.public { background: rgba(22, 192, 122, 0.12); color: rgb(22, 192, 122); }
        .visibility-badge.internal { background: rgba(249, 115, 22, 0.12); color: rgb(249, 115, 22); }

        .announcement-content-text {
          font-size: 13px;
          color: var(--text-secondary);
          line-height: 1.5;
        }

        .announcement-date {
          font-size: 11px;
          color: var(--text-muted);
        }

        /* Modal styling */
        .modal-overlay {
          position: fixed;
          top: 0;
          left: 0;
          right: 0;
          bottom: 0;
          background: rgba(0, 0, 0, 0.5);
          backdrop-filter: blur(5px);
          display: flex;
          align-items: center;
          justify-content: center;
          z-index: 1001;
          padding: 20px;
        }

        .modal-card {
          width: 100%;
          max-width: 360px;
          background: var(--bg-secondary);
        }

        .modal-title {
          font-size: 18px;
          color: var(--text-primary);
          margin-bottom: 16px;
        }

        .modal-input {
          width: 100%;
        }

        .modal-input-label {
          display: block;
          font-family: var(--font-space-grotesk);
          font-size: 12px;
          font-weight: 600;
          color: var(--text-secondary);
          margin-bottom: 6px;
        }

        .modal-select-field {
          width: 100%;
          padding: 12px;
          background: rgba(255, 255, 255, 0.04);
          border: 1px solid var(--border-light);
          border-radius: 12px;
          color: var(--text-primary);
          outline: none;
        }

        .modal-actions-row {
          display: flex;
          justify-content: flex-end;
          gap: 12px;
          margin-top: 24px;
        }

        .modal-cancel-btn {
          padding: 10px 16px;
          font-size: 14px;
          font-weight: 600;
          color: var(--text-secondary);
        }

        .modal-submit-btn {
          padding: 10px 16px;
          background: linear-gradient(135deg, rgb(15, 117, 73) 0%, rgb(22, 192, 122) 100%);
          color: #ffffff;
          border-radius: 10px;
          font-size: 14px;
          font-weight: 700;
        }

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
