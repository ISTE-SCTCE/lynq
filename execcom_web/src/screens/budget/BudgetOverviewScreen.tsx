import React, { useState, useEffect } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { 
  ArrowLeft, 
  Download, 
  Plus, 
  Trash, 
  Edit, 
  Check, 
  X, 
  TrendingUp, 
  AlertTriangle, 
  Clock, 
  FileSpreadsheet, 
  Layout, 
  History, 
  Calendar,
  Wallet
} from 'lucide-react';
import { AddCashDisclosure } from '../../components/ui/add-cash-disclosure';
import { InlineTableControl } from '../../components/ui/inline-table-control';
import { AppRole } from '../../core/constants';
import { 
  BarChart, 
  Bar, 
  XAxis, 
  YAxis, 
  Tooltip, 
  ResponsiveContainer 
} from 'recharts';
import { useAuth } from '../../core/auth-provider';
import { supabase } from '../../core/supabase-client';
import { GlassCard } from '../../shared/components/GlassCard';
import { NavBar } from '../../shared/components/NavBar';
import { CustomTextField } from '../../shared/components/CustomTextField';
import { BudgetRequestModel, EventBudgetModel } from '../../models/types';

export const BudgetOverviewScreen: React.FC = () => {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const { currentUser, permissions } = useAuth();
  
  const folderParam = searchParams.get('folder');
  const folderId = folderParam ? parseInt(folderParam) : null;

  const [activeTab, setActiveTab] = useState<'overview' | 'requests' | 'ledger' | 'income' | 'events'>('overview');
  const [isLoading, setIsLoading] = useState(true);
  const [requests, setRequests] = useState<BudgetRequestModel[]>([]);
  const [ledgerEntries, setLedgerEntries] = useState<any[]>([]);
  const [incomeEntries, setIncomeEntries] = useState<any[]>([]);
  const [eventBudgets, setEventBudgets] = useState<EventBudgetModel[]>([]);
  const [myFolderIds, setMyFolderIds] = useState<number[]>([]);

  // Allocation metrics
  const [forumAllocation, setForumAllocation] = useState(0);
  const [totalIncome, setTotalIncome] = useState(0);
  const [totalSpent, setTotalSpent] = useState(0);
  const [totalApproved, setTotalApproved] = useState(0);
  const [totalPlanned, setTotalPlanned] = useState(0);

  // Edit / Action states
  const [isActionLoading, setIsActionLoading] = useState(false);
  const [showEditBudgetModal, setShowEditBudgetModal] = useState<EventBudgetModel | null>(null);
  const [newBudgetLimit, setNewBudgetLimit] = useState('');
  
  const [showTransactionModal, setShowTransactionModal] = useState(false);
  const [transType, setTransType] = useState<'Income' | 'Expense'>('Expense');
  const [transAmount, setTransAmount] = useState('');
  const [transCategory, setTransCategory] = useState('Marketing');
  const [transSource, setTransSource] = useState('');
  const [transDesc, setTransDesc] = useState('');
  const [transFolder, setTransFolder] = useState<number | ''>('');

  // Sync Category with Transaction Type
  useEffect(() => {
    setTransCategory(transType === 'Expense' ? 'Marketing' : 'Membership Fees');
  }, [transType]);

  const loadBudgetData = async () => {
    if (!currentUser || !permissions) return;
    setIsLoading(true);
    try {
      // 1. Fetch user's folder memberships
      const { data: memberData } = await supabase
        .from('folder_members')
        .select('folder_id')
        .eq('user_id', currentUser.id);

      const fIds = (memberData || []).map((m) => m.folder_id);
      setMyFolderIds(fIds);
      if (fIds.length > 0 && transFolder === '') {
        setTransFolder(fIds[0]);
      }

      // 2. Load requests
      let reqQuery = supabase.from('budget_requests').select('*');
      if (!permissions.isAtLeastTier2) {
        reqQuery = reqQuery.in('folder_id', fIds);
      }
      const { data: reqData } = await reqQuery.order('created_at', { ascending: false });
      const loadedReqs = (reqData || []) as BudgetRequestModel[];
      setRequests(loadedReqs);

      // 3. Load Financial Ledger Data (Expenses)
      let ledgerQuery = supabase.from('financial_ledger').select('*');
      if (!permissions.canViewTotalBudget) {
        ledgerQuery = ledgerQuery.in('folder_id', fIds);
      }
      const { data: ledgerData } = await ledgerQuery.order('transaction_date', { ascending: false });
      const expenseEntries = (ledgerData || []).filter((e: any) => e.type !== 'Income');
      setLedgerEntries(expenseEntries);

      // 4. Load Financial Income Data
      let incomeQuery = supabase.from('financial_income').select('*');
      if (!permissions.canViewTotalBudget) {
        incomeQuery = incomeQuery.in('folder_id', fIds);
      }
      const { data: incomeData } = await incomeQuery.order('transaction_date', { ascending: false });
      const parsedIncomeEntries = incomeData || [];

      // Combine with legacy Income entries inside financial_ledger to ensure full backward compatibility
      const legacyIncomeEntries = (ledgerData || []).filter((e: any) => e.type === 'Income');
      const combinedIncomeEntries = [...parsedIncomeEntries, ...legacyIncomeEntries].sort(
        (a, b) => new Date(b.transaction_date || '').getTime() - new Date(a.transaction_date || '').getTime()
      );
      setIncomeEntries(combinedIncomeEntries);

      // Calculate totals
      const incomeSum = combinedIncomeEntries.reduce((sum, e: any) => sum + (parseFloat(e.amount) || 0), 0);
      const spentSum = expenseEntries.reduce((sum, e: any) => sum + (parseFloat(e.amount) || 0), 0);

      setTotalIncome(incomeSum);
      setTotalSpent(spentSum);

      // Calculate stats
      const approvedSum = loadedReqs
        .filter((r) => r.status === 'approved')
        .reduce((sum, r) => sum + r.amount, 0);
      const plannedSum = loadedReqs
        .filter((r) => r.status === 'pending')
        .reduce((sum, r) => sum + r.amount, 0);

      setTotalApproved(approvedSum);
      setTotalPlanned(plannedSum);

      // 5. Fetch Scoped Forum Allocations
      if (!permissions.canViewTotalBudget && fIds.length > 0) {
        const { data: allocationData } = await supabase
          .from('forum_budgets')
          .select('allocated_amount')
          .in('folder_id', fIds);

        const allocationSum = (allocationData || []).reduce(
          (sum, row) => sum + (parseFloat(row.allocated_amount) || 0), 
          0
        );
        setForumAllocation(allocationSum);
      }

      // 6. Load Event Budgets
      const { data: eventBudgetData } = await supabase
        .from('event_budgets')
        .select('*')
        .order('date', { ascending: false });
      setEventBudgets((eventBudgetData || []) as EventBudgetModel[]);

    } catch (e) {
      console.error('Error loading budget:', e);
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    if (currentUser && permissions) {
      loadBudgetData();
    }
  }, [currentUser?.id, !!permissions]);

  const handleReviewRequest = async (id: number, status: 'approved' | 'rejected') => {
    if (!currentUser) return;
    setIsActionLoading(true);
    try {
      const { error } = await supabase
        .from('budget_requests')
        .update({
          status,
          reviewed_by: currentUser.id,
          reviewed_at: new Date().toISOString(),
        })
        .eq('id', id);

      if (error) throw error;
      alert(`Budget request ${status}!`);
      loadBudgetData();
    } catch (e) {
      console.error('Review budget request error:', e);
      alert('Review failed');
    } finally {
      setIsActionLoading(false);
    }
  };

  const handleEditEventBudget = async () => {
    if (!showEditBudgetModal) return;
    const limit = parseFloat(newBudgetLimit);
    if (isNaN(limit)) return;

    setIsActionLoading(true);
    try {
      const { error } = await supabase
        .from('event_budgets')
        .update({ budget_limit: limit })
        .eq('id', showEditBudgetModal.id);

      if (error) throw error;
      setShowEditBudgetModal(null);
      setNewBudgetLimit('');
      loadBudgetData();
    } catch (e) {
      console.error('Edit budget limit error:', e);
      alert('Save failed');
    } finally {
      setIsActionLoading(false);
    }
  };

  const handleDeleteEventBudget = async (id: number) => {
    if (!window.confirm('Are you sure you want to delete this event budget? This action cannot be undone.')) return;
    setIsActionLoading(true);
    try {
      const { error } = await supabase.from('event_budgets').delete().eq('id', id);
      if (error) throw error;
      setEventBudgets(eventBudgets.filter((eb) => eb.id !== id));
      alert('Event budget deleted!');
    } catch (e) {
      console.error('Delete budget limit error:', e);
      alert('Delete failed');
    } finally {
      setIsActionLoading(false);
    }
  };

  const handleNewTransaction = async (e: React.FormEvent) => {
    e.preventDefault();
    const amt = parseFloat(transAmount);
    if (isNaN(amt) || !transFolder || !currentUser) return;

    setIsActionLoading(true);
    try {
      if (transType === 'Income') {
        const { error } = await supabase.from('financial_income').insert({
          amount: amt,
          category: transCategory,
          source: transSource.trim() || 'Direct',
          description: transDesc.trim(),
          folder_id: transFolder,
          transaction_date: new Date().toISOString(),
          created_by: currentUser.id,
        });
        if (error) throw error;
      } else {
        const { error } = await supabase.from('financial_ledger').insert({
          amount: amt,
          type: 'Expense',
          category: transCategory,
          source: transSource.trim() || 'Direct',
          description: transDesc.trim(),
          folder_id: transFolder,
          transaction_date: new Date().toISOString(),
          created_by: currentUser.id,
        });
        if (error) throw error;
      }
      setShowTransactionModal(false);
      setTransAmount('');
      setTransSource('');
      setTransDesc('');
      loadBudgetData();
      alert('Transaction recorded successfully!');
    } catch (err) {
      console.error('Add transaction error:', err);
      alert('Failed to record transaction');
    } finally {
      setIsActionLoading(false);
    }
  };

  const handleQuickAddCash = async (amount: number) => {
    if (!currentUser || !transFolder) return;
    try {
      const { error } = await supabase.from('financial_income').insert({
        amount: amount,
        category: 'Miscellaneous',
        source: 'Quick Balance Top-Up',
        description: 'Deposited allocation funds via quick dashboard top-up widget',
        folder_id: transFolder,
        transaction_date: new Date().toISOString(),
        created_by: currentUser.id,
      });

      if (error) throw error;
      await loadBudgetData();
    } catch (err) {
      console.error('Quick top-up error:', err);
      alert('Failed to record quick top-up');
    }
  };

  const handleExportStatement = () => {
    // Generate high-quality client side print view
    window.print();
  };

  if (!currentUser || !permissions) return null;

  const isAtLeastTier2 = permissions.isAtLeastTier2;
  const remaining = isAtLeastTier2 ? (totalIncome - totalSpent) : (forumAllocation - totalSpent);

  // Group chart data: Income vs Expense in last transactions
  const chartData = [
    { name: 'Income', amount: totalIncome, fill: '#16c07a' },
    { name: 'Expense', amount: totalSpent, fill: '#ef4444' }
  ];

  return (
    <div className="budget-overview-container">
      <header className="page-header">
        <button onClick={() => navigate('/home')} className="back-button">
          <ArrowLeft size={20} />
        </button>
        <h2 className="page-title">{isAtLeastTier2 ? 'Budget Management' : 'Forum Budget'}</h2>
        <div className="header-right flex-center" style={{ gap: '12px' }}>
          <button onClick={handleExportStatement} className="header-action-icon">
            <Download size={20} />
          </button>
          {isAtLeastTier2 && (
            <button onClick={() => setShowTransactionModal(true)} className="header-action-icon">
              <Plus size={20} />
            </button>
          )}
        </div>
      </header>

      {/* Tabs list bar */}
      <div className="budget-tab-row">
        <button 
          onClick={() => setActiveTab('overview')} 
          className={`budget-tab ${activeTab === 'overview' ? 'active' : ''}`}
        >
          <Layout size={14} style={{ marginRight: '6px' }} />
          Overview
        </button>
        <button 
          onClick={() => setActiveTab('requests')} 
          className={`budget-tab ${activeTab === 'requests' ? 'active' : ''}`}
        >
          <Clock size={14} style={{ marginRight: '6px' }} />
          Requests
        </button>
        {isAtLeastTier2 && (
          <button 
            onClick={() => setActiveTab('ledger')} 
            className={`budget-tab ${activeTab === 'ledger' ? 'active' : ''}`}
          >
            <History size={14} style={{ marginRight: '6px' }} />
            Ledger
          </button>
        )}
        <button 
          onClick={() => setActiveTab('events')} 
          className={`budget-tab ${activeTab === 'events' ? 'active' : ''}`}
        >
          <Calendar size={14} style={{ marginRight: '6px' }} />
          Events
        </button>
      </div>

      {isLoading ? (
        <div className="budget-loading">Loading financial registers...</div>
      ) : (
        <div className="budget-content-block" style={{ marginBottom: '40px' }}>
          
          {/* TAB 1: OVERVIEW SUMMARY */}
          {activeTab === 'overview' && (
            <div className="overview-tab-flow">
              <GlassCard className="budget-metrics-card" padding="24px">
                <span className="metrics-card-subtitle">NET AVAILABLE BALANCE</span>
                <h3 className={`metrics-card-title ${remaining >= 0 ? 'positive' : 'negative'}`}>
                  ₹{remaining.toLocaleString()}
                </h3>

                <div className="summary-split-row">
                  <div className="split-col">
                    <span className="split-label">{isAtLeastTier2 ? 'Total Income' : 'Forum Allocation'}</span>
                    <span className="split-val income">
                      ₹{isAtLeastTier2 ? totalIncome.toLocaleString() : forumAllocation.toLocaleString()}
                    </span>
                  </div>
                  <div className="split-col">
                    <span className="split-label">Total Expense</span>
                    <span className="split-val expense">₹{totalSpent.toLocaleString()}</span>
                  </div>
                </div>

                {/* Progress Visualizer */}
                {forumAllocation > 0 && !isAtLeastTier2 && (
                  <div className="allocation-progress-wrapper" style={{ marginTop: '20px' }}>
                    <div className="progress-bar-container">
                      <div 
                        className="progress-bar-fill" 
                        style={{ width: `${Math.min(100, (totalSpent / forumAllocation) * 100)}%` }}
                      ></div>
                    </div>
                    <span className="progress-bar-label">
                      Spent: {((totalSpent / forumAllocation) * 100).toFixed(0)}%
                    </span>
                  </div>
                )}
              </GlassCard>



              {/* Dynamic Recharts Bar Trends Graph */}
              <GlassCard className="trends-chart-card" padding="20px" style={{ marginTop: '20px' }}>
                <h4 className="chart-card-title flex-center" style={{ justifyContent: 'flex-start', gap: '8px' }}>
                  <TrendingUp size={16} /> Trends Analytics
                </h4>
                <div style={{ width: '100%', height: 200, marginTop: '20px' }}>
                  <ResponsiveContainer>
                    <BarChart data={chartData}>
                      <XAxis dataKey="name" stroke="var(--text-secondary)" />
                      <YAxis stroke="var(--text-secondary)" />
                      <Tooltip cursor={{ fill: 'rgba(255,255,255,0.03)' }} />
                      <Bar dataKey="amount" radius={[8, 8, 0, 0]} />
                    </BarChart>
                  </ResponsiveContainer>
                </div>
              </GlassCard>

              {/* Status minis approved/planned */}
              <div className="metrics-minis-row flex-center" style={{ gap: '12px', marginTop: '20px' }}>
                <GlassCard className="mini-stat-card flex-center" padding="14px">
                  <span className="mini-label">Approved Requests</span>
                  <span className="mini-value text-gradient">₹{totalApproved.toLocaleString()}</span>
                </GlassCard>
                <GlassCard className="mini-stat-card flex-center" padding="14px">
                  <span className="mini-label">Pending Requests</span>
                  <span className="mini-value" style={{ color: '#fbbf24' }}>₹{totalPlanned.toLocaleString()}</span>
                </GlassCard>
              </div>
            </div>
          )}

          {/* TAB 2: BUDGET REQUESTS */}
          {activeTab === 'requests' && (
            <div className="requests-tab-flow">
              <div className="requests-header-row flex-center" style={{ justifyContent: 'space-between', marginBottom: '16px' }}>
                <h4 className="section-subtitle-text">Request Registry</h4>
                <button onClick={() => navigate('/budget/request')} className="request-add-btn flex-center">
                  <Plus size={14} style={{ marginRight: '4px' }} /> Request
                </button>
              </div>

              {requests.length === 0 ? (
                <div className="requests-empty">No budget requests found.</div>
              ) : (
                <div className="requests-list">
                  {requests.map((req) => {
                    const isPending = req.status === 'pending';
                    return (
                      <GlassCard key={req.id} className="request-item-card" padding="16px">
                        <div className="request-card-header">
                          <span className="request-amount">₹{req.amount.toLocaleString()}</span>
                          <span className={`request-status-badge ${req.status}`}>
                            {req.status.toUpperCase()}
                          </span>
                        </div>
                        {req.reason && <p className="request-reason-text">{req.reason}</p>}
                        
                        {req.proposal_url && (
                          <a 
                            href={req.proposal_url} 
                            target="_blank" 
                            rel="noreferrer" 
                            className="proposal-link-btn"
                          >
                            View Attached Document
                          </a>
                        )}

                        {isPending && permissions.canApproveBudget && (
                          <div className="request-action-row" style={{ marginTop: '16px' }}>
                            <button 
                              onClick={() => handleReviewRequest(req.id, 'approved')}
                              className="review-btn approve flex-center"
                              disabled={isActionLoading}
                            >
                              <Check size={14} style={{ marginRight: '4px' }} /> Approve
                            </button>
                            <button 
                              onClick={() => handleReviewRequest(req.id, 'rejected')}
                              className="review-btn reject flex-center"
                              disabled={isActionLoading}
                            >
                              <X size={14} style={{ marginRight: '4px' }} /> Reject
                            </button>
                          </div>
                        )}
                      </GlassCard>
                    );
                  })}
                </div>
              )}
            </div>
          )}

          {/* TAB 3: HISTORY LEDGER (COMBINED GENERAL LEDGER) */}
          {activeTab === 'ledger' && isAtLeastTier2 && (() => {
            const combinedEntries = [
              ...ledgerEntries.map(e => ({ ...e, type: 'Expense' })),
              ...incomeEntries
            ].sort((a, b) => new Date(b.transaction_date || '').getTime() - new Date(a.transaction_date || '').getTime());

            return (
              <div className="ledger-tab-flow">
                {combinedEntries.length === 0 ? (
                  <div className="ledger-empty">No transactions logged in the general ledger.</div>
                ) : (
                  <div className="ledger-list-container">
                    <InlineTableControl
                      data={combinedEntries.map((entry) => ({
                        id: entry.id.toString(),
                        type: entry.type || 'Expense',
                        category: entry.category,
                        method: entry.source || 'Direct',
                        amount: entry.amount.toString(),
                        transaction_date: entry.transaction_date,
                        description: entry.description,
                      }))}
                      isEditable={permissions?.role >= AppRole.coreExeccom}
                      onUpdate={async (updatedItem) => {
                        const amountVal = parseFloat(updatedItem.amount);
                        if (isNaN(amountVal) || amountVal <= 0) {
                          alert("Validation Error: Amount must be a positive number.");
                          return;
                        }
                        if (!updatedItem.category.trim()) {
                          alert("Validation Error: Category cannot be empty.");
                          return;
                        }
                        if (!updatedItem.method.trim()) {
                          alert("Validation Error: Source/Method cannot be empty.");
                          return;
                        }

                        try {
                          // Determine if it was legacy income in financial_ledger or in financial_income
                          const isLegacy = ledgerEntries.some(e => e.id.toString() === updatedItem.id) ||
                                           (incomeEntries.some(e => e.id.toString() === updatedItem.id) && 
                                            !incomeEntries.find(e => e.id.toString() === updatedItem.id)?.created_at);
                          const targetTable = (updatedItem.type === 'Income' && !isLegacy) ? 'financial_income' : 'financial_ledger';

                          // 1. Fetch original record for audit logging
                          const { data: originalRecord } = await supabase
                            .from(targetTable)
                            .select('*')
                            .eq('id', updatedItem.id)
                            .single();

                          // 2. Perform database update
                          const { error } = await supabase
                            .from(targetTable)
                            .update({
                              type: updatedItem.type,
                              category: updatedItem.category,
                              source: updatedItem.method,
                              amount: amountVal,
                            })
                            .eq('id', updatedItem.id);

                          if (error) throw error;

                          // 3. Write modification history to audit log table
                          await supabase.from('ledger_change_history').insert({
                            ledger_id: parseInt(updatedItem.id),
                            table_name: targetTable,
                            edited_by: currentUser.id,
                            original_values: originalRecord || {},
                            updated_values: {
                              type: updatedItem.type,
                              category: updatedItem.category,
                              source: updatedItem.method,
                              amount: amountVal,
                            }
                          });

                          alert('Ledger transaction updated successfully!');
                          await loadBudgetData();
                        } catch (err: any) {
                          console.error('Update ledger error:', err);
                          alert('Failed to update ledger transaction: ' + err.message);
                        }
                      }}
                      onDelete={async (id) => {
                        try {
                          // Delete from both safely to handle new incomes vs legacy ledger records
                          await supabase.from('financial_income').delete().eq('id', id);
                          await supabase.from('financial_ledger').delete().eq('id', id);

                          alert('Ledger transaction deleted successfully!');
                          await loadBudgetData();
                        } catch (err: any) {
                          console.error('Delete ledger error:', err);
                          alert('Failed to delete ledger transaction: ' + err.message);
                        }
                      }}
                    />
                  </div>
                )}
              </div>
            );
          })()}

          {/* TAB 4: EVENT SPECIFIC BUDGETS */}
          {activeTab === 'events' && (
            <div className="events-budget-tab-flow">
              {eventBudgets.length === 0 ? (
                <div className="events-empty">No event budgets established.</div>
              ) : (
                <div className="events-budget-list">
                  {eventBudgets.map((eb) => {
                    const progress = eb.budget_limit > 0 ? (eb.actual_spent / eb.budget_limit) * 100 : 0;
                    const isOverBudget = eb.actual_spent > eb.budget_limit;
                    return (
                      <GlassCard key={eb.id} className="event-budget-card" padding="16px">
                        <div className="event-budget-header">
                          <div>
                            <h4 className="event-budget-name">{eb.event_name}</h4>
                            {eb.date && <span className="event-budget-date">{eb.date}</span>}
                          </div>
                          {isOverBudget && <AlertTriangle size={18} style={{ color: 'var(--accent-red)' }} />}
                        </div>

                        <div className="event-budget-info-split">
                          <span>Limit: ₹{eb.budget_limit.toLocaleString()}</span>
                          <span style={{ color: isOverBudget ? 'var(--accent-red)' : 'inherit' }}>
                            Spent: ₹{eb.actual_spent.toLocaleString()}
                          </span>
                        </div>

                        <div className="progress-bar-container" style={{ margin: '12px 0 6px 0' }}>
                          <div 
                            className={`progress-bar-fill ${isOverBudget ? 'over' : ''}`}
                            style={{ 
                              width: `${Math.min(100, progress)}%`,
                              backgroundColor: isOverBudget ? 'var(--accent-red)' : 'rgb(22, 192, 122)' 
                            }}
                          ></div>
                        </div>

                        {isOverBudget && (
                          <span className="over-budget-warning">
                            Over budget by ₹{(eb.actual_spent - eb.budget_limit).toLocaleString()}
                          </span>
                        )}

                        {permissions.canManageBudget && (
                          <div className="event-budget-actions" style={{ marginTop: '12px' }}>
                            <button 
                              onClick={() => { setShowEditBudgetModal(eb); setNewBudgetLimit(eb.budget_limit.toString()); }}
                              className="action-icon-pill flex-center"
                            >
                              <Edit size={14} style={{ marginRight: '4px' }} /> Edit Limit
                            </button>
                            <button 
                              onClick={() => handleDeleteEventBudget(eb.id)}
                              className="action-icon-pill destructive flex-center"
                            >
                              <Trash size={14} style={{ marginRight: '4px' }} /> Delete
                            </button>
                          </div>
                        )}
                      </GlassCard>
                    );
                  })}
                </div>
              )}
            </div>
          )}

        </div>
      )}

      {/* Edit Budget Limit Modal */}
      {showEditBudgetModal && (
        <div className="modal-overlay">
          <GlassCard className="modal-card" padding="24px">
            <h3 className="modal-title">Edit Budget Limit</h3>
            <span className="modal-subtitle-desc">{showEditBudgetModal.event_name}</span>
            <input
              type="number"
              value={newBudgetLimit}
              onChange={(e) => setNewBudgetLimit(e.target.value)}
              className="modal-input"
              style={{ marginTop: '16px' }}
            />
            <div className="modal-actions-row">
              <button onClick={() => setShowEditBudgetModal(null)} className="modal-cancel-btn" disabled={isActionLoading}>
                Cancel
              </button>
              <button onClick={handleEditEventBudget} className="modal-submit-btn" disabled={isActionLoading}>
                {isActionLoading ? 'Saving...' : 'Save'}
              </button>
            </div>
          </GlassCard>
        </div>
      )}

      {/* Record Transaction Modal */}
      {showTransactionModal && (
        <div className="modal-overlay">
          <GlassCard className="modal-card" padding="24px">
            <h3 className="modal-title">Log Transaction</h3>
            <form onSubmit={handleNewTransaction}>
              
              <div style={{ marginBottom: '12px' }}>
                <label className="modal-input-label">Type</label>
                <select
                  value={transType}
                  onChange={(e) => setTransType(e.target.value as any)}
                  className="modal-select-field"
                >
                  <option value="Expense">Expense (Debit)</option>
                  <option value="Income">Income (Credit)</option>
                </select>
              </div>

              <div style={{ marginBottom: '12px' }}>
                <label className="modal-input-label">Category</label>
                <select
                  value={transCategory}
                  onChange={(e) => setTransCategory(e.target.value)}
                  className="modal-select-field"
                >
                  {transType === 'Expense' ? (
                    <>
                      <option value="Marketing">Marketing</option>
                      <option value="Operations">Operations</option>
                      <option value="Refreshments">Refreshments</option>
                      <option value="Logistics">Logistics</option>
                      <option value="Prizes">Prizes</option>
                      <option value="Miscellaneous">Miscellaneous</option>
                    </>
                  ) : (
                    <>
                      <option value="Membership Fees">Membership Fees</option>
                      <option value="Sponsorship">Sponsorship</option>
                      <option value="Grants">Grants</option>
                      <option value="Ticket Sales">Ticket Sales</option>
                      <option value="Contributions">Contributions</option>
                      <option value="Miscellaneous">Miscellaneous</option>
                    </>
                  )}
                </select>
              </div>

              <div style={{ marginBottom: '12px' }}>
                <label className="modal-input-label">Forum Scoped association</label>
                <select
                  value={transFolder}
                  onChange={(e) => setTransFolder(parseInt(e.target.value))}
                  className="modal-select-field"
                  disabled={myFolderIds.length === 0}
                >
                  {myFolderIds.map((fid) => (
                    <option key={fid} value={fid}>Forum Folder #{fid}</option>
                  ))}
                </select>
              </div>

              <CustomTextField
                label="Amount (₹)"
                value={transAmount}
                onChange={setTransAmount}
                type="number"
              />

              <CustomTextField
                label="Source / Vendor"
                value={transSource}
                onChange={setTransSource}
                placeholder="Where did funds flow?"
              />

              <CustomTextField
                label="Brief Description"
                value={transDesc}
                onChange={setTransDesc}
                placeholder="Log transaction details"
              />

              <div className="modal-actions-row">
                <button type="button" onClick={() => setShowTransactionModal(false)} className="modal-cancel-btn" disabled={isActionLoading}>
                  Cancel
                </button>
                <button type="submit" className="modal-submit-btn" disabled={isActionLoading || !transAmount}>
                  {isActionLoading ? 'Saving...' : 'Record'}
                </button>
              </div>
            </form>
          </GlassCard>
        </div>
      )}

      <NavBar />

      <style>{`
        .budget-overview-container {
          padding: 16px 20px;
        }

        .page-header {
          display: flex;
          align-items: center;
          justify-content: space-between;
          height: 60px;
          margin-bottom: 16px;
        }

        .back-button, .header-action-icon {
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

        .budget-tab-row {
          display: flex;
          gap: 6px;
          overflow-x: auto;
          padding-bottom: 8px;
          margin-bottom: 20px;
          border-bottom: 1px solid var(--border-light);
        }

        .budget-tab {
          flex-shrink: 0;
          padding: 8px 16px;
          border-radius: 8px;
          font-family: var(--font-space-grotesk);
          font-size: 13px;
          font-weight: 700;
          color: var(--text-secondary);
          display: flex;
          align-items: center;
        }

        .budget-tab.active {
          color: rgb(22, 192, 122);
          border-bottom: 3px solid rgb(22, 192, 122);
          border-radius: 8px 8px 0 0;
        }

        .budget-loading, .requests-empty, .ledger-empty, .events-empty {
          text-align: center;
          padding: 40px;
          color: var(--text-secondary);
        }

        .budget-metrics-card {
          width: 100%;
          text-align: center;
        }

        .metrics-card-subtitle {
          font-size: 11px;
          color: var(--text-secondary);
          letter-spacing: 1.2px;
          font-weight: 600;
        }

        .metrics-card-title {
          font-family: var(--font-space-grotesk);
          font-size: 38px;
          font-weight: 800;
          margin: 8px 0 20px 0;
        }

        .metrics-card-title.positive {
          color: rgb(22, 192, 122);
        }

        .metrics-card-title.negative {
          color: var(--accent-red);
        }

        .summary-split-row {
          display: flex;
          justify-content: space-around;
          border-top: 1px solid var(--border-light);
          padding-top: 16px;
        }

        .split-col {
          display: flex;
          flex-direction: column;
        }

        .split-label {
          font-size: 11px;
          color: var(--text-muted);
          margin-bottom: 4px;
        }

        .split-val {
          font-family: var(--font-space-grotesk);
          font-size: 18px;
          font-weight: 700;
        }

        .split-val.income { color: rgb(22, 192, 122); }
        .split-val.expense { color: var(--accent-red); }

        .progress-bar-container {
          width: 100%;
          height: 8px;
          background: rgba(255,255,255,0.05);
          border-radius: 4px;
          overflow: hidden;
        }

        .progress-bar-fill {
          height: 100%;
          background: rgb(22, 192, 122);
          border-radius: 4px;
        }

        .progress-bar-fill.over {
          background-color: var(--accent-red);
        }

        .progress-bar-label {
          font-size: 10px;
          color: var(--text-muted);
          margin-top: 4px;
          display: block;
        }

        .chart-card-title {
          font-size: 13px;
          color: var(--text-secondary);
          text-transform: uppercase;
        }

        .mini-stat-card {
          flex: 1;
          flex-direction: column;
        }

        .mini-label {
          font-size: 10px;
          color: var(--text-muted);
          margin-bottom: 4px;
        }

        .mini-value {
          font-family: var(--font-space-grotesk);
          font-size: 16px;
          font-weight: 800;
        }

        /* Requests Tab */
        .requests-tab-flow, .ledger-tab-flow, .events-budget-tab-flow {
          display: flex;
          flex-direction: column;
          gap: 12px;
        }

        .requests-list, .ledger-list, .events-budget-list {
          display: flex;
          flex-direction: column;
          gap: 12px;
        }

        @media (min-width: 768px) {
          .requests-list, .ledger-list, .events-budget-list {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(320px, 1fr));
            gap: 20px;
          }
        }

        .section-subtitle-text {
          font-family: var(--font-space-grotesk);
          font-size: 12px;
          color: var(--text-secondary);
          text-transform: uppercase;
          letter-spacing: 1px;
        }

        .request-add-btn {
          background: rgba(22, 192, 122, 0.1);
          color: rgb(22, 192, 122);
          padding: 6px 12px;
          border-radius: 20px;
          font-family: var(--font-space-grotesk);
          font-weight: 700;
          font-size: 12px;
        }

        .request-item-card {
          width: 100%;
        }

        .request-card-header {
          display: flex;
          justify-content: space-between;
          align-items: center;
          margin-bottom: 12px;
          width: 100%;
        }

        .request-amount {
          font-family: var(--font-space-grotesk);
          font-size: 18px;
          font-weight: 800;
          color: var(--text-primary);
        }

        .request-status-badge {
          font-family: var(--font-space-grotesk);
          font-size: 10px;
          font-weight: 800;
          border-radius: 6px;
          padding: 4px 8px;
        }

        .request-status-badge.approved { background: rgba(22, 192, 122, 0.12); color: rgb(22, 192, 122); }
        .request-status-badge.pending { background: rgba(251, 191, 36, 0.12); color: rgb(251, 191, 36); }
        .request-status-badge.rejected { background: rgba(239, 68, 68, 0.12); color: rgb(239, 68, 68); }

        .request-reason-text {
          font-size: 13px;
          color: var(--text-secondary);
          line-height: 1.4;
          margin-bottom: 12px;
        }

        .proposal-link-btn {
          font-size: 12px;
          color: rgb(22, 192, 122);
          text-decoration: underline;
          display: inline-block;
          margin-bottom: 12px;
        }

        .request-action-row {
          display: flex;
          gap: 8px;
        }

        .review-btn {
          flex: 1;
          padding: 10px;
          border-radius: 10px;
          font-family: var(--font-space-grotesk);
          font-weight: 700;
          font-size: 12px;
        }

        .review-btn.approve {
          background: rgba(22, 192, 122, 0.1);
          color: rgb(22, 192, 122);
          border: 1px solid rgba(22, 192, 122, 0.3);
        }

        .review-btn.reject {
          background: rgba(239, 68, 68, 0.1);
          color: rgb(239, 68, 68);
          border: 1px solid rgba(239, 68, 68, 0.3);
        }

        /* Ledger Tab */
        .ledger-item-row {
          display: flex;
          align-items: center;
          justify-content: space-between;
          width: 100%;
        }

        .ledger-row-left {
          display: flex;
          flex-direction: column;
          gap: 2px;
        }

        .ledger-category {
          font-size: 14px;
          font-weight: 600;
          color: var(--text-primary);
        }

        .ledger-source, .ledger-date {
          font-size: 11px;
          color: var(--text-muted);
        }

        .ledger-amount {
          font-family: var(--font-space-grotesk);
          font-weight: 800;
          font-size: 16px;
        }

        .ledger-amount.income { color: rgb(22, 192, 122); }
        .ledger-amount.expense { color: var(--accent-red); }

        /* Event Budgets Tab */
        .event-budget-card {
          width: 100%;
        }

        .event-budget-header {
          display: flex;
          justify-content: space-between;
          align-items: flex-start;
          width: 100%;
          margin-bottom: 12px;
        }

        .event-budget-name {
          font-size: 16px;
          font-weight: 700;
          color: var(--text-primary);
        }

        .event-budget-date {
          font-size: 12px;
          color: var(--text-muted);
          display: block;
        }

        .event-budget-info-split {
          display: flex;
          justify-content: space-between;
          font-size: 13px;
          color: var(--text-secondary);
        }

        .over-budget-warning {
          font-size: 11px;
          color: var(--accent-red);
          font-weight: 700;
          display: block;
          margin-top: 6px;
        }

        .event-budget-actions {
          display: flex;
          gap: 8px;
        }

        .action-icon-pill {
          padding: 6px 12px;
          border-radius: 8px;
          font-size: 11px;
          font-weight: 600;
          color: var(--text-secondary);
          border: 1px solid var(--border-light);
          background: rgba(255,255,255,0.02);
        }

        .action-icon-pill.destructive {
          color: var(--accent-red);
          border-color: rgba(239, 68, 68, 0.2);
          background: rgba(239, 68, 68, 0.03);
        }

        /* Modal / Form elements */
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
          max-width: 380px;
          background: var(--bg-secondary);
        }

        .modal-title {
          font-size: 18px;
          color: var(--text-primary);
          margin-bottom: 6px;
        }

        .modal-subtitle-desc {
          font-size: 13px;
          color: var(--text-secondary);
          display: block;
        }

        .modal-input {
          width: 100%;
        }

        .modal-input-label {
          font-family: var(--font-space-grotesk);
          font-size: 12px;
          font-weight: 600;
          color: var(--text-secondary);
          margin-bottom: 4px;
          display: block;
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
          margin-top: 20px;
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
