import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../core/auth_provider.dart';

/// Particle model for constellation background
class _Particle {
  double x;
  double y;
  double vx;
  double vy;
  double r;
  Color color;
  double pulse;

  _Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.r,
    required this.color,
    required this.pulse,
  });
}

/// Particle constellation canvas painter
class _ParticleFieldPainter extends CustomPainter {
  final List<_Particle> particles;
  final double animationValue;

  _ParticleFieldPainter({
    required this.particles,
    required this.animationValue,
  });

  static const List<Color> colors = [
    Color(0xFF5F85A2),
    Color(0xFFD3E3F0),
    Color(0xFFD97D55),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (particles.isEmpty) return;

    const linkDistance = 130.0;
    final linePaint = Paint()
      ..strokeWidth = 0.6
      ..style = PaintingStyle.stroke;

    // Draw connecting lines between nearby particles
    for (int i = 0; i < particles.length; i++) {
      for (int j = i + 1; j < particles.length; j++) {
        final a = particles[i];
        final b = particles[j];
        final dx = a.x - b.x;
        final dy = a.y - b.y;
        final dist = math.sqrt(dx * dx + dy * dy);

        if (dist < linkDistance) {
          final opacity = (1.0 - dist / linkDistance) * 0.15;
          linePaint.color = const Color(0xFF5F85A2).withValues(alpha: opacity);
          canvas.drawLine(Offset(a.x, a.y), Offset(b.x, b.y), linePaint);
        }
      }
    }

    // Update + draw particles
    final dotPaint = Paint()..style = PaintingStyle.fill;

    for (final p in particles) {
      p.x += p.vx;
      p.y += p.vy;
      p.pulse += 0.02;

      if (p.x < 0 || p.x > size.width) p.vx *= -1;
      if (p.y < 0 || p.y > size.height) p.vy *= -1;

      final glow = (math.sin(p.pulse) + 1.0) / 2.0; // 0..1 breathing
      final alpha = (0.35 + glow * 0.35).clamp(0.0, 1.0);
      dotPaint.color = p.color.withValues(alpha: alpha);

      canvas.drawCircle(
        Offset(p.x, p.y),
        p.r + glow * 0.6,
        dotPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ParticleFieldPainter oldDelegate) => true;
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _entranceController;
  late AnimationController _loopController;
  late AnimationController _exitController;

  late Animation<double> _bounceScale;
  late Animation<double> _fadeOpacity;
  late Animation<double> _slideY;
  late Animation<double> _shinePosition;
  late Animation<double> _orbitAngle;

  late Animation<double> _exitScale;
  late Animation<double> _exitOpacity;

  final List<_Particle> _particles = [];
  final math.Random _random = math.Random();
  bool _isExiting = false;
  bool _initializedParticles = false;

  @override
  void initState() {
    super.initState();

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _loopController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat();

    _exitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _setupAnimations();

    _entranceController.forward().then((_) {
      _checkLoadingStateAndExit();
    });
  }

  void _setupAnimations() {
    // Spring bounce-in entrance
    _bounceScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 0.3, end: 1.08).chain(CurveTween(curve: Curves.easeOutBack)), weight: 60),
      TweenSequenceItem(tween: Tween<double>(begin: 1.08, end: 0.96).chain(CurveTween(curve: Curves.easeInOut)), weight: 20),
      TweenSequenceItem(tween: Tween<double>(begin: 0.96, end: 1.0).chain(CurveTween(curve: Curves.easeOut)), weight: 20),
    ]).animate(_entranceController);

    _fadeOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _entranceController, curve: const Interval(0.0, 0.4, curve: Curves.easeOut)),
    );

    _slideY = Tween<double>(begin: 16.0, end: 0.0).animate(
      CurvedAnimation(parent: _entranceController, curve: const Interval(0.2, 0.8, curve: Curves.easeOutCubic)),
    );

    // Continuous loop animations
    _orbitAngle = Tween<double>(begin: 0.0, end: 2 * math.pi).animate(_loopController);
    _shinePosition = Tween<double>(begin: -1.0, end: 2.5).animate(
      CurvedAnimation(parent: _loopController, curve: Curves.easeInOut),
    );

    // Exit transforms
    _exitScale = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _exitController, curve: Curves.easeInCubic),
    );
    _exitOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _exitController, curve: Curves.easeInQuad),
    );
  }

  void _initParticles(Size size) {
    if (_initializedParticles || size.width == 0) return;
    _initializedParticles = true;

    const count = 55;
    const colors = [Color(0xFF5F85A2), Color(0xFFD3E3F0), Color(0xFFD97D55)];

    for (int i = 0; i < count; i++) {
      _particles.add(_Particle(
        x: _random.nextDouble() * size.width,
        y: _random.nextDouble() * size.height,
        vx: (_random.nextDouble() - 0.5) * 0.35,
        vy: (_random.nextDouble() - 0.5) * 0.35,
        r: _random.nextDouble() * 1.8 + 0.8,
        color: colors[_random.nextInt(colors.length)],
        pulse: _random.nextDouble() * math.pi * 2,
      ));
    }
  }

  void _checkLoadingStateAndExit() {
    if (!mounted) return;
    final authProvider = context.read<AuthProvider>();

    if (authProvider.isLoading) {
      authProvider.addListener(_onAuthLoadingChanged);
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
    _loopController.dispose();
    _exitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    _initParticles(screenSize);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: AnimatedBuilder(
        animation: Listenable.merge([_entranceController, _loopController, _exitController]),
        builder: (context, child) {
          return FadeTransition(
            opacity: _exitOpacity,
            child: ScaleTransition(
              scale: _exitScale,
              child: Stack(
                children: [
                  // Particle field canvas background
                  CustomPainterWidget(
                    particles: _particles,
                    animationValue: _loopController.value,
                  ),

                  // Ambient glow halos
                  Positioned(
                    top: screenSize.height * 0.18,
                    left: screenSize.width * 0.12,
                    child: Container(
                      width: 320,
                      height: 320,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            const Color(0xFF5F85A2).withValues(alpha: 0.22),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: screenSize.height * 0.12,
                    right: screenSize.width * 0.08,
                    child: Container(
                      width: 280,
                      height: 280,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            const Color(0xFFD97D55).withValues(alpha: 0.18),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Radial vignette overlay for contrast
                  Container(
                    decoration: const BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment.center,
                        radius: 1.0,
                        colors: [
                          Color(0x330A0A0F),
                          Color(0xBF0A0A0F),
                        ],
                      ),
                    ),
                  ),

                  // Center content: Logo + Title + Tagline + Dots
                  Center(
                    child: Transform.translate(
                      offset: Offset(0, _slideY.value),
                      child: Opacity(
                        opacity: _fadeOpacity.value,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // ── Logo mark container with orbiting spark ──
                            SizedBox(
                              width: 96,
                              height: 96,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  // Orbiting spark
                                  Transform.rotate(
                                    angle: _orbitAngle.value,
                                    child: Align(
                                      alignment: Alignment.topCenter,
                                      child: Container(
                                        width: 7,
                                        height: 7,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: const Color(0xFFD97D55),
                                          boxShadow: [
                                            BoxShadow(
                                              color: const Color(0xFFD97D55).withValues(alpha: 0.7),
                                              blurRadius: 10,
                                              spreadRadius: 3,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),

                                  // Logo box with spring bounce-in
                                  Transform.scale(
                                    scale: _bounceScale.value,
                                    child: Container(
                                      width: 72,
                                      height: 72,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(18),
                                        gradient: const LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [Color(0xFF5F85A2), Color(0xFF3A5C7A)],
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFF5F85A2).withValues(alpha: 0.4),
                                            blurRadius: 30,
                                            offset: const Offset(0, 10),
                                          ),
                                        ],
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          const Icon(
                                            Icons.school_rounded,
                                            size: 32,
                                            color: Colors.white,
                                          ),
                                          // Diagonal shine sweep
                                          Positioned(
                                            left: _shinePosition.value * 72 - 36,
                                            top: -20,
                                            child: Transform.rotate(
                                              angle: math.pi / 6,
                                              child: Container(
                                                width: 24,
                                                height: 120,
                                                decoration: BoxDecoration(
                                                  gradient: LinearGradient(
                                                    colors: [
                                                      Colors.white.withValues(alpha: 0.0),
                                                      Colors.white.withValues(alpha: 0.45),
                                                      Colors.white.withValues(alpha: 0.0),
                                                    ],
                                                  ),
                                                ),
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
                            const SizedBox(height: 20),

                            // ── Wordmark ──
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'M-Lynq',
                                  style: GoogleFonts.spaceGrotesk(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF5F85A2).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: const Color(0xFF5F85A2).withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Text(
                                    'ISTE',
                                    style: GoogleFonts.spaceGrotesk(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF5F85A2),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Member Portal',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: const Color(0xFFD3E3F0).withValues(alpha: 0.5),
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                            const SizedBox(height: 36),

                            // ── Breathing loading dots ──
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: List.generate(3, (index) {
                                final phase = (_loopController.value * 2 * math.pi + index * 0.8) % (2 * math.pi);
                                final dotOpacity = (math.sin(phase) + 1.0) / 2.0;
                                return Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 4),
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: const Color(0xFF5F85A2).withValues(
                                      alpha: 0.3 + dotOpacity * 0.7,
                                    ),
                                  ),
                                );
                              }),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class CustomPainterWidget extends StatelessWidget {
  final List<_Particle> particles;
  final double animationValue;

  const CustomPainterWidget({
    super.key,
    required this.particles,
    required this.animationValue,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.infinite,
      painter: _ParticleFieldPainter(
        particles: particles,
        animationValue: animationValue,
      ),
    );
  }
}
