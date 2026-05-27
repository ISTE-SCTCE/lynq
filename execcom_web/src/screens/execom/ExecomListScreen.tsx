import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { Shield, Plus, ArrowLeft, Trash } from 'lucide-react';
import { useAuth } from '../../core/auth-provider';
import { supabase } from '../../core/supabase-client';
import { GlassCard } from '../../shared/components/GlassCard';
import { NavBar } from '../../shared/components/NavBar';
import { ExecomModel } from '../../models/types';

export const ExecomListScreen: React.FC = () => {
  const navigate = useNavigate();
  const { permissions, currentUser } = useAuth();
  const [execoms, setExecoms] = useState<ExecomModel[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [newExecomName, setNewExecomName] = useState('');
  const [isCreating, setIsCreating] = useState(false);

  const fetchExecoms = async () => {
    if (!currentUser || !permissions) return;
    setIsLoading(true);
    try {
      let query = supabase.from('execom').select('*');
      
      // If not Tier 2 or above, only show execom groups they are member of
      if (!permissions.isAtLeastTier2) {
        const { data: memberExecoms } = await supabase
          .from('execom_members')
          .select('execom_id')
          .eq('user_id', currentUser.id);
        
        const execomIds = (memberExecoms || []).map((m) => m.execom_id);
        if (execomIds.length > 0) {
          query = query.in('id', execomIds);
        } else {
          setExecoms([]);
          setIsLoading(false);
          return;
        }
      }

      const { data, error } = await query.order('name');
      if (error) throw error;
      setExecoms((data || []) as ExecomModel[]);
    } catch (e) {
      console.error('Error fetching execom teams:', e);
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    fetchExecoms();
  }, [currentUser, permissions]);

  const handleCreateExecom = async () => {
    if (!newExecomName.trim()) return;
    setIsCreating(true);
    try {
      const { data, error } = await supabase
        .from('execom')
        .insert({ name: newExecomName.trim() })
        .select()
        .single();
      
      if (error) throw error;

      // Add current user as member of new execom as owner/lead
      if (data && currentUser) {
        await supabase.from('execom_members').insert({
          execom_id: data.id,
          user_id: currentUser.id,
          execom_role: 'Owner',
        });
      }

      setNewExecomName('');
      setShowCreateModal(false);
      fetchExecoms();
    } catch (e) {
      console.error('Error creating execom:', e);
      alert('Failed to create execom');
    } finally {
      setIsCreating(false);
    }
  };

  const handleDeleteExecom = async (id: number, e: React.MouseEvent) => {
    e.stopPropagation();
    if (!window.confirm('Are you sure you want to delete this execom team? All members and linked data will be removed.')) return;
    
    try {
      const { error } = await supabase.from('execom').delete().eq('id', id);
      if (error) throw error;
      setExecoms(execoms.filter((f) => f.id !== id));
    } catch (e) {
      console.error('Delete error:', e);
      alert('Failed to delete execom');
    }
  };

  if (!currentUser || !permissions) return null;

  return (
    <div className="execom-list-container">
      <header className="page-header">
        <button onClick={() => navigate('/home')} className="back-button">
          <ArrowLeft size={20} />
        </button>
        <h2 className="page-title">Execom Teams</h2>
        {permissions.canManageExecom && (
          <button onClick={() => setShowCreateModal(true)} className="create-execom-button">
            <Plus size={20} />
          </button>
        )}
      </header>

      {isLoading ? (
        <div className="execom-loading">Loading execom teams...</div>
      ) : execoms.length === 0 ? (
        <div className="execom-empty">No execom teams available.</div>
      ) : (
        <div className="execom-grid">
          {execoms.map((execom) => (
            <GlassCard
              key={execom.id}
              className="execom-card"
              onClick={() => navigate(`/execom/${execom.id}`)}
              padding="20px"
            >
              <div className="execom-card-header">
                <div className="execom-icon-circle">
                  <Shield size={22} style={{ color: 'rgb(22, 192, 122)' }} />
                </div>
                {permissions.canManageExecom && (
                  <button onClick={(e) => handleDeleteExecom(execom.id, e)} className="delete-card-button">
                    <Trash size={16} />
                  </button>
                )}
              </div>
              <h4 className="execom-card-name">{execom.name}</h4>
              <span className="execom-card-meta">Interactive Hub</span>
            </GlassCard>
          ))}
        </div>
      )}

      {showCreateModal && (
        <div className="modal-overlay">
          <GlassCard className="modal-card" padding="24px">
            <h3 className="modal-title">Create Execom Team</h3>
            <input
              type="text"
              placeholder="Execom Name (e.g. Design, Technical)"
              value={newExecomName}
              onChange={(e) => setNewExecomName(e.target.value)}
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
                onClick={handleCreateExecom}
                className="modal-submit-btn"
                disabled={isCreating || !newExecomName.trim()}
              >
                {isCreating ? 'Creating...' : 'Create'}
              </button>
            </div>
          </GlassCard>
        </div>
      )}

      <NavBar />

      <style>{`
        .execom-list-container {
          padding: 16px 20px;
        }

        @media (min-width: 768px) {
          .execom-list-container {
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

        .back-button, .create-execom-button {
          color: var(--text-primary);
          display: flex;
          align-items: center;
          justify-content: center;
          background: none;
          border: none;
          cursor: pointer;
        }

        .page-title {
          font-family: var(--font-space-grotesk);
          font-weight: 800;
          font-size: 20px;
          color: var(--text-primary);
        }

        .execom-loading, .execom-empty {
          text-align: center;
          padding: 40px;
          font-size: 15px;
          color: var(--text-secondary);
        }

        .execom-grid {
          display: grid;
          grid-template-columns: repeat(2, 1fr);
          gap: 16px;
          margin-bottom: 40px;
        }

        @media (min-width: 768px) {
          .execom-grid {
            grid-template-columns: repeat(3, 1fr);
            gap: 20px;
          }
        }

        @media (min-width: 1200px) {
          .execom-grid {
            grid-template-columns: repeat(4, 1fr);
            gap: 24px;
          }
        }

        .execom-card {
          display: flex;
          flex-direction: column;
          align-items: flex-start;
          text-align: left;
          cursor: pointer;
        }

        .execom-card-header {
          width: 100%;
          display: flex;
          align-items: center;
          justify-content: space-between;
          margin-bottom: 16px;
        }

        .execom-icon-circle {
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
          background: none;
          border: none;
          cursor: pointer;
        }

        .delete-card-button:hover {
          color: var(--accent-red);
          opacity: 1;
        }

        .execom-card-name {
          font-size: 18px;
          font-weight: 700;
          color: var(--text-primary);
          margin-bottom: 4px;
        }

        .execom-card-meta {
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
          width: 100%;
          padding: 10px 14px;
          background: rgba(255, 255, 255, 0.05);
          border: 1px solid var(--border-light);
          border-radius: 10px;
          color: var(--text-primary);
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
          background: none;
          border: none;
          cursor: pointer;
        }

        .modal-submit-btn {
          padding: 10px 16px;
          background: linear-gradient(135deg, rgb(15, 117, 73) 0%, rgb(22, 192, 122) 100%);
          color: #ffffff;
          border-radius: 10px;
          font-size: 14px;
          font-weight: 700;
          border: none;
          cursor: pointer;
        }
      `}</style>
    </div>
  );
};
