import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { supabase } from '../lib/supabase';
import { GraduationCap, Mail, Lock, User, Phone, Hash, Building, AlertCircle, CheckCircle, ArrowLeft, Eye, EyeOff } from 'lucide-react';
import { ISTE_MEMBER_EMAILS } from '../lib/memberEmails';

const STEP = {
  EMAIL: 'emailEntry',
  ISTE_OTP: 'isteOtpVerify',
  ISTE_PWD_CREATE: 'istePasswordCreate',
  ISTE_LOGIN: 'isteLogin',
  GUEST_REG: 'guestRegistration',
  GUEST_OTP: 'guestOtpVerify',
};

const inputStyle = {
  width: '100%', padding: '13px 16px', background: '#fff', border: '1.5px solid #D3E3F0',
  borderRadius: 14, fontSize: 15, fontFamily: "'Inter',sans-serif", outline: 'none', color: '#111', transition: 'border-color 0.2s',
};

export default function LoginPage() {
  const navigate = useNavigate();
  const [step, setStep] = useState(STEP.EMAIL);
  const [email, setEmail] = useState('');
  const [otp, setOtp] = useState('');
  const [password, setPassword] = useState('');
  const [showPwd, setShowPwd] = useState(false);
  const [isteId, setIsteId] = useState('');
  const [guestName, setGuestName] = useState('');
  const [guestPhone, setGuestPhone] = useState('');
  const [guestRoll, setGuestRoll] = useState('');
  const [guestCollege, setGuestCollege] = useState('');
  const [memberData, setMemberData] = useState(null);
  // 'iste_member' | 'guest' | null — drives the tag shown on the OTP/login steps
  const [membershipTag, setMembershipTag] = useState(null);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState('');
  const [success, setSuccess] = useState('');

  const clearMessages = () => { setError(''); setSuccess(''); };

  // Step 1: Check email
  const handleEmailContinue = async () => {
    clearMessages();
    const trimmedEmail = email.trim().toLowerCase();
    if (!trimmedEmail) return setError('Please enter your email address.');
    setIsLoading(true);
    console.log('[Auth Debug] Checking email:', trimmedEmail);
    try {
      // Check if they are in the static list of ISTE Members
      const isIsteMember = ISTE_MEMBER_EMAILS.has(trimmedEmail);
      console.log('[Auth Debug] isIsteMember check:', isIsteMember);

      if (isIsteMember) {
        setMembershipTag('iste_member');
        console.log('[Auth Debug] ISTE member, sending OTP and routing to ISTE_OTP');
        await supabase.auth.signInWithOtp({ email: trimmedEmail, options: { shouldCreateUser: true } });
        setSuccess('OTP sent to your email!');
        setStep(STEP.ISTE_OTP);
        return;
      }

      // Guest flow — check if they exist in auth
      console.log('[Auth Debug] Checking guest existence in Supabase Auth...');
      const { error: authErr } = await supabase.auth.signInWithOtp({
        email: trimmedEmail,
        options: { shouldCreateUser: false }
      });

      if (!authErr) {
        // Existing guest — go to OTP verify
        console.log('[Auth Debug] Existing guest user found, OTP sent, routing to GUEST_OTP');
        setMembershipTag('guest');
        setSuccess('OTP sent to your email!');
        setStep(STEP.GUEST_OTP);
        return;
      }

      console.log('[Auth Debug] Auth user does not exist (or error occurred):', authErr);

      // Truly new user — show guest registration form
      console.log('[Auth Debug] Routing to GUEST_REG');
      setMembershipTag('guest');
      setStep(STEP.GUEST_REG);
    } catch (err) {
      console.error('[Auth Debug] Error during check:', err);
      setError(err.message || 'Something went wrong.');
    } finally {
      setIsLoading(false);
    }
  };

  // Step: Verify ISTE OTP
  const handleIsteOtpVerify = async () => {
    clearMessages();
    if (otp.length < 8) return setError('Please enter the 8-digit OTP.');
    setIsLoading(true);
    try {
      const { data, error: otpErr } = await supabase.auth.verifyOtp({ email: email.trim(), token: otp, type: 'email' });
      if (otpErr) throw otpErr;
      
      const uid = data.user?.id;
      if (uid) {
        // Upsert default profile for the ISTE member to public users table
        await supabase.from('users').upsert({ 
          id: uid, 
          email: email.trim().toLowerCase(), 
          role: 'user' 
        }, { onConflict: 'id' });
      }

      setSuccess('Logged in successfully!');
      navigate('/home');
    } catch (err) {
      setError(err.message || 'Invalid OTP.');
    } finally {
      setIsLoading(false);
    }
  };

  // Step: Guest registration — send OTP
  const handleGuestRegister = async () => {
    clearMessages();
    if (!guestName.trim() || !guestPhone.trim() || !guestRoll.trim() || !guestCollege.trim()) return setError('Please fill in all fields.');
    setIsLoading(true);
    try {
      // Store pending data in sessionStorage
      sessionStorage.setItem('pending_signup', JSON.stringify({ name: guestName, phone: guestPhone, roll_number: guestRoll, college: guestCollege, email: email.trim() }));
      await supabase.auth.signInWithOtp({ email: email.trim(), options: { shouldCreateUser: true } });
      setSuccess('OTP sent to your email!');
      setStep(STEP.GUEST_OTP);
    } catch (err) {
      setError(err.message || 'Failed to send OTP.');
    } finally {
      setIsLoading(false);
    }
  };

  // Step: Verify guest OTP
  const handleGuestOtpVerify = async () => {
    clearMessages();
    if (otp.length < 8) return setError('Please enter the 8-digit OTP.');
    setIsLoading(true);
    try {
      const { data, error: otpErr } = await supabase.auth.verifyOtp({ email: email.trim(), token: otp, type: 'email' });
      if (otpErr) throw otpErr;
      const uid = data.user?.id;
      const pending = JSON.parse(sessionStorage.getItem('pending_signup') || '{}');
      if (uid && pending.name) {
        await supabase.from('users').upsert({ id: uid, email: email.trim(), name: pending.name, phone: pending.phone, role: 'user' }, { onConflict: 'id' });
        await supabase.from('members_not_iste').upsert({ id: uid, name: pending.name, email: email.trim(), phone: pending.phone, roll_number: pending.roll_number, college: pending.college }, { onConflict: 'id' });
        sessionStorage.removeItem('pending_signup');
      }
      navigate('/home');
    } catch (err) {
      setError(err.message || 'Invalid OTP.');
    } finally {
      setIsLoading(false);
    }
  };

  const renderStep = () => {
    switch (step) {
      case STEP.EMAIL: {
        const isEmailValid = email.includes('@') && email.includes('.');
        const isLiveMember = isEmailValid && ISTE_MEMBER_EMAILS.has(email.trim().toLowerCase());
        return (
          <>
            <label style={{ fontSize: 13, fontWeight: 600, color: '#5F85A2', marginBottom: 6, display: 'block' }}>Email Address</label>
            <div style={{ position: 'relative', marginBottom: 12 }}>
              <Mail size={18} style={{ position: 'absolute', left: 14, top: 14, color: '#5F85A2' }} />
              <input style={{ ...inputStyle, paddingLeft: 42 }} type="email" placeholder="your@email.com" value={email} onChange={e => setEmail(e.target.value)} onKeyDown={e => e.key === 'Enter' && handleEmailContinue()} autoFocus />
            </div>

            {/* Live member status indicator */}
            {isEmailValid && (
              <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 20 }} className="fade-in">
                <div style={{ width: 8, height: 8, borderRadius: '50%', background: isLiveMember ? '#38A169' : '#D97D55', boxShadow: `0 0 8px ${isLiveMember ? '#38A169' : '#D97D55'}` }} />
                <span style={{ fontFamily: "'Space Grotesk',sans-serif", fontSize: 12, fontWeight: 700, color: isLiveMember ? '#2F855A' : '#D97D55' }}>
                  {isLiveMember ? '✓ ISTE Member Account Detected' : 'Guest Account Detected'}
                </span>
              </div>
            )}

            <button onClick={handleEmailContinue} disabled={isLoading} style={btnStyle}>
              {isLoading ? 'Checking...' : 'Continue →'}
            </button>
          </>
        );
      }
      case STEP.ISTE_OTP:
      case STEP.GUEST_OTP: return (
        <>
          {/* Membership tag */}
          {membershipTag && (
            <div style={{ display: 'inline-flex', alignItems: 'center', gap: 6, marginBottom: 14, padding: '4px 12px', borderRadius: 20, background: membershipTag === 'iste_member' ? 'rgba(95,133,162,0.12)' : 'rgba(217,125,85,0.12)', border: `1px solid ${membershipTag === 'iste_member' ? 'rgba(95,133,162,0.35)' : 'rgba(217,125,85,0.35)'}` }}>
              <div style={{ width: 8, height: 8, borderRadius: '50%', background: membershipTag === 'iste_member' ? '#5F85A2' : '#D97D55' }} />
              <span style={{ fontFamily: "'Space Grotesk',sans-serif", fontSize: 12, fontWeight: 700, color: membershipTag === 'iste_member' ? '#5F85A2' : '#D97D55' }}>
                {membershipTag === 'iste_member' ? 'ISTE Member' : 'Guest'}
              </span>
            </div>
          )}
          <p style={{ fontSize: 14, color: '#5F85A2', marginBottom: 16, fontFamily: "'Inter',sans-serif" }}>We sent an 8-digit code to <strong>{email}</strong></p>
          <label style={{ fontSize: 13, fontWeight: 600, color: '#5F85A2', marginBottom: 6, display: 'block' }}>OTP Code</label>
          <input style={{ ...inputStyle, letterSpacing: 6, fontSize: 20, textAlign: 'center', marginBottom: 20 }} type="text" placeholder="••••••••" maxLength={8} value={otp} onChange={e => setOtp(e.target.value.replace(/\D/g, ''))} autoFocus />
          <button onClick={step === STEP.ISTE_OTP ? handleIsteOtpVerify : handleGuestOtpVerify} disabled={isLoading} style={btnStyle}>
            {isLoading ? 'Verifying...' : 'Verify OTP →'}
          </button>
        </>
      );
      case STEP.GUEST_REG: return (
        <>
          {[
            { label: 'Full Name', icon: <User size={18} />, value: guestName, set: setGuestName, ph: 'John Doe', type: 'text' },
            { label: 'Phone Number', icon: <Phone size={18} />, value: guestPhone, set: setGuestPhone, ph: '+91 9876543210', type: 'tel' },
            { label: 'University Roll Number', icon: <Hash size={18} />, value: guestRoll, set: setGuestRoll, ph: 'RA2011003010287', type: 'text' },
            { label: 'College Name', icon: <Building size={18} />, value: guestCollege, set: setGuestCollege, ph: 'SRM Institute of Science & Technology', type: 'text' },
          ].map(f => (
            <div key={f.label} style={{ marginBottom: 14 }}>
              <label style={{ fontSize: 13, fontWeight: 600, color: '#5F85A2', marginBottom: 6, display: 'block' }}>{f.label}</label>
              <div style={{ position: 'relative' }}>
                <span style={{ position: 'absolute', left: 14, top: 14, color: '#5F85A2' }}>{f.icon}</span>
                <input style={{ ...inputStyle, paddingLeft: 42 }} type={f.type} placeholder={f.ph} value={f.value} onChange={e => f.set(e.target.value)} />
              </div>
            </div>
          ))}
          <button onClick={handleGuestRegister} disabled={isLoading} style={{ ...btnStyle, marginTop: 8 }}>{isLoading ? 'Sending OTP...' : 'Register & Send OTP →'}</button>
        </>
      );
      default: return null;
    }
  };

  const stepTitles = {
    [STEP.EMAIL]: 'Sign In',
    [STEP.ISTE_OTP]: 'Verify Your Email',
    [STEP.GUEST_REG]: 'Guest Registration',
    [STEP.GUEST_OTP]: 'Verify OTP',
  };

  return (
    <div style={{ minHeight: '100vh', background: '#EBF3FC', display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '24px', position: 'relative', overflow: 'hidden' }}>
      {/* Background halos */}
      <div style={{ position: 'absolute', top: -100, right: -80, width: 400, height: 400, borderRadius: '50%', background: '#C5D9EB', opacity: 0.4, filter: 'blur(80px)', pointerEvents: 'none' }} />
      <div style={{ position: 'absolute', bottom: -100, left: -80, width: 350, height: 350, borderRadius: '50%', background: '#C5D9EB', opacity: 0.3, filter: 'blur(80px)', pointerEvents: 'none' }} />

      <div style={{ width: '100%', maxWidth: 420, position: 'relative' }} className="fade-in">
        {/* Logo */}
        <div style={{ textAlign: 'center', marginBottom: 36 }}>
          <div style={{ width: 56, height: 56, borderRadius: 18, background: '#111', display: 'flex', alignItems: 'center', justifyContent: 'center', margin: '0 auto 14px', boxShadow: '0 8px 32px rgba(0,0,0,0.15)' }}>
            <GraduationCap size={28} color="#D3E3F0" />
          </div>
          <h1 style={{ fontFamily: "'Space Grotesk',sans-serif", fontSize: 26, fontWeight: 700, color: '#111', letterSpacing: '-0.5px' }}>
            {stepTitles[step]}
          </h1>
          <p style={{ fontFamily: "'Inter',sans-serif", fontSize: 14, color: '#5F85A2', marginTop: 6 }}>
            {step === STEP.EMAIL ? 'ISTE Student Chapter Member Portal' : 'Continue with your account'}
          </p>
        </div>

        {/* Card */}
        <div style={{ background: '#fff', borderRadius: 24, padding: 32, boxShadow: '0 4px 40px rgba(95,133,162,0.12)', border: '1.5px solid rgba(95,133,162,0.12)' }}>
          {/* Error / Success */}
          {error && (
            <div style={{ display: 'flex', alignItems: 'flex-start', gap: 10, background: '#FFF0F0', border: '1px solid #FFD0D0', borderRadius: 12, padding: '12px 14px', marginBottom: 20 }}>
              <AlertCircle size={18} color="#E53E3E" style={{ flexShrink: 0, marginTop: 1 }} />
              <p style={{ fontFamily: "'Inter',sans-serif", fontSize: 13, color: '#C53030', lineHeight: 1.5 }}>{error}</p>
            </div>
          )}
          {success && (
            <div style={{ display: 'flex', alignItems: 'center', gap: 10, background: '#F0FFF4', border: '1px solid #9AE6B4', borderRadius: 12, padding: '12px 14px', marginBottom: 20 }}>
              <CheckCircle size={18} color="#38A169" />
              <p style={{ fontFamily: "'Inter',sans-serif", fontSize: 13, color: '#276749' }}>{success}</p>
            </div>
          )}

          {renderStep()}

          {/* Back button */}
          {step !== STEP.EMAIL && (
            <button onClick={() => { clearMessages(); setStep(STEP.EMAIL); setOtp(''); }} style={{ display: 'flex', alignItems: 'center', gap: 6, background: 'none', border: 'none', color: '#5F85A2', cursor: 'pointer', fontSize: 14, fontFamily: "'Inter',sans-serif", fontWeight: 500, marginTop: 20 }}>
              <ArrowLeft size={16} /> Back to email
            </button>
          )}
        </div>
      </div>
    </div>
  );
}

const btnStyle = {
  width: '100%', padding: '13px 20px', background: '#111', color: '#fff',
  border: 'none', borderRadius: 28, fontSize: 15, fontWeight: 600,
  fontFamily: "'Space Grotesk',sans-serif", cursor: 'pointer', transition: 'opacity 0.2s',
};
