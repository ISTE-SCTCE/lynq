import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { ArrowLeft, CheckCircle2, Plus, Clock, AlertTriangle, AlertOctagon, Check, Play, FileCheck } from 'lucide-react';
import { useAuth } from '../../core/auth-provider';
import { supabase } from '../../core/supabase-client';
import { TaskModel } from '../../models/types';
import { GlassCard } from '../../shared/components/GlassCard';
import { NavBar } from '../../shared/components/NavBar';

import { motion, useSpring, useTransform } from 'framer-motion';

const RollingNumber: React.FC<{ value: number }> = ({ value }) => {
  const spring = useSpring(value, { mass: 0.8, stiffness: 75, damping: 15 });
  const display = useTransform(spring, (current) => Math.round(current).toString());

  useEffect(() => {
    spring.set(value);
  }, [value, spring]);

  return <motion.span>{display}</motion.span>;
};

const AnimatedCircularProgress: React.FC<{ percentage: number }> = ({ percentage }) => {
  const radius = 60;
  const stroke = 12;
  const normalizedRadius = radius - stroke * 2;
  const circumference = normalizedRadius * 2 * Math.PI;
  const strokeDashoffset = circumference - (percentage / 100) * circumference;

  return (
    <div style={{ position: 'relative', width: '120px', height: '120px', margin: '0 auto' }}>
      <svg height={radius * 2} width={radius * 2}>
        <circle
          stroke="rgba(255,255,255,0.05)"
          fill="transparent"
          strokeWidth={stroke}
          r={normalizedRadius}
          cx={radius}
          cy={radius}
        />
        <motion.circle
          stroke="var(--accent-teal)"
          fill="transparent"
          strokeWidth={stroke}
          strokeDasharray={circumference + ' ' + circumference}
          style={{ strokeDashoffset }}
          strokeLinecap="round"
          r={normalizedRadius}
          cx={radius}
          cy={radius}
          initial={{ strokeDashoffset: circumference }}
          animate={{ strokeDashoffset }}
          transition={{ duration: 1.5, ease: "easeOut" }}
          transform={`rotate(-90 ${radius} ${radius})`}
        />
      </svg>
      <div className="flex-center" style={{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0, flexDirection: 'column' }}>
        <span style={{ fontSize: '24px', fontWeight: '800', fontFamily: 'var(--font-space-grotesk)' }}>
          <RollingNumber value={percentage} />%
        </span>
      </div>
    </div>
  );
};

