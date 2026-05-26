import React, { useState, useEffect } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { ArrowLeft, FileText, Sparkles, Loader, Link as LinkIcon } from 'lucide-react';
import { useAuth } from '../../core/auth-provider';
import { supabase } from '../../core/supabase-client';
import { CustomTextField } from '../../shared/components/CustomTextField';
import { PrimaryButton } from '../../shared/components/PrimaryButton';
import { GlassCard } from '../../shared/components/GlassCard';

import { NavBar } from '../../shared/components/NavBar';

export const BudgetRequestScreen: React.FC = () => {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const { currentUser, permissions } = useAuth();
  
  const folderParam = searchParams.get('folder');
  const folderId = folderParam ? parseInt(folderParam) : null;

  // Form States
  const [amount, setAmount] = useState('');
  const [reason, setReason] = useState('');
  const [proposalFile, setProposalFile] = useState<File | null>(null);
  const [proposalName, setProposalName] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [folders, setFolders] = useState<any[]>([]);
  const [selectedFolder, setSelectedFolder] = useState<number | ''>(folderId || '');

  useEffect(() => {
    if (!currentUser) return;
    
    const fetchForums = async () => {
      try {
        const { data: memberData } = await supabase
          .from('folder_members')
          .select('folder_id, folders:folders(id, name)')
          .eq('user_id', currentUser.id);

        const loadedForums = (memberData || []).map((m: any) => m.folders).filter((f) => f);
        setFolders(loadedForums);
        if (loadedForums.length > 0 && selectedFolder === '') {
          setSelectedFolder(loadedForums[0].id);
        }
      } catch (e) {
        console.error('Error fetching forums for requests:', e);
      }
    };

    fetchForums();
  }, [currentUser]);

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) {
      setProposalFile(file);
      setProposalName(file.name);
    }
  };

  const uploadProposal = async (): Promise<string | null> => {
    if (!proposalFile) return null;
    try {
      const ext = proposalFile.name.split('.').pop();
      const fileName = `${crypto.randomUUID()}.${ext}`;
      const path = `proposals/${fileName}`;

      const { data, error } = await supabase.storage
        .from('proposals')
        .upload(path, proposalFile);

      if (error) throw error;

      const { data: { publicUrl } } = supabase.storage
        .from('proposals')
        .getPublicUrl(path);

      return publicUrl;
    } catch (e) {
      console.error('Proposal file upload failed:', e);
      return null;
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    const amt = parseFloat(amount);
    if (isNaN(amt) || !selectedFolder || !currentUser) return;

    setIsLoading(true);
    try {
      let uploadedUrl: string | null = null;
      if (proposalFile) {
        uploadedUrl = await uploadProposal();
      }

      const { error } = await supabase.from('budget_requests').insert({
        folder_id: selectedFolder,
        requested_by: currentUser.id,
        amount: amt,
        reason: reason.trim(),
        proposal_url: uploadedUrl,
        status: 'pending',
      });

      if (error) throw error;
      alert('Budget request submitted successfully!');
      navigate(folderId ? `/budget?folder=${folderId}` : '/budget');
    } catch (err) {
      console.error('Submit budget request error:', err);
      alert('Failed to submit budget request');
    } finally {
      setIsLoading(false);
    }
  };

  if (!currentUser || !permissions) return null;

  return (
    <div className="budget-request-container">
      <header className="page-header">
        <button onClick={() => navigate(folderId ? `/budget?folder=${folderId}` : '/budget')} className="back-button">
          <ArrowLeft size={20} />
        </button>
        <h2 className="page-title">Request Budget</h2>
        <div style={{ width: '20px' }}></div>
      </header>

      <form onSubmit={handleSubmit} className="request-form" style={{ marginBottom: '40px' }}>
        <GlassCard className="form-fields-card" padding="24px">
          
          <div style={{ marginBottom: '16px' }}>
            <label className="form-input-label">Forum Scoped Association</label>
            <select
              value={selectedFolder}
              onChange={(e) => setSelectedFolder(parseInt(e.target.value))}
              className="form-select-field"
              disabled={folders.length === 0}
            >
              {folders.map((f) => (
                <option key={f.id} value={f.id}>
                  {f.name}
                </option>
              ))}
            </select>
          </div>

          <CustomTextField
            label="Requested Amount (₹)"
            value={amount}
            onChange={setAmount}
            type="number"
            placeholder="Enter requested budget"
          />

          <CustomTextField
            label="Detailed Justification / Reason"
            value={reason}
            onChange={setReason}
            maxLines={4}
            placeholder="Provide budget breakdown and purposes"
          />

          {/* Proposal Document Uploader */}
          <div style={{ marginBottom: '24px' }}>
            <label className="form-input-label">Proposal Document (Optional PDF/Doc)</label>
            <label className="document-uploader-block flex-center">
              <FileText size={24} style={{ color: 'var(--text-muted)', marginRight: '10px' }} />
              <span className="uploader-label-text">
                {proposalName || 'Attach proposal invoice/document'}
              </span>
              <input 
                type="file" 
                accept=".pdf,.doc,.docx,.png,.jpg,.jpeg" 
                onChange={handleFileChange} 
                style={{ display: 'none' }} 
              />
            </label>
          </div>

          <div style={{ marginTop: '30px' }}>
            <PrimaryButton
              text="Submit Request"
              type="submit"
              isLoading={isLoading}
              disabled={!amount || !selectedFolder}
              icon={Sparkles}
            />
          </div>
        </GlassCard>
      </form>

      <NavBar />

      <style>{`
        .budget-request-container {
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

        .request-form {
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

        .form-select-field {
          width: 100%;
          padding: 14px;
          background: rgba(255, 255, 255, 0.04);
          border: 1px solid var(--border-light);
          border-radius: 14px;
          color: var(--text-primary);
          outline: none;
        }

        .document-uploader-block {
          width: 100%;
          border: 1px dashed var(--border-light);
          background-color: rgba(255, 255, 255, 0.03);
          border-radius: 14px;
          padding: 18px 16px;
          cursor: pointer;
          transition: all 0.2s ease;
        }

        .document-uploader-block:hover {
          background-color: rgba(255, 255, 255, 0.06);
        }

        .uploader-label-text {
          font-size: 13px;
          color: var(--text-secondary);
          font-weight: 500;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
          max-width: 260px;
        }
      `}</style>
    </div>
  );
};
