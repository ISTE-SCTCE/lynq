import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  // Shared Controllers
  final _emailCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();

  // Sign Up Only Controllers
  final _regNoCtrl = TextEditingController();
  final _collegeCtrl = TextEditingController();
  final _isteIdCtrl = TextEditingController();

  bool _otpSent = false;
  bool _isLoading = false;
  String? _error;

  static const _terracotta = Color(0xFFD97D55);
  static const _cream = Color(0xFFF4E9D7);
  static const _teal = Color(0xFF6FA4AF);
  static const _bg = Color(0xFF141414);
  static const _surface = Color(0xFF1E1E1E);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() {
          _otpSent = false;
          _error = null;
        });
      }
    });

    _animController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _fadeAnim = CurvedAnimation(
        parent: _animController, curve: Curves.easeOutCubic);
    _animController.forward();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _emailCtrl.dispose();
    _otpCtrl.dispose();
    _phoneCtrl.dispose();
    _nameCtrl.dispose();
    _regNoCtrl.dispose();
    _collegeCtrl.dispose();
    _isteIdCtrl.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _sendOTP() async {
    if (_emailCtrl.text.trim().isEmpty ||
        _nameCtrl.text.trim().isEmpty ||
        _phoneCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Please fill all required fields');
      return;
    }

    if (_tabController.index == 1) {
      // Sign Up specific validation
      if (_regNoCtrl.text.trim().isEmpty || _collegeCtrl.text.trim().isEmpty) {
        setState(() => _error = 'Registration Number and College are required');
        return;
      }
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Set signup profile data in provider temporarily
      if (_tabController.index == 1) {
        ref.read(authProvider.notifier).setPendingSignUpData({
          'name': _nameCtrl.text.trim(),
          'phone': _phoneCtrl.text.trim(),
          'roll_number': _regNoCtrl.text.trim(),
          'college': _collegeCtrl.text.trim(),
          'iste_id': _isteIdCtrl.text.trim(),
        });
      }

      await ref.read(authProvider.notifier).requestOTP(
        _emailCtrl.text.trim(),
        isSignUp: _tabController.index == 1,
      );
      setState(() {
        _otpSent = true;
        _isLoading = false;
      });
      _animController.forward(from: 0);
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<void> _verifyOTP() async {
    if (_otpCtrl.text.trim().isEmpty) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await ref.read(authProvider.notifier).verifyOTP(
        _emailCtrl.text.trim(),
        _otpCtrl.text.trim(),
      );
    } catch (e) {
      setState(() {
        _error = 'Invalid OTP. Please try again.';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          // Background orbs
          Positioned(
            top: -100, right: -60,
            child: Container(
              width: 300, height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  _terracotta.withValues(alpha: 0.15),
                  Colors.transparent,
                ]),
              ),
            ),
          ),
          Positioned(
            bottom: -80, left: -80,
            child: Container(
              width: 250, height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  _teal.withValues(alpha: 0.12),
                  Colors.transparent,
                ]),
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
                            gradient: LinearGradient(
                              colors: [
                                _terracotta.withValues(alpha: 0.3),
                                _teal.withValues(alpha: 0.2),
                              ],
                            ),
                            border: Border.all(
                                color: _terracotta.withValues(alpha: 0.4), width: 2),
                          ),
                          child: const Icon(Icons.school_rounded,
                              size: 28, color: _terracotta),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'ISTE Member',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 24, fontWeight: FontWeight.bold, color: _cream,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  // Tabs
                  if (!_otpSent)
                    TabBar(
                      controller: _tabController,
                      indicatorColor: _terracotta,
                      labelColor: _terracotta,
                      unselectedLabelColor: Colors.white38,
                      labelStyle: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, fontSize: 16),
                      tabs: const [
                        Tab(text: 'Sign In'),
                        Tab(text: 'Sign Up'),
                      ],
                    ),

                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_otpSent) ...[
                            Text(
                              'Enter your OTP',
                              style: GoogleFonts.spaceGrotesk(
                                  fontSize: 22, fontWeight: FontWeight.bold, color: _cream),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'An 8-digit code was sent to ${_emailCtrl.text}',
                              style: GoogleFonts.inter(fontSize: 14, color: Colors.white38),
                            ),
                            const SizedBox(height: 28),
                            _buildField(
                              controller: _otpCtrl,
                              hint: '8-digit OTP code',
                              icon: Icons.lock_outlined,
                              keyboardType: TextInputType.number,
                              maxLength: 8,
                              autofocus: true,
                            ),
                          ] else ...[
                            _buildField(
                              controller: _nameCtrl,
                              hint: 'Full Name',
                              icon: Icons.person_outline,
                            ),
                            const SizedBox(height: 16),
                            _buildField(
                              controller: _phoneCtrl,
                              hint: 'Phone Number',
                              icon: Icons.phone_outlined,
                              keyboardType: TextInputType.phone,
                            ),
                            const SizedBox(height: 16),
                            _buildField(
                              controller: _emailCtrl,
                              hint: 'Email Address',
                              icon: Icons.email_outlined,
                              keyboardType: TextInputType.emailAddress,
                            ),
                            
                            // Sign Up specific fields
                            if (_tabController.index == 1) ...[
                              const SizedBox(height: 16),
                              _buildField(
                                controller: _regNoCtrl,
                                hint: 'University Reg Number',
                                icon: Icons.badge_outlined,
                              ),
                              const SizedBox(height: 16),
                              _buildField(
                                controller: _collegeCtrl,
                                hint: 'College of Study',
                                icon: Icons.account_balance_outlined,
                              ),
                              const SizedBox(height: 16),
                              _buildField(
                                controller: _isteIdCtrl,
                                hint: 'ISTE Membership ID (Optional)',
                                icon: Icons.card_membership,
                              ),
                            ],
                          ],

                          if (_error != null) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
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
                                      color: _terracotta.withValues(alpha: 0.3),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: const Center(
                                      child: CircularProgressIndicator(
                                          color: _terracotta, strokeWidth: 2),
                                    ),
                                  )
                                : ElevatedButton(
                                    onPressed: _otpSent ? _verifyOTP : _sendOTP,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _terracotta,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(16)),
                                      elevation: 0,
                                    ),
                                    child: Text(
                                      _otpSent ? 'Verify OTP' : (_tabController.index == 0 ? 'Send OTP' : 'Sign Up'),
                                      style: GoogleFonts.spaceGrotesk(
                                          fontSize: 17, fontWeight: FontWeight.w700),
                                    ),
                                  ),
                          ),
                          if (_otpSent) ...[
                            const SizedBox(height: 16),
                            Center(
                              child: TextButton(
                                onPressed: () => setState(() {
                                  _otpSent = false;
                                  _otpCtrl.clear();
                                  _error = null;
                                }),
                                child: Text(
                                  'Change email',
                                  style: GoogleFonts.inter(color: Colors.white38, fontSize: 13),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 32),
                          if (!_otpSent && _tabController.index == 0)
                            Center(
                              child: OutlinedButton.icon(
                                onPressed: () => context.push('/link-web'),
                                icon: const Icon(Icons.link, color: Colors.white70),
                                label: Text('Link Website Account', style: GoogleFonts.inter(color: Colors.white70)),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Colors.white24),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                ),
                              ),
                            ),
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

  Widget _buildField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool enabled = true,
    TextInputType? keyboardType,
    int? maxLength,
    bool autofocus = false,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: _surface.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: TextField(
          controller: controller,
          enabled: enabled,
          keyboardType: keyboardType,
          maxLength: maxLength,
          autofocus: autofocus,
          style: GoogleFonts.inter(color: enabled ? Colors.white : Colors.white38),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.inter(color: Colors.white24, fontSize: 14),
            prefixIcon: Icon(icon, size: 20, color: Colors.white38),
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            counterText: '',
          ),
        ),
      ),
    );
  }
}
