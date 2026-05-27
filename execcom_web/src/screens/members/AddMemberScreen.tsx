import React, { useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { ArrowLeft, User, Mail, Phone, Calendar, Badge, ShieldAlert, Sparkles, FileSpreadsheet, Check, Plus } from 'lucide-react';
import { useAuth } from '../../core/auth-provider';
import { supabase } from '../../core/supabase-client';
import { AppRole, AppRoleLabels } from '../../core/constants';
import { CustomTextField } from '../../shared/components/CustomTextField';
import { PrimaryButton } from '../../shared/components/PrimaryButton';
import { GlassCard } from '../../shared/components/GlassCard';
import { NavBar } from '../../shared/components/NavBar';

export const AddMemberScreen: React.FC = () => {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const { currentUser, permissions } = useAuth();
  
  const [activeTab, setActiveTab] = useState<'individual' | 'bulk'>('individual');
  const [isLoading, setIsLoading] = useState(false);

  // Form States
  const [name, setName] = useState('');
  const [email, setEmail] = useState('');
  const [phone, setPhone] = useState('');
  const [rollNo, setRollNo] = useState('');
  const [branch, setBranch] = useState('');
  const [role, setRole] = useState('member');
  const [post, setPost] = useState('');
  const [plan, setPlan] = useState('1 Year');
  const [enableSwas, setEnableSwas] = useState(false);
  const [forum, setForum] = useState('');
  const [validFrom, setValidFrom] = useState(new Date().toISOString().split('T')[0]);
  const [validUntil, setValidUntil] = useState(
    new Date(new Date().setFullYear(new Date().getFullYear() + 1)).toISOString().split('T')[0]
  );

  // Bulk Import States
  const [csvData, setCsvData] = useState<any[]>([]);
  const [bulkStatus, setBulkStatus] = useState('');
  const [importResults, setImportResults] = useState<{ success: number; failed: number } | null>(null);

  const handleManualEnroll = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!name.trim() || !email.trim() || !currentUser) return;

    // Guard: Only Chairman/Vice Chairman can promote/assign Execcom+ roles
    const targetRoleLevel = AppRole[role as keyof typeof AppRole] || AppRole.member;
    if (targetRoleLevel >= AppRole.forumExeccom) {
      const curRoleLevel = AppRole[currentUser.role as keyof typeof AppRole] || AppRole.member;
      if (curRoleLevel < AppRole.viceChairman) {
        alert('Only Chairman/Vice Chairman can enroll members into Execcom+ roles.');
        return;
      }
    }

    setIsLoading(true);
    try {
      const response = await supabase.functions.invoke('admin-create-user', {
        body: {
          name: name.trim(),
          email: email.trim(),
          role,
          post: post.trim(),
          phone: phone.trim(),
          roll_number: rollNo.trim(),
          branch: branch.trim(),
          membership_plan: plan,
          membership_date: validFrom,
          forum: forum || null,
          expiry_date: validUntil,
        },
      });

      if (response.error) {
        throw new Error(response.error.message || 'Failed to create user.');
      }

      alert('Member enrolled successfully! Default password is: isteISTE2026');
      const execomParam = searchParams.get('execom');
      if (execomParam) {
        navigate(`/execom/${execomParam}`);
      } else {
        navigate('/members');
      }
    } catch (e: any) {
      console.error('Enrollment error:', e);
      alert(`Enrollment failed: ${e.message || e}`);
    } finally {
      setIsLoading(false);
    }
  };

  // CSV parsing logic for Bulk import (highly efficient pure JS CSV parser)
  const handleFileUpload = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    const reader = new FileReader();
    reader.onload = (event) => {
      const text = event.target?.result as string;
      if (!text) return;

      const lines = text.split('\n');
      const headers = lines[0]
        .toLowerCase()
        .replace(/"/g, '')
        .split(',')
        .map((h) => h.trim().replace(/ /g, '').replace(/_/g, ''));

      const data: any[] = [];
      for (let i = 1; i < lines.length; i++) {
        if (!lines[i].trim()) continue;
        const columns = lines[i].split(',').map((c) => c.replace(/"/g, '').trim());
        const item: any = {};
        headers.forEach((header, index) => {
          if (index < columns.length) {
            item[header] = columns[index];
          }
        });
        data.push(item);
      }

      setCsvData(data);
      setBulkStatus(`Loaded ${data.length} records. Ready to import.`);
    };
    reader.readAsText(file);
  };

  const handleProcessBulk = async () => {
    if (csvData.length === 0) return;
    setIsLoading(true);
    let success = 0;
    let failed = 0;

    const getVal = (row: any, keys: string[]) => {
      for (const k of keys) {
        const normalized = k.toLowerCase().replace(/ /g, '').replace(/_/g, '');
        if (row[normalized] !== undefined && row[normalized] !== '') {
          return row[normalized];
        }
      }
      return null;
    };

    for (let i = 0; i < csvData.length; i++) {
      const row = csvData[i];
      try {
        const rName = getVal(row, ['name', 'fullname', 'studentname']) || '';
        const rEmail = getVal(row, ['email', 'emailaddress', 'mail', 'id']) || '';
        const rRole = getVal(row, ['role', 'type', 'usertype']) || 'member';
        const rPost = getVal(row, ['post', 'designation', 'position']) || '';
        const rPhone = getVal(row, ['phone', 'phonenumber', 'whatsapp', 'mobile']) || '';
        const rRoll = getVal(row, ['rollnumber', 'rollno', 'regno']) || '';
        const rBranch = getVal(row, ['branch', 'department', 'dept']) || '';
        const rPlan = getVal(row, ['plan', 'membershipplan']) || '1 Year';
        const rForum = getVal(row, ['forum', 'forumname', 'chapter']) || '';

        if (!rEmail) {
          failed++;
          continue;
        }

        const res = await supabase.functions.invoke('admin-create-user', {
          body: {
            name: rName,
            email: rEmail,
            role: rRole.toLowerCase().trim().replace(/ /g, '_'),
            post: rPost,
            phone: rPhone,
            roll_number: rRoll,
            branch: rBranch,
            membership_plan: rPlan,
            forum: rForum || null,
            status: 'active',
          },
        });

        if (!res.error) {
          success++;
        } else {
          failed++;
        }
      } catch (err) {
        failed++;
      }
      setBulkStatus(`Importing... ${success + failed} / ${csvData.length}`);
    }

    setIsLoading(false);
    setImportResults({ success, failed });
  };

  if (!currentUser || !permissions) return null;

  return (
    <div className="add-member-container">
      <header className="page-header">
        <button onClick={() => navigate('/members')} className="back-button">
          <ArrowLeft size={20} />
        </button>
        
        {/* Toggle Slider Header */}
        <div className="toggle-header-tabs">
          <button 
            onClick={() => setActiveTab('individual')} 
            className={`header-tab-pill ${activeTab === 'individual' ? 'active' : ''}`}
          >
            INDIVIDUAL
          </button>
          <button 
            onClick={() => setActiveTab('bulk')} 
            className={`header-tab-pill ${activeTab === 'bulk' ? 'active' : ''}`}
          >
            BULK IMPORT
          </button>
        </div>
        <div style={{ width: '20px' }}></div>
      </header>

      {/* Manual Entry Form */}
      {activeTab === 'individual' ? (
        <form onSubmit={handleManualEnroll} className="enrollment-form" style={{ marginBottom: '40px' }}>
          <section className="form-section">
            <h4 className="section-title">Personal Details</h4>
            <GlassCard className="form-group-card" padding="20px">
              <CustomTextField
                label="Full Name"
                value={name}
                onChange={setName}
                prefixIcon={User}
                placeholder="John Doe"
              />
              <CustomTextField
                label="Email address"
                value={email}
                onChange={setEmail}
                prefixIcon={Mail}
                type="email"
                placeholder="name@iste.org"
              />
              <CustomTextField
                label="Phone number"
                value={phone}
                onChange={setPhone}
                prefixIcon={Phone}
                type="tel"
                placeholder="9876543210"
              />
            </GlassCard>
          </section>

          <section className="form-section">
            <h4 className="section-title">Academic & Org Profile</h4>
            <GlassCard className="form-group-card" padding="20px">
              <div className="form-row-split">
                <CustomTextField
                  label="Roll No"
                  value={rollNo}
                  onChange={setRollNo}
                  placeholder="22CS001"
                />
                <CustomTextField
                  label="Branch"
                  value={branch}
                  onChange={setBranch}
                  placeholder="CSE"
                />
              </div>
              
              <div style={{ marginBottom: '16px' }}>
                <label className="select-input-label">Organization Role</label>
                <select
                  value={role}
                  onChange={(e) => setRole(e.target.value)}
                  className="form-select-field"
                >
                  {Object.keys(AppRoleLabels).map((lvl) => {
                    const level = parseInt(lvl);
                    // Filter matches Flutter conditions: values.where(r != restricted && r != forumExeccom && r != coreExeccom)
                    if ([AppRole.restricted, AppRole.forumExeccom, AppRole.coreExeccom].includes(level)) return null;
                    const dbStr = level === AppRole.chairman ? 'chairman' :
                                  level === AppRole.viceChairman ? 'vice_chairman' :
                                  level === AppRole.panel ? 'panel' : 'member';
                    return (
                      <option key={level} value={dbStr}>
                        {AppRoleLabels[level as keyof typeof AppRoleLabels]}
                      </option>
                    );
                  })}
                </select>
              </div>

              <CustomTextField
                label="Active Post"
                value={post}
                onChange={setPost}
                placeholder="Executive Board Member"
              />
            </GlassCard>
          </section>

          <section className="form-section">
            <h4 className="section-title">Membership Status</h4>
            <GlassCard className="form-group-card" padding="20px">
              <div style={{ marginBottom: '16px' }}>
                <label className="select-input-label">Select Plan</label>
                <select
                  value={plan}
                  onChange={(e) => setPlan(e.target.value)}
                  className="form-select-field"
                >
                  <option value="1 Year">1 Year</option>
                  <option value="4 Years">4 Years</option>
                  <option value="Life Member">Life Member</option>
                </select>
              </div>

              <div className="form-switch-row">
                <span className="switch-row-label">Enable SWAS Forum Option</span>
                <label className="switch-input-container">
                  <input 
                    type="checkbox" 
                    checked={enableSwas}
                    onChange={(e) => {
                      setEnableSwas(e.target.checked);
                      if (!e.target.checked && forum === 'SWAS') {
                        setForum('');
                      }
                    }}
                  />
                  <span className="switch-slider"></span>
                </label>
              </div>

              <div style={{ marginBottom: '16px' }}>
                <label className="select-input-label">Forum Association</label>
                <select
                  value={forum}
                  onChange={(e) => setForum(e.target.value)}
                  className="form-select-field"
                >
                  <option value="">Choose Forum</option>
                  <option value="EXIS">EXIS</option>
                  <option value="BITS">BITS</option>
                  <option value="TORQ">TORQ</option>
                  <option value="GENESIS">GENESIS</option>
                  {enableSwas && <option value="SWAS">SWAS</option>}
                </select>
              </div>

              <div className="form-row-split">
                <div className="date-field-wrapper">
                  <label className="select-input-label">Valid From</label>
                  <input
                    type="date"
                    value={validFrom}
                    onChange={(e) => setValidFrom(e.target.value)}
                    className="form-date-input"
                  />
                </div>
                <div className="date-field-wrapper">
                  <label className="select-input-label">Valid Until</label>
                  <input
                    type="date"
                    value={validUntil}
                    onChange={(e) => setValidUntil(e.target.value)}
                    className="form-date-input"
                  />
                </div>
              </div>
            </GlassCard>
          </section>

          <div style={{ marginTop: '30px' }}>
            <PrimaryButton
              text="Enroll Member"
              type="submit"
              isLoading={isLoading}
              disabled={!name.trim() || !email.trim()}
              icon={Sparkles}
            />
          </div>
        </form>
      ) : (
        /* Bulk Import Layout */
        <div className="bulk-import-wrapper flex-center" style={{ flexDirection: 'column' }}>
          <div className="bulk-icon-cloud float-animation">
            <FileSpreadsheet size={48} style={{ color: 'rgb(22, 192, 122)' }} />
          </div>
          <h3 className="bulk-card-title">Bulk Enrollment</h3>
          <p className="bulk-card-desc">
            Import members from a CSV sheet. Supported columns: Name, Email, Phone, RollNumber, Branch, Role, Post, Plan, Forum.
          </p>

          {csvData.length > 0 ? (
            <GlassCard className="bulk-processor-card" padding="24px" style={{ width: '100%' }}>
              <div className="processor-header flex-center">
                <Check size={18} style={{ color: 'rgb(22, 192, 122)', marginRight: '8px' }} />
                <span className="processor-status">{bulkStatus}</span>
              </div>
              
              <div style={{ marginTop: '24px' }}>
                <PrimaryButton
                  text="Process Registry"
                  onClick={handleProcessBulk}
                  isLoading={isLoading}
                />
                <button 
                  onClick={() => { setCsvData([]); setImportResults(null); }}
                  className="bulk-reset-btn"
                  disabled={isLoading}
                >
                  Cancel & Reset
                </button>
              </div>
            </GlassCard>
          ) : (
            <label className="bulk-upload-label flex-center">
              <Plus size={16} style={{ marginRight: '8px' }} /> Load CSV File
              <input 
                type="file" 
                accept=".csv" 
                onChange={handleFileUpload} 
                style={{ display: 'none' }} 
              />
            </label>
          )}

          {/* Import Result Overlay Dialog */}
          {importResults && (
            <div className="modal-overlay">
              <GlassCard className="modal-card" padding="24px">
                <h3 className="modal-title">Import Results</h3>
                <div className="stat-result-box flex-center" style={{ background: 'rgba(22, 192, 122, 0.08)', color: '#16c07a', marginBottom: '12px' }}>
                  <span>Successful: {importResults.success}</span>
                </div>
                <div className="stat-result-box flex-center" style={{ background: 'rgba(239, 68, 68, 0.08)', color: '#ef4444' }}>
                  <span>Failed/Skipped: {importResults.failed}</span>
                </div>
                <div className="modal-actions-row" style={{ marginTop: '24px' }}>
                  <button 
                    onClick={() => { setCsvData([]); setImportResults(null); }} 
                    className="modal-submit-btn"
                  >
                    Done
                  </button>
                </div>
              </GlassCard>
            </div>
          )}
        </div>
      )}

      <NavBar />

      <style>{`
        .add-member-container {
          padding: 16px 20px;
        }

        .page-header {
          display: flex;
          align-items: center;
          justify-content: space-between;
          height: 60px;
          margin-bottom: 24px;
        }

        .back-button {
          color: var(--text-primary);
        }

        .toggle-header-tabs {
          display: flex;
          background: rgba(255, 255, 255, 0.04);
          border: 1px solid var(--border-light);
          border-radius: 12px;
          padding: 4px;
        }

        .header-tab-pill {
          padding: 8px 16px;
          border-radius: 8px;
          font-family: var(--font-space-grotesk);
          font-size: 11px;
          font-weight: 700;
          color: var(--text-muted);
        }

        .header-tab-pill.active {
          background: rgb(22, 192, 122);
          color: var(--bg-primary);
        }

        .form-section {
          display: flex;
          flex-direction: column;
          gap: 12px;
          margin-bottom: 24px;
        }

        .section-title {
          font-family: var(--font-space-grotesk);
          font-size: 13px;
          font-weight: 800;
          letter-spacing: 1.2px;
          color: var(--text-secondary);
          text-transform: uppercase;
        }

        .form-group-card {
          width: 100%;
        }

        .form-row-split {
          display: flex;
          gap: 12px;
        }

        .select-input-label {
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

        .form-switch-row {
          display: flex;
          align-items: center;
          justify-content: space-between;
          margin-bottom: 20px;
          width: 100%;
        }

        .switch-row-label {
          font-size: 14px;
          color: var(--text-secondary);
          font-weight: 500;
        }

        /* IOS Switch slider */
        .switch-input-container {
          position: relative;
          display: inline-block;
          width: 48px;
          height: 26px;
        }

        .switch-input-container input {
          opacity: 0;
          width: 0;
          height: 0;
        }

        .switch-slider {
          position: absolute;
          cursor: pointer;
          top: 0;
          left: 0;
          right: 0;
          bottom: 0;
          background-color: var(--text-muted);
          transition: .3s;
          border-radius: 34px;
        }

        .switch-slider:before {
          position: absolute;
          content: "";
          height: 20px;
          width: 20px;
          left: 3px;
          bottom: 3px;
          background-color: white;
          transition: .3s;
          border-radius: 50%;
        }

        input:checked + .switch-slider {
          background-color: rgb(22, 192, 122);
        }

        input:checked + .switch-slider:before {
          transform: translateX(22px);
        }

        .date-field-wrapper {
          flex: 1;
        }

        .form-date-input {
          width: 100%;
          padding: 12px;
          background: rgba(255, 255, 255, 0.04);
          border: 1px solid var(--border-light);
          border-radius: 12px;
          color: var(--text-primary);
          font-size: 13px;
          outline: none;
        }

        /* Bulk Import Layout */
        .bulk-import-wrapper {
          padding: 60px 20px;
          text-align: center;
        }

        .bulk-icon-cloud {
          width: 90px;
          height: 90px;
          border-radius: 50%;
          background: rgba(22, 192, 122, 0.08);
          border: 1px solid rgba(22, 192, 122, 0.2);
          display: flex;
          align-items: center;
          justify-content: center;
          margin-bottom: 24px;
        }

        .bulk-card-title {
          font-size: 22px;
          color: var(--text-primary);
          margin-bottom: 12px;
        }

        .bulk-card-desc {
          font-size: 13px;
          color: var(--text-muted);
          line-height: 1.6;
          margin-bottom: 40px;
          max-width: 320px;
        }

        .bulk-upload-label {
          background: linear-gradient(135deg, rgb(15, 117, 73) 0%, rgb(22, 192, 122) 100%);
          color: #ffffff;
          padding: 14px 28px;
          border-radius: 14px;
          font-family: var(--font-space-grotesk);
          font-weight: 700;
          font-size: 15px;
          cursor: pointer;
          box-shadow: 0 4px 15px rgba(22, 192, 122, 0.2);
        }

        .bulk-processor-card {
          text-align: center;
        }

        .processor-status {
          font-size: 14px;
          font-weight: 700;
          color: rgb(22, 192, 122);
        }

        .bulk-reset-btn {
          margin-top: 12px;
          color: var(--text-muted);
          font-size: 13px;
          display: block;
          width: 100%;
          text-align: center;
        }

        .stat-result-box {
          width: 100%;
          padding: 14px;
          border-radius: 12px;
          font-family: var(--font-space-grotesk);
          font-weight: 700;
          font-size: 15px;
        }

        /* Modal Layout */
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

        .modal-actions-row {
          display: flex;
          justify-content: flex-end;
        }

        .modal-submit-btn {
          padding: 10px 20px;
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
