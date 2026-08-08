import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../member_emails.dart';

// ── Auth State ─────────────────────────────────────────────────────────────

class MemberAuthState {
  final User? user;
  final Map<String, dynamic>? profile;
  final bool isLoading;
  final String? error;

  const MemberAuthState({
    this.user,
    this.profile,
    this.isLoading = false,
    this.error,
  });

  bool get isAuthenticated => user != null && profile != null;
  String get membershipId => profile?['membership_id'] as String? ?? '';
  String get name => profile?['name'] as String? ?? '';
  String get email => user?.email ?? '';
  String get role => profile?['role'] as String? ?? 'user';
  DateTime? get validityEnd {
    final s = profile?['validity_end'] as String?;
    return s != null ? DateTime.tryParse(s) : null;
  }
  bool get isMembershipValid => membershipId.isNotEmpty;
  int get daysUntilExpiry =>
      validityEnd != null ? validityEnd!.difference(DateTime.now()).inDays : -1;

  MemberAuthState copyWith({
    User? user,
    Map<String, dynamic>? profile,
    bool? isLoading,
    String? error,
  }) =>
      MemberAuthState(
        user: user ?? this.user,
        profile: profile ?? this.profile,
        isLoading: isLoading ?? this.isLoading,
        error: error,
      );
}

// ── Prefs key constants ────────────────────────────────────────────────────

const _kPendingSignUpKey = 'pending_signup_data';

// ── Auth Notifier ──────────────────────────────────────────────────────────

class AuthNotifier extends StateNotifier<MemberAuthState> {
  final SupabaseClient _supabase = Supabase.instance.client;

  AuthNotifier() : super(const MemberAuthState(isLoading: true)) {
    _init();
  }

  // In-memory pending data (also persisted to prefs before OTP send)
  Map<String, dynamic>? _pendingSignUpData;

  // ── Pending signup data: persist across app kills ────────────────────────

  void setPendingSignUpData(Map<String, dynamic> data) {
    _pendingSignUpData = data;
    _persistPendingSignUpData(data);
  }

