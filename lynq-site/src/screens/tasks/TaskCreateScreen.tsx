import React, { useState, useEffect } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { ArrowLeft, Check, Sparkles, UserPlus, Calendar, Layers, ShieldCheck } from 'lucide-react';
import { useAuth } from '../../core/auth-provider';
import { supabase } from '../../core/supabase-client';
import { GlassCard } from '../../shared/components/GlassCard';
import { PrimaryButton } from '../../shared/components/PrimaryButton';

export const TaskCreateScreen: React.FC = () => {
  const navigate = useNavigate();
  const { taskId } = useParams<{ taskId?: string }>();
  const isSubtask = !!taskId;
  const { currentUser, permissions } = useAuth();

  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [priority, setPriority] = useState<'low' | 'medium' | 'high' | 'critical'>('medium');
  const [deadline, setDeadline] = useState('');
  const [selectedForumId, setSelectedForumId] = useState<number | ''>('');
  const [proofRequired, setProofRequired] = useState(true);
  
  const [allUsers, setAllUsers] = useState<any[]>([]);
  const [selectedUsers, setSelectedUsers] = useState<string[]>([]);
  const [searchQuery, setSearchQuery] = useState('');
  const [folders, setFolders] = useState<any[]>([]);
  
  const [isSaving, setIsSaving] = useState(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);

  useEffect(() => {
    const loadFormOptions = async () => {
      try {
        // Fetch all users
        const { data: userData, error: userError } = await supabase
          .from('profiles')
          .select('id, name, role, post')
          .order('name');
        
        if (userError) throw userError;
        setAllUsers(userData || []);

        // Fetch folders if not a subtask
        if (!isSubtask) {
          const { data: folderData, error: folderError } = await supabase
            .from('folders')
            .select('id, name')
            .order('name');
          
          if (folderError) throw folderError;
          setFolders(folderData || []);
        }
      } catch (e: any) {
        console.error('Error loading task configurations:', e);
        setErrorMsg('Failed to load selection options.');
      }
    };

    loadFormOptions();
  }, [isSubtask]);

  if (!currentUser || !permissions) return null;

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!title.trim()) {
      setErrorMsg('Title is required.');
      return;
    }

    setIsSaving(true);
    setErrorMsg(null);

    try {
      if (isSubtask) {
        // Create Subtask
        const { error } = await supabase.from('subtasks').insert({
          task_id: parseInt(taskId!),
          title: title.trim(),
          description: description.trim() || null,
          assigned_to: selectedUsers,
          deadline: deadline || null,
          priority,
          proof_required: proofRequired,
        });

        if (error) throw error;
      } else {
        // Create main Task
        const { error } = await supabase.from('tasks').insert({
          title: title.trim(),
          description: description.trim() || null,
          created_by: currentUser.id,
          assigned_to: selectedUsers,
          forum_id: selectedForumId || null,
          deadline: deadline || null,
          priority,
          status: 'pending',
        });

        if (error) throw error;
      }

      navigate(-1);
    } catch (e: any) {
      console.error('Error saving task:', e);
      setErrorMsg(e.message || 'An error occurred while saving.');
    } finally {
      setIsSaving(false);
    }
  };

  const toggleUserSelection = (userId: string) => {
    setSelectedUsers(prev => 
      prev.includes(userId) ? prev.filter(id => id !== userId) : [...prev, userId]
    );
  };

  const filteredUsers = searchQuery.trim() === ''
    ? allUsers
    : allUsers.filter(u => u.name?.toLowerCase().includes(searchQuery.toLowerCase()));

  const priorities: { value: 'low' | 'medium' | 'high' | 'critical'; label: string; color: string }[] = [
    { value: 'low', label: 'Low', color: '#16c07a' },
    { value: 'medium', label: 'Medium', color: '#fbbf24' },
    { value: 'high', label: 'High', color: '#f97316' },
    { value: 'critical', label: 'Critical', color: '#ef4444' },
  ];

  return (
    <div className="task-create-container">
      <header className="page-header">
        <button onClick={() => navigate(-1)} className="back-button">
          <ArrowLeft size={20} />
        </button>
        <h2 className="page-title">{isSubtask ? 'Create Subtask' : 'Create Task'}</h2>
        <div style={{ width: '20px' }}></div>
      </header>

      <form onSubmit={handleSave} className="task-create-form" style={{ marginBottom: '50px' }}>
        {errorMsg && (
          <div className="error-banner">
            {errorMsg}
          </div>
        )}

        <GlassCard className="form-card" padding="20px">
          {/* Title */}
          <div className="form-group">
            <label className="form-label">Task Title</label>
            <input 
              type="text" 
              className="form-input" 
              placeholder="What needs to be done?"
              value={title}
              onChange={e => setTitle(e.target.value)}
              required
            />
          </div>

          {/* Description */}
          <div className="form-group">
            <label className="form-label">Description (Optional)</label>
            <textarea 
              className="form-input textarea" 
              placeholder="Add details, instructions, links..."
              value={description}
              onChange={e => setDescription(e.target.value)}
              rows={4}
            />
          </div>
        </GlassCard>

        {/* Priority */}
        <div className="section-title">Select Priority</div>
        <div className="priority-selector">
          {priorities.map((p) => {
            const isSelected = priority === p.value;
            return (
              <button
                type="button"
                key={p.value}
                onClick={() => setPriority(p.value)}
                className={`prio-btn ${isSelected ? 'active' : ''}`}
                style={{
                  '--prio-color': p.color,
                  backgroundColor: isSelected ? `${p.color}18` : 'rgba(255,255,255,0.02)',
                  borderColor: isSelected ? p.color : 'var(--border-light)'
                } as any}
              >
                <div className="dot" style={{ backgroundColor: p.color }}></div>
                {p.label}
              </button>
            );
          })}
        </div>

        {/* Deadline Picker */}
        <div className="section-title">Set Deadline</div>
        <GlassCard padding="14px" className="meta-card">
          <div className="form-group compact">
            <Calendar size={18} className="meta-icon" />
            <input 
              type="date" 
              className="form-input-date"
              value={deadline}
              onChange={e => setDeadline(e.target.value)}
            />
          </div>
        </GlassCard>

        {/* Forum Selector for main task only */}
        {!isSubtask && (
          <>
            <div className="section-title">Link to Forum (Optional)</div>
            <GlassCard padding="14px" className="meta-card">
              <div className="form-group compact">
                <Layers size={18} className="meta-icon" />
                <select
                  className="form-select"
                  value={selectedForumId}
                  onChange={e => setSelectedForumId(e.target.value ? parseInt(e.target.value) : '')}
                >
                  <option value="">General (No Forum)</option>
                  {folders.map(f => (
                    <option key={f.id} value={f.id}>{f.name}</option>
                  ))}
                </select>
              </div>
            </GlassCard>
          </>
        )}

        {/* Proof Required toggle for subtask only */}
        {isSubtask && (
          <>
            <div className="section-title">Completion Requirement</div>
            <GlassCard padding="16px" className="toggle-card">
              <div className="flex-row-between">
                <div className="toggle-meta">
                  <span className="toggle-title">Require Completion Proof</span>
                  <p className="toggle-desc">Tasker must upload a document or screenshot to request completion approval.</p>
                </div>
                <label className="switch">
                  <input 
                    type="checkbox" 
                    checked={proofRequired}
                    onChange={e => setProofRequired(e.target.checked)}
                  />
                  <span className="slider round"></span>
                </label>
              </div>
            </GlassCard>
          </>
        )}

        {/* Assignees Selection */}
        <div className="section-title">Assign Members</div>
        <GlassCard padding="16px" className="assignee-card">
          <input 
            type="text" 
            className="search-input" 
            placeholder="Search by name..."
            value={searchQuery}
            onChange={e => setSearchQuery(e.target.value)}
          />
          <div className="assignees-scroll-list">
            {filteredUsers.length === 0 ? (
              <div className="empty-search">No members found.</div>
            ) : (
              filteredUsers.map(user => {
                const isSelected = selectedUsers.includes(user.id);
                return (
                  <div 
                    key={user.id} 
                    className={`assignee-row ${isSelected ? 'selected' : ''}`}
                    onClick={() => toggleUserSelection(user.id)}
                  >
                    <div className="assignee-info">
                      <span className="assignee-name">{user.name}</span>
                      <span className="assignee-sub">{user.role} {user.post ? `· ${user.post}` : ''}</span>
                    </div>
                    <div className="checkbox-holder flex-center">
                      {isSelected && <Check size={14} className="check-icon" />}
                    </div>
                  </div>
                );
              })
            )}
          </div>
        </GlassCard>

        {/* Save Button */}
        <div style={{ marginTop: '30px' }}>
          <PrimaryButton type="submit" isLoading={isSaving} style={{ width: '100%' }}>
            <Sparkles size={18} style={{ marginRight: '8px' }} />
            Save Task Config
          </PrimaryButton>
        </div>
      </form>

      <style>{`
        .task-create-container {
          padding: 16px 20px;
          max-width: 700px;
          margin: 0 auto;
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

        .form-card {
          margin-bottom: 20px;
        }

        .form-group {
          display: flex;
          flex-direction: column;
          gap: 8px;
          margin-bottom: 16px;
        }

        .form-group:last-child {
          margin-bottom: 0;
        }

        .form-group.compact {
          flex-direction: row;
          align-items: center;
          gap: 12px;
          margin-bottom: 0;
        }

        .meta-icon {
          color: rgb(22, 192, 122);
        }

        .form-label {
          font-family: var(--font-space-grotesk);
          font-size: 13px;
          font-weight: 700;
          color: var(--text-muted);
        }

        .form-input {
          background: rgba(255,255,255,0.03);
          border: 1px solid var(--border-light);
          border-radius: 12px;
          padding: 12px 16px;
          font-family: var(--font-inter);
          font-size: 14px;
          color: var(--text-primary);
          outline: none;
          transition: border-color 0.2s ease;
        }

        .form-input:focus {
          border-color: rgba(22, 192, 122, 0.5);
        }

        .form-input.textarea {
          resize: none;
        }

        .form-input-date, .form-select {
          background: transparent;
          border: none;
          color: var(--text-primary);
          font-family: var(--font-inter);
          font-size: 14px;
          outline: none;
          width: 100%;
        }

        .form-select option {
          background: #111;
          color: #fff;
        }

        .section-title {
          font-family: var(--font-space-grotesk);
          font-weight: 700;
          font-size: 14px;
          color: var(--text-muted);
          margin: 20px 0 10px 4px;
        }

        .priority-selector {
          display: flex;
          gap: 8px;
          margin-bottom: 20px;
        }

        .prio-btn {
          flex: 1;
          display: flex;
          align-items: center;
          justify-content: center;
          gap: 8px;
          padding: 12px;
          border-radius: 12px;
          border: 1px solid var(--border-light);
          font-family: var(--font-space-grotesk);
          font-weight: 700;
          font-size: 12px;
          color: var(--text-secondary);
          cursor: pointer;
          transition: all 0.2s ease;
        }

        .prio-btn.active {
          color: var(--prio-color);
        }

        .prio-btn .dot {
          width: 8px;
          height: 8px;
          border-radius: 50%;
        }

        .toggle-card .flex-row-between {
          display: flex;
          justify-content: space-between;
          align-items: center;
        }

        .toggle-meta {
          flex: 1;
          padding-right: 16px;
        }

        .toggle-title {
          font-family: var(--font-space-grotesk);
          font-weight: 700;
          font-size: 14px;
          color: var(--text-primary);
          display: block;
        }

        .toggle-desc {
          font-size: 12px;
          color: var(--text-muted);
          margin-top: 4px;
          line-height: 1.4;
        }

        /* Switch styling */
        .switch {
          position: relative;
          display: inline-block;
          width: 44px;
          height: 24px;
        }

        .switch input {
          opacity: 0;
          width: 0;
          height: 0;
        }

        .slider {
          position: absolute;
          cursor: pointer;
          top: 0;
          left: 0;
          right: 0;
          bottom: 0;
          background-color: rgba(255,255,255,0.08);
          transition: .3s;
          border: 1px solid var(--border-light);
        }

        .slider:before {
          position: absolute;
          content: "";
          height: 16px;
          width: 16px;
          left: 3px;
          bottom: 3px;
          background-color: var(--text-muted);
          transition: .3s;
        }

        input:checked + .slider {
          background-color: rgba(22, 192, 122, 0.2);
          border-color: rgb(22, 192, 122);
        }

        input:checked + .slider:before {
          transform: translateX(20px);
          background-color: rgb(22, 192, 122);
        }

        .slider.round {
          border-radius: 24px;
        }

        .slider.round:before {
          border-radius: 50%;
        }

        /* Assignees List card */
        .assignee-card {
          display: flex;
          flex-direction: column;
          gap: 12px;
        }

        .search-input {
          background: rgba(255,255,255,0.03);
          border: 1px solid var(--border-light);
          border-radius: 10px;
          padding: 8px 12px;
          font-family: var(--font-inter);
          font-size: 13px;
          color: var(--text-primary);
          outline: none;
        }

        .assignees-scroll-list {
          max-height: 200px;
          overflow-y: auto;
          display: flex;
          flex-direction: column;
          gap: 6px;
          padding-right: 4px;
        }

        .assignees-scroll-list::-webkit-scrollbar {
          width: 4px;
        }
        .assignees-scroll-list::-webkit-scrollbar-thumb {
          background: var(--border-light);
          border-radius: 2px;
        }

        .assignee-row {
          display: flex;
          justify-content: space-between;
          align-items: center;
          padding: 8px 12px;
          border-radius: 8px;
          cursor: pointer;
          background: rgba(255,255,255,0.01);
          border: 1px solid transparent;
          transition: all 0.2s ease;
        }

        .assignee-row:hover {
          background: rgba(255,255,255,0.03);
        }

        .assignee-row.selected {
          background: rgba(22, 192, 122, 0.05);
          border-color: rgba(22, 192, 122, 0.15);
        }

        .assignee-info {
          display: flex;
          flex-direction: column;
          gap: 2px;
        }

        .assignee-name {
          font-family: var(--font-space-grotesk);
          font-weight: 700;
          font-size: 13px;
          color: var(--text-primary);
        }

        .assignee-sub {
          font-size: 11px;
          color: var(--text-muted);
        }

        .checkbox-holder {
          width: 18px;
          height: 18px;
          border-radius: 4px;
          border: 1px solid var(--border-light);
          transition: all 0.2s ease;
        }

        .assignee-row.selected .checkbox-holder {
          border-color: rgb(22, 192, 122);
          background: rgb(22, 192, 122);
          color: #fff;
        }

        .empty-search {
          text-align: center;
          padding: 20px;
          color: var(--text-muted);
          font-size: 13px;
        }
      `}</style>
    </div>
  );
};
