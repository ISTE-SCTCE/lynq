import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_model.dart';
import '../models/folder_model.dart';
import 'app_cache.dart';
import 'constants.dart';
import 'permission_engine.dart';

class AuthProvider extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;

  User? _authUser;
  UserModel? _currentUser;
  List<FolderMemberModel> _folderMemberships = [];
  Map<int, List<FolderPermissionModel>> _folderPermissions = {};
  PermissionEngine? _permissionEngine;
  bool _isLoading = true;
  bool _isShowingSplash = true;
  Future<void>? _pendingLoad;
  String? _loadingUserId;
  int _generation = 0;
  bool _disposed = false;
  StreamSubscription<AuthState>? _authSubscription;
  String? _error;
  String? get error => _error;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool get isLoading => _isLoading;
  User? get authUser => _authUser;
  UserModel? get currentUser => _currentUser;
  PermissionEngine? get permissions => _permissionEngine;
  // Only backend-provisioned roles determine access, never free-text titles.
  AppRole get role => AppRole.fromString(_currentUser?.role ?? 'restricted');
  bool get isShowingSplash => _isShowingSplash;
  bool get isAuthenticated => _authUser != null && _currentUser != null;

  void hideSplash() {
    _isShowingSplash = false;
    _notify();
  }

  AuthProvider() {
    _initAuth();
  }

  void _initAuth() {
    // Check if already has a session
    final session = _supabase.auth.currentSession;
    if (session != null) {
      _authUser = session.user;
      unawaited(_loadUserData().catchError((Object _) {}));
    } else {
      _isLoading = false;
      _notify();
    }

    // Listen for auth state changes
    _authSubscription = _supabase.auth.onAuthStateChange.listen(
      (data) {
        final newUser = data.session?.user;

        if (newUser == null) {
          _generation++;
          _pendingLoad = null;
          _loadingUserId = null;
          _authUser = null;
          _currentUser = null;
          _folderMemberships = [];
          _folderPermissions = {};
          _permissionEngine = null;
          _isLoading = false;
          AppCache().invalidateAll();
          _notify();
          return;
        }

        _authUser = newUser;
        // Refresh server-owned access on token refresh as well as sign-in.
        unawaited(_loadUserData().catchError((Object _) {}));
      },
      onError: (Object _) {
        _generation++;
        _pendingLoad = null;
        _loadingUserId = null;
        _authUser = null;
        _currentUser = null;
        _permissionEngine = null;
        _isLoading = false;
        AppCache().invalidateAll();
        _error = 'Your session could not be refreshed. Please sign in again.';
        _notify();
      },
    );
  }

  Future<void> _loadUserData() {
    final userId = _authUser?.id;
    if (userId == null) return Future<void>.value();
    if (_pendingLoad != null && _loadingUserId == userId) return _pendingLoad!;
    final generation = ++_generation;
    _loadingUserId = userId;
    _isLoading = true;
    _currentUser = null;
    _permissionEngine = null;
    _error = null;
    AppCache().invalidateAll();
    _pendingLoad = _fetchUserData(userId, generation);
    return _pendingLoad!;
  }

  Future<void> _fetchUserData(String userId, int generation) async {
    bool isCurrent() =>
        !_disposed && generation == _generation && _authUser?.id == userId;
    try {
      // Fetch the exact authenticated identity; provisioning is server-owned.
      Map<String, dynamic>? userData = await _supabase
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle()
          .timeout(const Duration(seconds: 15));

      // Never adopt another profile by email or create an Execom account here.
      if (userData == null) {
        throw const AuthException(
          'Your account has no linked profile. Please contact an administrator.',
        );
      }
      final profile = UserModel.fromJson(userData);
      if (userData['status'] != 'active' ||
          (profile.suspendedUntil?.isAfter(DateTime.now()) ?? false)) {
        throw const AuthException(
          'Your account is not active. Please contact an administrator.',
        );
      }
      if (AppRole.fromString(profile.role) == AppRole.restricted) {
        throw const AuthException(
          'Your account does not have approved Lynq access.',
        );
      }
      if (!isCurrent()) return;
      // Data is assigned only once all access queries succeed.
      List<FolderMemberModel> memberships = [];
      final folderPermissions = <int, List<FolderPermissionModel>>{};

      // Fail closed if access data cannot be loaded; do not invent permissions.
      try {
        final membershipData = await _supabase
            .from('folder_members')
            .select('*, profiles(id, name, email, role, post)')
            .eq('user_id', userId)
            .timeout(const Duration(seconds: 15));
        memberships = (membershipData as List)
            .map((e) => FolderMemberModel.fromJson(e))
            .toList();
      } catch (e) {
        rethrow;
      }

      final folderIds = memberships.map((m) => m.folderId).toList();

      final List<Map<String, dynamic>> globalPermData = await _supabase
          .from('global_feature_permissions')
          .select()
          .timeout(const Duration(seconds: 10));

      final globalPerms = globalPermData
          .map(
            (e) => FolderPermissionModel(
              id: 0,
              folderId: 0,
              feature: e['feature'] as String,
              allowed: e['allowed'] as bool,
            ),
          )
          .toList();

      try {
        if (folderIds.isNotEmpty) {
          final permData = await _supabase
              .from('folder_permissions')
              .select()
              .inFilter('execom_id', folderIds)
              .timeout(const Duration(seconds: 15));
          final allPerms = (permData as List)
              .map((e) => FolderPermissionModel.fromJson(e))
              .toList();

          for (final p in allPerms) {
            folderPermissions.putIfAbsent(p.folderId, () => []).add(p);
          }
        }
      } catch (e) {
        rethrow;
      }

      if (!isCurrent()) return;
      _currentUser = profile;
      _folderMemberships = memberships;
      _folderPermissions = folderPermissions;
      // 4. Build permission engine
      _permissionEngine = PermissionEngine(
        user: _currentUser!,
        userFolderMemberships: _folderMemberships,
        folderPermissions: _folderPermissions,
        globalPermissions: globalPerms,
      );
    } catch (e) {
      if (isCurrent()) {
        _currentUser = null;
        _permissionEngine = null;
        _error = e is AuthException
            ? e.message
            : 'Unable to load your access details. Please check your connection and try again.';
      }
      rethrow;
    } finally {
      if (isCurrent()) {
        _pendingLoad = null;
        _loadingUserId = null;
        _isLoading = false;
        _notify();
      }
    }
  }

  Future<void> refreshUserData() async {
    await _loadUserData();
  }

  Future<void> signIn(String email, String password) async {
    try {
      final res = await _supabase.auth.signInWithPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );

      if (res.session == null) {
        throw const AuthException(
          'Sign-in did not return a session. Please try again.',
        );
      }
      _authUser = res.session?.user;
      if (_authUser != null) {
        await _loadUserData();
        if (_currentUser == null) {
          throw Exception('Profile loading failed. Please contact admin.');
        }
      }
    } catch (e) {
      _isLoading = false;
      _notify();
      rethrow;
    }
  }

  Future<void> signOut() async {
    _generation++;
    _pendingLoad = null;
    _loadingUserId = null;
    AppCache().invalidateAll();
    _authUser = null;
    _currentUser = null;
    _folderMemberships = [];
    _folderPermissions = {};
    _permissionEngine = null;
    _isLoading = false;
    _notify();
    await _supabase.auth.signOut();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _authSubscription?.cancel();
    super.dispose();
  }
}
