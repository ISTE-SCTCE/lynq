import React, { useState, useEffect } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { ArrowLeft, Save, Loader } from 'lucide-react';
import { useAuth } from '../../core/auth-provider';
import { supabase } from '../../core/supabase-client';
import { FolderFeature } from '../../core/constants';
import { GlassCard } from '../../shared/components/GlassCard';
import { NavBar } from '../../shared/components/NavBar';

export const FolderPermissionsScreen: React.FC = () => {
  const { id } = useParams<{ id: string }>();
  const folderId = parseInt(id || '0');
  const navigate = useNavigate();
  const { permissions, currentUser } = useAuth();
  const [featureMap, setFeatureMap] = useState<Record<string, boolean>>({});
  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);

  useEffect(() => {
    if (!folderId || !currentUser) return;

    const fetchPermissions = async () => {
      setIsLoading(true);
      try {
        const { data, error } = await supabase
          .from('folder_permissions')
          .select('id, folder_id:execom_id, feature, allowed')
          .eq('execom_id', folderId);

        if (error) throw error;

        const mapped: Record<string, boolean> = {};
        FolderFeature.all.forEach((f) => {
          mapped[f] = false;
        });

        (data || []).forEach((p: any) => {
          mapped[p.feature] = p.allowed;
        });

        setFeatureMap(mapped);
      } catch (e) {
        console.error('Error loading permissions:', e);
      } finally {
        setIsLoading(false);
      }
    };

    fetchPermissions();
  }, [folderId, currentUser]);

  const handleToggle = (feature: string) => {
    setFeatureMap((prev) => ({
      ...prev,
      [feature]: !prev[feature],
    }));
  };

  const handleSave = async () => {
    setIsSaving(true);
    try {
      // Upsert permissions to guarantee existence
      const upserts = FolderFeature.all.map((feature) => ({
        execom_id: folderId,
        feature,
        allowed: featureMap[feature] || false,
      }));

      const { error } = await supabase
        .from('folder_permissions')
        .upsert(upserts, { onConflict: 'execom_id,feature' });

      if (error) throw error;
      alert('Permissions saved successfully!');
      navigate(`/folders/${folderId}`);
    } catch (e) {
      console.error('Save permissions error:', e);
      alert('Failed to save permissions');
    } finally {
      setIsSaving(false);
    }
  };

  if (!currentUser || !permissions) return null;

  return (
    <div className="permissions-screen-container">
      <header className="page-header">
        <button onClick={() => navigate(`/folders/${folderId}`)} className="back-button">
          <ArrowLeft size={20} />
        </button>
        <h2 className="page-title">Team Permissions</h2>
        <button 
          onClick={handleSave} 
          disabled={isSaving || isLoading} 
          className="save-button flex-center"
        >
          {isSaving ? <Loader size={20} className="spinner" /> : <Save size={20} />}
        </button>
      </header>

      {isLoading ? (
        <div className="permissions-loading">Loading configuration data...</div>
      ) : (
        <div className="permissions-content-list" style={{ marginBottom: '40px' }}>
          <p className="permissions-desc-text">
            Toggle which features are enabled for members within this folder.
          </p>

          {FolderFeature.all.map((feature) => {
            const isAllowed = featureMap[feature] || false;
            return (
              <GlassCard 
                key={feature} 
                className="permission-toggle-card" 
                padding="14px 20px"
              >
                <div className="toggle-row">
                  <span className="feature-label">{FolderFeature.label(feature)}</span>
                  <label className="switch-input-container">
                    <input 
                      type="checkbox" 
                      checked={isAllowed}
                      onChange={() => handleToggle(feature)}
                    />
                    <span className="switch-slider"></span>
                  </label>
                </div>
              </GlassCard>
            );
          })}
        </div>
      )}

      <NavBar />

      <style>{`
        .permissions-screen-container {
          padding: 16px 20px;
        }

        .page-header {
          display: flex;
          align-items: center;
          justify-content: space-between;
          height: 60px;
          margin-bottom: 20px;
        }

        .back-button, .save-button {
          color: var(--text-primary);
        }

        .save-button:disabled {
          opacity: 0.5;
        }

        .page-title {
          font-family: var(--font-space-grotesk);
          font-weight: 800;
          font-size: 20px;
          color: var(--text-primary);
        }

        .permissions-loading {
          text-align: center;
          padding: 40px;
          color: var(--text-secondary);
        }

        .permissions-desc-text {
          font-size: 13px;
          color: var(--text-secondary);
          margin-bottom: 20px;
          line-height: 1.4;
        }

        .permissions-content-list {
          display: flex;
          flex-direction: column;
          gap: 12px;
        }

        .permission-toggle-card {
          width: 100%;
        }

        .toggle-row {
          display: flex;
          align-items: center;
          justify-content: space-between;
          width: 100%;
        }

        .feature-label {
          font-size: 15px;
          font-weight: 600;
          color: var(--text-primary);
        }

        /* IOS Styled Switch Button */
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

        .spinner {
          animation: spin 1s linear infinite;
        }

        @keyframes spin {
          to { transform: rotate(360deg); }
        }
      `}</style>
    </div>
  );
};
