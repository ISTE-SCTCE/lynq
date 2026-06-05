import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme.dart';

enum AuthStep {
  emailEntry,
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
  final _otpCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _regNoCtrl = TextEditingController();
  final _collegeCtrl = TextEditingController();
  final _isteIdCtrl = TextEditingController();
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

  // --- Step Actions ---

  Future<void> _checkEmail() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Please enter your email address');
      return;
    }
    // Simple email format validation
    if (!email.contains('@') || !email.contains('.')) {
      setState(() => _error = 'Please enter a valid email address');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final membership = await ref.read(authProvider.notifier).checkEmailMembership(email);
      if (membership != null) {
        final bool hasPassword = membership['has_password'] == true;
        final String role = membership['role'] ?? 'member';
        _isteIdCtrl.text = membership['iste_id'] ?? '';
        
        final bool isExecom = role != 'member' && role != 'user';

        if (isExecom) {
          // Execom members should already have an account from the lynq app.
          // They just need to log in.
          _changeStep(AuthStep.isteLogin);
        } else {
          // General members need to create a password on their first login.
          if (hasPassword) {
            // Already created a password previously, just log in
            _changeStep(AuthStep.isteLogin);
          } else {
            // First time, create a password
            _nameCtrl.text = membership['name'] ?? '';
            _phoneCtrl.text = membership['phone'] ?? '';
            _changeStep(AuthStep.istePasswordCreate);
          }
        }
      } else {
        // Case 2: Non-ISTE Member Registration
        _changeStep(AuthStep.guestRegistration);
      }
    } catch (e) {
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
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

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Register with password
      await ref.read(authProvider.notifier).registerIsteMemberWithPassword(
        _emailCtrl.text.trim(),
        password,
        {
          'iste_id': _isteIdCtrl.text.trim(),
          'name': _nameCtrl.text.trim(),
          'phone': _phoneCtrl.text.trim(),
        },
      );

      // Sign out to force them to log in on the login screen
      await ref.read(authProvider.notifier).signOut();

      // Clear password field for login prompt
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

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await ref.read(authProvider.notifier).loginIsteMemberWithPassword(
        _isteIdCtrl.text.trim(),
        password,
      );
    } catch (e) {
      setState(() => _error = 'Invalid credentials. Please verify your password.');
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

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Temporarily store sign up info
      ref.read(authProvider.notifier).setPendingSignUpData({
        'name': _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'roll_number': _regNoCtrl.text.trim(),
        'college': _collegeCtrl.text.trim(),
      });

      // Request OTP
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

  Future<void> _verifyOtp() async {
    final otp = _otpCtrl.text.trim();
    if (otp.isEmpty) {
      setState(() => _error = 'Please enter the OTP');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

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

  // --- UI Builders ---

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
                          
                          // CTA Button
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

  void _handleNextStepAction() {
    switch (_currentStep) {
      case AuthStep.emailEntry:
        _checkEmail();
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
        _verifyOtp();
        break;
    }
  }

  String _getButtonText() {
    switch (_currentStep) {
      case AuthStep.emailEntry:
        return 'Continue';
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
    return Column(
      children: [
        const SizedBox(height: 16),
        Center(
          child: TextButton(
            onPressed: () {
              if (_currentStep == AuthStep.guestOtpVerify) {
                _changeStep(AuthStep.guestRegistration);
              } else {
                _changeStep(AuthStep.emailEntry);
              }
            },
            child: Text(
              _currentStep == AuthStep.guestOtpVerify ? 'Change details' : 'Go back to email entry',
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
