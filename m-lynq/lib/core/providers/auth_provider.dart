import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
      } else if (state.user?.id != newUser.id) {
        _loadProfile(newUser);
      }
    });
  }

  // ── Profile loading ──────────────────────────────────────────────────────

  Future<void> _loadProfile(User user) async {
    state = MemberAuthState(user: user, isLoading: true);
    try {
      // Run all queries in parallel
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

      final userResponse    = results[0];
      final memberResponse  = results[1];
      final notIsteResponse = results[2];

      if (userResponse == null) {
        // Check whether we have persisted signup data — if yes, the user is
        // stranded mid-registration (app was killed between OTP send and verify).
        // Restore the pending data so verifyOTP can re-complete profile creation
        // when they enter the OTP again.
        final restored = await _restorePendingSignUpData();
        if (restored != null) {
          _pendingSignUpData = restored;
        }
        state = MemberAuthState(
          user: user,
          isLoading: false,
          // Use a special error code the router can detect to redirect back to registration
          error: restored != null
              ? 'registration_incomplete'
              : 'User profile not found. Please sign up first.',
        );
        return;
      }

      // Remove null values so they don't overwrite non-null data on merge
      final userClean    = Map<String, dynamic>.from(userResponse)..removeWhere((_, v) => v == null);
      final memberClean  = Map<String, dynamic>.from(memberResponse ?? {})..removeWhere((_, v) => v == null);
      final notIsteClean = Map<String, dynamic>.from(notIsteResponse ?? {})..removeWhere((_, v) => v == null);

      // Merge: later maps win on conflict
      final merged = {...userClean, ...memberClean, ...notIsteClean};

      // Map iste_id → membership_id for backward-compat with UI
      if (merged['iste_id'] != null) merged['membership_id'] = merged['iste_id'];
      // Map expiry columns → validity_end for UI
      merged['validity_end'] ??= merged['expiry_date'] ?? merged['membership_expiry'];

      // Clear any stale pending data now that profile is fully loaded
      await _clearPendingSignUpData();

      state = MemberAuthState(user: user, profile: merged, isLoading: false);
    } catch (e) {
      state = MemberAuthState(user: user, isLoading: false, error: '$e');
    }
  }

  // ── ISTE Member Password Flow ────────────────────────────────────────────
  //
  // Fixed flow:
  //   1. checkEmailMembership(email)
  //      → null            : no members row at all        → guest path
  //      → {status:'pending_iste_id'} : row exists, iste_id null → show message
  //      → {status:'execom_unactivated'} : execom, no user_id   → show message
  //      → {status:'login'}  : has_password true           → login step
  //      → {status:'otp_required'} : first-time member    → send OTP, then create pw
  //
  //   2. requestIsteMemberOTP(email) — sends OTP to the matched member email
  //   3. verifyIsteMemberOTP(email, otp) — verifies OTP, sets _isteOtpVerified flag
  //   4. registerIsteMemberWithPassword(email, password, profileData)
  //      — only callable after OTP verified

  bool _isteOtpVerified = false;

  Future<Map<String, dynamic>?> checkEmailMembership(String email) async {
    final memberRes = await _supabase.from('members')
        .select()
        .ilike('email', email.trim())
        .maybeSingle();

    if (memberRes != null) {
      // If they are in the members table, direct OTP login is enough!
      return {
        'status': 'member_otp_login',
        'iste_id': memberRes['iste_id'],
        'name': memberRes['name'] ?? '',
        'phone': memberRes['phone'] ?? '',
      };
    }

    // Check if they are already registered as a guest (exist in users table)
    final userRes = await _supabase.from('users')
        .select('id')
        .ilike('email', email.trim())
        .maybeSingle();

    if (userRes != null) {
      return {'status': 'guest_login'};
    }

    // No row at all and no guest user → guest registration path
    return null;
  }

  /// Step 2 of ISTE member first-login: send OTP to verify email ownership.
  Future<void> requestIsteMemberOTP(String email) async {
    _isteOtpVerified = false;
    // shouldCreateUser: false — we are NOT creating a new user here,
    // we are verifying ownership of the email before allowing password creation.
    await _supabase.auth.signInWithOtp(
      email: email.trim(),
      shouldCreateUser: false,
      emailRedirectTo: 'com.iste.memberapp://login-callback',
    );
  }

  /// Step 3: Verify the OTP sent by requestIsteMemberOTP.
  /// On success, sets _isteOtpVerified = true so registerIsteMemberWithPassword
  /// is allowed to proceed.
  Future<void> verifyIsteMemberOTP(String email, String otp) async {
    final res = await _supabase.auth.verifyOTP(
      email: email.trim(),
      token: otp,
      type: OtpType.email,
    );
    if (res.user == null) {
      throw Exception('OTP verification failed. Please try again.');
    }
    _isteOtpVerified = true;
    // Sign out immediately — they verified ownership, now they'll set a password
    // via registerIsteMemberWithPassword which calls signUp with email+password.
    await _supabase.auth.signOut();
  }

  /// Step 4: Register the ISTE member with a password.
  /// REQUIRES _isteOtpVerified == true, otherwise throws.
  Future<void> registerIsteMemberWithPassword(
    String email,
    String password,
    Map<String, dynamic> profileData,
  ) async {
    if (!_isteOtpVerified) {
      throw Exception('Email verification required before setting a password.');
    }

    final res = await _supabase.auth.signUp(
      email: email.trim(),
      password: password,
    );

    if (res.user != null) {
      await _supabase.from('users').upsert({
        'id': res.user!.id,
        'email': email.trim(),
        'name': profileData['name'],
        'phone': profileData['phone'],
        'role': 'user',
      });

      // Link the existing members row to this new auth user
      final updateRes = await _supabase.from('members').update({
        'user_id': res.user!.id,
      }).eq('iste_id', profileData['iste_id']).select();

      if ((updateRes as List).isEmpty) {
        // The iste_id didn't match any row — this should never happen after
        // checkEmailMembership succeeded, but handle it defensively.
        throw Exception(
          'Account setup incomplete: ISTE ID ${profileData['iste_id']} not found in members table. '
          'Please contact your execom.',
        );
      }

      _isteOtpVerified = false;
      await _loadProfile(res.user!);
    } else {
      throw Exception('Sign-up failed: no user returned. Please try again.');
    }
  }

  // Legacy / still-used: checkIsteMember (cross-validates email+phone+isteId)
  Future<Map<String, dynamic>?> checkIsteMember(String email, String phone, String isteId) async {
    // Check if the account is already claimed
    final existingProfile = await _supabase.from('members')
        .select('user_id')
        .eq('iste_id', isteId)
        .maybeSingle();

    if (existingProfile != null && existingProfile['user_id'] != null) {
      throw Exception('This account has already been claimed. Please switch to Log In and use your password.');
    }

    return await _supabase.from('members')
        .select()
        .eq('email', email)
        .eq('phone', phone)
        .eq('iste_id', isteId)
        .maybeSingle();
  }

  Future<void> loginIsteMemberWithPassword(String isteId, String password) async {
    final memberRes = await _supabase.from('members')
        .select('email, user_id')
        .eq('iste_id', isteId)
        .maybeSingle();

    if (memberRes == null) throw Exception('ISTE ID not found in database');

    // If user_id is null, the account was never activated
    if (memberRes['user_id'] == null) {
      throw Exception(
        'No account has been set up for this ISTE ID yet. '
        'Please use the "First time login" flow to create your password.',
      );
    }

    final email = memberRes['email'] as String;
    await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  // ── Guest OTP Flow ───────────────────────────────────────────────────────

  Future<void> requestOTP(String email, {bool isSignUp = false}) async {
    await _supabase.auth.signInWithOtp(
      email: email.trim(),
      shouldCreateUser: isSignUp, // Allow creating new users if signing up
      emailRedirectTo: 'com.iste.memberapp://login-callback',
    );
  }

  Future<void> verifyOTP(String email, String otp) async {
    final res = await _supabase.auth.verifyOTP(
      email: email.trim(),
      token: otp,
      type: OtpType.email,
    );

    if (res.user != null) {
      try {
        // Step 1: Check if they exist in the members table
        final memberRes = await _supabase.from('members')
            .select()
            .ilike('email', email.trim())
            .maybeSingle();

        if (memberRes != null) {
          // They are a registered member in the members table!
          // Link user_id in the members table if not set yet
          if (memberRes['user_id'] == null) {
            await _supabase.from('members').update({
              'user_id': res.user!.id,
            }).eq('id', memberRes['id']);
          }

          // Automatically provision / update users table entry
          await _supabase.from('users').upsert({
            'id': res.user!.id,
            'email': email.trim(),
            'name': memberRes['name'] ?? 'Member',
            'phone': memberRes['phone'],
            'role': memberRes['role'] ?? 'member', // Keep role from members table (e.g. member, Core Execom, etc.)
            'branch': memberRes['department'],
            'status': 'active',
          });

          await _loadProfile(res.user!);
          return;
        }

        // Step 2: Otherwise they are a guest (restore pending guest registration data)
        if (_pendingSignUpData == null) {
          _pendingSignUpData = await _restorePendingSignUpData();
        }

        if (_pendingSignUpData != null) {
          await _supabase.from('users').upsert({
            'id': res.user!.id,
            'email': email.trim(),
            'name': _pendingSignUpData!['name'],
            'phone': _pendingSignUpData!['phone'],
            'roll_number': _pendingSignUpData!['roll_number'],
            'college': _pendingSignUpData!['college'],
            'role': 'user',
          });

          await _supabase.from('members_not_iste').upsert({
            'id': res.user!.id,
            'name': _pendingSignUpData!['name'],
            'email': email.trim(),
            'phone': _pendingSignUpData!['phone'],
            'roll_number': _pendingSignUpData!['roll_number'],
            'college': _pendingSignUpData!['college'],
          });

          await _loadProfile(res.user!);
        } else {
          // Existed guest logger - load profile directly
          await _loadProfile(res.user!);
        }
      } catch (e) {
        state = MemberAuthState(user: res.user, isLoading: false, error: 'Failed to sync profile: $e');
      } finally {
        await _clearPendingSignUpData();
      }
    }
  }

  // ── Misc ─────────────────────────────────────────────────────────────────

  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  Future<void> refresh() async {
    final user = _supabase.auth.currentUser;
    if (user != null) await _loadProfile(user);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, MemberAuthState>(
  (ref) => AuthNotifier(),
);
