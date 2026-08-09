import React, { useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { ArrowLeft, Image as ImageIcon, Sparkles, Loader } from 'lucide-react';
import { useAuth } from '../../core/auth-provider';
import { supabase } from '../../core/supabase-client';
import { CustomTextField } from '../../shared/components/CustomTextField';
import { PrimaryButton } from '../../shared/components/PrimaryButton';
import { GlassCard } from '../../shared/components/GlassCard';

import { NavBar } from '../../shared/components/NavBar';

export const EventFormScreen: React.FC = () => {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const { currentUser, permissions } = useAuth();
  
  const folderParam = searchParams.get('folder');
  const folderId = folderParam ? parseInt(folderParam) : null;

  // Form States
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [date, setDate] = useState(new Date().toISOString().split('T')[0]);
  const [location, setLocation] = useState('');
  const [isPaid, setIsPaid] = useState(false);
  const [memberPrice, setMemberPrice] = useState('0');
  const [nonMemberPrice, setNonMemberPrice] = useState('0');
  
  const [posterFile, setPosterFile] = useState<File | null>(null);
  const [posterPreview, setPosterPreview] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(false);

  const allowedRolesList = ['member', 'restricted', 'panel', 'forum_execcom', 'core_execcom', 'vice_chairman', 'chairman'];
  const [selectedRoles, setSelectedRoles] = useState<string[]>(allowedRolesList);

  const [numDays, setNumDays] = useState('1');
  const [category, setCategory] = useState('General');
  const [coordinatorName, setCoordinatorName] = useState('');
  const [chairName, setChairName] = useState('');
  const [templateFile, setTemplateFile] = useState<File | null>(null);
  const categories = ['Hackathon', 'Workshop', 'Seminar', 'General'];

  const handleImageChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) {
      setPosterFile(file);
      setPosterPreview(URL.createObjectURL(file));
    }
  };

  const uploadPoster = async (): Promise<string | null> => {
    if (!posterFile) return null;
    try {
      const ext = posterFile.name.split('.').pop();
      const fileName = `${crypto.randomUUID()}.${ext}`;
      const path = `posters/${fileName}`;

      const { data, error } = await supabase.storage
        .from('event_posters')
        .upload(path, posterFile, {
          contentType: 'image/jpeg',
        });

      if (error) throw error;

      const { data: { publicUrl } } = supabase.storage
        .from('event_posters')
        .getPublicUrl(path);

      return publicUrl;
    } catch (e) {
      console.error('Poster upload failed:', e);
      return null;
    }
  };

  const uploadTemplate = async (): Promise<string | null> => {
    if (!templateFile) return null;
    try {
      const ext = templateFile.name.split('.').pop() || 'html';
      const fileName = `template_${crypto.randomUUID()}.${ext}`;
      const path = `templates/${fileName}`;

      const { data, error } = await supabase.storage
        .from('event_posters')
        .upload(path, templateFile, {
          contentType: 'text/html',
        });

      if (error) throw error;

      const { data: { publicUrl } } = supabase.storage
        .from('event_posters')
        .getPublicUrl(path);

      return publicUrl;
    } catch (e) {
      console.error('Template upload failed:', e);
      return null;
    }
  };

  const handleRoleToggle = (role: string) => {
    setSelectedRoles((prev) =>
      prev.includes(role) ? prev.filter((r) => r !== role) : [...prev, role]
    );
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!title.trim() || !currentUser) return;

    setIsLoading(true);
    try {
      let uploadedUrl: string | null = null;
      if (posterFile) {
        uploadedUrl = await uploadPoster();
      }

      let uploadedTemplateUrl: string | null = null;
      if (templateFile) {
        uploadedTemplateUrl = await uploadTemplate();
      }

      const { error } = await supabase.from('events').insert({
        title: title.trim(),
        description: description.trim(),
        date,
        execom_id: folderId,
        created_by: currentUser.id,
        member_price: parseInt(memberPrice) || 0,
        non_member_price: parseInt(nonMemberPrice) || 0,
        is_paid: isPaid,
        location: location.trim(),
        allowed_roles: selectedRoles,
        poster_url: uploadedUrl,
        num_days: parseInt(numDays) || 1,
        category,
        coordinator_name: coordinatorName.trim() || null,
        chair_name: chairName.trim() || null,
        template_url: uploadedTemplateUrl,
      });

      if (error) throw error;
      alert('Event created successfully!');
      navigate(folderId ? `/events?folder=${folderId}` : '/events');
    } catch (e) {
      console.error('Create event error:', e);
      alert('Failed to create event');
    } finally {
      setIsLoading(false);
    }
  };

  if (!currentUser || !permissions) return null;

  return (
    <div className="event-form-container">
      <header className="page-header">
        <button onClick={() => navigate(folderId ? `/events?folder=${folderId}` : '/events')} className="back-button">
          <ArrowLeft size={20} />
        </button>
        <h2 className="page-title">Create Event</h2>
        <div style={{ width: '20px' }}></div>
      </header>

      <form onSubmit={handleSubmit} className="event-form" style={{ marginBottom: '40px' }}>
        <GlassCard className="form-fields-card" padding="24px">
          {/* File input image uploader */}
          <label className="image-uploader-block flex-center" style={{ backgroundImage: posterPreview ? `url(${posterPreview})` : 'none' }}>
            {!posterPreview && (
              <div className="uploader-content flex-center" style={{ flexDirection: 'column' }}>
                <ImageIcon size={36} style={{ color: 'var(--text-muted)', marginBottom: '8px' }} />
                <span className="uploader-label">Add Event Poster</span>
              </div>
            )}
            <input 
              type="file" 
              accept="image/*" 
              onChange={handleImageChange} 
              style={{ display: 'none' }} 
            />
          </label>

          <CustomTextField
            label="Event Title"
            value={title}
            onChange={setTitle}
            placeholder="Introduce the event"
          />

          <CustomTextField
            label="Description"
            value={description}
            onChange={setDescription}
            maxLines={4}
            placeholder="Detail event schedules and features"
          />

          <div style={{ marginBottom: '16px' }}>
            <label className="form-input-label">Date</label>
            <input
              type="date"
              value={date}
              onChange={(e) => setDate(e.target.value)}
              className="form-date-picker"
            />
          </div>

          <CustomTextField
            label="Location"
            value={location}
            onChange={setLocation}
            placeholder="Venue details"
          />

          <div style={{ marginBottom: '16px' }}>
            <label className="form-input-label">Event Category</label>
            <select
              value={category}
              onChange={(e) => setCategory(e.target.value)}
              className="form-date-picker"
              style={{ width: '100%', background: 'rgba(255, 255, 255, 0.04)', border: '1px solid var(--border-light)', borderRadius: '14px', color: 'var(--text-primary)', padding: '14px', outline: 'none' }}
            >
              {categories.map((c) => (
                <option key={c} value={c} style={{ background: '#121212', color: 'white' }}>{c}</option>
              ))}
            </select>
          </div>

          <CustomTextField
            label="Event Coordinator Name"
            value={coordinatorName}
            onChange={setCoordinatorName}
            placeholder="Name of Coordinator"
          />

          <CustomTextField
            label="Chapter Chairperson Name"
            value={chairName}
            onChange={setChairName}
            placeholder="Name of Chairperson"
          />

          <div style={{ marginBottom: '16px' }}>
            <label className="form-input-label">Upload HTML Certificate Template (Optional)</label>
            <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
              <input
                type="file"
                accept=".html"
                id="template-file-input"
                style={{ display: 'none' }}
                onChange={(e) => {
                  const file = e.target.files?.[0];
                  if (file) setTemplateFile(file);
                }}
              />
              <button
                type="button"
                onClick={() => document.getElementById('template-file-input')?.click()}
                className="role-filter-chip"
                style={{ padding: '12px 20px', cursor: 'pointer', height: 'auto', display: 'flex', alignItems: 'center', gap: '8px' }}
              >
                Choose File
              </button>
              <span style={{ fontSize: '13px', color: templateFile ? 'rgb(22, 192, 122)' : 'var(--text-muted)' }}>
                {templateFile ? templateFile.name : 'No file chosen'}
              </span>
            </div>
          </div>

          <div style={{ marginBottom: '16px' }}>
            <label className="form-input-label">Number of Days</label>
            <input
              type="number"
              min="1"
              value={numDays}
              onChange={(e) => setNumDays(e.target.value)}
              className="form-date-picker"
              placeholder="e.g. 1"
            />
          </div>

          {/* Allowed Roles Checkboxes */}
          <div style={{ marginBottom: '20px' }}>
            <label className="form-input-label">Allowed Roles</label>
            <div className="roles-chips-grid">
              {allowedRolesList.map((role) => {
                const isSelected = selectedRoles.includes(role);
                return (
                  <button
                    key={role}
                    type="button"
                    onClick={() => handleRoleToggle(role)}
                    className={`role-filter-chip ${isSelected ? 'active' : ''}`}
                  >
                    {role.replace('_', ' ')}
                  </button>
                );
              })}
            </div>
          </div>

          {/* Is Paid Switch */}
          <div className="form-switch-row">
            <span className="switch-row-label">Is Paid Event?</span>
            <label className="switch-input-container">
              <input 
                type="checkbox" 
                checked={isPaid}
                onChange={(e) => setIsPaid(e.target.checked)}
              />
              <span className="switch-slider"></span>
            </label>
          </div>

          {isPaid && (
            <div className="form-row-split animate-slide">
              <CustomTextField
                label="Member Price (₹)"
                value={memberPrice}
                onChange={setMemberPrice}
                type="number"
              />
              <CustomTextField
                label="Non-Member Price (₹)"
                value={nonMemberPrice}
                onChange={setNonMemberPrice}
                type="number"
              />
            </div>
          )}

          <div style={{ marginTop: '24px' }}>
            <PrimaryButton
              text="Create Event"
              type="submit"
              isLoading={isLoading}
              disabled={!title.trim()}
              icon={Sparkles}
            />
          </div>
        </GlassCard>
      </form>

      <NavBar />

      <style>{`
        .event-form-container {
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

        .event-form {
          width: 100%;
        }

        .form-fields-card {
          width: 100%;
        }

        .image-uploader-block {
          width: 100%;
          height: 180px;
          border-radius: 14px;
          border: 1px dashed var(--border-light);
          background-color: rgba(255, 255, 255, 0.03);
          background-size: cover;
          background-position: center;
          margin-bottom: 20px;
          cursor: pointer;
          position: relative;
        }

        .uploader-label {
          font-size: 13px;
          color: var(--text-secondary);
          font-weight: 500;
        }

        .form-input-label {
          display: block;
          font-family: var(--font-space-grotesk);
          font-size: 13px;
          font-weight: 600;
          color: var(--text-secondary);
          margin-bottom: 8px;
        }

        .form-date-picker {
          width: 100%;
          padding: 14px;
          background: rgba(255, 255, 255, 0.04);
          border: 1px solid var(--border-light);
          border-radius: 14px;
          color: var(--text-primary);
          outline: none;
        }

        .roles-chips-grid {
          display: flex;
          flex-wrap: wrap;
          gap: 8px;
        }

        .role-filter-chip {
          padding: 6px 12px;
          border-radius: 20px;
          background: rgba(255, 255, 255, 0.03);
          border: 1px solid var(--border-light);
          color: var(--text-secondary);
          font-size: 12px;
          text-transform: capitalize;
        }

        .role-filter-chip.active {
          background: rgba(22, 192, 122, 0.15);
          border-color: rgba(22, 192, 122, 0.3);
          color: rgb(22, 192, 122);
          font-weight: 700;
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
          font-weight: 600;
        }

        /* switch slider */
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

        .form-row-split {
          display: flex;
          gap: 12px;
        }

        .animate-slide {
          animation: slideUp 0.25s cubic-bezier(0.4, 0, 0.2, 1);
        }

        @keyframes slideUp {
          from { transform: translateY(10px); opacity: 0; }
          to { transform: translateY(0); opacity: 1; }
        }
      `}</style>
    </div>
  );
};