  Future<void> _persistPendingSignUpData(Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPendingSignUpKey, jsonEncode(data));
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> _restorePendingSignUpData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kPendingSignUpKey);
      if (raw != null) {
        return Map<String, dynamic>.from(jsonDecode(raw) as Map);
      }
    } catch (_) {}
    return null;
  }

  Future<void> _clearPendingSignUpData() async {
    _pendingSignUpData = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kPendingSignUpKey);
    } catch (_) {}
  }

  // ── Initialisation ───────────────────────────────────────────────────────

  void _init() {
    final session = _supabase.auth.currentSession;
    if (session != null) {
      _loadProfile(session.user);
    } else {
      state = const MemberAuthState(isLoading: false);
    }

    _supabase.auth.onAuthStateChange.listen((data) {
      final newUser = data.session?.user;
      if (newUser == null) {
        state = const MemberAuthState(isLoading: false);
      } else if (state.user?.id != newUser.id || state.profile == null) {
        _loadProfile(newUser);
      }
    });
  }

  // ── Profile loading ──────────────────────────────────────────────────────

  Future<void> _loadProfile(User user) async {
    state = MemberAuthState(user: user, isLoading: true);
    try {
      final userEmail = (user.email ?? '').trim().toLowerCase();

      // Parallel queries: users table by id, members table by user_id, members_not_iste by id
      final results = await Future.wait([
        _supabase
            .from('users')
            .select('id, email, name, phone, role, roll_number, branch, year, forum')
            .eq('id', user.id)
            .maybeSingle(),
        _supabase
            .from('members')
            .select('id, user_id, name, email, phone, iste_id, role, status, plan, plan_type, joined_date, expiry_date, membership_expiry, department, forum, forum_name')
            .eq('user_id', user.id)
            .maybeSingle(),
        _supabase
            .from('members_not_iste')
            .select('id, name, email, phone, roll_number, college')
            .eq('id', user.id)
            .maybeSingle(),
      ]);

      Map<String, dynamic>? userResponse    = results[0];
      Map<String, dynamic>? memberResponse  = results[1];
      Map<String, dynamic>? notIsteResponse = results[2];

      // Fallback: If members row by user_id was null, try matching members by email
      if (memberResponse == null && userEmail.isNotEmpty) {
        final memberByEmail = await _supabase
            .from('members')
            .select('id, user_id, name, email, phone, iste_id, role, status, plan, plan_type, joined_date, expiry_date, membership_expiry, department, forum, forum_name')
            .ilike('email', userEmail)
            .maybeSingle();

        if (memberByEmail != null) {
          memberResponse = memberByEmail;
          // Auto-link user_id in members table if not set or mismatched
          if (memberByEmail['user_id'] != user.id) {
            try {
              await _supabase.from('members').update({
                'user_id': user.id,
              }).eq('id', memberByEmail['id']);
            } catch (e) {
              // Ignore update error
            }
          }
        }
      }

      // Auto-provision user record in `users` table if missing
      if (userResponse == null) {
        final restored = await _restorePendingSignUpData();
        final nameToUse = memberResponse?['name'] ?? restored?['name'] ?? userEmail.split('@').first;
        final phoneToUse = memberResponse?['phone'] ?? restored?['phone'];
        final roleToUse = memberResponse?['role'] ?? 'member';
        final branchToUse = memberResponse?['department'];

        try {
          await _supabase.from('users').upsert({
            'id': user.id,
            'email': userEmail,
            'name': nameToUse,
            'phone': phoneToUse,
            'role': roleToUse,
            'branch': branchToUse,
            'status': 'active',
          });

          // Re-query user row after creation
          userResponse = await _supabase
              .from('users')
              .select('id, email, name, phone, role, roll_number, branch, year, forum')
              .eq('id', user.id)
              .maybeSingle();
        } catch (_) {}
      }

      // Remove null values so they don't overwrite non-null data on merge
      final userClean    = Map<String, dynamic>.from(userResponse ?? {})..removeWhere((_, v) => v == null);
      final memberClean  = Map<String, dynamic>.from(memberResponse ?? {})..removeWhere((_, v) => v == null);
      final notIsteClean = Map<String, dynamic>.from(notIsteResponse ?? {})..removeWhere((_, v) => v == null);

      // Merge: later maps win on conflict
      final merged = {...userClean, ...memberClean, ...notIsteClean};

      // Map iste_id → membership_id for backward-compat with UI
      if (merged['iste_id'] != null) merged['membership_id'] = merged['iste_id'];
      // Map expiry columns → validity_end for UI
      merged['validity_end'] ??= merged['expiry_date'] ?? merged['membership_expiry'];

      // Clear any stale pending data now that profile is loaded
      await _clearPendingSignUpData();

      state = MemberAuthState(user: user, profile: merged, isLoading: false);
    } catch (e) {
      state = MemberAuthState(user: user, isLoading: false, error: '$e');
    }
  }

  // ── Member Email Check ─────────────────────────────────────────────────

  Future<Map<String, dynamic>?> checkEmailMembership(String email) async {
    final cleanEmail = email.trim().toLowerCase();

    // 1. Check if email is in official static list
    if (isIsteMemberEmail(cleanEmail)) {
      return {
        'status': 'member_otp_login',
        'is_iste_member': true,
      };
    }

    // 2. Check if in members database table
    final memberRes = await _supabase.from('members')
        .select('id, iste_id, name, phone, email')
        .ilike('email', cleanEmail)
        .maybeSingle();

    if (memberRes != null) {
      return {
        'status': 'member_otp_login',
        'is_iste_member': true,
        'iste_id': memberRes['iste_id'],
        'name': memberRes['name'] ?? '',
        'phone': memberRes['phone'] ?? '',
      };
    }

    // 3. Check if existing guest user in users table
    final userRes = await _supabase.from('users')
        .select('id')
        .ilike('email', cleanEmail)
        .maybeSingle();

    if (userRes != null) {
      return {
        'status': 'guest_login',
        'is_iste_member': false,
      };
    }

    // 4. Truly new user → guest registration path
    return null;
  }

  // ── OTP Flow ─────────────────────────────────────────────────────────────

  Future<void> requestOTP(String email, {bool isSignUp = false}) async {
    await _supabase.auth.signInWithOtp(
      email: email.trim(),
      shouldCreateUser: isSignUp,
      emailRedirectTo: 'com.iste.memberapp://login-callback',
    );
  }

  Future<void> verifyOTP(String email, String otp) async {
    final cleanEmail = email.trim().toLowerCase();
    final res = await _supabase.auth.verifyOTP(
      email: cleanEmail,
      token: otp,
      type: OtpType.email,
    );

    if (res.user != null) {
      try {
        // Check if matching member in members table
        final memberRes = await _supabase.from('members')
            .select()
            .ilike('email', cleanEmail)
            .maybeSingle();

        if (memberRes != null) {
          // Link user_id in members table if needed
          if (memberRes['user_id'] != res.user!.id) {
            await _supabase.from('members').update({
              'user_id': res.user!.id,
            }).eq('id', memberRes['id']);
          }

          // Provision users table entry
          await _supabase.from('users').upsert({
            'id': res.user!.id,
            'email': cleanEmail,
            'name': memberRes['name'] ?? 'Member',
            'phone': memberRes['phone'],
            'role': memberRes['role'] ?? 'member',
            'branch': memberRes['department'],
            'status': 'active',
          });

          await _loadProfile(res.user!);
          return;
        }

        // Restore pending guest data if any
        if (_pendingSignUpData == null) {
          _pendingSignUpData = await _restorePendingSignUpData();
        }

        if (_pendingSignUpData != null) {
          await _supabase.from('users').upsert({
            'id': res.user!.id,
            'email': cleanEmail,
            'name': _pendingSignUpData!['name'],
            'phone': _pendingSignUpData!['phone'],
            'roll_number': _pendingSignUpData!['roll_number'],
            'college': _pendingSignUpData!['college'],
            'role': 'user',
          });

          await _supabase.from('members_not_iste').upsert({
            'id': res.user!.id,
            'name': _pendingSignUpData!['name'],
            'email': cleanEmail,
            'phone': _pendingSignUpData!['phone'],
            'roll_number': _pendingSignUpData!['roll_number'],
            'college': _pendingSignUpData!['college'],
          });

          await _loadProfile(res.user!);
        } else {
          // Provision baseline user if missing
          await _supabase.from('users').upsert({
            'id': res.user!.id,
            'email': cleanEmail,
            'role': 'user',
            'status': 'active',
          });
          await _loadProfile(res.user!);
        }
      } catch (e) {
        state = MemberAuthState(user: res.user, isLoading: false, error: 'Failed to sync profile: $e');
      } finally {
        await _clearPendingSignUpData();
      }
    } else {
      throw Exception('OTP verification failed. Please try again.');
    }
  }

  // ── Misc ─────────────────────────────────────────────────────────────────

  Future<void> signOut() async {
    await _supabase.auth.signOut();
    state = const MemberAuthState(isLoading: false);
  }

  Future<void> refresh() async {
    final user = _supabase.auth.currentUser;
    if (user != null) await _loadProfile(user);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, MemberAuthState>(
  (ref) => AuthNotifier(),
);
