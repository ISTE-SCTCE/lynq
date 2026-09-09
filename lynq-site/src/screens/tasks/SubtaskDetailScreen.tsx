import React, { useState, useEffect } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { ArrowLeft, Clock, AlertCircle, FileText, CheckCircle2, ChevronRight, Check, Trash2, Edit, Play, FileCheck, X, Link as LinkIcon, Send, Upload, Eye, ExternalLink } from 'lucide-react';
import { useAuth } from '../../core/auth-provider';
import { supabase } from '../../core/supabase-client';
import { GlassCard } from '../../shared/components/GlassCard';
import { PrimaryButton } from '../../shared/components/PrimaryButton';
import { NavBar } from '../../shared/components/NavBar';

export const SubtaskDetailScreen: React.FC = () => {
  const navigate = useNavigate();
  const { taskId, subtaskId } = useParams<{ taskId: string; subtaskId: string }>();
  const { currentUser, permissions } = useAuth();

  const [subtask, setSubtask] = useState<any | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isUploading, setIsUploading] = useState(false);
  const [notes, setNotes] = useState('');
  const [driveLink, setDriveLink] = useState('');
  const [errorMsg, setErrorMsg] = useState<string | null>(null);

  // Rejection dialog
  const [showRejectModal, setShowRejectModal] = useState<any | null>(null); // Proof model to reject
  const [rejectionReason, setRejectionReason] = useState('');
  const [isRejecting, setIsRejecting] = useState(false);

  const loadSubtask = async () => {
    if (!subtaskId) return;
    setIsLoading(true);
    try {
      const { data, error } = await supabase
        .from('subtasks')
        .select('*, task_proofs(*)')
        .eq('id', parseInt(subtaskId))
        .single();
      
      if (error) throw error;
      setSubtask(data);
    } catch (e: any) {
      console.error('Error loading subtask:', e);
      setErrorMsg(e.message || 'Subtask not found.');
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    loadSubtask();
  }, [subtaskId]);

  if (!currentUser || !permissions) return null;

  if (isLoading) {
    return (
      <div className="subtask-detail-loading flex-center" style={{ height: '100vh', flexDirection: 'column' }}>
        <div className="spinner"></div>
        <span style={{ marginTop: '16px', color: 'var(--text-muted)' }}>Loading subtask details...</span>
      </div>
    );
  }

  if (!subtask) {
    return (
      <div className="subtask-detail-error flex-center" style={{ height: '100vh', flexDirection: 'column' }}>
        <AlertCircle size={48} style={{ color: 'var(--accent-red)' }} />
        <span style={{ marginTop: '16px', color: 'var(--text-muted)' }}>Subtask not found.</span>
        <button onClick={() => navigate(-1)} className="back-to-list-btn">Go Back</button>
      </div>
    );
  }

  const isComplete = subtask.status === 'completed';
  const canVerify = permissions.isAtLeastTier1;
  
  // Checking if current user is assigned to the subtask
  const isMyTask = subtask.assigned_to?.includes(currentUser.id);
  const canUpload = isMyTask || permissions.isAtLeastTier2;
  const needsProof = subtask.proof_required && subtask.status !== 'completed' && subtask.status !== 'awaiting_verification';

  const getPriorityColor = (prio: string) => {
    switch (prio) {
      case 'critical': return '#ef4444';
      case 'high': return '#f97316';
      case 'medium': return '#fbbf24';
      default: return '#16c07a';
    }
  };

  const getStatusBadge = (status: string) => {
    switch (status) {
      case 'completed':
        return { label: 'Completed', color: '#16c07a', icon: Check };
      case 'in_progress':
        return { label: 'Active', color: '#2563eb', icon: Play };
      case 'awaiting_verification':
      case 'review':
        return { label: 'Awaiting Verification', color: '#fbbf24', icon: FileCheck };
      default:
        return { label: 'Pending', color: '#6b7280', icon: Clock };
    }
  };

  const getFileTypeIcon = (type: string) => {
    switch (type) {
      case 'pdf': return FileText;
      case 'drive_link': return LinkIcon;
      default: return FileText;
    }
  };

  const handleFileUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    setIsUploading(true);
    setErrorMsg(null);

    try {
      const ext = file.name.split('.').pop() || 'jpg';
      const path = `proofs/${subtask.id}/${Date.now()}.${ext}`;
      
      const { error: uploadError } = await supabase.storage
        .from('task-proofs')
        .upload(path, file);
      
      if (uploadError) throw uploadError;

      const { data: publicUrlData } = supabase.storage
        .from('task-proofs')
        .getPublicUrl(path);

      const publicUrl = publicUrlData.publicUrl;

      let fileType = 'image';
      if (ext === 'pdf') fileType = 'pdf';
      else if (['mp4', 'mov'].includes(ext)) fileType = 'video';
      else if (['docx', 'doc'].includes(ext)) fileType = 'document';

      const { error: insertError } = await supabase.from('task_proofs').insert({
        subtask_id: subtask.id,
        uploaded_by: currentUser.id,
        file_url: publicUrl,
        file_type: fileType,
        notes: notes.trim() || null,
      });

      if (insertError) throw insertError;

      // Update subtask status
      await supabase
        .from('subtasks')
        .update({ status: 'awaiting_verification' })
        .eq('id', subtask.id);

      setNotes('');
      loadSubtask();
    } catch (e: any) {
      console.error('Upload failed:', e);
      setErrorMsg(e.message || 'File upload failed.');
    } finally {
      setIsUploading(false);
    }
  };

  const handleDriveLinkSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!driveLink.trim()) return;

    setIsUploading(true);
    setErrorMsg(null);

    try {
      const { error: insertError } = await supabase.from('task_proofs').insert({
        subtask_id: subtask.id,
        uploaded_by: currentUser.id,
        file_url: driveLink.trim(),
        file_type: 'drive_link',
        notes: notes.trim() || null,
      });

      if (insertError) throw insertError;

      // Update subtask status
      await supabase
        .from('subtasks')
        .update({ status: 'awaiting_verification' })
        .eq('id', subtask.id);

      setDriveLink('');
      setNotes('');
      loadSubtask();
    } catch (e: any) {
      console.error('Drive link submission failed:', e);
      setErrorMsg(e.message || 'Failed to submit drive link.');
    } finally {
      setIsUploading(false);
    }
  };

  const handleReviewProof = async (proof: any, status: 'approved' | 'rejected') => {
    try {
      const { error } = await supabase
        .from('task_proofs')
        .update({
          status: status,
          reviewed_by: currentUser.id,
          reviewed_at: new Date().toISOString(),
          rejection_reason: status === 'rejected' ? rejectionReason.trim() : null,
        })
        .eq('id', proof.id);

      if (error) throw error;

      if (status === 'approved') {
        // Complete the subtask
        await supabase
          .from('subtasks')
          .update({ status: 'completed' })
          .eq('id', subtask.id);

        // Update main task completion via RPC
        await supabase.rpc('update_task_completion', { task_id_param: parseInt(taskId!) });
      } else {
        // Revert subtask to pending
        await supabase
          .from('subtasks')
          .update({ status: 'pending' })
          .eq('id', subtask.id);
      }

      setShowRejectModal(null);
      setRejectionReason('');
      loadSubtask();
    } catch (e: any) {
      console.error('Review submission failed:', e);
      alert('Failed to submit review: ' + e.message);
    }
  };

  const subPrioColor = getPriorityColor(subtask.priority);
  const subStatus = getStatusBadge(subtask.status);
  const StatusIcon = subStatus.icon;

  return (
    <div className="subtask-detail-container" style={{ paddingBottom: '80px' }}>
      <header className="page-header">
        <button onClick={() => navigate(-1)} className="back-button">
          <ArrowLeft size={20} />
        </button>
        <h2 className="page-title">Subtask View</h2>
        <div style={{ width: '20px' }}></div>
      </header>

      {errorMsg && (
        <div className="error-banner">
          {errorMsg}
        </div>
      )}

      {/* Subtask Status Box */}
      <div 
        className="subtask-status-box" 
        style={{
          borderColor: `${subStatus.color}40`,
          backgroundColor: `${subStatus.color}08`,
          borderLeft: `5px solid ${subStatus.color}`
        }}
      >
        <div className="flex-row-between">
          <div className="status-label flex-center" style={{ color: subStatus.color, gap: '6px' }}>
            <StatusIcon size={18} />
            <span style={{ fontWeight: '700', fontSize: '13px' }}>{subStatus.label}</span>
          </div>
          <span 
            className="prio-tag" 
            style={{ 
              backgroundColor: `${subPrioColor}18`, 
              color: subPrioColor, 
              border: `1px solid ${subPrioColor}35` 
            }}
          >
            {subtask.priority.toUpperCase()} PRIORITY
          </span>
        </div>
        <h1 className="subtask-title-text">{subtask.title}</h1>
        {subtask.description && <p className="subtask-desc-text">{subtask.description}</p>}
        
        {subtask.deadline && (
          <div className="deadline flex-center" style={{ color: 'var(--text-muted)', fontSize: '11px', marginTop: '12px', justifyContent: 'flex-start' }}>
            <Clock size={12} style={{ marginRight: '6px' }} />
            <span>Due on {new Date(subtask.deadline).toLocaleDateString()}</span>
          </div>
        )}
      </div>

      {/* Submitted Proofs list */}
      {subtask.task_proofs && subtask.task_proofs.length > 0 && (
        <div className="section-block">
          <h3 className="section-title">Submitted Proofs</h3>
          <div className="proofs-list">
            {subtask.task_proofs.map((proof: any) => {
              const ProofIcon = getFileTypeIcon(proof.file_type);
              const proofStatus = getStatusBadge(proof.status);

              return (
                <GlassCard key={proof.id} className="proof-card" padding="16px">
                  <div className="flex-row-between">
                    <div className="proof-meta flex-center" style={{ gap: '10px', justifyContent: 'flex-start' }}>
                      <div 
                        className="proof-icon-holder flex-center" 
                        style={{ backgroundColor: `${proofStatus.color}15`, color: proofStatus.color }}
                      >
                        <ProofIcon size={18} />
                      </div>
                      <div className="proof-text-info">
                        <span className="proof-type-lbl">
                          {proof.file_type === 'drive_link' ? 'Drive Link / URL' : 'Uploaded Document'}
                        </span>
                        <span className="proof-status-lbl" style={{ color: proofStatus.color }}>
                          {proof.status.toUpperCase()}
                        </span>
                      </div>
                    </div>

                    <a 
                      href={proof.file_url} 
                      target="_blank" 
                      rel="noopener noreferrer" 
                      className="view-proof-btn flex-center"
                    >
                      <ExternalLink size={13} style={{ marginRight: '4px' }} />
                      View
                    </a>
                  </div>

                  {proof.notes && <p className="proof-notes-text">Notes: {proof.notes}</p>}

                  {proof.rejection_reason && (
                    <div className="rejection-reason-box">
                      <strong>Rejection Reason:</strong> {proof.rejection_reason}
                    </div>
                  )}

                  {canVerify && proof.status === 'pending' && (
                    <div className="review-actions flex-center" style={{ gap: '10px', marginTop: '16px' }}>
                      <button 
                        onClick={() => setShowRejectModal(proof)}
                        className="review-btn reject flex-center"
                      >
                        Reject
                      </button>
                      <button 
                        onClick={() => handleReviewProof(proof, 'approved')}
                        className="review-btn approve flex-center"
                      >
                        Approve
                      </button>
                    </div>
                  )}
                </GlassCard>
              );
            })}
          </div>
        </div>
      )}

      {/* Upload/Submit proof block */}
      {canUpload && needsProof && (
        <GlassCard className="submit-proof-box" padding="20px" style={{ marginTop: '24px' }}>
          <h3 className="submit-title" style={{ fontFamily: 'var(--font-space-grotesk)', margin: '0 0 4px 0' }}>Submit Proof</h3>
          <p className="submit-subtitle" style={{ fontSize: '12px', color: 'var(--text-muted)', margin: '0 0 16px 0' }}>
            Upload document/image proofs to verify completion
          </p>

          <div className="form-group" style={{ marginBottom: '14px' }}>
            <textarea 
              className="notes-input" 
              placeholder="Add submission notes or remarks... (optional)"
              value={notes}
              onChange={e => setNotes(e.target.value)}
              rows={2}
            />
          </div>

          {isUploading ? (
            <div className="flex-center" style={{ padding: '16px 0' }}>
              <div className="spinner"></div>
            </div>
          ) : (
            <div className="upload-options flex-center" style={{ flexDirection: 'column', gap: '12px' }}>
              {/* File upload button */}
              <label className="file-upload-lbl flex-center">
                <Upload size={16} style={{ marginRight: '8px' }} />
                Upload Evidence File
                <input 
                  type="file" 
                  onChange={handleFileUpload} 
                  style={{ display: 'none' }}
                  accept=".jpg,.jpeg,.png,.pdf,.doc,.docx,.mp4,.mov" 
                />
              </label>

              <div className="divider-text">OR SUBMIT URL</div>

              {/* URL paste input */}
              <form onSubmit={handleDriveLinkSubmit} className="url-form flex-center" style={{ width: '100%' }}>
                <input 
                  type="url" 
                  className="url-input" 
                  placeholder="Paste Google Drive link or file URL"
                  value={driveLink}
                  onChange={e => setDriveLink(e.target.value)}
                  required
                />
                <button type="submit" className="url-submit-btn flex-center">
                  <Send size={14} />
                </button>
              </form>
            </div>
          )}
        </GlassCard>
      )}

      {/* Rejection Modal Dialog */}
      {showRejectModal !== null && (
        <div className="modal-overlay flex-center" onClick={() => setShowRejectModal(null)}>
          <GlassCard className="reject-modal" padding="20px" onClick={e => e.stopPropagation()}>
            <div className="modal-header flex-center" style={{ justifyContent: 'space-between', marginBottom: '16px' }}>
              <h4 className="modal-title" style={{ margin: 0, fontFamily: 'var(--font-space-grotesk)' }}>Reject Proof</h4>
              <button className="close-btn" onClick={() => setShowRejectModal(null)}>
                <X size={18} />
              </button>
            </div>
            
            <div className="form-group" style={{ marginBottom: '16px' }}>
              <label className="form-label">Reason for Rejection</label>
              <textarea 
                className="notes-input" 
                placeholder="Why is this submission rejected?"
                value={rejectionReason}
                onChange={e => setRejectionReason(e.target.value)}
                rows={3}
                required
              />
            </div>

            <div className="modal-actions flex-center" style={{ justifyContent: 'flex-end', gap: '10px' }}>
              <button className="modal-btn cancel" onClick={() => setShowRejectModal(null)}>Cancel</button>
              <button 
                className="modal-btn confirm" 
                onClick={() => handleReviewProof(showRejectModal, 'rejected')}
                disabled={!rejectionReason.trim() || isRejecting}
              >
                Reject Proof
              </button>
            </div>
          </GlassCard>
        </div>
      )}

      <NavBar />

      <style>{`
        .subtask-detail-container {
          padding: 16px 20px;
          max-width: 680px;
          margin: 0 auto;
        }

        .page-header {
          display: flex;
          align-items: center;
          justify-content: space-between;
          height: 60px;
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

        .error-banner {
          background: rgba(239, 68, 68, 0.15);
          border: 1px solid rgba(239, 68, 68, 0.3);
          color: #ef4444;
          padding: 12px;
          border-radius: 12px;
          font-size: 13px;
          font-weight: 600;
          margin-bottom: 16px;
        }

        .subtask-status-box {
          padding: 16px 20px;
          border-radius: 0 16px 16px 0;
          border: 1px solid transparent;
          margin: 16px 0 24px 0;
        }

        .prio-tag {
          font-family: var(--font-space-grotesk);
          font-weight: 700;
          font-size: 10px;
          padding: 4px 8px;
          border-radius: 20px;
        }

        .subtask-title-text {
          font-family: var(--font-space-grotesk);
          font-size: 22px;
          font-weight: 800;
          color: var(--text-primary);
          margin: 12px 0 8px 0;
          line-height: 1.3;
        }

        .subtask-desc-text {
          font-size: 14px;
          color: var(--text-muted);
          line-height: 1.45;
          margin: 0;
        }

        .section-block {
          margin-top: 24px;
        }

        .section-title {
          font-family: var(--font-space-grotesk);
          font-size: 15px;
          font-weight: 800;
          color: var(--text-primary);
          margin: 0 0 12px 4px;
        }

        .proofs-list {
          display: flex;
          flex-direction: column;
          gap: 12px;
        }

        .proof-card {
          width: 100%;
        }

        .flex-row-between {
          display: flex;
          justify-content: space-between;
          align-items: center;
        }

        .proof-icon-holder {
          width: 36px;
          height: 36px;
          border-radius: 8px;
          flex-shrink: 0;
        }

        .proof-text-info {
          display: flex;
          flex-direction: column;
          gap: 2px;
        }

        .proof-type-lbl {
          font-family: var(--font-space-grotesk);
          font-weight: 700;
          font-size: 13px;
          color: var(--text-primary);
        }

        .proof-status-lbl {
          font-size: 10px;
          font-weight: 700;
        }

        .view-proof-btn {
          padding: 6px 12px;
          border-radius: 8px;
          background: rgba(255,255,255,0.04);
          border: 1px solid var(--border-light);
          color: var(--text-secondary);
          font-family: var(--font-space-grotesk);
          font-weight: 700;
          font-size: 12px;
          cursor: pointer;
        }

        .proof-notes-text {
          font-size: 12px;
          color: var(--text-muted);
          background: rgba(255,255,255,0.01);
          border-radius: 8px;
          padding: 8px 10px;
          border-left: 2px solid var(--border-light);
          margin: 12px 0 0 0;
        }

        .rejection-reason-box {
          font-size: 12px;
          color: #ef4444;
          background: rgba(239, 68, 68, 0.05);
          border-radius: 8px;
          padding: 8px 10px;
          border-left: 2px solid #ef4444;
          margin-top: 12px;
        }

        .review-actions {
          width: 100%;
        }

        .review-btn {
          flex: 1;
          padding: 10px;
          border-radius: 8px;
          font-family: var(--font-space-grotesk);
          font-weight: 700;
          font-size: 13px;
          cursor: pointer;
          border: none;
        }

        .review-btn.approve {
          background: rgb(22, 192, 122);
          color: #fff;
        }

        .review-btn.reject {
          background: rgba(239, 68, 68, 0.15);
          color: #ef4444;
          border: 1px solid rgba(239, 68, 68, 0.25);
        }

        /* Submit Proof Card */
        .notes-input {
          width: 100%;
          background: rgba(255,255,255,0.02);
          border: 1px solid var(--border-light);
          border-radius: 10px;
          padding: 10px 12px;
          font-family: var(--font-inter);
          font-size: 13px;
          color: var(--text-primary);
          outline: none;
          resize: none;
        }

        .file-upload-lbl {
          width: 100%;
          padding: 12px;
          background: rgb(22, 192, 122);
          color: #fff;
          border-radius: 12px;
          font-family: var(--font-space-grotesk);
          font-weight: 700;
          font-size: 14px;
          cursor: pointer;
        }

        .divider-text {
          width: 100%;
          text-align: center;
          font-family: var(--font-space-grotesk);
          font-weight: 700;
          font-size: 10px;
          color: var(--text-muted);
          position: relative;
          margin: 4px 0;
        }

        .url-form {
          display: flex;
          gap: 8px;
          width: 100%;
        }

        .url-input {
          flex: 1;
          background: rgba(255,255,255,0.02);
          border: 1px solid var(--border-light);
          border-radius: 10px;
          padding: 10px 12px;
          font-family: var(--font-inter);
          font-size: 13px;
          color: var(--text-primary);
          outline: none;
        }

        .url-submit-btn {
          width: 40px;
          height: 40px;
          background: rgba(22, 192, 122, 0.15);
          color: rgb(22, 192, 122);
          border-radius: 10px;
          cursor: pointer;
        }

        /* Modal styling */
        .modal-overlay {
          position: fixed;
          top: 0;
          left: 0;
          right: 0;
          bottom: 0;
          background: rgba(0,0,0,0.6);
          backdrop-filter: blur(5px);
          z-index: 1000;
        }

        .reject-modal {
          width: 90%;
          max-width: 400px;
        }

        .form-label {
          font-family: var(--font-space-grotesk);
          font-size: 12px;
          font-weight: 700;
          color: var(--text-muted);
          margin-bottom: 6px;
          display: block;
        }

        .modal-btn {
          padding: 10px 16px;
          border-radius: 8px;
          font-family: var(--font-space-grotesk);
          font-weight: 700;
          font-size: 13px;
          cursor: pointer;
        }

        .modal-btn.cancel {
          background: transparent;
          color: var(--text-muted);
        }

        .modal-btn.confirm {
          background: #ef4444;
          color: #fff;
          border: none;
        }

        .modal-btn.confirm:disabled {
          opacity: 0.5;
          cursor: not-allowed;
        }

        .close-btn {
          color: var(--text-muted);
        }
      `}</style>
    </div>
  );
};
