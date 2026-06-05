import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  DateTime? get validityEnd {
    final s = profile?['validity_end'] as String?;
    return s != null ? DateTime.tryParse(s) : null;
  }
  bool get isMembershipValid =>
      validityEnd != null && validityEnd!.isAfter(DateTime.now());
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

// ── Auth Notifier ──────────────────────────────────────────────────────────

class AuthNotifier extends StateNotifier<MemberAuthState> {
  final SupabaseClient _supabase = Supabase.instance.client;

  AuthNotifier() : super(const MemberAuthState(isLoading: true)) {
    _init();
  }

  Map<String, dynamic>? _pendingSignUpData;

  void setPendingSignUpData(Map<String, dynamic> data) {
    _pendingSignUpData = data;
  }

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

  Future<void> _loadProfile(User user) async {
    state = MemberAuthState(user: user, isLoading: true);
    try {
      // Run both queries in parallel instead of sequentially
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
        state = MemberAuthState(
          user: user,
          isLoading: false,
          error: 'User profile not found. Please sign up first.',
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

      state = MemberAuthState(user: user, profile: merged, isLoading: false);
    } catch (e) {
      state = MemberAuthState(user: user, isLoading: false, error: '$e');
    }
  }

  // --- New ISTE Member Password Flow ---
  
  Future<Map<String, dynamic>?> checkEmailMembership(String email) async {
    final memberRes = await _supabase.from('members')
        .select()
        .ilike('email', email.trim())
        .maybeSingle();
    
    if (memberRes == null || memberRes['iste_id'] == null) {
      return null;
    }

    final isteId = memberRes['iste_id'] as String;
    
    // Check if user_id is set (which means they have set a password/claimed account)
    final bool hasPassword = memberRes['user_id'] != null;

    return {
      'iste_id': isteId,
      'has_password': hasPassword,
      'role': memberRes['role'] ?? 'member',
      'name': memberRes['name'] ?? '',
      'phone': memberRes['phone'] ?? '',
    };
  }
  
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

  Future<void> registerIsteMemberWithPassword(String email, String password, Map<String, dynamic> profileData) async {
    final res = await _supabase.auth.signUp(
      email: email,
      password: password,
    );
    
    if (res.user != null) {
      await _supabase.from('users').upsert({
        'id': res.user!.id,
        'email': email,
        'name': profileData['name'],
        'phone': profileData['phone'],
        'role': 'user', 
      });
      // Link the existing members row to this new auth user
      await _supabase.from('members').update({
        'user_id': res.user!.id,
      }).eq('iste_id', profileData['iste_id']);
      
      await _loadProfile(res.user!);
    }
  }

  Future<void> loginIsteMemberWithPassword(String isteId, String password) async {
    final memberRes = await _supabase.from('members').select('email').eq('iste_id', isteId).maybeSingle();
    if (memberRes == null) throw Exception('ISTE ID not found in database');
    
    final email = memberRes['email'] as String;
    await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  // --- End New ISTE Member Password Flow ---

  Future<void> requestOTP(String email, {bool isSignUp = false}) async {
    await _supabase.auth.signInWithOtp(
      email: email,
      shouldCreateUser: isSignUp, // Allow creating new users if signing up
      emailRedirectTo: 'com.iste.memberapp://login-callback',
    );
  }

  Future<void> verifyOTP(String email, String otp) async {
    final res = await _supabase.auth.verifyOTP(
      email: email,
      token: otp,
      type: OtpType.email,
    );

    // If we have pending signup data and auth succeeded, create user profile
    if (_pendingSignUpData != null && res.user != null) {
      try {
        await _supabase.from('users').upsert({
          'id': res.user!.id,
          'email': email,
          'name': _pendingSignUpData!['name'],
          'phone': _pendingSignUpData!['phone'],
          'roll_number': _pendingSignUpData!['roll_number'],
          'college': _pendingSignUpData!['college'],
          'role': 'user', 
        });

        // Non-ISTE members are tracked in members_not_iste only
        // (iste_non_member table was removed in db cleanup)
        await _supabase.from('members_not_iste').upsert({
          'id': res.user!.id,
          'name': _pendingSignUpData!['name'],
          'email': email,
          'phone': _pendingSignUpData!['phone'],
          'roll_number': _pendingSignUpData!['roll_number'],
          'college': _pendingSignUpData!['college'],
        });
        
        // Refresh profile after insertion
        await _loadProfile(res.user!);
      } catch (e) {
        state = MemberAuthState(user: res.user, isLoading: false, error: 'Failed to save profile details: $e');
      } finally {
        _pendingSignUpData = null;
      }
    }
  }

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
