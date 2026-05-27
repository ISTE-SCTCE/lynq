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
      // 1. Fetch from public.users
      final userResponse = await _supabase
          .from('users')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (userResponse == null) {
        state = MemberAuthState(
          user: user,
          isLoading: false,
          error: 'User profile not found. Please sign up first.',
        );
        return;
      }

      // 2. Fetch from member_profiles
      final memberResponse = await _supabase
          .from('member_profiles')
          .select()
          .eq('user_id', user.id)
          .maybeSingle();

      // Merge data
      final merged = {
        ...userResponse,
        if (memberResponse != null) ...memberResponse,
      };

      state = MemberAuthState(user: user, profile: merged, isLoading: false);
    } catch (e) {
      state = MemberAuthState(user: user, isLoading: false, error: '$e');
    }
  }

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
        
        // Refresh profile after insertion to override any race-condition error from onAuthStateChange
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
