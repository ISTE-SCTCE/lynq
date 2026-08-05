import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme.dart';

enum AuthStep {
  emailEntry,
  isteOtpVerify,      // NEW: OTP gate before first-time ISTE password creation
  istePasswordCreate,
  isteLogin,
  guestRegistration,
  guestOtpVerify
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

  // Controllers
  final _emailCtrl = TextEditingController();
  final _otpCtrl   = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _nameCtrl  = TextEditingController();
  final _regNoCtrl = TextEditingController();
  final _collegeCtrl = TextEditingController();
  final _isteIdCtrl  = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _isLoading = false;
  String? _error;
  String? _successMessage;

  static const _bg = MemberTheme.mBackground;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _fadeAnim = CurvedAnimation(
        parent: _animController, curve: Curves.easeOutCubic);
    _animController.forward();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _otpCtrl.dispose();
    _phoneCtrl.dispose();
    _nameCtrl.dispose();
    _regNoCtrl.dispose();
    _collegeCtrl.dispose();
    _isteIdCtrl.dispose();
    _passwordCtrl.dispose();
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

  Future<void> _checkEmail() async {
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

      if (membership == null) {
        // No members row → guest registration
        _changeStep(AuthStep.guestRegistration);
        return;
      }

      final String status = membership['status'] as String? ?? '';

      switch (status) {
        case 'member_otp_login':
          // Member: send OTP to log in directly (auto-create auth user if first time)
          await ref.read(authProvider.notifier).requestOTP(email, isSignUp: true);
          setState(() {
            _successMessage = 'A verification code was sent to $email. Enter it to log in.';
          });
          _changeStep(AuthStep.guestOtpVerify);
          break;

        case 'guest_login':
          // Existing guest: send OTP to log in directly
          await ref.read(authProvider.notifier).requestOTP(email, isSignUp: false);
          setState(() {
            _successMessage = 'A verification code was sent to $email. Enter it to log in.';
          });
          _changeStep(AuthStep.guestOtpVerify);
          break;

        case 'pending_iste_id':
          // Members row exists but iste_id not yet assigned by admin
          setState(() {
            _error = 'Your ISTE membership is registered but your ISTE ID hasn\'t been issued yet. '
                     'Please contact your execom to get your ID assigned.';
          });
          break;

        case 'execom_unactivated':
          // Execom member row exists but no auth account has been created via lynq
          setState(() {
            _error = 'Your execom account has not been activated yet. '
                     'Please contact your chapter admin to set up your account in the execom app.';
          });
          break;

        case 'login':
          // Account exists and has a password → go to login
          _isteIdCtrl.text = membership['iste_id'] ?? '';
          _nameCtrl.text = membership['name'] ?? '';
          _changeStep(AuthStep.isteLogin);
          break;

        case 'otp_required':
          // First-time member: send OTP to verify email before allowing password creation
          _isteIdCtrl.text = membership['iste_id'] ?? '';
          _nameCtrl.text  = membership['name'] ?? '';
          _phoneCtrl.text = membership['phone'] ?? '';

          // Send OTP for email ownership verification
          await ref.read(authProvider.notifier).requestIsteMemberOTP(email);

          setState(() {
            _successMessage =
                'A verification code was sent to $email. Enter it below to confirm your email.';
          });
          _changeStep(AuthStep.isteOtpVerify);
          break;

        default:
          // Fallback — treat as guest
          _changeStep(AuthStep.guestRegistration);
      }
    } catch (e) {
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Verify the OTP sent to the ISTE member's email, then proceed to password creation.
  Future<void> _verifyIsteMemberOtp() async {
    final otp = _otpCtrl.text.trim();
    if (otp.isEmpty) {
      setState(() => _error = 'Please enter the verification code');
      return;
    }

    setState(() { _isLoading = true; _error = null; });

    try {
      await ref.read(authProvider.notifier).verifyIsteMemberOTP(
        _emailCtrl.text.trim(),
        otp,
      );
      _otpCtrl.clear();
      setState(() {
        _successMessage = 'Email verified! Now set a password for your ISTE account.';
      });
      _changeStep(AuthStep.istePasswordCreate);
    } catch (e) {
      setState(() => _error = 'Invalid or expired verification code. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _createPassword() async {
    final password = _passwordCtrl.text;
    if (password.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters');
      return;
    }

    setState(() { _isLoading = true; _error = null; });

    try {
      await ref.read(authProvider.notifier).registerIsteMemberWithPassword(
        _emailCtrl.text.trim(),
        password,
        {
          'iste_id': _isteIdCtrl.text.trim(),
          'name':    _nameCtrl.text.trim(),
          'phone':   _phoneCtrl.text.trim(),
        },
      );

      // Sign out to force them to log in explicitly
      await ref.read(authProvider.notifier).signOut();
      _passwordCtrl.clear();

      setState(() {
        _successMessage = 'Password set successfully! Please log in below.';
      });
      _changeStep(AuthStep.isteLogin);
    } catch (e) {
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loginMember() async {
    final password = _passwordCtrl.text;
    if (password.isEmpty) {
      setState(() => _error = 'Please enter your password');
      return;
    }

    setState(() { _isLoading = true; _error = null; });

    try {
      await ref.read(authProvider.notifier).loginIsteMemberWithPassword(
        _isteIdCtrl.text.trim(),
        password,
      );
    } catch (e) {
      final msg = e.toString().replaceAll('Exception: ', '');
      setState(() => _error = msg.contains('set up for this ISTE ID')
          ? msg
          : 'Invalid credentials. Please verify your password.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signUpGuest() async {
    if (_nameCtrl.text.trim().isEmpty ||
        _phoneCtrl.text.trim().isEmpty ||
        _regNoCtrl.text.trim().isEmpty ||
        _collegeCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Please fill all required fields');
      return;
    }

    setState(() { _isLoading = true; _error = null; });

    try {
      // Persist signup form data BEFORE sending OTP so it survives app kills
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

      _changeStep(AuthStep.guestOtpVerify);
    } catch (e) {
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyGuestOtp() async {
    final otp = _otpCtrl.text.trim();
    if (otp.isEmpty) {
      setState(() => _error = 'Please enter the OTP');
      return;
    }

    setState(() { _isLoading = true; _error = null; });

    try {
      await ref.read(authProvider.notifier).verifyOTP(
        _emailCtrl.text.trim(),
        otp,
      );
    } catch (e) {
      setState(() => _error = 'Invalid OTP code. Please try again.');
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
          // Background soft design halo
          Positioned(
            top: -100, right: -60,
            child: Container(
              width: 300, height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFC5D9EB).withOpacity(0.3),
              ),
            ),
          ),
          Positioned(
            bottom: -80, left: -80,
            child: Container(
              width: 250, height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFC5D9EB).withOpacity(0.2),
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
                  // Logo / Brand
                  Center(
                    child: Column(
                      children: [
                        Container(
                          width: 60, height: 60,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: MemberTheme.mSlate.withOpacity(0.12),
                            border: Border.all(
                                color: MemberTheme.mDarkCharcoal, width: 2),
                          ),
                          child: const Icon(Icons.school_rounded,
                              size: 28, color: MemberTheme.mDarkCharcoal),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'ISTE Member',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 24, fontWeight: FontWeight.bold, color: MemberTheme.mDarkCharcoal,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_successMessage != null) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.green.withOpacity(0.25)),
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
                                color: Colors.red.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.red.withOpacity(0.25)),
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
                          const SizedBox(height: 28),

                          // CTA Button — only show if the current step has an action
                          // (info-only states like pending_iste_id don't need a button)
                          if (_hasActionButton())
                            SizedBox(
                              width: double.infinity,
                              height: 56,
                              child: _isLoading
                                  ? Container(
                                      decoration: BoxDecoration(
                                        color: MemberTheme.mSlate.withOpacity(0.3),
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
                                            fontSize: 17, fontWeight: FontWeight.w700),
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

  Widget _buildCurrentStepView() {
    switch (_currentStep) {
      case AuthStep.emailEntry:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sign In', style: GoogleFonts.spaceGrotesk(fontSize: 22, fontWeight: FontWeight.bold, color: MemberTheme.mDarkCharcoal)),
            const SizedBox(height: 8),
            Text('Enter your email address to continue registration or login.', style: GoogleFonts.inter(fontSize: 14, color: MemberTheme.mDarkCharcoal.withOpacity(0.5))),
            const SizedBox(height: 24),
            _buildField(controller: _emailCtrl, hint: 'Email Address', icon: Icons.email_outlined, keyboardType: TextInputType.emailAddress),
          ],
        );

      case AuthStep.isteOtpVerify:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Verify Your Email', style: GoogleFonts.spaceGrotesk(fontSize: 22, fontWeight: FontWeight.bold, color: MemberTheme.mDarkCharcoal)),
            const SizedBox(height: 8),
            Text(
              'We sent a verification code to ${_emailCtrl.text} to confirm you own this ISTE member email.',
              style: GoogleFonts.inter(fontSize: 14, color: MemberTheme.mDarkCharcoal.withOpacity(0.5)),
            ),
            const SizedBox(height: 28),
            _buildField(controller: _otpCtrl, hint: 'Verification Code', icon: Icons.lock_outlined, keyboardType: TextInputType.number, autofocus: true),
          ],
        );

      case AuthStep.istePasswordCreate:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Create Password', style: GoogleFonts.spaceGrotesk(fontSize: 22, fontWeight: FontWeight.bold, color: MemberTheme.mDarkCharcoal)),
            const SizedBox(height: 8),
            Text('Hi ${_nameCtrl.text}, set a secure password to claim your ISTE account (${_isteIdCtrl.text}).', style: GoogleFonts.inter(fontSize: 14, color: MemberTheme.mDarkCharcoal.withOpacity(0.5))),
            const SizedBox(height: 24),
            _buildField(controller: _emailCtrl, hint: 'Email', icon: Icons.email_outlined, enabled: false),
            const SizedBox(height: 16),
            _buildField(controller: _passwordCtrl, hint: 'New Password (min 6 chars)', icon: Icons.lock_outline, isPassword: true),
          ],
        );

      case AuthStep.isteLogin:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Member Login', style: GoogleFonts.spaceGrotesk(fontSize: 22, fontWeight: FontWeight.bold, color: MemberTheme.mDarkCharcoal)),
            const SizedBox(height: 8),
            Text('Enter your password to sign in.', style: GoogleFonts.inter(fontSize: 14, color: MemberTheme.mDarkCharcoal.withOpacity(0.5))),
            const SizedBox(height: 24),
            _buildField(controller: _isteIdCtrl, hint: 'ISTE Membership ID', icon: Icons.card_membership, enabled: false),
            const SizedBox(height: 16),
            _buildField(controller: _passwordCtrl, hint: 'Password', icon: Icons.lock_outline, isPassword: true),
          ],
        );

      case AuthStep.guestRegistration:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Guest Registration', style: GoogleFonts.spaceGrotesk(fontSize: 22, fontWeight: FontWeight.bold, color: MemberTheme.mDarkCharcoal)),
            const SizedBox(height: 8),
            Text('No ISTE membership found for this email. Sign up as a guest below.', style: GoogleFonts.inter(fontSize: 14, color: MemberTheme.mDarkCharcoal.withOpacity(0.5))),
            const SizedBox(height: 24),
            _buildField(controller: _emailCtrl, hint: 'Email Address', icon: Icons.email_outlined, enabled: false),
            const SizedBox(height: 16),
            _buildField(controller: _nameCtrl, hint: 'Full Name', icon: Icons.person_outline),
            const SizedBox(height: 16),
            _buildField(controller: _phoneCtrl, hint: 'Phone Number', icon: Icons.phone_outlined, keyboardType: TextInputType.phone),
            const SizedBox(height: 16),
            _buildField(controller: _regNoCtrl, hint: 'University Roll Number', icon: Icons.badge_outlined),
            const SizedBox(height: 16),
            _buildField(controller: _collegeCtrl, hint: 'College Name', icon: Icons.account_balance_outlined),
          ],
        );

      case AuthStep.guestOtpVerify:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Verify OTP', style: GoogleFonts.spaceGrotesk(fontSize: 22, fontWeight: FontWeight.bold, color: MemberTheme.mDarkCharcoal)),
            const SizedBox(height: 8),
            Text('A verification code was sent to ${_emailCtrl.text}.', style: GoogleFonts.inter(fontSize: 14, color: MemberTheme.mDarkCharcoal.withOpacity(0.5))),
            const SizedBox(height: 28),
            _buildField(controller: _otpCtrl, hint: 'OTP Code', icon: Icons.lock_outlined, keyboardType: TextInputType.number, autofocus: true),
          ],
        );
    }
  }

