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
  bool _isLoadingUserData = false; // guard against concurrent loads

  User? get authUser => _authUser;
  UserModel? get currentUser => _currentUser;
  PermissionEngine? get permissions => _permissionEngine;
  AppRole get role => _currentUser != null ? AppRole.fromString(_currentUser!.role) : AppRole.restricted;
  bool get isLoading => _isLoading;
  bool get isShowingSplash => _isShowingSplash;
  bool get isAuthenticated => _authUser != null && _currentUser != null;

  void hideSplash() {
    _isShowingSplash = false;
    notifyListeners();
  }

  AuthProvider() {
    _initAuth();
  }

  void _initAuth() {
    // Check if already has a session
    final session = _supabase.auth.currentSession;
    if (session != null) {
      _authUser = session.user;
      _loadUserData();
    } else {
      _isLoading = false;
      notifyListeners();
    }

    // Listen for auth state changes
    _supabase.auth.onAuthStateChange.listen((data) async {
      final newUser = data.session?.user;

      if (newUser == null) {
        _authUser = null;
        _currentUser = null;
        _folderMemberships = [];
        _folderPermissions = {};
        _permissionEngine = null;
        _isLoading = false;
        AppCache().invalidateAll();
        notifyListeners();
        return;
      }

      // Only reload if the user actually changed — prevents a double-load
      // when signIn() already calls _loadUserData() before this fires.
      if (_authUser?.id != newUser.id && !_isLoadingUserData) {
        _authUser = newUser;
        await _loadUserData();
      }
    });
  }

  Future<void> _loadUserData() async {
    if (_authUser == null || _isLoadingUserData) {
      _isLoading = false;
      notifyListeners();
      return;
    }
    _isLoadingUserData = true;

    try {
      // 1. Fetch user profile with timeout
      final userData = await _supabase
          .from('profiles')
          .select()
          .eq('id', _authUser!.id)
          .single()
          .timeout(const Duration(seconds: 15));
      _currentUser = UserModel.fromJson(userData);

      // 2. Fetch folder memberships with timeout
      final membershipData = await _supabase
          .from('folder_members')
          .select('*, profiles(id, name, email, role, post)')
          .eq('user_id', _authUser!.id)
          .timeout(const Duration(seconds: 15));
      _folderMemberships = (membershipData as List)
          .map((e) => FolderMemberModel.fromJson(e))
          .toList();

      final folderIds = _folderMemberships.map((m) => m.folderId).toList();
      
      final List<Map<String, dynamic>> globalPermData = await _supabase
          .from('global_feature_permissions')
          .select()
          .timeout(const Duration(seconds: 10))
          .catchError((_) => <Map<String, dynamic>>[]);
          
      final globalPerms = globalPermData
          .map((e) => FolderPermissionModel(
                id: 0,
                folderId: 0,
                feature: e['feature'] as String,
                allowed: e['allowed'] as bool,
              ))
          .toList();

      if (folderIds.isNotEmpty) {
        final permData = await _supabase
            .from('folder_permissions')
            .select()
            .inFilter('execom_id', folderIds)
            .timeout(const Duration(seconds: 15));
        final allPerms = (permData as List)
            .map((e) => FolderPermissionModel.fromJson(e))
            .toList();

        _folderPermissions = {};
        for (final p in allPerms) {
          _folderPermissions.putIfAbsent(p.folderId, () => []).add(p);
        }
      } else {
        _folderPermissions = {};
      }

      // 4. Build permission engine
      _permissionEngine = PermissionEngine(
        user: _currentUser!,
        userFolderMemberships: _folderMemberships,
        folderPermissions: _folderPermissions,
        globalPermissions: globalPerms,
      );
    } catch (e) {
      debugPrint('Error loading user data: $e');
      _currentUser = null;
      _permissionEngine = null;
      rethrow;
    } finally {
      _isLoadingUserData = false;
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshUserData() async {
    await _loadUserData();
  }

  Future<void> signIn(String email, String password) async {
    try {
      final res = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
      
      _authUser = res.session?.user;
      if (_authUser != null) {
        await _loadUserData();
        if (_currentUser == null) {
          throw Exception('Profile loading failed. Please contact admin.');
        }
      }
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _supabase.auth.signOut();
    _authUser = null;
    _currentUser = null;
    _folderMemberships = [];
    _folderPermissions = {};
    _permissionEngine = null;
    _isLoading = false;
    notifyListeners();
  }
}
