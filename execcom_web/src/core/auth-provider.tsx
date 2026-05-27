import React, { createContext, useContext, useState, useEffect, useCallback } from 'react';
import { User } from '@supabase/supabase-js';
import { supabase } from './supabase-client';
import { UserModel, ExecomMemberModel, ExecomPermissionModel } from '../models/types';
import { PermissionEngine } from './permission-engine';

interface AuthContextType {
  authUser: User | null;
  currentUser: UserModel | null;
  execomMemberships: ExecomMemberModel[];
  execomPermissions: Record<number, ExecomPermissionModel[]>;
  permissions: PermissionEngine | null;
  isLoading: boolean;
  isShowingSplash: boolean;
  isAuthenticated: boolean;
  hideSplash: () => void;
  signIn: (email: string, password: string) => Promise<void>;
  signOut: () => Promise<void>;
  refreshUserData: () => Promise<void>;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

// ─── LocalStorage cache helpers ───────────────────────────────────────────────
const CACHE_KEY = (uid: string) => `lynq_user_cache_${uid}`;

interface UserCache {
  user: UserModel;
  memberships: ExecomMemberModel[];
  permissionsMap: Record<number, ExecomPermissionModel[]>;
  cachedAt: number;
}

function readCache(uid: string): UserCache | null {
  try {
    const raw = localStorage.getItem(CACHE_KEY(uid));
    if (!raw) return null;
    const parsed: UserCache = JSON.parse(raw);
    // Cache valid for 5 minutes
    if (Date.now() - parsed.cachedAt > 5 * 60 * 1000) return null;
    return parsed;
  } catch { return null; }
}

function writeCache(uid: string, data: Omit<UserCache, 'cachedAt'>) {
  try {
    localStorage.setItem(CACHE_KEY(uid), JSON.stringify({ ...data, cachedAt: Date.now() }));
  } catch { /* quota errors — ignore */ }
}

function clearCache(uid: string) {
  try { localStorage.removeItem(CACHE_KEY(uid)); } catch { /* ignore */ }
}

// ─── Session init with timeout ─────────────────────────────────────────────────
const getSessionWithTimeout = async (ms: number) => {
  const sessionPromise = supabase.auth.getSession();
  const timeout = new Promise<null>((resolve) => setTimeout(() => resolve(null), ms));
  const result = await Promise.race([sessionPromise, timeout]);
  if (result === null) return { data: { session: null } };
  return result as Awaited<ReturnType<typeof supabase.auth.getSession>>;
};

// ─── Build permissions map ─────────────────────────────────────────────────────
function buildPermissionsMap(perms: ExecomPermissionModel[]): Record<number, ExecomPermissionModel[]> {
  const map: Record<number, ExecomPermissionModel[]> = {};
  perms.forEach((p) => {
    if (!map[p.execom_id]) map[p.execom_id] = [];
    map[p.execom_id].push(p);
  });
  return map;
}

// ─── Provider ─────────────────────────────────────────────────────────────────
export const AuthProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [authUser, setAuthUser] = useState<User | null>(null);
  const [currentUser, setCurrentUser] = useState<UserModel | null>(null);
  const [execomMemberships, setExecomMemberships] = useState<ExecomMemberModel[]>([]);
  const [execomPermissions, setExecomPermissions] = useState<Record<number, ExecomPermissionModel[]>>({});
  const [permissions, setPermissions] = useState<PermissionEngine | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isShowingSplash, setIsShowingSplash] = useState(true);

  const hideSplash = useCallback(() => setIsShowingSplash(false), []);

  // Apply a fully loaded user state in one batch
  const applyUserState = useCallback((
    parsedUser: UserModel,
    memberships: ExecomMemberModel[],
    permissionsMap: Record<number, ExecomPermissionModel[]>
  ) => {
    setCurrentUser(parsedUser);
    setExecomMemberships(memberships);
    setExecomPermissions(permissionsMap);
    setPermissions(new PermissionEngine(parsedUser, memberships, permissionsMap));
  }, []);

  const loadUserData = useCallback(async (user: User | null, skipCache = false) => {
    if (!user) {
      setCurrentUser(null);
      setExecomMemberships([]);
      setExecomPermissions({});
      setPermissions(null);
      setIsLoading(false);
      return;
    }

    // ── Step 1: Serve from cache instantly (while fetching fresh in background)
    if (!skipCache) {
      const cached = readCache(user.id);
      if (cached) {
        applyUserState(cached.user, cached.memberships, cached.permissionsMap);
        setIsLoading(false);
        // Background refresh — don't await
        loadUserData(user, true).catch(console.error);
        return;
      }
    }

    try {
      // ── Step 2: Fetch profile + memberships IN PARALLEL (saves ~150ms)
      const [profileRes, membershipsRes] = await Promise.all([
        supabase.from('users').select().eq('id', user.id).single(),
        supabase.from('execom_members')
          .select('*, users:users(id, name, email, role, post)')
          .eq('user_id', user.id),
      ]);

      if (profileRes.error || !profileRes.data) {
        throw new Error(profileRes.error?.message || 'Profile not found.');
      }

      const parsedUser = profileRes.data as UserModel;
      const memberships = (membershipsRes.data || []) as ExecomMemberModel[];

      // ── Step 3: Fetch permissions (needs execom IDs from memberships)
      const execomIds = memberships.map((m) => m.execom_id);
      let permQuery = supabase.from('execom_permissions').select();
      if (execomIds.length > 0) {
        permQuery = permQuery.or(`execom_id.eq.0,execom_id.in.(${execomIds.join(',')})`);
      } else {
        permQuery = permQuery.eq('execom_id', 0);
      }
      const { data: permData } = await permQuery;
      const permissionsMap = buildPermissionsMap((permData || []) as ExecomPermissionModel[]);

      // ── Step 4: Apply state + write cache
      applyUserState(parsedUser, memberships, permissionsMap);
      writeCache(user.id, { user: parsedUser, memberships, permissionsMap });

    } catch (e) {
      console.error('Error loading user data:', e);
      if (!skipCache) {
        // On failure, try serving stale cache rather than showing nothing
        const stale = readCache(user.id);
        if (stale) applyUserState(stale.user, stale.memberships, stale.permissionsMap);
        else { setCurrentUser(null); setPermissions(null); }
      }
    } finally {
      setIsLoading(false);
    }
  }, [applyUserState]);

  const refreshUserData = useCallback(async () => {
    if (authUser) await loadUserData(authUser, true); // force bypass cache
  }, [authUser, loadUserData]);

  useEffect(() => {
    const initSession = async () => {
      try {
        const { data: sessionData } = await getSessionWithTimeout(3000);
        const u = sessionData?.session?.user ?? null;
        if (u) {
          setAuthUser(u);
          await loadUserData(u);
        } else {
          setAuthUser(null);
          setIsLoading(false);
        }
      } catch (err) {
        console.error('Session initialization failed:', err);
        setAuthUser(null);
        setIsLoading(false);
      }
    };

    initSession();

    const { data: { subscription } } = supabase.auth.onAuthStateChange(async (_event, session) => {
      const newUser = session?.user ?? null;
      if (newUser) {
        setAuthUser(newUser);
        await loadUserData(newUser);
      } else {
        setAuthUser(null);
        setCurrentUser(null);
        setPermissions(null);
        setIsLoading(false);
      }
    });

    return () => subscription.unsubscribe();
  }, [loadUserData]);

  const signIn = async (email: string, password: string) => {
    setIsLoading(true);
    const { data, error } = await supabase.auth.signInWithPassword({ email, password });
    if (error) { setIsLoading(false); throw error; }
    setAuthUser(data.user);
    await loadUserData(data.user, true); // fresh load on sign-in — no stale cache
  };

  const signOut = async () => {
    if (authUser) clearCache(authUser.id);
    setIsLoading(true);
    await supabase.auth.signOut();
    setAuthUser(null);
    setCurrentUser(null);
    setExecomMemberships([]);
    setExecomPermissions({});
    setPermissions(null);
    setIsLoading(false);
  };

  const isAuthenticated = authUser !== null && currentUser !== null;

  return (
    <AuthContext.Provider
      value={{
        authUser, currentUser, execomMemberships, execomPermissions,
        permissions, isLoading, isShowingSplash, isAuthenticated,
        hideSplash, signIn, signOut, refreshUserData,
      }}
    >
      {children}
    </AuthContext.Provider>
  );
};

export const useAuth = () => {
  const context = useContext(AuthContext);
  if (context === undefined) throw new Error('useAuth must be used within an AuthProvider');
  return context;
};
