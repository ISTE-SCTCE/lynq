import React, { useState, useEffect } from 'react';
import { useNavigate, useParams, Link } from 'react-router-dom';
import { ArrowLeft, Clock, Users, Calendar, Plus, CheckCircle2, ChevronRight, Check, Trash2, Edit, AlertCircle, Play, FileCheck, X } from 'lucide-react';
import { useAuth } from '../../core/auth-provider';
import { supabase } from '../../core/supabase-client';
import { GlassCard } from '../../shared/components/GlassCard';
import { NavBar } from '../../shared/components/NavBar';

export const TaskDetailScreen: React.FC = () => {
  const navigate = useNavigate();
  const { id } = useParams<{ id: string }>();
  const { currentUser, permissions } = useAuth();
  
  const [task, setTask] = useState<any | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  const [showOptions, setShowOptions] = useState(false);
  const [showStatusModal, setShowStatusModal] = useState<number | null>(null); // Subtask ID

  const loadTask = async () => {
    if (!id) return;
    setIsLoading(true);
    try {
      const { data, error } = await supabase
        .from('tasks')
        .select('*, subtasks:subtasks(*, task_proofs(*))')
        .eq('id', parseInt(id))
        .single();
      
      if (error) throw error;
      setTask(data);
    } catch (e: any) {
      console.error('Error loading task details:', e);
      setErrorMsg(e.message || 'Task not found.');
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    loadTask();

    // Setup real-time updates
    const channel = supabase
      .channel(`task_detail:${id}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'tasks', filter: `id=eq.${id}` }, () => {
        loadTask();
      })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'subtasks', filter: `task_id=eq.${id}` }, () => {
        loadTask();
      })
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [id]);

  if (!currentUser || !permissions) return null;

  if (isLoading) {
    return (
      <div className="task-detail-loading flex-center" style={{ height: '100vh', flexDirection: 'column' }}>
        <div className="spinner"></div>
        <span style={{ marginTop: '16px', color: 'var(--text-muted)' }}>Loading task checklist...</span>
      </div>
    );
  }

  if (!task) {
    return (
      <div className="task-detail-error flex-center" style={{ height: '100vh', flexDirection: 'column' }}>
        <AlertCircle size={48} style={{ color: 'var(--accent-red)' }} />
        <span style={{ marginTop: '16px', color: 'var(--text-muted)' }}>Task not found.</span>
        <button onClick={() => navigate('/tasks')} className="back-to-list-btn">Back to Board</button>
      </div>
    );
  }

  const subtasks = task.subtasks || [];
  const completedSubtasks = subtasks.filter((s: any) => s.status === 'completed').length;
  const progressPercentage = subtasks.length > 0 ? (completedSubtasks / subtasks.length) * 100 : 0;
  
  const isOverdue = task.deadline && new Date(task.deadline) < new Date() && task.status !== 'completed';
  const canVerify = permissions.isAtLeastTier1;
  const canEdit = permissions.isAtLeastTier1;

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
        return { label: 'In Review', color: '#fbbf24', icon: FileCheck };
      default:
        return { label: 'Pending', color: '#6b7280', icon: Clock };
    }
  };

  const getTimeRemainingLabel = () => {
    if (!task.deadline) return 'No deadline';
    const remainingMs = new Date(task.deadline).getTime() - new Date().getTime();
    const remainingDays = Math.ceil(remainingMs / (1000 * 60 * 60 * 24));
    
    if (remainingDays < 0) {
      return `${Math.abs(remainingDays)}d overdue`;
    }
    if (remainingDays === 0) return 'Due today';
    return `${remainingDays}d left`;
  };

  const handleUpdateSubtaskStatus = async (subtaskId: number, newStatus: string) => {
    try {
      const { error } = await supabase
        .from('subtasks')
        .update({ status: newStatus, updated_at: new Date().toISOString() })
        .eq('id', subtaskId);
      
      if (error) throw error;
      
      // Auto-trigger completion logic if necessary via RPC
      await supabase.rpc('update_task_completion', { task_id_param: task.id });
      
      setShowStatusModal(null);
      loadTask();
    } catch (e: any) {
      console.error('Error updating subtask status:', e);
      alert('Failed to update status: ' + e.message);
    }
  };

  const handleDeleteTask = async () => {
    if (!window.confirm('Are you sure you want to delete this task?')) return;
    try {
      const { error } = await supabase
        .from('tasks')
        .delete()
        .eq('id', task.id);
      
      if (error) throw error;
      navigate('/tasks');
    } catch (e: any) {
      alert('Failed to delete task: ' + e.message);
    }
  };

  const handleMarkComplete = async () => {
    try {
      const { error } = await supabase
        .from('tasks')
        .update({ status: 'completed', completion_percentage: 100 })
        .eq('id', task.id);
      
      if (error) throw error;
      setShowOptions(false);
      loadTask();
    } catch (e: any) {
      alert('Failed to mark complete: ' + e.message);
    }
  };

  const prioColor = getPriorityColor(task.priority);
  const statusInfo = getStatusBadge(task.status);
  const StatusIcon = statusInfo.icon;

  return (
    <div className="task-detail-container" style={{ paddingBottom: '80px' }}>
      <header className="page-header">
        <button onClick={() => navigate('/tasks')} className="back-button">
          <ArrowLeft size={20} />
        </button>
        <h2 className="page-title">Task View</h2>
        {canEdit ? (
          <button onClick={() => setShowOptions(true)} className="options-button">
            <Edit size={20} />
          </button>
        ) : (
          <div style={{ width: '20px' }}></div>
        )}
      </header>

      {/* Header Info */}
      <div className="task-header-block" style={{ borderLeft: `5px solid ${prioColor}` }}>
        <div className="status-tags flex-center" style={{ justifyContent: 'flex-start', gap: '8px' }}>
          <span 
            className="prio-badge" 
            style={{ backgroundColor: `${prioColor}18`, color: prioColor, border: `1px solid ${prioColor}35` }}
          >
            {task.priority.toUpperCase()} PRIORITY
          </span>
          <span 
            className="status-badge"
            style={{ backgroundColor: `${statusInfo.color}18`, color: statusInfo.color, border: `1px solid ${statusInfo.color}35` }}
          >
            <StatusIcon size={12} style={{ marginRight: '4px' }} />
            {statusInfo.label}
          </span>
        </div>
        <h1 className="task-title-text">{task.title}</h1>
        {task.description && <p className="task-desc-text">{task.description}</p>}
      </div>

      {/* Completion Percentage Ring */}
      <div className="progress-section flex-center" style={{ flexDirection: 'column', margin: '24px 0' }}>
        <div className="progress-ring-outer">
          <div className="progress-ring-inner">
            <span className="percentage-text">{progressPercentage.toFixed(0)}%</span>
            <span className="fraction-text">{completedSubtasks}/{subtasks.length} Done</span>
          </div>
          <svg className="progress-svg" viewBox="0 0 100 100">
            <circle className="circle-bg" cx="50" cy="50" r="44"></circle>
            <circle 
              className="circle-fill" 
              cx="50" 
              cy="50" 
              r="44" 
              style={{
                stroke: task.status === 'completed' ? '#16c07a' : prioColor,
                strokeDasharray: `${2 * Math.PI * 44}`,
                strokeDashoffset: `${2 * Math.PI * 44 * (1 - progressPercentage / 100)}`
              }}
            ></circle>
          </svg>
        </div>
      </div>

      {/* Info Cards Row */}
      <div className="info-cards-row">
        <GlassCard className="info-card" padding="12px">
          <Calendar size={18} className="card-icon" style={{ color: 'var(--accent-teal)' }} />
          <span className="card-lbl">Deadline</span>
          <span className="card-val" style={{ color: isOverdue ? '#ef4444' : 'var(--text-primary)' }}>
            {task.deadline ? new Date(task.deadline).toLocaleDateString() : 'No deadline'}
          </span>
        </GlassCard>
        
        <GlassCard className="info-card" padding="12px">
          <Users size={18} className="card-icon" style={{ color: 'var(--accent-teal)' }} />
          <span className="card-lbl">Assigned</span>
          <span className="card-val">{task.assigned_to?.length || 0} Members</span>
        </GlassCard>

        <GlassCard className="info-card" padding="12px">
          <Clock size={18} className="card-icon" style={{ color: 'var(--accent-teal)' }} />
          <span className="card-lbl">Time Left</span>
          <span className="card-val" style={{ color: isOverdue ? '#ef4444' : 'var(--text-primary)' }}>
            {getTimeRemainingLabel()}
          </span>
        </GlassCard>
      </div>

      {/* Subtasks Section */}
      <div className="subtasks-section">
        <div className="subtasks-header flex-center" style={{ justifyContent: 'space-between' }}>
          <h3 className="section-title">Subtasks Checklist</h3>
          {canVerify && (
            <Link to={`/tasks/${task.id}/subtasks/create`} className="add-subtask-btn flex-center">
              <Plus size={16} style={{ marginRight: '4px' }} />
              Add
            </Link>
          )}
        </div>

        {subtasks.length === 0 ? (
          <div className="empty-subtasks">No subtasks configured yet.</div>
        ) : (
          <div className="subtasks-list">
            {subtasks.map((sub: any, idx: number) => {
              const isSubComplete = sub.status === 'completed';
              const latestProof = sub.task_proofs && sub.task_proofs.length > 0
                ? sub.task_proofs.reduce((a: any, b: any) => new Date(a.created_at) > new Date(b.created_at) ? a : b)
                : null;
              
              const subPrioColor = getPriorityColor(sub.priority);
              const subStatus = getStatusBadge(sub.status);

              return (
                <div 
                  key={sub.id} 
                  className="subtask-row"
                  style={{ borderLeft: `3px solid ${subPrioColor}` }}
                >
                  <button 
                    onClick={() => canVerify && setShowStatusModal(sub.id)}
                    className="check-btn flex-center"
                    style={{
                      borderColor: subStatus.color,
                      backgroundColor: isSubComplete ? subStatus.color : 'transparent',
                      color: isSubComplete ? '#fff' : subStatus.color
                    }}
                  >
                    {isSubComplete ? <Check size={16} /> : idx + 1}
                  </button>

                  <div className="subtask-details" onClick={() => navigate(`/tasks/${task.id}/subtasks/${sub.id}`)}>
                    <span className={`subtask-title ${isSubComplete ? 'completed' : ''}`}>
                      {sub.title}
                    </span>
                    {latestProof && (
                      <div className="subtask-proof-indicator" style={{ color: getStatusBadge(latestProof.status).color }}>
                        Proof uploaded · {latestProof.status.toUpperCase()}
                      </div>
                    )}
                  </div>

                  <ChevronRight size={18} className="chevron-icon" onClick={() => navigate(`/tasks/${task.id}/subtasks/${sub.id}`)} />
                </div>
              );
            })}
          </div>
        )}
      </div>

      {/* Options Panel Drawer */}
      {showOptions && (
        <div className="modal-overlay flex-center" onClick={() => setShowOptions(false)}>
          <div className="options-drawer" onClick={e => e.stopPropagation()}>
            <div className="drawer-handle"></div>
            <h4 className="drawer-title">Manage Task</h4>
            
            <button className="drawer-opt-btn" onClick={handleMarkComplete}>
              <CheckCircle2 size={18} className="opt-icon" style={{ color: '#16c07a' }} />
              Mark Entire Task Complete
            </button>
            <button className="drawer-opt-btn text-danger" onClick={handleDeleteTask}>
              <Trash2 size={18} className="opt-icon" style={{ color: '#ef4444' }} />
              Delete Task
            </button>

            <button className="drawer-cancel-btn" onClick={() => setShowOptions(false)}>Cancel</button>
          </div>
        </div>
      )}

      {/* Subtask Status Selector Modal */}
      {showStatusModal !== null && (
        <div className="modal-overlay flex-center" onClick={() => setShowStatusModal(null)}>
          <GlassCard className="status-modal" padding="20px" onClick={e => e.stopPropagation()}>
            <div className="modal-header flex-center" style={{ justifyContent: 'space-between', marginBottom: '16px' }}>
              <h4 className="modal-title" style={{ margin: 0, fontFamily: 'var(--font-space-grotesk)' }}>Update Status</h4>
              <button className="close-btn" onClick={() => setShowStatusModal(null)}>
                <X size={18} />
              </button>
            </div>
            
            <div className="status-options-list">
              {[
                { value: 'pending', label: 'Pending', color: '#6b7280', icon: Clock },
                { value: 'in_progress', label: 'Active / In Progress', color: '#2563eb', icon: Play },
                { value: 'awaiting_verification', label: 'Awaiting Verification', color: '#fbbf24', icon: FileCheck },
                { value: 'completed', label: 'Completed', color: '#16c07a', icon: Check }
              ].map(st => {
                const IconComp = st.icon;
                return (
                  <button 
                    key={st.value}
                    className="status-opt-row"
                    onClick={() => handleUpdateSubtaskStatus(showStatusModal, st.value)}
                  >
                    <IconComp size={18} style={{ color: st.color, marginRight: '12px' }} />
                    <span className="status-opt-label">{st.label}</span>
                  </button>
                );
              })}
            </div>
          </GlassCard>
        </div>
      )}

      <NavBar />

      <style>{`
        .task-detail-container {
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

        .back-button, .options-button {
          color: var(--text-primary);
        }

        .page-title {
          font-family: var(--font-space-grotesk);
          font-weight: 800;
          font-size: 20px;
          color: var(--text-primary);
        }

        .task-header-block {
          padding: 16px 20px;
          background: rgba(255,255,255,0.02);
          border-radius: 0 16px 16px 0;
          margin: 16px 0;
        }

        .prio-badge, .status-badge {
          font-family: var(--font-space-grotesk);
          font-weight: 700;
          font-size: 10px;
          padding: 4px 10px;
          border-radius: 20px;
          text-transform: uppercase;
        }

        .task-title-text {
          font-family: var(--font-space-grotesk);
          font-size: 24px;
          font-weight: 800;
          color: var(--text-primary);
          margin: 12px 0 8px 0;
          line-height: 1.25;
        }

        .task-desc-text {
          font-size: 14px;
          color: var(--text-muted);
          line-height: 1.45;
          margin: 0;
        }

        /* Progress ring percentage */
        .progress-ring-outer {
          position: relative;
          width: 150px;
          height: 150px;
        }

        .progress-svg {
          width: 100%;
          height: 100%;
          transform: rotate(-90deg);
        }

        .circle-bg {
          fill: none;
          stroke: rgba(255,255,255,0.04);
          stroke-width: 6;
        }

        .circle-fill {
          fill: none;
          stroke-width: 6;
          stroke-linecap: round;
          transition: stroke-dashoffset 0.8s cubic-bezier(0.4, 0, 0.2, 1);
        }

        .progress-ring-inner {
          position: absolute;
          top: 0;
          left: 0;
          width: 100%;
          height: 100%;
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
        }

        .percentage-text {
          font-family: var(--font-space-grotesk);
          font-size: 32px;
          font-weight: 800;
          color: var(--text-primary);
        }

        .fraction-text {
          font-size: 11px;
          color: var(--text-muted);
          margin-top: 2px;
        }

        /* Info Cards */
        .info-cards-row {
          display: flex;
          gap: 10px;
          margin-bottom: 24px;
        }

        .info-card {
          flex: 1;
          display: flex;
          flex-direction: column;
          align-items: center;
          text-align: center;
          gap: 4px;
        }

        .card-icon {
          margin-bottom: 2px;
        }

        .card-lbl {
          font-size: 10px;
          color: var(--text-muted);
          text-transform: uppercase;
          font-weight: 700;
        }

        .card-val {
          font-family: var(--font-space-grotesk);
          font-weight: 700;
          font-size: 12px;
        }

        /* Subtasks List */
        .subtasks-section {
          margin-top: 10px;
        }

        .subtasks-header .section-title {
          font-family: var(--font-space-grotesk);
          font-size: 16px;
          font-weight: 800;
          color: var(--text-primary);
          margin: 0;
        }

        .add-subtask-btn {
          color: rgb(22, 192, 122);
          font-family: var(--font-space-grotesk);
          font-weight: 700;
          font-size: 13px;
        }

        .empty-subtasks {
          text-align: center;
          padding: 30px;
          color: var(--text-muted);
          font-size: 13px;
          background: rgba(255,255,255,0.01);
          border: 1px dashed var(--border-light);
          border-radius: 12px;
          margin-top: 12px;
        }

        .subtasks-list {
          display: flex;
          flex-direction: column;
          gap: 10px;
          margin-top: 12px;
        }

        .subtask-row {
          display: flex;
          align-items: center;
          background: rgba(255,255,255,0.02);
          border: 1px solid var(--border-light);
          border-radius: 12px;
          padding: 12px 14px;
          transition: all 0.2s ease;
        }

        .subtask-row:hover {
          background: rgba(255,255,255,0.04);
        }

        .check-btn {
          width: 32px;
          height: 32px;
          border-radius: 50%;
          border: 1.5px solid;
          font-family: var(--font-space-grotesk);
          font-weight: 800;
          font-size: 12px;
          cursor: pointer;
          flex-shrink: 0;
          transition: all 0.2s ease;
        }

        .subtask-details {
          flex: 1;
          margin: 0 14px;
          display: flex;
          flex-direction: column;
          gap: 2px;
          cursor: pointer;
        }

        .subtask-title {
          font-family: var(--font-space-grotesk);
          font-weight: 700;
          font-size: 14px;
          color: var(--text-primary);
        }

        .subtask-title.completed {
          text-decoration: line-through;
          color: var(--text-muted);
        }

        .subtask-proof-indicator {
          font-size: 11px;
          font-weight: 600;
        }

        .chevron-icon {
          color: var(--text-muted);
          cursor: pointer;
        }

        /* Modals and Options Drawer */
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

        .options-drawer {
          background: #181818;
          width: 100%;
          max-width: 500px;
          border-radius: 24px 24px 0 0;
          border-top: 1px solid var(--border-light);
          position: absolute;
          bottom: 0;
          padding: 20px 24px;
          box-shadow: 0 -10px 30px rgba(0,0,0,0.5);
          display: flex;
          flex-direction: column;
          align-items: center;
          animation: slideUp 0.3s ease-out;
        }

        @keyframes slideUp {
          from { transform: translateY(100%); }
          to { transform: translateY(0); }
        }

        .drawer-handle {
          width: 40px;
          height: 4px;
          background: rgba(255,255,255,0.15);
          border-radius: 2px;
          margin-bottom: 16px;
        }

        .drawer-title {
          font-family: var(--font-space-grotesk);
          font-weight: 800;
          font-size: 16px;
          color: var(--text-primary);
          margin-bottom: 20px;
        }

        .drawer-opt-btn {
          width: 100%;
          display: flex;
          align-items: center;
          padding: 14px 16px;
          background: rgba(255,255,255,0.02);
          border: 1px solid var(--border-light);
          border-radius: 12px;
          font-family: var(--font-inter);
          font-weight: 600;
          font-size: 14px;
          color: var(--text-primary);
          cursor: pointer;
          margin-bottom: 10px;
          transition: all 0.2s ease;
        }

        .drawer-opt-btn:hover {
          background: rgba(255,255,255,0.04);
        }

        .drawer-opt-btn.text-danger {
          color: #ef4444;
        }

        .opt-icon {
          margin-right: 12px;
        }

        .drawer-cancel-btn {
          width: 100%;
          padding: 14px;
          background: transparent;
          color: var(--text-muted);
          font-family: var(--font-space-grotesk);
          font-weight: 700;
          font-size: 14px;
          cursor: pointer;
          margin-top: 10px;
        }

        /* Status update modal */
        .status-modal {
          width: 90%;
          max-width: 400px;
        }

        .status-options-list {
          display: flex;
          flex-direction: column;
          gap: 8px;
        }

        .status-opt-row {
          width: 100%;
          display: flex;
          align-items: center;
          padding: 12px 14px;
          background: rgba(255,255,255,0.02);
          border: 1px solid var(--border-light);
          border-radius: 10px;
          color: var(--text-primary);
          font-family: var(--font-inter);
          font-weight: 600;
          font-size: 13.5px;
          cursor: pointer;
          transition: all 0.2s ease;
        }

        .status-opt-row:hover {
          background: rgba(255,255,255,0.05);
        }

        .close-btn {
          color: var(--text-muted);
        }
      `}</style>
    </div>
  );
};