  bool _hasActionButton() => _currentStep != AuthStep.emailEntry || true;
  // emailEntry always has Continue; info states fall through because the error
  // message is displayed instead and the button text is still 'Continue' to
  // let user try a different email — so always return true.

  void _handleNextStepAction() {
    switch (_currentStep) {
      case AuthStep.emailEntry:
        _checkEmail();
        break;
      case AuthStep.isteOtpVerify:
        _verifyIsteMemberOtp();
        break;
      case AuthStep.istePasswordCreate:
        _createPassword();
        break;
      case AuthStep.isteLogin:
        _loginMember();
        break;
      case AuthStep.guestRegistration:
        _signUpGuest();
        break;
      case AuthStep.guestOtpVerify:
        _verifyGuestOtp();
        break;
    }
  }

  String _getButtonText() {
    switch (_currentStep) {
      case AuthStep.emailEntry:
        return 'Continue';
      case AuthStep.isteOtpVerify:
        return 'Verify & Continue';
      case AuthStep.istePasswordCreate:
        return 'Create Password';
      case AuthStep.isteLogin:
        return 'Log In';
      case AuthStep.guestRegistration:
        return 'Register & Send OTP';
      case AuthStep.guestOtpVerify:
        return 'Verify OTP';
    }
  }

  Widget _buildBackLink() {
    if (_currentStep == AuthStep.emailEntry) {
      return const SizedBox.shrink();
    }
    // For OTP steps, "Change details" goes back one level; others go to email entry
    final bool isOtpStep = _currentStep == AuthStep.guestOtpVerify ||
        _currentStep == AuthStep.isteOtpVerify;
    return Column(
      children: [
        const SizedBox(height: 16),
        Center(
          child: TextButton(
            onPressed: () {
              if (_currentStep == AuthStep.guestOtpVerify) {
                _changeStep(AuthStep.guestRegistration);
              } else if (_currentStep == AuthStep.isteOtpVerify) {
                _changeStep(AuthStep.emailEntry);
              } else if (_currentStep == AuthStep.istePasswordCreate) {
                // Can't go back from password creation after OTP verified —
                // they'd need to restart. Go back to email.
                _changeStep(AuthStep.emailEntry);
              } else {
                _changeStep(AuthStep.emailEntry);
              }
            },
            child: Text(
              isOtpStep ? 'Change details' : 'Go back to email entry',
              style: GoogleFonts.inter(color: MemberTheme.mDarkCharcoal.withOpacity(0.5), fontSize: 13),
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
    bool isPassword = false,
  }) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      maxLength: maxLength,
      autofocus: autofocus,
      obscureText: isPassword,
      style: GoogleFonts.inter(
        color: enabled ? MemberTheme.mDarkCharcoal : MemberTheme.mDarkCharcoal.withOpacity(0.38),
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.inter(
          color: MemberTheme.mDarkCharcoal.withOpacity(0.3),
          fontSize: 14,
        ),
        prefixIcon: Icon(
          icon,
          size: 20,
          color: MemberTheme.mDarkCharcoal.withOpacity(0.38),
        ),
        counterText: '',
      ),
    );
  }
}
