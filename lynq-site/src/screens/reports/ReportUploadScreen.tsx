import React, { useState, useEffect } from 'react';
import { useNavigate, useLocation } from 'react-router-dom';
import { ArrowLeft, FileText, Sparkles, X } from 'lucide-react';
import { useAuth } from '../../core/auth-provider';
import { supabase } from '../../core/supabase-client';
import { AppRole, AppRoleLabels } from '../../core/constants';
import { CustomTextField } from '../../shared/components/CustomTextField';
import { PrimaryButton } from '../../shared/components/PrimaryButton';
import { GlassCard } from '../../shared/components/GlassCard';
import { NavBar } from '../../shared/components/NavBar';

export const ReportUploadScreen: React.FC = () => {
  const navigate = useNavigate();
  const location = useLocation();
  const { currentUser, permissions } = useAuth();

  // Check if editing
  const stateData = location.state as { existingReport?: any } | null;
  const existingReport = stateData?.existingReport;
  const isEditing = !!existingReport;

  // Form States
  const [title, setTitle] = useState('');
  const [content, setContent] = useState('');
  const [selectedFile, setSelectedFile] = useState<File | null>(null);
  const [fileName, setFileName] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [visibility, setVisibility] = useState<string[]>([]);

  useEffect(() => {
    if (isEditing && existingReport) {
      setTitle(existingReport.title || '');
      setContent(existingReport.content || '');
      if (existingReport.file_url) {
        setFileName(existingReport.file_url.split('/').pop() || 'Attached File');
      }
      if (Array.isArray(existingReport.visibility)) {
        setVisibility(existingReport.visibility);
      }
    }
  }, [isEditing, existingReport]);

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) {
      if (file.size > 10 * 1024 * 1024) {
        alert('File size must be smaller than 10MB.');
        return;
      }
      setSelectedFile(file);
      setFileName(file.name);
    }
  };

  const uploadReportFile = async (): Promise<string | null> => {
    if (!selectedFile) return null;
    try {
      const timestamp = Date.now();
      const path = `reports/${timestamp}-${selectedFile.name}`;

      const { data, error } = await supabase.storage
        .from('reports')
        .upload(path, selectedFile);

      if (error) throw error;

      const { data: { publicUrl } } = supabase.storage
        .from('reports')
        .getPublicUrl(path);

      return publicUrl;
    } catch (e) {
      console.error('File upload failed:', e);
      return null;
    }
  };

  const handleVisibilityToggle = (roleKey: string) => {
    setVisibility((prev) =>
      prev.includes(roleKey) ? prev.filter((r) => r !== roleKey) : [...prev, roleKey]
    );
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!title.trim() || !currentUser) return;

    setIsLoading(true);
    try {
      let uploadedUrl: string | null = null;
      if (selectedFile) {
        uploadedUrl = await uploadReportFile();
      }

      if (!isEditing) {
        // Insert new report
        const { error } = await supabase.from('event_reports').insert({
          title: title.trim(),
          content: content.trim(),
          file_url: uploadedUrl,
          uploaded_by: currentUser.id,
          created_by_email: currentUser.email,
          visibility,
        });

        if (error) throw error;
        alert('Report uploaded successfully!');
      } else {
        // Update report
        const updateParams: any = {
          title: title.trim(),
          content: content.trim(),
          visibility,
        };
        if (uploadedUrl) {
          updateParams.file_url = uploadedUrl;
        }

        const { error } = await supabase
          .from('event_reports')
          .update(updateParams)
          .eq('id', existingReport.id);

        if (error) throw error;
        alert('Report updated successfully!');
      }

      navigate('/reports');
    } catch (err) {
      console.error('Error submitting report:', err);
      alert('Failed to submit report');
    } finally {
      setIsLoading(false);
    }
  };

  if (!currentUser || !permissions || !permissions.canUploadReports) {
    return (
      <div className="add-member-container flex-center" style={{ minHeight: '300px' }}>
        <span>You do not have permission to upload reports.</span>
      </div>
    );
  }

  const roleList = [
    { label: 'Chairman', value: 'chairman' },
    { label: 'Vice Chair', value: 'vice_chairman' },
    { label: 'Core Execcom', value: 'core_execcom' },
    { label: 'Execcom', value: 'forum_execcom' },
    { label: 'Panel', value: 'panel' },
    { label: 'Member', value: 'member' },
  ];

  return (
    <div className="report-upload-container">
      <header className="page-header">
        <button onClick={() => navigate('/reports')} className="back-button">
          <ArrowLeft size={20} />
        </button>
        <h2 className="page-title">{isEditing ? 'Edit Report' : 'Upload Report'}</h2>
        <div style={{ width: '20px' }}></div>
      </header>

      <form onSubmit={handleSubmit} className="report-upload-form" style={{ marginBottom: '40px' }}>
        <GlassCard className="form-fields-card" padding="24px">
          
          <CustomTextField
            label="Report Title"
            value={title}
            onChange={setTitle}
            placeholder="E.g. IEEE Scoped Hackathon Report"
          />

          <CustomTextField
            label="Report Content / Description"
            value={content}
            onChange={setContent}
            maxLines={8}
            placeholder="Log event summaries, registration metrics, and outputs"
          />

          {/* Attached Document File Row */}
          <div style={{ marginBottom: '20px' }}>
            <label className="form-input-label">Attached Document (Max 10MB)</label>
            <div className="file-selector-row flex-center">
              <span className="file-name-span">{fileName || 'No file selected'}</span>
              <div className="file-actions flex-center">
                <label className="attach-button flex-center">
                  Attach
                  <input 
                    type="file" 
                    accept=".pdf,.doc,.docx,.png,.jpg,.jpeg" 
                    onChange={handleFileChange} 
                    style={{ display: 'none' }} 
                  />
                </label>
                {fileName && (
                  <button 
                    type="button" 
                    onClick={() => { setSelectedFile(null); setFileName(''); }}
                    className="clear-file-btn"
                  >
                    <X size={18} />
                  </button>
                )}
              </div>
            </div>
          </div>

          {/* Visibility Checkboxes */}
          <div style={{ marginBottom: '24px' }}>
            <label className="form-input-label">Visibility (Who can view this report)</label>
            <div className="roles-chips-grid">
              {roleList.map((role) => {
                const isSelected = visibility.includes(role.value);
                return (
                  <button
                    key={role.value}
                    type="button"
                    onClick={() => handleVisibilityToggle(role.value)}
                    className={`role-filter-chip ${isSelected ? 'active' : ''}`}
                  >
                    {role.label}
                  </button>
                );
              })}
            </div>
          </div>

          <div style={{ marginTop: '30px' }}>
            <PrimaryButton
              text={isEditing ? 'Update Report' : 'Upload Report'}
              type="submit"
              isLoading={isLoading}
              disabled={!title.trim()}
              icon={Sparkles}
            />
          </div>
        </GlassCard>
      </form>

      <NavBar />

      <style>{`
        .report-upload-container {
          padding: 16px 20px;
        }

        .page-header {
          display: flex;
          align-items: center;
          justify-content: space-between;
          height: 60px;
          margin-bottom: 20px;
        }

        .back-button {
          color: var(--text-primary);
        }

        .page-title {
          font-family: var(--font-space-grotesk);
          font-weight: 800;
          font-size: 20px;
          color: var(--text-primary);
        }

        .report-upload-form {
          width: 100%;
        }

        .form-fields-card {
          width: 100%;
        }

        .form-input-label {
          display: block;
          font-family: var(--font-space-grotesk);
          font-size: 13px;
          font-weight: 600;
          color: var(--text-secondary);
          margin-bottom: 8px;
        }

        .file-selector-row {
          width: 100%;
          justify-content: space-between;
          padding: 12px 16px;
          background: rgba(255,255,255,0.03);
          border: 1px solid var(--border-light);
          border-radius: 14px;
        }

        .file-name-span {
          font-size: 13px;
          color: var(--text-secondary);
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
          max-width: 180px;
        }

        .file-actions {
          gap: 12px;
        }

        .attach-button {
          padding: 6px 12px;
          border-radius: 8px;
          background: rgba(22, 192, 122, 0.1);
          color: rgb(22, 192, 122);
          border: 1px solid rgba(22, 192, 122, 0.2);
          font-family: var(--font-space-grotesk);
          font-weight: 700;
          font-size: 12px;
          cursor: pointer;
        }

        .clear-file-btn {
          color: var(--accent-red);
        }

        .roles-chips-grid {
          display: flex;
          flex-wrap: wrap;
          gap: 8px;
        }

        .role-filter-chip {
          padding: 6px 12px;
          border-radius: 20px;
          background: rgba(255, 255, 255, 0.03);
          border: 1px solid var(--border-light);
          color: var(--text-secondary);
          font-size: 12px;
        }

        .role-filter-chip.active {
          background: rgba(22, 192, 122, 0.15);
          border-color: rgba(22, 192, 122, 0.3);
          color: rgb(22, 192, 122);
          font-weight: 700;
        }
      `}</style>
    </div>
  );
};
