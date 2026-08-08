import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme.dart';
import '../../core/member_emails.dart';

enum AuthStep {
  emailEntry,
  isteOtpVerify,
  guestRegistration,
  guestOtpVerify,
}

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with TickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  // Step state
  AuthStep _currentStep = AuthStep.emailEntry;
  String? _membershipTag; // 'iste_member' | 'guest'

  // Controllers
  final _emailCtrl = TextEditingController();
  final _otpCtrl   = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _nameCtrl  = TextEditingController();
  final _regNoCtrl = TextEditingController();
  final _collegeCtrl = TextEditingController();

  bool _isLoading = false;
  String? _error;
  String? _successMessage;

  static const _bg = MemberTheme.mBackground;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(
        parent: _animController, curve: Curves.easeOutCubic);
    _animController.forward();
    _emailCtrl.addListener(_onEmailChanged);
  }

  void _onEmailChanged() {
    if (_currentStep == AuthStep.emailEntry) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _emailCtrl.removeListener(_onEmailChanged);
    _emailCtrl.dispose();
    _otpCtrl.dispose();
    _phoneCtrl.dispose();
    _nameCtrl.dispose();
    _regNoCtrl.dispose();
    _collegeCtrl.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _changeStep(AuthStep step) {
    setState(() {
      _currentStep = step;
      _error = null;
      _successMessage = null;
    });
    _animController.forward(from: 0);
  }

  // ── Step Actions ──────────────────────────────────────────────────────────

  Future<void> _handleEmailContinue() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Please enter your email address');
      return;
    }
    if (!email.contains('@') || !email.contains('.')) {
      setState(() => _error = 'Please enter a valid email address');
      return;
    }

    setState(() { _isLoading = true; _error = null; });

    try {
      final membership = await ref.read(authProvider.notifier).checkEmailMembership(email);

      if (membership != null && membership['is_iste_member'] == true) {
        // ISTE Member: send OTP and go to ISTE OTP verify
        _membershipTag = 'iste_member';
        await ref.read(authProvider.notifier).requestOTP(email, isSignUp: true);
        setState(() {
          _successMessage = 'OTP sent to your email!';
        });
        _changeStep(AuthStep.isteOtpVerify);
        return;
      }

      if (membership != null && membership['status'] == 'guest_login') {
        // Existing guest user: send OTP and go to Guest OTP verify
        _membershipTag = 'guest';
        await ref.read(authProvider.notifier).requestOTP(email, isSignUp: false);
        setState(() {
          _successMessage = 'OTP sent to your email!';
        });
        _changeStep(AuthStep.guestOtpVerify);
        return;
      }

      // New guest user: go to registration form
      _membershipTag = 'guest';
      _changeStep(AuthStep.guestRegistration);
    } catch (e) {
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGuestRegister() async {
    if (_nameCtrl.text.trim().isEmpty ||
        _phoneCtrl.text.trim().isEmpty ||
        _regNoCtrl.text.trim().isEmpty ||
        _collegeCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Please fill in all fields');
      return;
    }

    setState(() { _isLoading = true; _error = null; });

    try {
      ref.read(authProvider.notifier).setPendingSignUpData({
        'name':        _nameCtrl.text.trim(),
        'phone':       _phoneCtrl.text.trim(),
        'roll_number': _regNoCtrl.text.trim(),
        'college':     _collegeCtrl.text.trim(),
      });

      await ref.read(authProvider.notifier).requestOTP(
        _emailCtrl.text.trim(),
        isSignUp: true,
      );

      setState(() {
        _successMessage = 'OTP sent to your email!';
      });
      _changeStep(AuthStep.guestOtpVerify);
    } catch (e) {
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleOtpVerify() async {
    final otp = _otpCtrl.text.trim();
    if (otp.isEmpty || otp.length < 6) {
      setState(() => _error = 'Please enter the verification code');
      return;
    }

    setState(() { _isLoading = true; _error = null; });

    try {
      await ref.read(authProvider.notifier).verifyOTP(
        _emailCtrl.text.trim(),
        otp,
      );
    } catch (e) {
      setState(() => _error = 'Invalid or expired OTP code. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── UI Builders ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          // Background design halos
          Positioned(
            top: -100, right: -60,
            child: Container(
              width: 300, height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFC5D9EB).withValues(alpha: 0.3),
              ),
            ),
          ),
          Positioned(
            bottom: -80, left: -80,
            child: Container(
              width: 250, height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFC5D9EB).withValues(alpha: 0.2),
              ),
            ),
          ),
          // Main content
          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  // Logo / Brand Header
                  Center(
                    child: Column(
                      children: [
                        Container(
                          width: 58, height: 58,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: MemberTheme.mSlate.withValues(alpha: 0.12),
                            border: Border.all(
                                color: MemberTheme.mDarkCharcoal, width: 2),
                          ),
                          child: const Icon(Icons.school_rounded,
                              size: 28, color: MemberTheme.mDarkCharcoal),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _getStepTitle(),
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 24, fontWeight: FontWeight.bold, color: MemberTheme.mDarkCharcoal,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'ISTE Student Chapter Member Portal',
                          style: GoogleFonts.inter(
                            fontSize: 13, color: MemberTheme.mDarkCharcoal.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_successMessage != null) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.green.withValues(alpha: 0.25)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.check_circle_outline_rounded,
                                      size: 16, color: Colors.green),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(_successMessage!,
                                        style: GoogleFonts.inter(
                                            fontSize: 13, color: Colors.green)),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          _buildCurrentStepView(),

                          if (_error != null) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.error_outline_rounded,
                                      size: 16, color: Colors.redAccent),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(_error!,
                                        style: GoogleFonts.inter(
                                            fontSize: 13, color: Colors.redAccent)),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 24),

                          // CTA Button
                          SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: _isLoading
                                ? Container(
                                    decoration: BoxDecoration(
                                      color: MemberTheme.mSlate.withValues(alpha: 0.3),
                                      borderRadius: BorderRadius.circular(28),
                                    ),
                                    child: const Center(
                                      child: CircularProgressIndicator(
                                          color: MemberTheme.mSlate, strokeWidth: 2.5),
                                    ),
                                  )
                                : ElevatedButton(
                                    onPressed: _handleNextStepAction,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: MemberTheme.mDarkCharcoal,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(28)),
                                      elevation: 0,
                                    ),
                                    child: Text(
                                      _getButtonText(),
                                      style: GoogleFonts.spaceGrotesk(
                                          fontSize: 16, fontWeight: FontWeight.w700),
                                    ),
                                  ),
                          ),

                          _buildBackLink(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getStepTitle() {
    switch (_currentStep) {
      case AuthStep.emailEntry:
        return 'Sign In';
      case AuthStep.isteOtpVerify:
        return 'Verify Email';
      case AuthStep.guestRegistration:
        return 'Guest Registration';
      case AuthStep.guestOtpVerify:
        return 'Verify OTP';
    }
  }

  Widget _buildCurrentStepView() {
    switch (_currentStep) {
      case AuthStep.emailEntry:
        final emailText = _emailCtrl.text.trim().toLowerCase();
        final isEmailValid = emailText.contains('@') && emailText.contains('.');
        final isIsteMember = isEmailValid && isIsteMemberEmail(emailText);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Email Address', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: MemberTheme.mDarkCharcoal)),
            const SizedBox(height: 8),
            _buildField(controller: _emailCtrl, hint: 'your@email.com', icon: Icons.email_outlined, keyboardType: TextInputType.emailAddress, autofocus: true),
            const SizedBox(height: 12),

            // Live member detection indicator
            if (isEmailValid)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isIsteMember ? Colors.green.withValues(alpha: 0.1) : Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: isIsteMember ? Colors.green.withValues(alpha: 0.3) : Colors.orange.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(isIsteMember ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                        size: 16, color: isIsteMember ? Colors.green : Colors.orange),
                    const SizedBox(width: 8),
                    Text(
                      isIsteMember ? '✓ ISTE Member Account Detected' : 'Guest Account Detected',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 12, fontWeight: FontWeight.w700,
                        color: isIsteMember ? Colors.green.shade800 : Colors.orange.shade800,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );

      case AuthStep.isteOtpVerify:
      case AuthStep.guestOtpVerify:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_membershipTag != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: _membershipTag == 'iste_member'
                      ? Colors.blue.withValues(alpha: 0.1)
                      : Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _membershipTag == 'iste_member'
                        ? Colors.blue.withValues(alpha: 0.3)
                        : Colors.orange.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _membershipTag == 'iste_member' ? Icons.workspace_premium_rounded : Icons.person_outline_rounded,
                      size: 14,
                      color: _membershipTag == 'iste_member' ? Colors.blue : Colors.orange,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _membershipTag == 'iste_member' ? 'ISTE Member' : 'Guest Account',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 12, fontWeight: FontWeight.bold,
                        color: _membershipTag == 'iste_member' ? Colors.blue : Colors.orange,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            Text(
              'We sent a verification code to ${_emailCtrl.text}',
              style: GoogleFonts.inter(fontSize: 14, color: MemberTheme.mDarkCharcoal.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 20),
            _buildField(controller: _otpCtrl, hint: '••••••••', icon: Icons.lock_outlined, keyboardType: TextInputType.number, autofocus: true, maxLength: 8),
          ],
        );

      case AuthStep.guestRegistration:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('No ISTE membership record was found for ${_emailCtrl.text}. Register as a guest below:',
                style: GoogleFonts.inter(fontSize: 13, color: MemberTheme.mDarkCharcoal.withValues(alpha: 0.6))),
            const SizedBox(height: 16),
            _buildField(controller: _nameCtrl, hint: 'Full Name', icon: Icons.person_outline),
            const SizedBox(height: 12),
            _buildField(controller: _phoneCtrl, hint: 'Phone Number (+91)', icon: Icons.phone_outlined, keyboardType: TextInputType.phone),
            const SizedBox(height: 12),
            _buildField(controller: _regNoCtrl, hint: 'University Roll Number', icon: Icons.badge_outlined),
            const SizedBox(height: 12),
            _buildField(controller: _collegeCtrl, hint: 'College Name', icon: Icons.account_balance_outlined),
          ],
        );
    }
  }

  void _handleNextStepAction() {
    switch (_currentStep) {
      case AuthStep.emailEntry:
        _handleEmailContinue();
        break;
      case AuthStep.isteOtpVerify:
      case AuthStep.guestOtpVerify:
        _handleOtpVerify();
        break;
      case AuthStep.guestRegistration:
        _handleGuestRegister();
        break;
    }
  }

  String _getButtonText() {
    switch (_currentStep) {
      case AuthStep.emailEntry:
        return 'Continue →';
      case AuthStep.isteOtpVerify:
      case AuthStep.guestOtpVerify:
        return 'Verify OTP →';
      case AuthStep.guestRegistration:
        return 'Register & Send OTP →';
    }
  }

  Widget _buildBackLink() {
    if (_currentStep == AuthStep.emailEntry) {
      return const SizedBox.shrink();
    }
    return Column(
      children: [
        const SizedBox(height: 12),
        Center(
          child: TextButton.icon(
            onPressed: () {
              setState(() {
                _error = null;
                _successMessage = null;
                _otpCtrl.clear();
              });
              if (_currentStep == AuthStep.guestOtpVerify && _membershipTag == 'guest') {
                _changeStep(AuthStep.guestRegistration);
              } else {
                _changeStep(AuthStep.emailEntry);
              }
            },
            icon: const Icon(Icons.arrow_back_rounded, size: 16, color: MemberTheme.mDarkCharcoal),
            label: Text(
              _currentStep == AuthStep.guestOtpVerify && _membershipTag == 'guest'
                  ? 'Back to registration details'
                  : 'Back to email entry',
              style: GoogleFonts.inter(color: MemberTheme.mDarkCharcoal, fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool enabled = true,
    TextInputType? keyboardType,
    int? maxLength,
    bool autofocus = false,
  }) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      maxLength: maxLength,
      autofocus: autofocus,
      style: GoogleFonts.inter(
        color: enabled ? MemberTheme.mDarkCharcoal : MemberTheme.mDarkCharcoal.withValues(alpha: 0.38),
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.inter(
          color: MemberTheme.mDarkCharcoal.withValues(alpha: 0.3),
          fontSize: 14,
        ),
        prefixIcon: Icon(
          icon,
          size: 20,
          color: MemberTheme.mDarkCharcoal.withValues(alpha: 0.38),
        ),
        counterText: '',
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFD3E3F0), width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFD3E3F0), width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: MemberTheme.mDarkCharcoal, width: 2),
        ),
      ),
    );
  }
}
