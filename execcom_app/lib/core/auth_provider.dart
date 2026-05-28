import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_model.dart';
import '../models/folder_model.dart';
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
        notifyListeners();
        return;
      }

      if (_authUser?.id != newUser.id) {
        _authUser = newUser;
        await _loadUserData();
      }
    });
  }

  Future<void> _loadUserData() async {
    if (_authUser == null) {
      _isLoading = false;
      notifyListeners();
      return;
    }

    try {
      // 1. Fetch user profile with timeout
      final userData = await _supabase
          .from('users')
          .select()
          .eq('id', _authUser!.id)
          .single()
          .timeout(const Duration(seconds: 15));
      _currentUser = UserModel.fromJson(userData);

      // 2. Fetch folder memberships with timeout
      final membershipData = await _supabase
          .from('folder_members')
          .select('*, users!folder_members_user_id_fkey(id, name, email, role, post)')
          .eq('user_id', _authUser!.id)
          .timeout(const Duration(seconds: 15));
      _folderMemberships = (membershipData as List)
          .map((e) => FolderMemberModel.fromJson(e))
          .toList();

      // 3. Fetch folder permissions
      // We always fetch global permissions (ID 0)
      // and permissions for folders the user belongs to.
      final folderIds = _folderMemberships.map((m) => m.folderId).toList();
      var permQuery = _supabase.from('folder_permissions').select();
      
      if (folderIds.isNotEmpty) {
        // Include global (0) + folder-specific permissions
        permQuery = permQuery.or('folder_id.eq.0,folder_id.in.(${folderIds.join(",")})');
      } else {
        // No folder memberships: only fetch global permissions
        permQuery = permQuery.eq('folder_id', 0);
      }
      
      final permData = await permQuery.timeout(const Duration(seconds: 15));
      final allPerms = (permData as List)
          .map((e) => FolderPermissionModel.fromJson(e))
          .toList();

      _folderPermissions = {};
      for (final p in allPerms) {
        _folderPermissions.putIfAbsent(p.folderId, () => []).add(p);
      }

      // 4. Build permission engine
      _permissionEngine = PermissionEngine(
        user: _currentUser!,
        userFolderMemberships: _folderMemberships,
        folderPermissions: _folderPermissions,
      );
    } catch (e) {
      debugPrint('Error loading user data: $e');
      // If profile fails, clear current user to ensure we stay on login
      _currentUser = null;
      _permissionEngine = null;
      rethrow;
      // If we are at initialization, we must set isLoading = false
    } finally {
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
