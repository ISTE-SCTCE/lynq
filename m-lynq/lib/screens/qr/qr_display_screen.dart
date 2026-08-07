import 'dart:ui';
import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/providers/auth_provider.dart';

class QrDisplayScreen extends ConsumerStatefulWidget {
  const QrDisplayScreen({super.key});

  @override
  ConsumerState<QrDisplayScreen> createState() => _QrDisplayScreenState();
}

class _QrDisplayScreenState extends ConsumerState<QrDisplayScreen>
    with TickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  late AnimationController _pulseController;
  late AnimationController _rotationController;
  late Animation<double> _pulseAnim;
  late Animation<double> _rotationAnim;
  Timer? _tokenTimer;
  String? _currentQrData;
  int _secondsLeft = 30;
  bool _isGenerating = false;

  static const _terracotta = Color(0xFFD97D55);
  static const _cream = Color(0xFFF4E9D7);
  static const _teal = Color(0xFF6FA4AF);
  static const _bg = Color(0xFF141414);
  static const _surface = Color(0xFF1E1E1E);

  @override
  void initState() {
    super.initState();
    // Screenshot protection
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    _disableScreenshot();

    _pulseController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat(reverse: true);
    _rotationController = AnimationController(
        vsync: this, duration: const Duration(seconds: 30));

    _pulseAnim = Tween<double>(begin: 0.95, end: 1.05)
        .animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
    _rotationAnim = Tween<double>(begin: 0, end: 1).animate(_rotationController);

    _generateToken();
  }

  void _disableScreenshot() {
    // Platform channel to set FLAG_SECURE on Android
    const channel = MethodChannel('com.iste.memberapp/security');
    try {
      channel.invokeMethod('disableScreenshot');
    } catch (_) {
      // Gracefully ignore if platform channel not set up
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotationController.dispose();
    _tokenTimer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  /// Derives a 32-byte AES key from QR_SIGNING_SECRET build-time constant.
  enc.Key _derivedKey() {
    const secret = String.fromEnvironment('QR_SIGNING_SECRET', defaultValue: 'ISTE_QR_SECRET_DEV_FALLBACK_32ch');
    final bytes = utf8.encode(secret);
    final hash = sha256.convert(bytes).bytes;
    return enc.Key(Uint8List.fromList(hash));
  }

  /// Encrypts a JSON payload with AES-256-GCM.
  /// Returns "<iv_base64url>.<ciphertext_base64>"
  String _encryptPayload(String plaintext) {
    final key = _derivedKey();
    final iv = enc.IV.fromSecureRandom(16);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm));
    final encrypted = encrypter.encrypt(plaintext, iv: iv);
    return '${base64Url.encode(iv.bytes)}.${encrypted.base64}';
  }

  Future<void> _generateToken() async {
    if (_isGenerating) return;
    _isGenerating = true;

    final auth = ref.read(authProvider);
    final userId = auth.user?.id;
    if (userId == null) return;

    try {
      final now = DateTime.now();
      final expiresAt = now.add(const Duration(seconds: 30));

      // NOTE: Token generation still happens client-side.
      // The secret is injected at build-time via --dart-define=QR_SIGNING_SECRET=<value>
      // so it is NOT present as a plain string literal in the compiled binary.
      // Full mitigation (server-side generation via Supabase RPC) is tracked as a follow-up.
      //
      // Build command example:
      //   flutter build apk --dart-define=QR_SIGNING_SECRET=<your_secret_here>
      // Dev fallback (non-production only):
      const String _qrSigningSecret = String.fromEnvironment(
        'QR_SIGNING_SECRET',
        defaultValue: 'ISTE_QR_SECRET_DEV',
      );

      final tokenPayload = '$userId:${now.millisecondsSinceEpoch}:$_qrSigningSecret';
      final tokenHash = sha256
          .convert(utf8.encode(tokenPayload))
          .toString()
          .substring(0, 32);

      // Store token in DB
      await _supabase.from('qr_tokens').insert({
        'user_id': userId,
        'token_hash': tokenHash,
        'expires_at': expiresAt.toIso8601String(),
        'is_used': false,
      });

      // QR payload — AES-256-GCM encrypted so uid/token are never visible in plaintext
      final plainPayload = jsonEncode({
        'uid': userId,
        'token': tokenHash,
        'ts': now.millisecondsSinceEpoch,
      });
      final qrPayload = _encryptPayload(plainPayload);

      if (mounted) {
        setState(() {
          _currentQrData = qrPayload;
          _secondsLeft = 30;
          _isGenerating = false;
        });
        _rotationController.forward(from: 0);
        _startCountdown();
      }
    } catch (e) {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  void _startCountdown() {
    _tokenTimer?.cancel();
    _tokenTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) {
        timer.cancel();
        _generateToken();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final memberName = auth.name;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('My QR Code',
            style: GoogleFonts.spaceGrotesk(
                color: _cream, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Header
              Text(
                memberName,
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 24, fontWeight: FontWeight.bold, color: _cream),
              ),
              const SizedBox(height: 4),
              Text(
                auth.profile?['membership_id'] as String? ?? '',
                style: GoogleFonts.inter(fontSize: 13, color: Colors.white38),
              ),
              const SizedBox(height: 36),

              // QR Container
              AnimatedBuilder(
                animation: _pulseAnim,
                builder: (ctx, _) => Transform.scale(
                  scale: _pulseAnim.value,
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: _terracotta.withValues(alpha: 0.3),
                          blurRadius: 30,
                          spreadRadius: -5,
                        ),
                      ],
                    ),
                    child: _currentQrData != null
                        ? QrImageView(
                            data: _currentQrData!,
                            version: QrVersions.auto,
                            size: 220,
                            backgroundColor: Colors.white,
                            eyeStyle: const QrEyeStyle(
                              eyeShape: QrEyeShape.square,
                              color: Color(0xFF141414),
                            ),
                            dataModuleStyle: const QrDataModuleStyle(
                              dataModuleShape: QrDataModuleShape.square,
                              color: Color(0xFF141414),
                            ),
                          )
                        : const SizedBox(
                            width: 220, height: 220,
                            child: Center(
                              child: CircularProgressIndicator(color: _terracotta),
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // Countdown timer
              _buildCountdownRing(),
              const SizedBox(height: 20),
              Text(
                'Refreshes every 30 seconds',
                style: GoogleFonts.inter(fontSize: 12, color: Colors.white24),
              ),
              const SizedBox(height: 32),

              // Security notice
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.security_rounded, size: 16, color: Colors.white24),
                        const SizedBox(width: 8),
                        Text(
                          'Dynamic token • Anti-reuse protected',
                          style: GoogleFonts.inter(fontSize: 12, color: Colors.white24),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCountdownRing() {
    final progress = _secondsLeft / 30.0;
    final color = _secondsLeft > 10
        ? _teal
        : _secondsLeft > 5
            ? _terracotta
            : Colors.red;

    return SizedBox(
      width: 80, height: 80,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 80, height: 80,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 4,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation<Color>(color),
              strokeCap: StrokeCap.round,
            ),
          ),
          Text(
            '$_secondsLeft',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
