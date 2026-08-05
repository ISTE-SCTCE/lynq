import { createContext, useContext, useState, useEffect } from 'react';
import { supabase } from '../lib/supabase';

const AuthContext = createContext(null);

export function AuthProvider({ children }) {
  const [user, setUser] = useState(null);
  const [profile, setProfile] = useState(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState(null);

  const loadProfile = async (authUser) => {
    if (!authUser) { setProfile(null); setIsLoading(false); return; }
    try {
      const [usersRes, membersRes, notIsteRes] = await Promise.all([
        supabase.from('users').select('id,email,name,phone,role,roll_number,branch,year,forum').eq('id', authUser.id).maybeSingle(),
        supabase.from('members').select('id,user_id,name,email,phone,iste_id,role,status,plan,plan_type,joined_date,expiry_date,membership_expiry,department,forum,forum_name').eq('user_id', authUser.id).maybeSingle(),
        supabase.from('members_not_iste').select('id,name,email,phone,roll_number,college').eq('id', authUser.id).maybeSingle(),
      ]);
      const userClean = usersRes.data || {};
      const memberClean = membersRes.data || {};
      const notIsteClean = notIsteRes.data || {};
      const merged = { ...userClean, ...memberClean, ...notIsteClean };
      merged.membership_id = merged.iste_id || '';
      merged.validity_end = merged.validity_end || merged.expiry_date || merged.membership_expiry || null;
      setProfile(merged);
    } catch (err) {
      setError(err.message);
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    supabase.auth.getSession().then(({ data: { session } }) => {
      setUser(session?.user ?? null);
      loadProfile(session?.user ?? null);
    });
    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, session) => {
      const newUser = session?.user ?? null;
      setUser(newUser);
      setIsLoading(true);
      loadProfile(newUser);
    });
    return () => subscription.unsubscribe();
  }, []);

  const refresh = () => { setIsLoading(true); loadProfile(user); };

  const signOut = async () => {
    await supabase.auth.signOut();
    setUser(null);
    setProfile(null);
  };

  const isAuthenticated = !!(user && profile);
  const name = profile?.name || '';
  const role = profile?.role || 'user';
  const membershipId = profile?.membership_id || '';
  const validityEnd = profile?.validity_end ? new Date(profile.validity_end) : null;
  const isMembershipValid = !!membershipId;
  const daysUntilExpiry = validityEnd ? Math.ceil((validityEnd - new Date()) / (1000 * 60 * 60 * 24)) : null;

  const value = {
    user, profile, isLoading, error, isAuthenticated,
    name, role, membershipId, validityEnd, isMembershipValid, daysUntilExpiry,
    refresh, signOut,
  };

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used within AuthProvider');
  return ctx;
}