export const TaskListScreen: React.FC = () => {
  const navigate = useNavigate();
  const { currentUser, permissions } = useAuth();

  const [activeTab, setActiveTab] = useState<'all' | 'pending' | 'active' | 'review' | 'done'>('all');
  const [tasks, setTasks] = useState<any[]>([]);
  const [isLoading, setIsLoading] = useState(true);

  // Statistics counters
  const [pendingCount, setPendingCount] = useState(0);
  const [activeCount, setActiveCount] = useState(0);
  const [reviewCount, setReviewCount] = useState(0);

  const fetchTasks = async () => {
    setIsLoading(true);
    try {
      const { data, error } = await supabase
        .from('tasks')
        .select('*, subtasks:subtasks(*)')
        .order('created_at', { ascending: false });

      if (error) throw error;
      const loadedTasks = data || [];
      setTasks(loadedTasks);

      // Calculate statistical badge numbers
      let pSum = 0;
      let aSum = 0;
      let rSum = 0;

      loadedTasks.forEach((t) => {
        if (t.status === 'pending') pSum++;
        if (t.status === 'in_progress') aSum++;
        if (t.status === 'awaiting_verification' || t.status === 'review') rSum++;
      });

      setPendingCount(pSum);
      setActiveCount(aSum);
      setReviewCount(rSum);
    } catch (e) {
      console.error('Error loading tasks:', e);
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    fetchTasks();

    // Listen in real-time
    const channel = supabase
      .channel('public:tasks')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'tasks' }, () => {
        fetchTasks();
      })
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, []);

  if (!currentUser || !permissions) return null;

  const getFilteredTasks = () => {
    switch (activeTab) {
      case 'pending':
        return tasks.filter((t) => t.status === 'pending');
      case 'active':
        return tasks.filter((t) => t.status === 'in_progress');
      case 'review':
        return tasks.filter((t) => t.status === 'awaiting_verification' || t.status === 'review');
      case 'done':
        return tasks.filter((t) => t.status === 'completed');
      default:
        return tasks;
    }
  };

  const getPriorityColor = (prio: string) => {
    switch (prio) {
      case 'critical': return '#ef4444'; // Red
      case 'high': return '#f97316'; // Orange
      case 'medium': return '#fbbf24'; // Amber
      default: return '#16c07a'; // Low: Emerald
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

  const filtered = getFilteredTasks();
  const canCreate = permissions.isAtLeastTier1;

  const overallProgress = tasks.length > 0 
    ? Math.round((tasks.filter(t => t.status === 'completed').length / tasks.length) * 100) 
    : 0;

  return (
    <div className="task-list-container">
      <header className="page-header">
        <button onClick={() => navigate('/home')} className="back-button">
          <ArrowLeft size={20} />
        </button>
        <h2 className="page-title">Tasks Management</h2>
        {canCreate ? (
          <button onClick={() => navigate('/tasks/create')} className="create-task-btn">
            <Plus size={20} />
          </button>
        ) : (
          <div style={{ width: '20px' }}></div>
        )}
      </header>

      {/* Redesigned Hero Dashboard */}
      <GlassCard padding="24px" style={{ marginBottom: '24px', display: 'flex', flexDirection: 'column', gap: '24px' }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <div style={{ flex: 1 }}>
            <h3 style={{ fontSize: '18px', fontWeight: '800', fontFamily: 'var(--font-space-grotesk)', marginBottom: '8px' }}>Platform Progress</h3>
            <p style={{ fontSize: '13px', color: 'var(--text-muted)' }}>Keep track of your team's ongoing tasks and overall execution.</p>
          </div>
          <AnimatedCircularProgress percentage={overallProgress} />
        </div>
        
        <div className="stats-badges-row flex-center" style={{ gap: '12px' }}>
          <div className="stat-badge flex-center pending" style={{ padding: '16px', flex: 1, alignItems: 'flex-start' }}>
            <span className="stat-badge-num" style={{ fontSize: '28px' }}><RollingNumber value={pendingCount} /></span>
            <span className="stat-badge-lbl" style={{ marginTop: '4px' }}>Pending</span>
          </div>
          <div className="stat-badge flex-center active" style={{ padding: '16px', flex: 1, alignItems: 'flex-start' }}>
            <span className="stat-badge-num" style={{ fontSize: '28px' }}><RollingNumber value={activeCount} /></span>
            <span className="stat-badge-lbl" style={{ marginTop: '4px' }}>Active</span>
          </div>
          <div className="stat-badge flex-center review" style={{ padding: '16px', flex: 1, alignItems: 'flex-start' }}>
            <span className="stat-badge-num" style={{ fontSize: '28px' }}><RollingNumber value={reviewCount} /></span>
            <span className="stat-badge-lbl" style={{ marginTop: '4px' }}>Review</span>
          </div>
        </div>
      </GlassCard>

      {/* Filter Tabs Header */}
      <div className="tasks-tabs-row">
        {['all', 'pending', 'active', 'review', 'done'].map((tab) => (
          <button
            key={tab}
            onClick={() => setActiveTab(tab as any)}
            className={`tasks-tab-btn ${activeTab === tab ? 'active' : ''}`}
          >
            {tab.toUpperCase()}
          </button>
        ))}
      </div>

      {/* Tasks Cards listing flow */}
      {isLoading ? (
        <div className="tasks-loading">Loading board checklist...</div>
      ) : filtered.length === 0 ? (
        <div className="tasks-empty flex-center" style={{ flexDirection: 'column' }}>
          <CheckCircle2 size={48} style={{ color: 'var(--text-muted)', marginBottom: '16px' }} />
          <span>No tasks found in this board.</span>
        </div>
      ) : (
        <div className="tasks-flow-list" style={{ marginBottom: '40px' }}>
          {filtered.map((task) => {
            const prioColor = getPriorityColor(task.priority);
            const statusInfo = getStatusBadge(task.status);
            const StatusIcon = statusInfo.icon;
            
            // Subtask progress calculation
            const subtasks = task.subtasks || [];
            const completedCount = subtasks.filter((s: any) => s.status === 'completed').length;
            const progressPercentage = subtasks.length > 0 ? (completedCount / subtasks.length) * 100 : 0;
            const isOverdue = task.deadline && new Date(task.deadline) < new Date() && task.status !== 'completed';

            return (
              <GlassCard 
                key={task.id} 
                className="task-card-wrapper" 
                padding="18px"
                onClick={() => navigate(`/tasks/${task.id}`)}
                style={{ borderLeft: `4px solid ${prioColor}`, cursor: 'pointer' }}
              >
                <div className="task-card-header">
                  <h3 className="task-card-title">{task.title}</h3>
                  <span 
                    className="status-pill flex-center"
                    style={{ background: `${statusInfo.color}14`, color: statusInfo.color, border: `1px solid ${statusInfo.color}25` }}
                  >
                    <StatusIcon size={11} style={{ marginRight: '4px' }} />
                    {statusInfo.label}
                  </span>
                </div>

                {task.description && <p className="task-desc-text">{task.description}</p>}

                {subtasks.length > 0 && (
                  <div className="subtask-progress-block" style={{ margin: '14px 0 10px 0' }}>
                    <div className="progress-bar-container">
                      <div className="progress-bar-fill" style={{ width: `${progressPercentage}%` }}></div>
                    </div>
                    <span className="progress-meta-text">
                      Subtasks: {completedCount}/{subtasks.length} ({progressPercentage.toFixed(0)}%)
                    </span>
                  </div>
                )}

                <div className="task-card-footer flex-center" style={{ justifyContent: 'space-between', marginTop: '14px' }}>
                  <div className="deadline-block flex-center" style={{ color: isOverdue ? 'var(--accent-red)' : 'var(--text-muted)' }}>
                    <Clock size={12} style={{ marginRight: '4px' }} />
                    <span style={{ fontSize: '11px', fontWeight: '700' }}>
                      {isOverdue ? 'Overdue!' : task.deadline ? new Date(task.deadline).toLocaleDateString() : 'No deadline'}
                    </span>
                  </div>

                  <span className="prio-tag" style={{ color: prioColor, fontSize: '11px', fontWeight: '700' }}>
                    {task.priority.toUpperCase()} PRIORITY
                  </span>
                </div>
              </GlassCard>
            );
          })}
        </div>
      )}

      <NavBar />

      <style>{`
        .task-list-container {
          padding: 16px 20px;
        }

        @media (min-width: 768px) {
          .task-list-container {
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

        .back-button, .create-task-btn {
          color: var(--text-primary);
        }

        .page-title {
          font-family: var(--font-space-grotesk);
          font-weight: 800;
          font-size: 20px;
          color: var(--text-primary);
        }

        .stats-badges-row {
          width: 100%;
        }

        .stat-badge {
          flex: 1;
          flex-direction: column;
          padding: 8px 12px;
          border-radius: 12px;
          background: rgba(255,255,255,0.03);
          border: 1px solid var(--border-light);
        }

        .stat-badge.pending { border-color: rgba(107, 114, 128, 0.2); color: #6b7280; }
        .stat-badge.active { border-color: rgba(37, 99, 235, 0.2); color: #2563eb; }
        .stat-badge.review { border-color: rgba(251, 191, 36, 0.2); color: #fbbf24; }

        .stat-badge-num {
          font-family: var(--font-space-grotesk);
          font-size: 18px;
          font-weight: 800;
        }

        .stat-badge-lbl {
          font-size: 11px;
          font-weight: 600;
        }

        .tasks-tabs-row {
          display: flex;
          gap: 6px;
          overflow-x: auto;
          padding-bottom: 8px;
          margin-bottom: 20px;
          border-bottom: 1px solid var(--border-light);
        }

        .tasks-tab-btn {
          flex-shrink: 0;
          padding: 8px 16px;
          border-radius: 8px;
          font-family: var(--font-space-grotesk);
          font-size: 13px;
          font-weight: 700;
          color: var(--text-secondary);
        }

        .tasks-tab-btn.active {
          color: rgb(22, 192, 122);
          border-bottom: 3px solid rgb(22, 192, 122);
          border-radius: 8px 8px 0 0;
        }

        .tasks-loading, .tasks-empty {
          text-align: center;
          padding: 40px;
          color: var(--text-secondary);
        }

        .tasks-flow-list {
          display: grid;
          grid-template-columns: 1fr;
          gap: 12px;
        }

        @media (min-width: 768px) {
          .tasks-flow-list {
            grid-template-columns: repeat(2, 1fr);
            gap: 20px;
          }
        }

        @media (min-width: 1200px) {
          .tasks-flow-list {
            grid-template-columns: repeat(3, 1fr);
            gap: 24px;
          }
        }

        .task-card-wrapper {
          width: 100%;
          transition: transform 0.2s ease;
        }

        .task-card-wrapper:hover {
          transform: translateY(-2px);
        }

        .task-card-header {
          display: flex;
          justify-content: space-between;
          align-items: flex-start;
          width: 100%;
          margin-bottom: 8px;
        }

        .task-card-title {
          font-size: 16px;
          font-weight: 700;
          color: var(--text-primary);
        }

        .status-pill {
          padding: 4px 8px;
          border-radius: 20px;
          font-family: var(--font-space-grotesk);
          font-weight: 700;
          font-size: 10px;
          text-transform: uppercase;
        }

        .task-desc-text {
          font-size: 13px;
          color: var(--text-secondary);
          line-height: 1.4;
        }

        .progress-bar-container {
          width: 100%;
          height: 6px;
          background: rgba(255,255,255,0.05);
          border-radius: 3px;
          overflow: hidden;
        }

        .progress-bar-fill {
          height: 100%;
          background: rgb(22, 192, 122);
          border-radius: 3px;
        }

        .progress-meta-text {
          font-size: 11px;
          color: var(--text-muted);
          margin-top: 4px;
          display: block;
        }
      `}</style>
    </div>
  );
};
