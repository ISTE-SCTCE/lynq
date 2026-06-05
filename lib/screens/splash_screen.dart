import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../core/auth_provider.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _bgController;
  late AnimationController _contentController;

  late Animation<double> _fillAnimation;

  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;
  late Animation<Offset> _titleSlide;
  late Animation<double> _titleOpacity;
  late Animation<double> _taglineOpacity;

  @override
  void initState() {
    super.initState();
    
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _contentController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _fillAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _bgController, curve: Curves.easeInOutCirc),
    );

    _logoScale = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _contentController, curve: const Interval(0.0, 0.5, curve: Curves.easeOutBack)),
    );
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _contentController, curve: const Interval(0.0, 0.4, curve: Curves.easeIn)),
    );

    _titleSlide = Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero).animate(
      CurvedAnimation(parent: _contentController, curve: const Interval(0.3, 0.7, curve: Curves.easeOutCubic)),
    );
    _titleOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _contentController, curve: const Interval(0.3, 0.7, curve: Curves.easeIn)),
    );

    _taglineOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _contentController, curve: const Interval(0.6, 1.0, curve: Curves.easeIn)),
    );

    _bgController.forward().then((_) {
      _contentController.forward().then((_) {
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) {
            context.read<AuthProvider>().hideSplash();
          }
        });
      });
    });
  }

  @override
  void dispose() {
    _bgController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final maxRadius = screenSize.height * 1.5;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        alignment: Alignment.center,
        children: [
          // Background Color Fill Animation
          AnimatedBuilder(
            animation: _bgController,
            builder: (context, child) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  if (_fillAnimation.value > 0)
                    Container(
                      width: maxRadius * _fillAnimation.value,
                      height: maxRadius * _fillAnimation.value,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle, 
                        color: AppTheme.darkGreen, // Solid dark green fill
                      ),
                    ),
                ],
              );
            },
          ),
          
          // Content Animation
          AnimatedBuilder(
            animation: _contentController,
            builder: (context, child) {
              if (_bgController.isAnimating || _contentController.value == 0) return const SizedBox();
              
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FadeTransition(
                    opacity: _logoOpacity,
                    child: ScaleTransition(
                      scale: _logoScale,
                      child: Image.asset(
                        'assets/images/logo-lynq.png',
                        width: 120,
                        height: 120,
                        fit: BoxFit.contain,
                        color: Colors.white, // Carved out white effect
                        errorBuilder: (context, error, stackTrace) => const Icon(
                          Icons.error_outline,
                          size: 80,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SlideTransition(
                    position: _titleSlide,
                    child: FadeTransition(
                      opacity: _titleOpacity,
                      child: Text(
                        'lynq',
                        style: const TextStyle(
                          fontFamily: 'Qurova',
                          fontSize: 48,
                          color: Colors.white,
                          letterSpacing: 4.0,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FadeTransition(
                    opacity: _taglineOpacity,
                    child: Text(
                      'Connect. Coordinate. Lead.',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        color: Colors.white70,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 64),
                  FadeTransition(
                    opacity: _taglineOpacity,
                    child: const SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: Colors.white54,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
