import React, { useState, useEffect } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { ArrowLeft, User, Shield, Moon, Sun, Lock, RefreshCw, Info, LogOut, X, Key, Check } from 'lucide-react';
import { useAuth } from '../../core/auth-provider';
import { supabase } from '../../core/supabase-client';
import { GlassCard } from '../../shared/components/GlassCard';
import { PrimaryButton } from '../../shared/components/PrimaryButton';
import { NavBar } from '../../shared/components/NavBar';
import { AppRoleLabels, appRoleFromString } from '../../core/constants';

export const SettingsScreen: React.FC = () => {
  const navigate = useNavigate();
  const { currentUser, permissions, signOut, refreshUserData } = useAuth();
  
  const [isDarkMode, setIsDarkMode] = useState(() => {
    return document.documentElement.getAttribute('data-theme') === 'dark';
  });

  const [showPasswordModal, setShowPasswordModal] = useState(false);
  const [newPassword, setNewPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [isUpdatingPassword, setIsUpdatingPassword] = useState(false);
  const [passError, setPassError] = useState<string | null>(null);

  const [showAboutModal, setShowAboutModal] = useState(false);
  const [isRefreshing, setIsRefreshing] = useState(false);

  useEffect(() => {
    // Synchronize dark theme attribute
    document.documentElement.setAttribute('data-theme', isDarkMode ? 'dark' : 'light');
    localStorage.setItem('theme', isDarkMode ? 'dark' : 'light');
  }, [isDarkMode]);

  if (!currentUser || !permissions) return null;
  
  const roleEnum = appRoleFromString(currentUser.role);
  const roleLabel = AppRoleLabels[roleEnum] || currentUser.role;

  const handleToggleTheme = () => {
    setIsDarkMode(prev => !prev);
  };

  const handleUpdatePassword = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!newPassword.trim()) return;
    
    if (newPassword !== confirmPassword) {
      setPassError('Passwords do not match.');
      return;
    }

    setIsUpdatingPassword(true);
    setPassError(null);

    try {
      const { error } = await supabase.auth.updateUser({
        password: newPassword.trim(),
      });

      if (error) throw error;
      
      alert('Password updated successfully!');
      setShowPasswordModal(false);
      setNewPassword('');
      setConfirmPassword('');
    } catch (err: any) {
      console.error('Password update failed:', err);
      setPassError(err.message || 'Failed to update password.');
    } finally {
      setIsUpdatingPassword(false);
    }
  };

  const handleRefreshData = async () => {
    setIsRefreshing(true);
    try {
      await refreshUserData();
      alert('Data refreshed successfully!');
    } catch (e) {
      console.error(e);
    } finally {
      setIsRefreshing(false);
    }
  };

  return (
    <div className="settings-container" style={{ paddingBottom: '80px' }}>
      <header className="page-header">
        <button onClick={() => navigate('/home')} className="back-button">
          <ArrowLeft size={20} />
        </button>
        <h2 className="page-title">Settings</h2>
        <div style={{ width: '20px' }}></div>
      </header>

      <div className="settings-grid-layout">
        <div className="settings-left-pane">
          {/* Profile Card Block */}
          <GlassCard className="profile-card" padding="24px" style={{ textAlign: 'center', marginBottom: '24px' }}>
            <div className="avatar-large flex-center">
              {currentUser.name?.[0]?.toUpperCase()}
            </div>
            <h3 className="profile-name">{currentUser.name}</h3>
            {currentUser.post && <span className="profile-post">{currentUser.post}</span>}
            <div className="profile-role-tag">{roleLabel}</div>
            <p className="profile-email">{currentUser.email}</p>
          </GlassCard>

          {/* Logout Action */}
          <div style={{ marginTop: '24px', marginBottom: '24px' }}>
            <button className="signout-btn flex-center" onClick={signOut}>
              <LogOut size={16} style={{ marginRight: '8px' }} />
              Sign Out of Account
            </button>
          </div>
        </div>

        <div className="settings-right-pane">
          {/* Settings Options Categories */}
          
          {/* Category: Appearance */}
          <div className="settings-section">
            <h4 className="section-title">Appearance</h4>
            <GlassCard padding="0" className="options-card">
              <div className="option-tile flex-center" onClick={handleToggleTheme}>
                <div className="tile-icon-wrapper flex-center theme">
                  {isDarkMode ? <Moon size={18} /> : <Sun size={18} />}
                </div>
                <div className="tile-text">
                  <span className="tile-title">Dark Mode</span>
                  <span className="tile-desc">Toggle darker background layouts</span>
                </div>
                <label className="switch" onClick={e => e.stopPropagation()}>
                  <input 
                    type="checkbox" 
                    checked={isDarkMode}
                    onChange={handleToggleTheme}
                  />
                  <span className="slider round"></span>
                </label>
              </div>
            </GlassCard>
          </div>

          {/* Category: Security */}
          <div className="settings-section">
            <h4 className="section-title">Account & Security</h4>
            <GlassCard padding="0" className="options-card">
              <div className="option-tile flex-center" onClick={() => setShowPasswordModal(true)}>
                <div className="tile-icon-wrapper flex-center security">
                  <Lock size={18} />
                </div>
                <div className="tile-text">
                  <span className="tile-title">Change Password</span>
                  <span className="tile-desc">Modify your log in password</span>
                </div>
                <Key size={14} className="arrow-icon" />
              </div>

              <div className="option-tile flex-center" onClick={handleRefreshData}>
                <div className="tile-icon-wrapper flex-center refresh">
                  <RefreshCw size={18} className={isRefreshing ? 'spinning' : ''} />
                </div>
                <div className="tile-text">
                  <span className="tile-title">Refresh Account Data</span>
                  <span className="tile-desc">Force synchronise cache states</span>
                </div>
                <Check size={14} className="arrow-icon" />
              </div>
            </GlassCard>
          </div>

          {/* Category: System */}
          <div className="settings-section">
            <h4 className="section-title">System</h4>
            <GlassCard padding="0" className="options-card">
              <div className="option-tile flex-center" onClick={() => setShowAboutModal(true)}>
                <div className="tile-icon-wrapper flex-center system">
                  <Info size={18} />
                </div>
                <div className="tile-text">
                  <span className="tile-title">About Execcom</span>
                  <span className="tile-desc">View system versions and specs</span>
                </div>
                <Info size={14} className="arrow-icon" />
              </div>

              {permissions.canManageGlobalPermissions && (
                <div className="option-tile flex-center" onClick={() => navigate('/settings/permissions')}>
                  <div className="tile-icon-wrapper flex-center admin">
                    <Shield size={18} />
                  </div>
                  <div className="tile-text">
                    <span className="tile-title">Global Permission Manager</span>
                    <span className="tile-desc">Adjust administrative level checks</span>
                  </div>
                  <Shield size={14} className="arrow-icon" />
                </div>
              )}
            </GlassCard>
          </div>
        </div>
      </div>

      {/* Password Edit Modal */}
      {showPasswordModal && (
        <div className="modal-overlay flex-center" onClick={() => setShowPasswordModal(false)}>
          <GlassCard className="password-modal" padding="24px" onClick={e => e.stopPropagation()}>
            <div className="modal-header flex-center" style={{ justifyContent: 'space-between', marginBottom: '16px' }}>
              <h4 className="modal-title" style={{ margin: 0 }}>Update Password</h4>
              <button className="close-btn" onClick={() => setShowPasswordModal(false)}>
                <X size={18} />
              </button>
            </div>

            {passError && <div className="modal-error">{passError}</div>}

            <form onSubmit={handleUpdatePassword}>
              <div className="form-group" style={{ marginBottom: '12px' }}>
                <label className="form-label">New Password</label>
                <input 
                  type="password" 
                  className="modal-input" 
                  value={newPassword}
                  onChange={e => setNewPassword(e.target.value)}
                  placeholder="Enter at least 6 characters"
                  required
                />
              </div>

              <div className="form-group" style={{ marginBottom: '20px' }}>
                <label className="form-label">Confirm Password</label>
                <input 
                  type="password" 
                  className="modal-input" 
                  value={confirmPassword}
                  onChange={e => setConfirmPassword(e.target.value)}
                  placeholder="Repeat new password"
                  required
                />
              </div>

              <PrimaryButton type="submit" isLoading={isUpdatingPassword} style={{ width: '100%' }}>
                Save Settings
              </PrimaryButton>
            </form>
          </GlassCard>
        </div>
      )}

      {/* About App Modal */}
      {showAboutModal && (
        <div className="modal-overlay flex-center" onClick={() => setShowAboutModal(false)}>
          <GlassCard className="about-modal" padding="24px" style={{ textAlign: 'center' }} onClick={e => e.stopPropagation()}>
            <div className="modal-header flex-center" style={{ justifyContent: 'space-between', marginBottom: '12px' }}>
              <h4 style={{ margin: 0, fontFamily: 'var(--font-space-grotesk)' }}>About Application</h4>
              <button className="close-btn" onClick={() => setShowAboutModal(false)}>
                <X size={18} />
              </button>
            </div>
            
            <div className="avatar-large flex-center" style={{ margin: '16px auto', background: 'rgba(22, 192, 122, 0.15)', color: 'rgb(22, 192, 122)' }}>
              ISTE
            </div>

            <h3 style={{ fontFamily: 'var(--font-space-grotesk)', fontSize: '18px', fontWeight: '800', margin: '8px 0 2px 0' }}>
              ISTE Execcom Web
            </h3>
            <span style={{ fontSize: '12px', color: 'var(--text-muted)' }}>Version 1.0.0 (Production Build)</span>
            
            <p style={{ fontSize: '13px', color: 'var(--text-secondary)', lineHeight: '1.45', margin: '16px 0 0 0', textAlign: 'left' }}>
              Execcom Management Web portal facilitates real-time tracking of budgets, notices, registrations, chat channels, and tasks for executive committee organizers.
            </p>
          </GlassCard>
        </div>
      )}

      <NavBar />

      <style>{`
        .settings-container {
          padding: 16px 20px;
          width: 100%;
          max-width: 100%;
          margin: 0;
        }

        @media (min-width: 768px) {
          .settings-container {
            padding: 24px 0;
          }
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

        /* Profile Card */
        .avatar-large {
          width: 72px;
          height: 72px;
          border-radius: 50%;
          background: rgba(22, 192, 122, 0.15);
          color: rgb(22, 192, 122);
          font-family: var(--font-space-grotesk);
          font-weight: 800;
          font-size: 28px;
          margin: 0 auto 12px auto;
        }

        .profile-name {
          font-family: var(--font-space-grotesk);
          font-weight: 800;
          font-size: 20px;
          color: var(--text-primary);
          margin-bottom: 4px;
        }

        .profile-post {
          font-family: var(--font-inter);
          font-weight: 600;
          font-size: 13px;
          color: var(--text-secondary);
          background: rgba(255,255,255,0.04);
          padding: 3px 10px;
          border-radius: 12px;
          border: 1px solid var(--border-light);
          display: inline-block;
          margin-bottom: 8px;
        }

        .profile-role-tag {
          font-family: var(--font-space-grotesk);
          font-size: 11px;
          font-weight: 700;
          color: var(--text-muted);
          text-transform: uppercase;
        }

        .profile-email {
          font-size: 12px;
          color: var(--text-muted);
          margin: 4px 0 0 0;
        }

        /* Categories Section */
        .settings-section {
          margin-bottom: 20px;
        }

        .settings-section .section-title {
          font-family: var(--font-space-grotesk);
          font-weight: 700;
          font-size: 13px;
          color: var(--text-muted);
          text-transform: uppercase;
          margin-bottom: 8px;
          margin-left: 4px;
        }

        .options-card {
          border-radius: 16px;
          overflow: hidden;
        }

        .option-tile {
          padding: 12px 16px;
          justify-content: flex-start;
          cursor: pointer;
          border-bottom: 1px solid var(--border-light);
          transition: background-color 0.2s ease;
        }

        .option-tile:last-child {
          border-bottom: none;
        }

        .option-tile:hover {
          background: rgba(255,255,255,0.02);
        }

        .tile-icon-wrapper {
          width: 38px;
          height: 38px;
          border-radius: 10px;
          flex-shrink: 0;
          color: var(--text-secondary);
        }

        .tile-icon-wrapper.theme { background: rgba(22, 192, 122, 0.1); color: rgb(22, 192, 122); }
        .tile-icon-wrapper.security { background: rgba(38, 138, 255, 0.1); color: #268aff; }
        .tile-icon-wrapper.refresh { background: rgba(245, 158, 11, 0.1); color: #f59e0b; }
        .tile-icon-wrapper.system { background: rgba(107, 114, 128, 0.1); color: #6b7280; }
        .tile-icon-wrapper.admin { background: rgba(239, 68, 68, 0.1); color: #ef4444; }

        .tile-text {
          flex: 1;
          margin-left: 14px;
          display: flex;
          flex-direction: column;
          text-align: left;
        }

        .tile-title {
          font-family: var(--font-space-grotesk);
          font-weight: 700;
          font-size: 14px;
          color: var(--text-primary);
        }

        .tile-desc {
          font-size: 11px;
          color: var(--text-muted);
        }

        .arrow-icon {
          color: var(--text-muted);
        }

        .signout-btn {
          width: 100%;
          padding: 14px;
          background: rgba(239, 68, 68, 0.15);
          color: #ef4444;
          border: 1px solid rgba(239, 68, 68, 0.25);
          border-radius: 12px;
          font-family: var(--font-space-grotesk);
          font-weight: 700;
          font-size: 14px;
          cursor: pointer;
        }

        .spinning {
          animation: spin 1s linear infinite;
        }
        @keyframes spin {
          to { transform: rotate(360deg); }
        }

        /* Toggle Button */
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

        /* Modals */
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

        .password-modal, .about-modal {
          width: 90%;
          max-width: 400px;
        }

        .modal-error {
          background: rgba(239,68,68,0.15);
          border: 1px solid rgba(239,68,68,0.25);
          color: #ef4444;
          padding: 8px 12px;
          border-radius: 8px;
          font-size: 12px;
          font-weight: 600;
          margin-bottom: 12px;
        }

        .form-label {
          font-family: var(--font-space-grotesk);
          font-size: 12px;
          font-weight: 700;
          color: var(--text-muted);
          margin-bottom: 6px;
          display: block;
        }

        .modal-input {
          background: rgba(255,255,255,0.02);
          border: 1px solid var(--border-light);
          border-radius: 10px;
          padding: 10px 12px;
          font-family: var(--font-inter);
          font-size: 13.5px;
          color: var(--text-primary);
          outline: none;
        }

        .close-btn {
          color: var(--text-muted);
        }

        .settings-grid-layout {
          display: flex;
          flex-direction: column;
          gap: 24px;
        }

        @media (min-width: 1024px) {
          .settings-grid-layout {
            display: grid;
            grid-template-columns: 1fr 1.6fr;
            gap: 32px;
            align-items: start;
          }
        }
      `}</style>
    </div>
  );
};
