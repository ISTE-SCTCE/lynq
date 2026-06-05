import React, { createContext, useContext, useState, useEffect, useCallback } from 'react';
import { User } from '@supabase/supabase-js';
import { supabase } from './supabase-client';
import { UserModel, FolderMemberModel, FolderPermissionModel } from '../models/types';
import { PermissionEngine } from './permission-engine';

interface AuthContextType {
  authUser: User | null;
  currentUser: UserModel | null;
  folderMemberships: FolderMemberModel[];
  folderPermissions: Record<number, FolderPermissionModel[]>;
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
  memberships: FolderMemberModel[];
  permissionsMap: Record<number, FolderPermissionModel[]>;
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
function buildPermissionsMap(perms: FolderPermissionModel[]): Record<number, FolderPermissionModel[]> {
  const map: Record<number, FolderPermissionModel[]> = {};
  perms.forEach((p) => {
    if (!map[p.folder_id]) map[p.folder_id] = [];
    map[p.folder_id].push(p);
  });
  return map;
}

// ─── Provider ─────────────────────────────────────────────────────────────────
export const AuthProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [authUser, setAuthUser] = useState<User | null>(null);
  const [currentUser, setCurrentUser] = useState<UserModel | null>(null);
  const [folderMemberships, setFolderMemberships] = useState<FolderMemberModel[]>([]);
  const [folderPermissions, setFolderPermissions] = useState<Record<number, FolderPermissionModel[]>>({});
  const [permissions, setPermissions] = useState<PermissionEngine | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isShowingSplash, setIsShowingSplash] = useState(false);

  const hideSplash = useCallback(() => setIsShowingSplash(false), []);

  // Apply a fully loaded user state in one batch
  const applyUserState = useCallback((
    parsedUser: UserModel,
    memberships: FolderMemberModel[],
    permissionsMap: Record<number, FolderPermissionModel[]>
  ) => {
    setCurrentUser(parsedUser);
    setFolderMemberships(memberships);
    setFolderPermissions(permissionsMap);
    setPermissions(new PermissionEngine(parsedUser, memberships, permissionsMap));
  }, []);

  const loadUserData = useCallback(async (user: User | null, skipCache = false) => {
    if (!user) {
      setCurrentUser(null);
      setFolderMemberships([]);
      setFolderPermissions({});
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
      const [profileRes, membershipsRes] = await Promise.all([
        supabase
          .from('users')
          .select('id, email, name, role, post, phone, roll_number, branch, forum, is_sudo')
          .eq('id', user.id)
          .single(),
        supabase.from('folder_members')
          .select('id, folder_id:execom_id, folder_role:execom_role, user_id, joined_at, users:users(id, name, email, role, post)')
          .eq('user_id', user.id),
      ]);

      if (profileRes.error || !profileRes.data) {
        throw new Error(profileRes.error?.message || 'Profile not found.');
      }

      const parsedUser = profileRes.data as UserModel;
      const memberships = (membershipsRes.data || []) as unknown as FolderMemberModel[];

      // ── Step 3: Fetch permissions (needs folder IDs from memberships)
      const folderIds = memberships.map((m) => m.folder_id);
      let permQuery = supabase.from('folder_permissions').select('id, folder_id:execom_id, feature, allowed');
      if (folderIds.length > 0) {
        permQuery = permQuery.or(`execom_id.eq.0,execom_id.in.(${folderIds.join(',')})`);
      } else {
        permQuery = permQuery.eq('execom_id', 0);
      }
      const { data: permData } = await permQuery;
      const permissionsMap = buildPermissionsMap((permData || []) as FolderPermissionModel[]);

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
    let initialLoadDone = false;

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
      } finally {
        initialLoadDone = true;
      }
    };

    initSession();

    // Only react to meaningful auth events — NOT TOKEN_REFRESHED or INITIAL_SESSION
    // which would cause a double loadUserData race condition.
    const { data: { subscription } } = supabase.auth.onAuthStateChange(async (event, session) => {
      // Skip events handled by initSession or that don't require a profile reload
      if (event === 'INITIAL_SESSION' || event === 'TOKEN_REFRESHED') return;

      const newUser = session?.user ?? null;
      if (newUser) {
        // For SIGNED_IN events from the listener (e.g. OAuth / magic link), only
        // reload if the initial load has already completed to avoid races.
        if (!initialLoadDone) return;
        setAuthUser(newUser);
        await loadUserData(newUser, true);
      } else {
        setAuthUser(null);
        setCurrentUser(null);
        setFolderMemberships([]);
        setFolderPermissions({});
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
    // Ensure splash is dismissed after a successful manual sign-in
    setIsShowingSplash(false);
  };

  const signOut = async () => {
    if (authUser) clearCache(authUser.id);
    setIsLoading(true);
    await supabase.auth.signOut();
    setAuthUser(null);
    setCurrentUser(null);
    setFolderMemberships([]);
    setFolderPermissions({});
    setPermissions(null);
    setIsLoading(false);
  };

  const isAuthenticated = authUser !== null && currentUser !== null;

  return (
    <AuthContext.Provider
      value={{
        authUser, currentUser, folderMemberships, folderPermissions,
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
