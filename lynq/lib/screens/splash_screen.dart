import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:flutter/physics.dart';
import '../core/theme.dart';
import '../core/auth_provider.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _entranceController;
  late AnimationController _exitController;

  // Entrance animations
  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;
  late Animation<double> _logoBlur;
  late Animation<Offset> _titleSlide;
  late Animation<double> _titleOpacity;
  late Animation<double> _taglineOpacity;
  late Animation<Offset> _taglineSlide;

  // Exit animations
  late Animation<double> _exitScale;
  late Animation<double> _exitOpacity;

  bool _isExiting = false;

  @override
  void initState() {
    super.initState();
    
    // Premium Entrance: 2.0 seconds total with spring-like feel
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    // Apple-style swift exit: 600ms smooth fade/scale out
    _exitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _setupAnimations();

    _entranceController.forward().then((_) {
      _checkLoadingStateAndExit();
    });
  }

  void _setupAnimations() {
    // Elegant spring-based scale and blur reveal for logo
    _logoScale = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _entranceController, curve: const Interval(0.0, 0.6, curve: Curves.easeOutBack)),
    );
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _entranceController, curve: const Interval(0.0, 0.4, curve: Curves.easeOut)),
    );
    _logoBlur = Tween<double>(begin: 10.0, end: 0.0).animate(
      CurvedAnimation(parent: _entranceController, curve: const Interval(0.0, 0.5, curve: Curves.easeOut)),
    );

    // Title gracefully floats up
    _titleSlide = Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(
      CurvedAnimation(parent: _entranceController, curve: const Interval(0.3, 0.8, curve: Curves.easeOutCubic)),
    );
    _titleOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _entranceController, curve: const Interval(0.3, 0.7, curve: Curves.easeIn)),
    );

    // Tagline delicately fades and slides in
    _taglineSlide = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
      CurvedAnimation(parent: _entranceController, curve: const Interval(0.5, 0.9, curve: Curves.easeOutCubic)),
    );
    _taglineOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _entranceController, curve: const Interval(0.5, 0.9, curve: Curves.easeIn)),
    );

    // Exit transforms - slight scale up and smooth alpha fade
    _exitScale = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _exitController, curve: Curves.easeInCubic),
    );
    _exitOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _exitController, curve: Curves.easeInQuad),
    );
  }

  void _checkLoadingStateAndExit() {
    if (!mounted) return;
    
    final authProvider = context.read<AuthProvider>();
    
    if (authProvider.isLoading) {
      authProvider.addListener(_onAuthLoadingChanged);
      setState(() {});
    } else {
      _triggerExit();
    }
  }

  void _onAuthLoadingChanged() {
    if (!mounted) return;
    final authProvider = context.read<AuthProvider>();
    if (!authProvider.isLoading) {
      authProvider.removeListener(_onAuthLoadingChanged);
      _triggerExit();
    }
  }

  void _triggerExit() {
    if (_isExiting) return;
    setState(() {
      _isExiting = true;
    });
    _exitController.forward().then((_) {
      if (mounted) {
        context.read<AuthProvider>().hideSplash();
      }
    });
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _exitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Hardcoded to #1E1E1E per user requirements for the premium look
    const bgColor = Color(0xFF1E1E1E);
    const primaryColor = Colors.white;
    
    return Scaffold(
      backgroundColor: bgColor,
      body: AnimatedBuilder(
        animation: Listenable.merge([_entranceController, _exitController]),
        builder: (context, child) {
          return FadeTransition(
            opacity: _exitOpacity,
            child: ScaleTransition(
              scale: _exitScale,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    RepaintBoundary(
                      child: ImageFilterBlur(
                        blur: _logoBlur.value,
                        child: FadeTransition(
                          opacity: _logoOpacity,
                          child: ScaleTransition(
                            scale: _logoScale,
                            child: Image.asset(
                              'assets/images/logo-lynq.png',
                              width: 110,
                              height: 110,
                              fit: BoxFit.contain,
                              color: primaryColor,
                              errorBuilder: (context, error, stackTrace) => const Icon(
                                Icons.link_rounded,
                                size: 90,
                                color: primaryColor,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    RepaintBoundary(
                      child: SlideTransition(
                        position: _titleSlide,
                        child: FadeTransition(
                          opacity: _titleOpacity,
                          child: const Text(
                            'lynq',
                            style: TextStyle(
                              fontFamily: 'Qurova',
                              fontSize: 48,
                              color: primaryColor,
                              letterSpacing: 6.0,
                              fontWeight: FontWeight.w300,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    RepaintBoundary(
                      child: SlideTransition(
                        position: _taglineSlide,
                        child: FadeTransition(
                          opacity: _taglineOpacity,
                          child: Text(
                            'Connect. Coordinate. Lead.',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              color: Colors.white60,
                              fontWeight: FontWeight.w400,
                              letterSpacing: 2.0,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 72),
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeInOut,
                      opacity: (_entranceController.isCompleted && !_isExiting) ? 1.0 : 0.0,
                      child: const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white24,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class ImageFilterBlur extends StatelessWidget {
  final double blur;
  final Widget child;

  const ImageFilterBlur({super.key, required this.blur, required this.child});

  @override
  Widget build(BuildContext context) {
    if (blur <= 0.0) return child;
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
      child: child,
    );
  }
}
