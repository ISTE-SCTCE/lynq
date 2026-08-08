import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme.dart';
import '../../shared/mlynq_illustrations.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    // If auth finishes loading and user is already authenticated, auto-route to home
    if (!authState.isLoading && authState.isAuthenticated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/home');
      });
    }

    if (authState.isLoading) {
      return const Scaffold(
        backgroundColor: MemberTheme.mBackground,
        body: Center(
          child: CircularProgressIndicator(color: MemberTheme.mSlate),
        ),
      );
    }

    return Scaffold(
      backgroundColor: MemberTheme.mBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Spacer(flex: 2),
              
              // Custom Minimalist Illustration
              const MlynqOnboardingIllustration(),
              
              const Spacer(flex: 2),

              // Title Section
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Learn Something\nNew Today',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                    color: MemberTheme.mDarkCharcoal,
                    height: 1.15,
                  ),
                ),
              ),
              
              const SizedBox(height: 16),

              // Subtitle Paragraph
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Learn something new today to grow knowledge, creativity, confidence, and future success.',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    color: MemberTheme.mDarkCharcoal.withValues(alpha: 0.65),
                    height: 1.45,
                  ),
                ),
              ),

              const Spacer(flex: 3),

              // Custom Onboarding CTA button
              GestureDetector(
                onTap: () {
                  if (authState.isAuthenticated) {
                    context.go('/home');
                  } else {
                    context.go('/login');
                  }
                },
                child: Container(
                  height: 64,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: MemberTheme.mSlate,
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: [
                      BoxShadow(
                        color: MemberTheme.mSlate.withValues(alpha: 0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: const BoxDecoration(
                            color: MemberTheme.mDarkCharcoal,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                        Text(
                          'Get Started',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(width: 52),
                      ],
                    ),
                  ),
                ),
              ),
              
              const Spacer(flex: 1),
            ],
          ),
        ),
      ),
    );
  }
}
