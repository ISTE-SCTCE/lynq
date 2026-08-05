import { useState } from 'react';
import { useAuth } from '../contexts/AuthContext';
import { supabase } from '../lib/supabase';
import DashboardLayout from '../components/DashboardLayout';
import { User, Mail, Phone, Hash, Book, GraduationCap, Calendar, Shield, Award, Edit2, CheckCircle, AlertCircle } from 'lucide-react';

const inputStyle = {
  width: '100%', padding: '12px 14px 12px 42px', background: '#fff', border: '1.5px solid #D3E3F0',
  borderRadius: 14, fontSize: 14, fontFamily: "'Inter',sans-serif", outline: 'none', color: '#111', transition: 'border-color 0.2s',
};

export default function ProfilePage() {
  const { user, profile, name, membershipId, validityEnd, isMembershipValid, daysUntilExpiry, refresh } = useAuth();
  const [editing, setEditing] = useState(false);
  const [formName, setFormName] = useState(profile?.name || '');
  const [formPhone, setFormPhone] = useState(profile?.phone || '');
  const [formRoll, setFormRoll] = useState(profile?.roll_number || '');
  const [formBranch, setFormBranch] = useState(profile?.branch || profile?.department || '');
  const [formYear, setFormYear] = useState(profile?.year?.toString() || '');
  const [isSaving, setIsSaving] = useState(false);
  const [saveMsg, setSaveMsg] = useState('');
  const [saveError, setSaveError] = useState('');

  const avatarUrl = name ? `https://api.dicebear.com/7.x/notionists/png?seed=${encodeURIComponent(name)}` : null;

  const startEdit = () => {
    setFormName(profile?.name || '');
    setFormPhone(profile?.phone || '');
    setFormRoll(profile?.roll_number || '');
    setFormBranch(profile?.branch || profile?.department || '');
    setFormYear(profile?.year?.toString() || '');
    setEditing(true);
    setSaveMsg(''); setSaveError('');
  };

  const handleSave = async () => {
    setSaveMsg(''); setSaveError('');
    setIsSaving(true);
    try {
      // Update users table
      await supabase.from('users').update({ name: formName, phone: formPhone, roll_number: formRoll, branch: formBranch, year: formYear ? parseInt(formYear) : null }).eq('id', user.id);
      // Update members table
      await supabase.from('members').upsert({ user_id: user.id, name: formName, phone: formPhone, roll_number: formRoll, branch: formBranch }, { onConflict: 'user_id' });
      setSaveMsg('Profile updated successfully!');
      setEditing(false);
      refresh();
    } catch (err) {
      setSaveError(err.message || 'Failed to save.');
    } finally {
      setIsSaving(false);
    }
  };

  const infoRows = [
    { icon: <User size={16} />, label: 'Full Name', value: profile?.name },
    { icon: <Mail size={16} />, label: 'Email', value: user?.email },
    { icon: <Hash size={16} />, label: 'ISTE ID', value: profile?.iste_id || profile?.membership_id || '-' },
    { icon: <Phone size={16} />, label: 'Phone', value: profile?.phone },
    { icon: <Hash size={16} />, label: 'Roll Number', value: profile?.roll_number },
    { icon: <Book size={16} />, label: 'Branch', value: profile?.branch || profile?.department },
    { icon: <Calendar size={16} />, label: 'Year', value: profile?.year },
    { icon: <GraduationCap size={16} />, label: 'Membership', value: profile?.plan || profile?.plan_type || profile?.membership_type || 'Annual' },
    { icon: <Shield size={16} />, label: 'Forum', value: profile?.forum_name || profile?.forum },
  ];

  const validityStr = validityEnd ? validityEnd.toLocaleDateString('en-IN', { day: 'numeric', month: 'long', year: 'numeric' }) : null;

  return (
    <DashboardLayout>
      <div style={{ maxWidth: 680, margin: '0 auto', padding: '32px 24px', background: '#141414', minHeight: '100vh' }}>
        {/* Membership card */}
        <div style={{ background: 'linear-gradient(135deg,#1a1a2e 0%,#16213e 50%,#0f3460 100%)', borderRadius: 24, padding: '28px', marginBottom: 24, position: 'relative', overflow: 'hidden', boxShadow: '0 8px 32px rgba(0,0,0,0.4)' }}>
          {/* Subtle glow */}
          <div style={{ position: 'absolute', top: -40, right: -40, width: 180, height: 180, borderRadius: '50%', background: 'rgba(95,133,162,0.2)', filter: 'blur(40px)', pointerEvents: 'none' }} />

          <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', marginBottom: 24 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
              <GraduationCap size={20} color="rgba(255,255,255,0.7)" />
              <span style={{ fontFamily: "'Space Grotesk',sans-serif", fontSize: 13, color: 'rgba(255,255,255,0.7)', fontWeight: 600, letterSpacing: 1 }}>ISTE STUDENT CHAPTER</span>
            </div>
            <span style={{ fontFamily: "'Space Grotesk',sans-serif", fontSize: 11, fontWeight: 700, padding: '4px 10px', borderRadius: 20, border: `1.5px solid ${isMembershipValid ? '#48BB78' : '#E53E3E'}`, color: isMembershipValid ? '#48BB78' : '#E53E3E', letterSpacing: 1 }}>
              {isMembershipValid ? 'ACTIVE' : 'EXPIRED'}
            </span>
          </div>

          {/* Avatar */}
          {avatarUrl ? (
            <img src={avatarUrl} alt="avatar" style={{ width: 56, height: 56, borderRadius: '50%', border: '2.5px solid rgba(255,255,255,0.2)', marginBottom: 14 }} />
          ) : (
            <div style={{ width: 56, height: 56, borderRadius: '50%', background: 'rgba(255,255,255,0.1)', display: 'flex', alignItems: 'center', justifyContent: 'center', marginBottom: 14 }}>
              <User size={28} color="rgba(255,255,255,0.6)" />
            </div>
          )}

          <div style={{ fontFamily: "'Space Grotesk',sans-serif", fontSize: 22, fontWeight: 700, color: '#EAE0CC', letterSpacing: 1.5, textTransform: 'uppercase', marginBottom: 12 }}>{name || 'Member'}</div>

          <div style={{ display: 'flex', alignItems: 'center', gap: 16, flexWrap: 'wrap' }}>
            <div>
              <div style={{ fontFamily: "'Inter',sans-serif", fontSize: 10, color: 'rgba(255,255,255,0.4)', fontWeight: 700, letterSpacing: 1 }}>MEMBER ID</div>
              <div style={{ fontFamily: "'Space Grotesk',sans-serif", fontSize: 18, fontWeight: 700, color: '#D97D55', marginTop: 2 }}>{membershipId || '—'}</div>
            </div>
            {validityStr && (
              <div style={{ marginLeft: 'auto' }}>
                <div style={{ fontFamily: "'Inter',sans-serif", fontSize: 10, color: 'rgba(255,255,255,0.4)', fontWeight: 700, letterSpacing: 1 }}>VALID UNTIL</div>
                <div style={{ fontFamily: "'Space Grotesk',sans-serif", fontSize: 14, fontWeight: 600, color: daysUntilExpiry !== null && daysUntilExpiry <= 30 ? '#E53E3E' : 'rgba(255,255,255,0.8)', marginTop: 2 }}>{validityStr}</div>
              </div>
            )}
          </div>
        </div>

        {/* Member details card */}
        <div style={{ background: '#1A1A1A', borderRadius: 24, border: '1.5px solid rgba(255,255,255,0.07)', padding: '24px', marginBottom: 24 }}>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 20 }}>
            <h2 style={{ fontFamily: "'Space Grotesk',sans-serif", fontSize: 17, fontWeight: 700, color: '#fff' }}>Member Details</h2>
            {!editing && (
              <button onClick={startEdit} style={{ display: 'flex', alignItems: 'center', gap: 6, padding: '8px 14px', background: 'rgba(58,175,169,0.15)', border: '1px solid rgba(58,175,169,0.3)', color: '#3AAFA9', borderRadius: 12, cursor: 'pointer', fontFamily: "'Inter',sans-serif", fontSize: 13, fontWeight: 600 }}>
                <Edit2 size={14} /> Edit
              </button>
            )}
          </div>

          {editing ? (
            /* Edit form */
            <div>
              {saveError && (
                <div style={{ display: 'flex', gap: 8, background: 'rgba(229,62,62,0.1)', border: '1px solid rgba(229,62,62,0.3)', borderRadius: 12, padding: '10px 14px', marginBottom: 16 }}>
                  <AlertCircle size={16} color="#E53E3E" />
                  <span style={{ fontFamily: "'Inter',sans-serif", fontSize: 13, color: '#E53E3E' }}>{saveError}</span>
                </div>
              )}
              {[
                { label: 'Full Name', icon: <User size={15} color="#5F85A2" />, value: formName, set: setFormName, ph: 'Your full name' },
                { label: 'Phone Number', icon: <Phone size={15} color="#5F85A2" />, value: formPhone, set: setFormPhone, ph: '+91 9876543210' },
                { label: 'Roll Number', icon: <Hash size={15} color="#5F85A2" />, value: formRoll, set: setFormRoll, ph: 'University roll number' },
                { label: 'Branch', icon: <Book size={15} color="#5F85A2" />, value: formBranch, set: setFormBranch, ph: 'e.g. Computer Science' },
                { label: 'Year', icon: <Calendar size={15} color="#5F85A2" />, value: formYear, set: setFormYear, ph: 'e.g. 2' },
              ].map(f => (
                <div key={f.label} style={{ marginBottom: 14 }}>
                  <label style={{ fontFamily: "'Inter',sans-serif", fontSize: 12, fontWeight: 600, color: 'rgba(255,255,255,0.4)', marginBottom: 6, display: 'block' }}>{f.label}</label>
                  <div style={{ position: 'relative' }}>
                    <span style={{ position: 'absolute', left: 14, top: '50%', transform: 'translateY(-50%)' }}>{f.icon}</span>
                    <input style={{ ...inputStyle, background: '#111', color: '#fff', borderColor: 'rgba(255,255,255,0.1)' }} value={f.value} onChange={e => f.set(e.target.value)} placeholder={f.ph} />
                  </div>
                </div>
              ))}
              <div style={{ display: 'flex', gap: 10, marginTop: 20 }}>
                <button onClick={handleSave} disabled={isSaving} style={{ flex: 1, padding: '12px', background: '#3AAFA9', color: '#fff', border: 'none', borderRadius: 20, fontFamily: "'Space Grotesk',sans-serif", fontWeight: 700, fontSize: 15, cursor: 'pointer' }}>
                  {isSaving ? 'Saving...' : 'Save Changes'}
                </button>
                <button onClick={() => setEditing(false)} style={{ flex: 1, padding: '12px', background: 'rgba(255,255,255,0.06)', color: 'rgba(255,255,255,0.6)', border: '1px solid rgba(255,255,255,0.1)', borderRadius: 20, fontFamily: "'Space Grotesk',sans-serif", fontWeight: 600, fontSize: 15, cursor: 'pointer' }}>
                  Cancel
                </button>
              </div>
            </div>
          ) : (
            /* Display mode */
            <div style={{ display: 'flex', flexDirection: 'column', gap: 0 }}>
              {saveMsg && (
                <div style={{ display: 'flex', gap: 8, background: 'rgba(72,187,120,0.1)', border: '1px solid rgba(72,187,120,0.3)', borderRadius: 12, padding: '10px 14px', marginBottom: 16 }}>
                  <CheckCircle size={16} color="#48BB78" />
                  <span style={{ fontFamily: "'Inter',sans-serif", fontSize: 13, color: '#48BB78' }}>{saveMsg}</span>
                </div>
              )}
              {infoRows.map((row, i) => row.value && (
                <div key={row.label} style={{ display: 'flex', alignItems: 'center', padding: '14px 0', borderBottom: i < infoRows.length - 1 ? '1px solid rgba(255,255,255,0.06)' : 'none', gap: 14 }}>
                  <div style={{ color: '#5F85A2', flexShrink: 0 }}>{row.icon}</div>
                  <div style={{ flex: 1 }}>
                    <div style={{ fontFamily: "'Inter',sans-serif", fontSize: 11, color: 'rgba(255,255,255,0.35)', fontWeight: 600, marginBottom: 2 }}>{row.label.toUpperCase()}</div>
                    <div style={{ fontFamily: "'Inter',sans-serif", fontSize: 14, color: '#EAE0CC', fontWeight: 500 }}>{row.value}</div>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
    </DashboardLayout>
  );
}
