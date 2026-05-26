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

// Timeout only for session init — prevents indefinite hang when offline/no session
const getSessionWithTimeout = async (ms: number) => {
  const sessionPromise = supabase.auth.getSession();
  const timeout = new Promise<null>((resolve) => setTimeout(() => resolve(null), ms));
  const result = await Promise.race([sessionPromise, timeout]);
  if (result === null) return { data: { session: null } };
  return result as Awaited<ReturnType<typeof supabase.auth.getSession>>;
};

export const AuthProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [authUser, setAuthUser] = useState<User | null>(null);
  const [currentUser, setCurrentUser] = useState<UserModel | null>(null);
  const [folderMemberships, setFolderMemberships] = useState<FolderMemberModel[]>([]);
  const [folderPermissions, setFolderPermissions] = useState<Record<number, FolderPermissionModel[]>>({});
  const [permissions, setPermissions] = useState<PermissionEngine | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isShowingSplash, setIsShowingSplash] = useState(true);

  const hideSplash = useCallback(() => {
    setIsShowingSplash(false);
  }, []);

  // Load the real user profile + memberships + permissions from DB
  const loadUserData = useCallback(async (user: User | null) => {
    if (!user) {
      setCurrentUser(null);
      setFolderMemberships([]);
      setFolderPermissions({});
      setPermissions(null);
      setIsLoading(false);
      return;
    }

    try {
      // 1. Fetch user profile from DB — always real data
      const { data: userData, error: userError } = await supabase
        .from('users')
        .select()
        .eq('id', user.id)
        .single();

      if (userError || !userData) {
        throw new Error(userError?.message || 'Profile not found.');
      }

      const parsedUser = userData as UserModel;
      setCurrentUser(parsedUser);

      // 2. Fetch folder memberships
      const { data: membershipsData } = await supabase
        .from('folder_members')
        .select('*, users:users(id, name, email, role, post)')
        .eq('user_id', user.id);

      const memberships = (membershipsData || []) as FolderMemberModel[];
      setFolderMemberships(memberships);

      // 3. Fetch folder permissions
      const folderIds = memberships.map((m) => m.folder_id);
      let permQuery = supabase.from('folder_permissions').select();

      if (folderIds.length > 0) {
        permQuery = permQuery.or(`folder_id.eq.0,folder_id.in.(${folderIds.join(',')})`);
      } else {
        permQuery = permQuery.eq('folder_id', 0);
      }

      const { data: permData } = await permQuery;
      const allPerms = (permData || []) as FolderPermissionModel[];

      const permissionsMap: Record<number, FolderPermissionModel[]> = {};
      allPerms.forEach((p) => {
        if (!permissionsMap[p.folder_id]) permissionsMap[p.folder_id] = [];
        permissionsMap[p.folder_id].push(p);
      });
      setFolderPermissions(permissionsMap);

      // 4. Build permission engine with real role data
      const engine = new PermissionEngine(parsedUser, memberships, permissionsMap);
      setPermissions(engine);
    } catch (e) {
      console.error('Error loading user data:', e);
      setCurrentUser(null);
      setPermissions(null);
    } finally {
      setIsLoading(false);
    }
  }, []);

  const refreshUserData = useCallback(async () => {
    if (authUser) {
      await loadUserData(authUser);
    }
  }, [authUser, loadUserData]);

  useEffect(() => {
    const initSession = async () => {
      try {
        // 3s timeout prevents indefinite hang when there's no network/session
        const { data: sessionData } = await getSessionWithTimeout(3000);
        const u = sessionData?.session?.user ?? null;

        if (u) {
          setAuthUser(u);
          await loadUserData(u);
        } else {
          // No active session — go to login
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

    // Listen for auth state changes (token refresh, sign out from another tab, etc.)
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

    return () => {
      subscription.unsubscribe();
    };
  }, [loadUserData]);

  const signIn = async (email: string, password: string) => {
    setIsLoading(true);
    const { data, error } = await supabase.auth.signInWithPassword({ email, password });
    if (error) {
      setIsLoading(false);
      throw error;
    }
    setAuthUser(data.user);
    await loadUserData(data.user);
  };

  const signOut = async () => {
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
        authUser,
        currentUser,
        folderMemberships,
        folderPermissions,
        permissions,
        isLoading,
        isShowingSplash,
        isAuthenticated,
        hideSplash,
        signIn,
        signOut,
        refreshUserData,
      }}
    >
      {children}
    </AuthContext.Provider>
  );
};

export const useAuth = () => {
  const context = useContext(AuthContext);
  if (context === undefined) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
};
