import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { Folder, Plus, ArrowLeft, MoreVertical, Trash } from 'lucide-react';
import { useAuth } from '../../core/auth-provider';
import { supabase } from '../../core/supabase-client';
import { GlassCard } from '../../shared/components/GlassCard';
import { NavBar } from '../../shared/components/NavBar';

export const FolderListScreen: React.FC = () => {
  const navigate = useNavigate();
  const { permissions, currentUser } = useAuth();
  const [folders, setFolders] = useState<any[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [newFolderName, setNewFolderName] = useState('');
  const [isCreating, setIsCreating] = useState(false);

  const fetchFolders = async () => {
    if (!currentUser || !permissions) return;
    setIsLoading(true);
    try {
      let query = supabase.from('folders').select('*');
      
      // If not Tier 2 or above, only show folders they are member of
      if (!permissions.isAtLeastTier2) {
        const { data: memberFolders } = await supabase
          .from('folder_members')
          .select('folder_id')
          .eq('user_id', currentUser.id);
        
        const folderIds = (memberFolders || []).map((m) => m.folder_id);
        if (folderIds.length > 0) {
          query = query.in('id', folderIds);
        } else {
          setFolders([]);
          setIsLoading(false);
          return;
        }
      }

      const { data, error } = await query.order('name');
      if (error) throw error;
      setFolders(data || []);
    } catch (e) {
      console.error('Error fetching folders:', e);
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    fetchFolders();
  }, [currentUser, permissions]);

  const handleCreateFolder = async () => {
    if (!newFolderName.trim()) return;
    setIsCreating(true);
    try {
      const { data, error } = await supabase
        .from('folders')
        .insert({ name: newFolderName.trim() })
        .select()
        .single();
      
      if (error) throw error;

      // Add current user as member of new folder as owner/lead
      if (data && currentUser) {
        await supabase.from('folder_members').insert({
          folder_id: data.id,
          user_id: currentUser.id,
          folder_role: 'Owner',
        });
      }

      setNewFolderName('');
      setShowCreateModal(false);
      fetchFolders();
    } catch (e) {
      console.error('Error creating folder:', e);
      alert('Failed to create folder');
    } finally {
      setIsCreating(false);
    }
  };

  const handleDeleteFolder = async (id: number, e: React.MouseEvent) => {
    e.stopPropagation();
    if (!window.confirm('Are you sure you want to delete this forum? All members and linked data will be removed.')) return;
    
    try {
      const { error } = await supabase.from('folders').delete().eq('id', id);
      if (error) throw error;
      setFolders(folders.filter((f) => f.id !== id));
    } catch (e) {
      console.error('Delete error:', e);
      alert('Failed to delete folder');
    }
  };

  if (!currentUser || !permissions) return null;

  return (
    <div className="folder-list-container">
      <header className="page-header">
        <button onClick={() => navigate('/home')} className="back-button">
          <ArrowLeft size={20} />
        </button>
        <h2 className="page-title">Active Forums</h2>
        {permissions.canManageFolders && (
          <button onClick={() => setShowCreateModal(true)} className="create-folder-button">
            <Plus size={20} />
          </button>
        )}
      </header>

      {isLoading ? (
        <div className="folders-loading">Loading active forums...</div>
      ) : folders.length === 0 ? (
        <div className="folders-empty">No forums available.</div>
      ) : (
        <div className="folders-grid">
          {folders.map((folder) => (
            <GlassCard
              key={folder.id}
              className="folder-card"
              onClick={() => navigate(`/folders/${folder.id}`)}
              padding="20px"
            >
              <div className="folder-card-header">
                <div className="folder-icon-circle">
                  <Folder size={22} style={{ color: 'rgb(22, 192, 122)' }} />
                </div>
                {permissions.canManageFolders && (
                  <button onClick={(e) => handleDeleteFolder(folder.id, e)} className="delete-card-button">
                    <Trash size={16} />
                  </button>
                )}
              </div>
              <h4 className="folder-card-name">{folder.name}</h4>
              <span className="folder-card-meta">Interactive Hub</span>
            </GlassCard>
          ))}
        </div>
      )}

      {showCreateModal && (
        <div className="modal-overlay">
          <GlassCard className="modal-card" padding="24px">
            <h3 className="modal-title">Create Forum</h3>
            <input
              type="text"
              placeholder="Forum Name (e.g. IEEE, CSI)"
              value={newFolderName}
              onChange={(e) => setNewFolderName(e.target.value)}
              className="modal-input"
            />
            <div className="modal-actions-row">
              <button 
                onClick={() => setShowCreateModal(false)}
                className="modal-cancel-btn"
                disabled={isCreating}
              >
                Cancel
              </button>
              <button
                onClick={handleCreateFolder}
                className="modal-submit-btn"
                disabled={isCreating || !newFolderName.trim()}
              >
                {isCreating ? 'Creating...' : 'Create'}
              </button>
            </div>
          </GlassCard>
        </div>
      )}

      <NavBar />

      <style>{`
        .folder-list-container {
          padding: 16px 20px;
        }

        @media (min-width: 768px) {
          .folder-list-container {
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

        .back-button, .create-folder-button {
          color: var(--text-primary);
          display: flex;
          align-items: center;
          justify-content: center;
        }

        .page-title {
          font-family: var(--font-space-grotesk);
          font-weight: 800;
          font-size: 20px;
          color: var(--text-primary);
        }

        .folders-loading, .folders-empty {
          text-align: center;
          padding: 40px;
          font-size: 15px;
          color: var(--text-secondary);
        }

        .folders-grid {
          display: grid;
          grid-template-columns: repeat(2, 1fr);
          gap: 16px;
          margin-bottom: 40px;
        }

        @media (min-width: 768px) {
          .folders-grid {
            grid-template-columns: repeat(3, 1fr);
            gap: 20px;
          }
        }

        @media (min-width: 1200px) {
          .folders-grid {
            grid-template-columns: repeat(4, 1fr);
            gap: 24px;
          }
        }

        .folder-card {
          display: flex;
          flex-direction: column;
          align-items: flex-start;
          text-align: left;
        }

        .folder-card-header {
          width: 100%;
          display: flex;
          align-items: center;
          justify-content: space-between;
          margin-bottom: 16px;
        }

        .folder-icon-circle {
          width: 44px;
          height: 44px;
          border-radius: 12px;
          background: rgba(22, 192, 122, 0.1);
          display: flex;
          align-items: center;
          justify-content: center;
        }

        .delete-card-button {
          color: var(--text-muted);
          opacity: 0.6;
          transition: all 0.2s ease;
        }

        .delete-card-button:hover {
          color: var(--accent-red);
          opacity: 1;
        }

        .folder-card-name {
          font-size: 18px;
          font-weight: 700;
          color: var(--text-primary);
          margin-bottom: 4px;
        }

        .folder-card-meta {
          font-size: 12px;
          color: var(--text-muted);
        }

        /* Modal Overlays */
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
          margin-bottom: 20px;
        }

        .modal-actions-row {
          display: flex;
          justify-content: flex-end;
          gap: 12px;
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
      `}</style>
    </div>
  );
};
