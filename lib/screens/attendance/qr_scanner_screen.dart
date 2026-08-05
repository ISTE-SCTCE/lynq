import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../core/auth_provider.dart';

class QrScannerScreen extends StatefulWidget {
  final int? eventId;
  const QrScannerScreen({super.key, this.eventId});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  MobileScannerController? _scannerController;
  bool _isProcessing = false;
  bool _torchOn = false;
  _ScanResult? _lastResult;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;
  int _numDays = 1;
  int _currentDay = 1;

  static const _terracotta = Color(0xFFD97D55);
  static const _cream = Color(0xFFF4E9D7);
  static const _sage = Color(0xFFB8C4A9);
  static const _teal = Color(0xFF6FA4AF);
  static const _bg = Color(0xFF141414);

  @override
  void initState() {
    super.initState();
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      returnImage: false,
    );
    _pulseController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.6, end: 1.0).animate(
        CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
    _fetchEventNumDays();
  }

  @override
  void dispose() {
    _scannerController?.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  // ── Fetch num_days for event-specific scan mode ────────────────────────
  Future<void> _fetchEventNumDays() async {
    if (widget.eventId == null) return;
    try {
      final data = await _supabase
          .from('events')
          .select('num_days')
          .eq('id', widget.eventId!)
          .maybeSingle();
      if (data != null && mounted) {
        final days = (data['num_days'] as int?) ?? 1;
        setState(() => _numDays = days);
        if (days > 1) _promptDaySelection();
      }
    } catch (_) {}
  }

  void _promptDaySelection() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C2E),
        title: Text('Select Scan Day', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(_numDays, (i) {
            final day = i + 1;
            return RadioListTile<int>(
              value: day,
              groupValue: _currentDay,
              title: Text('Day $day', style: GoogleFonts.inter(color: Colors.white)),
              activeColor: _sage,
              onChanged: (val) {
                setState(() => _currentDay = val!);
                Navigator.pop(ctx);
              },
            );
          }),
        ),
      ),
    );
  }

  Future<void> _processBarcode(BarcodeCapture capture) async {
    if (_isProcessing) return;
    final code = capture.barcodes.firstOrNull?.rawValue;
    if (code == null) return;

    setState(() => _isProcessing = true);
    HapticFeedback.mediumImpact();

    try {
      // QR payload format: {"uid":"<userId>","token":"<tokenHash>","ts":<timestamp>}
      Map<String, dynamic> payload;
      try {
        payload = jsonDecode(code) as Map<String, dynamic>;
      } catch (_) {
        setState(() {
          _lastResult = _ScanResult(success: false, message: 'Invalid QR format');
          _isProcessing = false;
        });
        return;
      }

      final userId = payload['uid'] as String?;
      final token = payload['token'] as String?;
      final ts = payload['ts'] as int?;

      if (userId == null || token == null || ts == null) {
        setState(() {
          _lastResult = _ScanResult(success: false, message: 'Malformed QR payload');
          _isProcessing = false;
        });
        return;
      }

      // Client-side ts check: advisory early rejection of obviously-stale QRs.
      // This is NOT a security boundary — the DB expires_at check is the real guard.
      // A malicious client supplying a fake ts will still fail the DB query below.
      final tokenTime = DateTime.fromMillisecondsSinceEpoch(ts);
      final age = DateTime.now().difference(tokenTime);
      if (age.inSeconds > 30) {
        setState(() {
          _lastResult = _ScanResult(success: false, message: 'QR token expired. Member must refresh.');
          _isProcessing = false;
        });
        HapticFeedback.heavyImpact();
        return;
      }

      // Validate token in DB
      final tokenRows = await _supabase
          .from('qr_tokens')
          .select()
          .eq('user_id', userId)
          .eq('token_hash', token)
          .eq('is_used', false)
          .gt('expires_at', DateTime.now().toIso8601String())
          .limit(1);

      if ((tokenRows as List).isEmpty) {
        setState(() {
          _lastResult = _ScanResult(success: false, message: 'Token invalid or already used');
          _isProcessing = false;
        });
        HapticFeedback.heavyImpact();
        return;
      }

      final tokenRow = tokenRows.first as Map<String, dynamic>;
      final tokenId = tokenRow['id'] as int;
      final auth = context.read<AuthProvider>();

      // Check for duplicate attendance
      if (widget.eventId != null) {
        final existing = await _supabase
            .from('attendance')
            .select('id')
            .eq('event_id', widget.eventId!)
            .eq('user_id', userId)
            .limit(1);

        if ((existing as List).isNotEmpty) {
          // Fetch user name
          final userRow = await _supabase
              .from('users')
              .select('name')
              .eq('id', userId)
              .single();
          setState(() {
            _lastResult = _ScanResult(
              success: false,
              message: 'Already marked: ${userRow['name']}',
              userName: userRow['name'] as String?,
            );
            _isProcessing = false;
          });
          return;
        }
      }

      // Fetch user name for display
      final userRow = await _supabase
          .from('users')
          .select('name, roll_number, branch')
          .eq('id', userId)
          .maybeSingle();

      if (widget.eventId != null) {
        // Use atomic RPC to prevent race condition between simultaneous scans:
        // mark_attendance_atomic does SELECT FOR UPDATE + INSERT in one transaction.
        final rpcResult = await _supabase.rpc('mark_attendance_atomic', params: {
          'p_event_id':   widget.eventId,
          'p_user_id':    userId,
          'p_token_id':   tokenId,
          'p_scanned_by': auth.authUser?.id,
          'p_day_number': _currentDay,
        }) as Map<String, dynamic>;

        final bool rpcSuccess = rpcResult['success'] == true;
        final String? rpcError = rpcResult['error'] as String?;

        HapticFeedback.lightImpact();
        if (rpcSuccess) {
          setState(() {
            _lastResult = _ScanResult(
              success: true,
              message: 'Attendance marked!',
              userName: userRow?['name'] as String?,
              rollNumber: userRow?['roll_number'] as String?,
              branch: userRow?['branch'] as String?,
            );
            _isProcessing = false;
          });
        } else {
          final friendlyMsg = rpcError == 'already_attended'
              ? 'Already marked: ${userRow?['name'] ?? userId}'
              : rpcError == 'token_invalid_or_race'
                  ? 'Token already used or expired (race condition prevented)'
                  : 'Failed to mark attendance: $rpcError';
          HapticFeedback.heavyImpact();
          setState(() {
            _lastResult = _ScanResult(
              success: false,
              message: friendlyMsg,
              userName: userRow?['name'] as String?,
            );
            _isProcessing = false;
          });
        }

        // Auto-reset after 3 seconds
        await Future.delayed(const Duration(seconds: 3));
        if (mounted) setState(() => _lastResult = null);
      } else {
        // GLOBAL SCAN MODE
        HapticFeedback.lightImpact();
        if (!mounted) return;
        
        await _showUserEventsBottomSheet(
          userId: userId,
          tokenId: tokenId,
          userRow: userRow,
        );
        
        if (mounted) {
          setState(() {
             _isProcessing = false;
          });
        }
      }
    } catch (e) {
      setState(() {
        _lastResult = _ScanResult(success: false, message: 'Error: $e');
        _isProcessing = false;
      });
      // Auto-reset after 3 seconds
      await Future.delayed(const Duration(seconds: 3));
      if (mounted) setState(() => _lastResult = null);
    }
  }

  Future<void> _showUserEventsBottomSheet({
    required String userId,
    required int tokenId,
    required Map<String, dynamic>? userRow,
  }) async {
    final auth = context.read<AuthProvider>();

    // Fetch active events (newest first)
    final eventsRes = await _supabase
        .from('events')
        .select('id, title, date, type, num_days')
        .order('date', ascending: false)
        .limit(20);

    final events = (eventsRes as List).cast<Map<String, dynamic>>();

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      backgroundColor: _bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(24),
          height: MediaQuery.of(ctx).size.height * 0.7,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // User info header
              Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: _terracotta.withValues(alpha: 0.2),
                    child: Text(
                      userRow?['name'] != null ? userRow!['name'][0].toUpperCase() : '?',
                      style: GoogleFonts.spaceGrotesk(fontSize: 24, color: _terracotta),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          userRow?['name'] ?? 'Unknown Member',
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 20, fontWeight: FontWeight.bold, color: _cream),
                        ),
                        if (userRow?['roll_number'] != null)
                          Text(
                            '${userRow!['roll_number']} · ${userRow['branch'] ?? ""}',
                            style: GoogleFonts.inter(fontSize: 13, color: Colors.white60),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Divider(color: Colors.white12),
              const SizedBox(height: 16),
              Text(
                'Select Event to Mark Attendance',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 16, fontWeight: FontWeight.bold, color: _cream),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: events.isEmpty
                    ? Center(
                        child: Text(
                          'No ongoing events found',
                          style: GoogleFonts.inter(color: Colors.white54),
                        ),
                      )
                    : ListView.separated(
                        itemCount: events.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (ctx, i) {
                          final event = events[i];
                          return InkWell(
                            onTap: () async {
                              Navigator.pop(ctx);

                              // For multi-day events, let the scanner pick which day
                              int scanDay = 1;
                              final evtNumDays = (event['num_days'] as int?) ?? 1;
                              if (evtNumDays > 1 && mounted) {
                                final picked = await showDialog<int>(
                                  context: context,
                                  builder: (dCtx) => AlertDialog(
                                    backgroundColor: const Color(0xFF1C1C2E),
                                    title: Text('Select Day', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.bold)),
                                    content: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: List.generate(evtNumDays, (i) => ListTile(
                                        title: Text('Day ${i + 1}', style: GoogleFonts.inter(color: Colors.white)),
                                        onTap: () => Navigator.pop(dCtx, i + 1),
                                      )),
                                    ),
                                  ),
                                );
                                if (picked == null) return;
                                scanDay = picked;
                              }

                              // Eligibility check: verify the scanned member's role
                              // is in this event's allowed_roles before marking attendance.
                              final eventDetail = await _supabase
                                  .from('events')
                                  .select('allowed_roles')
                                  .eq('id', event['id'])
                                  .maybeSingle();

                              if (eventDetail != null) {
                                final allowedRoles = eventDetail['allowed_roles'] as List?;
                                if (allowedRoles != null && allowedRoles.isNotEmpty) {
                                  // Fetch the scanned member's role
                                  final memberRole = await _supabase
                                      .from('users')
                                      .select('role')
                                      .eq('id', userId)
                                      .maybeSingle();
                                  final String scannedUserRole =
                                      memberRole?['role'] as String? ?? 'user';
                                  if (!allowedRoles.map((r) => r.toString()).contains(scannedUserRole)) {
                                    setState(() {
                                      _lastResult = _ScanResult(
                                        success: false,
                                        message: '${userRow?['name'] ?? 'Member'} is not eligible for ${event['title']} '
                                            '(role: $scannedUserRole)',
                                        userName: userRow?['name'] as String?,
                                      );
                                    });
                                    await Future.delayed(const Duration(seconds: 3));
                                    if (mounted) setState(() => _lastResult = null);
                                    return;
                                  }
                                }
                              }

                              final rpcResult = await _supabase.rpc('mark_attendance_atomic', params: {
                                'p_event_id':   event['id'],
                                'p_user_id':    userId,
                                'p_token_id':   tokenId,
                                'p_scanned_by': auth.authUser?.id,
                                'p_day_number': scanDay,
                              }) as Map<String, dynamic>;

                              final bool rpcSuccess = rpcResult['success'] == true;
                              final String? rpcError = rpcResult['error'] as String?;

                              if (rpcSuccess) {
                                HapticFeedback.lightImpact();
                                setState(() {
                                  _lastResult = _ScanResult(
                                    success: true,
                                    message: 'Marked for ${event['title']}',
                                    userName: userRow?['name'] as String?,
                                    rollNumber: userRow?['roll_number'] as String?,
                                    branch: userRow?['branch'] as String?,
                                  );
                                });
                              } else {
                                final friendlyMsg = rpcError == 'already_attended'
                                    ? 'Already marked for ${event['title']}'
                                    : rpcError == 'token_invalid_or_race'
                                        ? 'Token already used (race condition prevented)'
                                        : 'Failed: $rpcError';
                                setState(() {
                                  _lastResult = _ScanResult(
                                    success: false,
                                    message: friendlyMsg,
                                    userName: userRow?['name'] as String?,
                                  );
                                });
                              }

                              // Auto-reset
                              await Future.delayed(const Duration(seconds: 3));
                              if (mounted) setState(() => _lastResult = null);
                            },
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.white12),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: _sage.withValues(alpha: 0.2),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.event_rounded, color: _sage, size: 20),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          event['title'] ?? 'Unknown',
                                          style: GoogleFonts.inter(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
                                        ),
                                        if (event['type'] != null)
                                          Text(
                                            event['type'],
                                            style: GoogleFonts.inter(
                                              fontSize: 12,
                                              color: Colors.white60,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.chevron_right_rounded, color: Colors.white38),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera view
          MobileScanner(
            controller: _scannerController!,
            onDetect: _processBarcode,
          ),
          // Overlay
          _buildOverlay(),
          // Result card
          if (_lastResult != null) _buildResultCard(_lastResult!),
          // Top bar
          _buildTopBar(),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: GestureDetector(
                    onTap: () => context.pop(),
                    child: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white, size: 20),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Text(
                      widget.eventId != null
                          ? 'Scanning for Event #${widget.eventId}${_numDays > 1 ? " · Day $_currentDay" : ""}'
                          : 'QR Attendance Scanner',
                      style: GoogleFonts.spaceGrotesk(
                          color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                  ),
                ),
              ),
            ),
            // Day switcher chip (multi-day events only)
            if (_numDays > 1) ...[              const SizedBox(width: 8),
              GestureDetector(
                onTap: _promptDaySelection,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _sage.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _sage.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    'Day $_currentDay',
                    style: GoogleFonts.spaceGrotesk(color: _sage, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ),
            ],
            const SizedBox(width: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: GestureDetector(
                  onTap: () {
                    setState(() => _torchOn = !_torchOn);
                    _scannerController?.toggleTorch();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _torchOn
                          ? _terracotta.withValues(alpha: 0.5)
                          : Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: _torchOn ? _terracotta : Colors.white12),
                    ),
                    child: Icon(
                      _torchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                      color: Colors.white, size: 20,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverlay() {
    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (ctx, _) {
        return CustomPaint(
          painter: _ScannerOverlayPainter(
            pulseValue: _pulseAnim.value,
            isSuccess: _lastResult?.success,
            terracotta: _terracotta,
            sage: _sage,
          ),
          child: const SizedBox.expand(),
        );
      },
    );
  }

  Widget _buildResultCard(_ScanResult result) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 60),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: (result.success ? _sage : Colors.red)
                    .withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: (result.success ? _sage : Colors.red)
                      .withValues(alpha: 0.5),
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: (result.success ? _sage : Colors.red)
                          .withValues(alpha: 0.2),
                    ),
                    child: Icon(
                      result.success
                          ? Icons.check_circle_rounded
                          : Icons.cancel_rounded,
                      color: result.success ? _sage : Colors.red.shade400,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (result.userName != null)
                          Text(result.userName!,
                              style: GoogleFonts.spaceGrotesk(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: _cream)),
                        Text(result.message,
                            style: GoogleFonts.inter(
                                fontSize: 13,
                                color: result.success ? _sage : Colors.red.shade300)),
                        if (result.rollNumber != null)
                          Text(
                            '${result.rollNumber} · ${result.branch ?? ""}',
                            style: GoogleFonts.inter(fontSize: 11, color: Colors.white38),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Scanner Overlay Painter ────────────────────────────────────────────────

class _ScannerOverlayPainter extends CustomPainter {
  final double pulseValue;
  final bool? isSuccess;
  final Color terracotta;
  final Color sage;

  const _ScannerOverlayPainter({
    required this.pulseValue,
    required this.isSuccess,
    required this.terracotta,
    required this.sage,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.42);
    const boxSize = 260.0;
    final rect = Rect.fromCenter(center: center, width: boxSize, height: boxSize);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(24));

    // Dark overlay outside scan area
    final overlayPaint = Paint()..color = Colors.black.withValues(alpha: 0.55);
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height)),
        Path()..addRRect(rrect),
      ),
      overlayPaint,
    );

    // Corner bracket color
    final color = isSuccess == true ? sage : isSuccess == false ? Colors.red : terracotta;
    final bracketPaint = Paint()
      ..color = color.withValues(alpha: pulseValue)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const bLen = 28.0;
    const r = 24.0;
    // Top-left
    canvas.drawLine(rect.topLeft + const Offset(r, 0), rect.topLeft + Offset(r + bLen, 0), bracketPaint);
    canvas.drawLine(rect.topLeft + const Offset(0, r), rect.topLeft + Offset(0, r + bLen), bracketPaint);
    // Top-right
    canvas.drawLine(rect.topRight + const Offset(-r, 0), rect.topRight + Offset(-r - bLen, 0), bracketPaint);
    canvas.drawLine(rect.topRight + const Offset(0, r), rect.topRight + Offset(0, r + bLen), bracketPaint);
    // Bottom-left
    canvas.drawLine(rect.bottomLeft + const Offset(r, 0), rect.bottomLeft + Offset(r + bLen, 0), bracketPaint);
    canvas.drawLine(rect.bottomLeft + const Offset(0, -r), rect.bottomLeft + Offset(0, -r - bLen), bracketPaint);
    // Bottom-right
    canvas.drawLine(rect.bottomRight + const Offset(-r, 0), rect.bottomRight + Offset(-r - bLen, 0), bracketPaint);
    canvas.drawLine(rect.bottomRight + const Offset(0, -r), rect.bottomRight + Offset(0, -r - bLen), bracketPaint);
  }

  @override
  bool shouldRepaint(_ScannerOverlayPainter old) =>
      old.pulseValue != pulseValue || old.isSuccess != isSuccess;
}

// ── Result Model ──────────────────────────────────────────────────────────

class _ScanResult {
  final bool success;
  final String message;
  final String? userName;
  final String? rollNumber;
  final String? branch;

  const _ScanResult({
    required this.success,
    required this.message,
    this.userName,
    this.rollNumber,
    this.branch,
  });
}
