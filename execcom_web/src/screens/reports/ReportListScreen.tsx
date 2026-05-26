import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { ArrowLeft, Plus, Eye, Trash, Edit, FileText, Loader } from 'lucide-react';
import { useAuth } from '../../core/auth-provider';
import { supabase } from '../../core/supabase-client';
import { AppRole, appRoleFromString } from '../../core/constants';
import { GlassCard } from '../../shared/components/GlassCard';
import { NavBar } from '../../shared/components/NavBar';

export const ReportListScreen: React.FC = () => {
  const navigate = useNavigate();
  const { currentUser, permissions } = useAuth();

  const [reports, setReports] = useState<any[]>([]);
  const [userCache, setUserCache] = useState<Record<string, any>>({});
  const [isLoading, setIsLoading] = useState(true);

  const fetchReports = async () => {
    if (!currentUser || !permissions) return;
    setIsLoading(true);
    try {
      const { data, error } = await supabase
        .from('event_reports')
        .select('*')
        .order('created_at', { ascending: false });

      if (error) throw error;
      const loadedReports = data || [];

      // Fetch uploader info for cache
      const uploaderIds = Array.from(new Set(loadedReports.map((r) => r.uploaded_by).filter((id) => id)));
      if (uploaderIds.length > 0) {
        const { data: usersData } = await supabase
          .from('users')
          .select('id, name, post, role')
          .in('id', uploaderIds);

        if (usersData) {
          const cache: Record<string, any> = {};
          usersData.forEach((u) => {
            cache[u.id] = u;
          });
          setUserCache(cache);
        }
      }

      // Filter reports matching role hierarchy visibility rules
      const myRole = permissions.role;
      const filtered = loadedReports.filter((report) => {
        const uploaderId = report.uploaded_by;
        if (uploaderId === currentUser.id) return true; // Owner always sees
        if (myRole === AppRole.chairman) return true; // Chairman sees all

        const uploaderRoleStr = userCache[uploaderId]?.role;
        if (uploaderRoleStr) {
          const uploaderRole = appRoleFromString(uploaderRoleStr);
          if (myRole === AppRole.viceChairman && uploaderRole <= AppRole.viceChairman) return true;
        }

        const visibility = Array.isArray(report.visibility) ? report.visibility : [];
        const roleDbStr = (myRole as AppRole) === AppRole.chairman ? 'chairman' :
                         myRole === AppRole.viceChairman ? 'vice_chairman' :
                         myRole === AppRole.coreExeccom ? 'core_execcom' :
                         myRole === AppRole.forumExeccom ? 'forum_execcom' :
                         myRole === AppRole.panel ? 'panel' : 'member';
        
        if (visibility.includes(roleDbStr)) return true;
        return false;
      });

      setReports(filtered);
    } catch (e) {
      console.error('Error fetching reports:', e);
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    fetchReports();
  }, [currentUser, permissions]);

  const handleDeleteReport = async (id: string, fileUrl?: string) => {
    if (!window.confirm('Are you sure you want to delete this report? This action cannot be undone.')) return;

    try {
      if (fileUrl && fileUrl.includes('/reports/')) {
        const path = fileUrl.split('/reports/').pop();
        if (path) {
          await supabase.storage.from('reports').remove([path]);
        }
      }

      const { error } = await supabase.from('event_reports').delete().eq('id', id);
      if (error) throw error;

      setReports(reports.filter((r) => r.id !== id));
      alert('Report deleted successfully!');
    } catch (e) {
      console.error('Delete report error:', e);
      alert('Failed to delete report');
    }
  };

  if (!currentUser || !permissions) return null;

  return (
    <div className="reports-list-container">
      <header className="page-header">
        <button onClick={() => navigate('/home')} className="back-button">
          <ArrowLeft size={20} />
        </button>
        <h2 className="page-title">Forum Reports</h2>
        {permissions.canUploadReports ? (
          <button onClick={() => navigate('/reports/upload')} className="create-report-btn">
            <Plus size={20} />
          </button>
        ) : (
          <div style={{ width: '20px' }}></div>
        )}
      </header>

      {isLoading ? (
        <div className="reports-loading flex-center" style={{ height: '200px' }}>
          <Loader size={24} className="spinner" />
        </div>
      ) : reports.length === 0 ? (
        <div className="reports-empty flex-center" style={{ flexDirection: 'column', height: '200px' }}>
          <FileText size={44} style={{ color: 'var(--text-muted)', marginBottom: '12px' }} />
          <span>No reports published yet.</span>
        </div>
      ) : (
        <div className="reports-list-flow" style={{ marginBottom: '40px' }}>
          {reports.map((report) => {
            const uploader = userCache[report.uploaded_by];
            const uploaderDisplay = uploader 
              ? `${uploader.name} (${uploader.post || getRoleLabel(uploader.role)})`
              : 'Unknown';
            
            const isOwner = report.uploaded_by === currentUser.id;
            const canManage = isOwner || permissions.role >= AppRole.viceChairman;

            return (
              <GlassCard key={report.id} className="report-item-card" padding="20px">
                <div className="report-card-header">
                  <h3 className="report-card-title">{report.title}</h3>
                  {canManage && (
                    <div className="report-actions flex-center" style={{ gap: '10px' }}>
                      <button 
                        onClick={() => navigate('/reports/upload', { state: { existingReport: report } })} 
                        className="action-icon"
                      >
                        <Edit size={16} />
                      </button>
                      <button 
                        onClick={() => handleDeleteReport(report.id, report.file_url)} 
                        className="action-icon destructive"
                      >
                        <Trash size={16} />
                      </button>
                    </div>
                  )}
                </div>

                <span className="report-uploader-text">By: {uploaderDisplay}</span>
                <p className="report-content-text">{report.content}</p>

                {report.file_url && (
                  <a 
                    href={report.file_url} 
                    target="_blank" 
                    rel="noreferrer" 
                    className="report-preview-link flex-center"
                  >
                    <Eye size={14} style={{ marginRight: '6px' }} /> Preview Linked Document
                  </a>
                )}
              </GlassCard>
            );
          })}
        </div>
      )}

      <NavBar />

      <style>{`
        .reports-list-container {
          padding: 16px 20px;
        }

        @media (min-width: 768px) {
          .reports-list-container {
            padding: 24px 0;
          }
        }

        .page-header {
          display: flex;
          align-items: center;
          justify-content: space-between;
          height: 60px;
          margin-bottom: 20px;
        }

        .back-button, .create-report-btn {
          color: var(--text-primary);
        }

        .page-title {
          font-family: var(--font-space-grotesk);
          font-weight: 800;
          font-size: 20px;
          color: var(--text-primary);
        }

        .reports-loading, .reports-empty {
          text-align: center;
          color: var(--text-secondary);
        }

        .reports-list-flow {
          display: grid;
          grid-template-columns: 1fr;
          gap: 16px;
        }

        @media (min-width: 768px) {
          .reports-list-flow {
            grid-template-columns: repeat(2, 1fr);
            gap: 20px;
          }
        }

        @media (min-width: 1200px) {
          .reports-list-flow {
            grid-template-columns: repeat(3, 1fr);
            gap: 24px;
          }
        }

        .report-item-card {
          width: 100%;
        }

        .report-card-header {
          display: flex;
          justify-content: space-between;
          align-items: flex-start;
          width: 100%;
          margin-bottom: 4px;
        }

        .report-card-title {
          font-size: 18px;
          font-weight: 700;
          color: var(--text-primary);
        }

        .action-icon {
          color: var(--text-muted);
          transition: color 0.2s ease;
        }

        .action-icon:hover {
          color: rgb(22, 192, 122);
        }

        .action-icon.destructive:hover {
          color: var(--accent-red);
        }

        .report-uploader-text {
          font-size: 12px;
          color: var(--text-muted);
          display: block;
          margin-bottom: 12px;
        }

        .report-content-text {
          font-size: 14px;
          color: var(--text-primary);
          line-height: 1.5;
          margin-bottom: 16px;
        }

        .report-preview-link {
          display: inline-flex;
          padding: 8px 14px;
          border-radius: 10px;
          background: rgba(22, 192, 122, 0.1);
          color: rgb(22, 192, 122);
          border: 1px solid rgba(22, 192, 122, 0.2);
          font-family: var(--font-space-grotesk);
          font-weight: 700;
          font-size: 13px;
          transition: all 0.2s ease;
        }

        .report-preview-link:hover {
          background: rgba(22, 192, 122, 0.18);
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

const getRoleLabel = (role: string) => {
  switch (role) {
    case 'chairman': return 'Chairman';
    case 'vice_chairman': return 'Vice Chair';
    case 'core_execcom': return 'Core Execcom';
    case 'forum_execcom':
    case 'execcom': return 'Execcom';
    case 'member': return 'Member';
    default: return role;
  }
};
