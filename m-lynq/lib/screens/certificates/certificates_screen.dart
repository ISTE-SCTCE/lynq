import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers/auth_provider.dart';

// ── Design tokens ─────────────────────────────────────────────────────────────
class _T {
  static const bg         = Color(0xFFFAF6EC); // warm cream
  static const navy       = Color(0xFF1B2A4A); // headers/primary text
  static const gold       = Color(0xFFC9A227); // seal accent, active chip
  static const teal       = Color(0xFF2F6F6E); // download action / workshop
  static const lavender   = Color(0xFF6B4E9E); // seminar
  static const muted      = Color(0xFF6b6558); // subtitles
  static const caption    = Color(0xFF8a8371); // date/meta
  static const cardSurf   = Color(0xFFFFFDF8); // card bg
  static const cardBorder = Color(0xFFE7DFC9); // card border
  static const divider    = Color(0xFFEFE9D8); // hairline

  static Color sealColor(String? cat) => switch (cat?.toLowerCase()) {
    'hackathon' => gold,
    'workshop'  => teal,
    'seminar'   => lavender,
    _           => navy,
  };
}

// ── Category filter options ───────────────────────────────────────────────────
const _kFilterAll       = 'All';
const _kFilters         = ['All', 'Hackathon', 'Workshop', 'Seminar'];

// ── Main screen ───────────────────────────────────────────────────────────────
class CertificatesScreen extends ConsumerStatefulWidget {
  const CertificatesScreen({super.key});

  @override
  ConsumerState<CertificatesScreen> createState() => _CertificatesScreenState();
}

class _CertificatesScreenState extends ConsumerState<CertificatesScreen>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _all  = [];
  bool _isLoading = true;
  String _activeFilter = _kFilterAll;
  late AnimationController _shimmerCtrl;

  @override
  void initState() {
    super.initState();
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _load();
  }

  @override
  void dispose() {
    _shimmerCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final auth = ref.read(authProvider);
    final uid  = auth.user?.id ?? '';
    if (uid.isEmpty) { setState(() => _isLoading = false); return; }

    try {
      // Pull certificates joined with event data (new + legacy url columns)
      final data = await _supabase
          .from('certificates')
          .select('id, event_id, student_name, certificate_url, file_url, issued_at, events(id, title, date, category, type)')
          .eq('user_id', uid)
          .order('issued_at', ascending: false);

      if (mounted) {
        setState(() {
          _all = (data as List).map((item) {
            final m = Map<String, dynamic>.from(item as Map);
            final ev = m['events'] as Map<String, dynamic>?;
            // Normalise url: prefer new column, fall back to legacy
            m['_url'] = (m['certificate_url'] as String?)?.isNotEmpty == true
                ? m['certificate_url']
                : m['file_url'] as String? ?? '';
            // Normalise category: prefer events.category, fallback events.type, then null
            m['_category'] = ev?['category'] as String? ?? ev?['type'] as String?;
            m['_eventTitle'] = ev?['title'] as String? ?? 'Event';
            m['_eventDate']  = ev?['date']  as String? ?? '';
            m['_eventId']    = ev?['id']    as int?;
            return m;
          }).toList();
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_activeFilter == _kFilterAll) return _all;
    return _all.where((c) =>
        (c['_category'] as String?)?.toLowerCase() == _activeFilter.toLowerCase()
    ).toList();
  }

  @override
  Widget build(BuildContext context) {
    final count = _all.length;

    return Scaffold(
      backgroundColor: _T.bg,
      appBar: AppBar(
        backgroundColor: _T.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _T.navy, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'My Certificates',
              style: GoogleFonts.cormorantGaramond(
                fontSize: 19, fontWeight: FontWeight.w700, color: _T.navy),
            ),
            if (!_isLoading)
              Text(
                '$count ${count == 1 ? 'certificate' : 'certificates'} earned',
                style: GoogleFonts.inter(fontSize: 11, color: _T.muted),
              ),
          ],
        ),
      ),
      body: Column(
        children: [
          // ── Filter chip row ─────────────────────────────────────────────
          SizedBox(
            height: 48,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              itemCount: _kFilters.length,
              itemBuilder: (ctx, i) {
                final f = _kFilters[i];
                final active = f == _activeFilter;
                return GestureDetector(
                  onTap: () => setState(() => _activeFilter = f),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeInOut,
                    margin: const EdgeInsets.only(right: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                    decoration: BoxDecoration(
                      color: active ? _T.navy : Colors.transparent,
                      borderRadius: BorderRadius.circular(40),
                      border: Border.all(
                        color: active ? _T.navy : _T.cardBorder,
                        width: active ? 1.5 : 1,
                      ),
                    ),
                    child: Text(
                      f,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: active ? Colors.white : _T.navy,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // ── Content ─────────────────────────────────────────────────────
          Expanded(
            child: _isLoading
                ? _buildSkeletonList()
                : _filtered.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _load,
                        color: _T.navy,
                        backgroundColor: _T.cardSurf,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                          itemCount: _filtered.length,
                          itemBuilder: (ctx, i) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _CertCard(
                              cert: _filtered[i],
                              shimmerCtrl: _shimmerCtrl,
                            ),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  // ── Shimmer skeleton ────────────────────────────────────────────────────────
  Widget _buildSkeletonList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      itemCount: 3,
      itemBuilder: (_, __) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _SkeletonCard(ctrl: _shimmerCtrl),
      ),
    );
  }

  // ── Empty state ─────────────────────────────────────────────────────────────
  Widget _buildEmptyState() {
    final hasFilter = _activeFilter != _kFilterAll;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: _T.navy.withValues(alpha: 0.2), width: 2),
              ),
              child: Icon(Icons.workspace_premium_outlined,
                  size: 36, color: _T.navy.withValues(alpha: 0.3)),
            ),
            const SizedBox(height: 20),
            Text(
              hasFilter ? 'No ${ _activeFilter } certificates' : 'No certificates yet',
              style: GoogleFonts.cormorantGaramond(
                  fontSize: 20, fontWeight: FontWeight.w700, color: _T.navy),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              hasFilter
                  ? 'You haven\'t earned any $_activeFilter certificates yet.'
                  : 'Attend events and mark your attendance to start earning certificates.',
              style: GoogleFonts.inter(fontSize: 13, color: _T.muted, height: 1.55),
              textAlign: TextAlign.center,
            ),
            if (!hasFilter) ...[
              const SizedBox(height: 28),
              GestureDetector(
                onTap: () => context.push('/events'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 13),
                  decoration: BoxDecoration(
                    color: _T.navy,
                    borderRadius: BorderRadius.circular(40),
                  ),
                  child: Text(
                    'Browse Events',
                    style: GoogleFonts.inter(
                        fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Certificate Card ──────────────────────────────────────────────────────────
class _CertCard extends StatelessWidget {
  final Map<String, dynamic> cert;
  final AnimationController shimmerCtrl;

  const _CertCard({required this.cert, required this.shimmerCtrl});

  @override
  Widget build(BuildContext context) {
    final category   = cert['_category'] as String?;
    final eventTitle = cert['_eventTitle'] as String? ?? 'Event';
    final dateStr    = cert['_eventDate'] as String? ?? '';
    final eventId    = cert['_eventId'] as int?;
    final url        = cert['_url'] as String? ?? '';
    final issuedAt   = DateTime.tryParse(cert['issued_at'] as String? ?? '');
    final sealColor  = _T.sealColor(category);

    String formattedDate = '';
    if (dateStr.isNotEmpty) {
      final d = DateTime.tryParse(dateStr);
      if (d != null) {
        const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
        formattedDate = '${d.day} ${months[d.month - 1]} ${d.year}';
      }
    }

    return GestureDetector(
      onTap: eventId != null ? () => context.push('/events/$eventId') : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            color: _T.cardSurf,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _T.cardBorder),
          ),
          child: Stack(
            children: [
              // ── Circuit-trace corner ornament ──────────────────────────
              Positioned(
                top: 0, right: 0,
                child: Opacity(
                  opacity: 0.12,
                  child: CustomPaint(
                    size: const Size(80, 80),
                    painter: _CircuitTracePainter(color: _T.gold),
                  ),
                ),
              ),

              // ── Card content ───────────────────────────────────────────
              Column(
                children: [
                  // Main row
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Seal badge
                        _SealBadge(color: sealColor),
                        const SizedBox(width: 14),

                        // Text column
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (category != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 3),
                                  child: Text(
                                    category.toUpperCase(),
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.4,
                                      color: sealColor,
                                    ),
                                  ),
                                ),
                              Text(
                                eventTitle,
                                style: GoogleFonts.cormorantGaramond(
                                    fontSize: 16, fontWeight: FontWeight.w700, color: _T.navy),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Certificate of Participation',
                                style: GoogleFonts.inter(fontSize: 11, color: _T.muted),
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Icon(Icons.calendar_today_rounded,
                                      size: 11, color: _T.caption),
                                  const SizedBox(width: 4),
                                  Text(
                                    formattedDate.isNotEmpty
                                        ? formattedDate
                                        : (issuedAt != null
                                            ? 'Issued ${issuedAt.day}/${issuedAt.month}/${issuedAt.year}'
                                            : 'ISTE SCTCE'),
                                    style: GoogleFonts.inter(fontSize: 11, color: _T.caption),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Action bar ─────────────────────────────────────────
                  if (url.isNotEmpty) ...[
                    Divider(height: 1, color: _T.divider),
                    IntrinsicHeight(
                      child: Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => launchUrl(Uri.parse(url),
                                  mode: LaunchMode.externalApplication),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: const RoundedRectangleBorder(),
                              ),
                              child: Text('View',
                                  style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: _T.navy)),
                            ),
                          ),
                          VerticalDivider(width: 1, color: _T.divider),
                          Expanded(
                            child: TextButton(
                              onPressed: () => launchUrl(Uri.parse(url),
                                  mode: LaunchMode.externalApplication),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: const RoundedRectangleBorder(),
                              ),
                              child: Text('Download',
                                  style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: _T.teal)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Seal badge widget ─────────────────────────────────────────────────────────
class _SealBadge extends StatelessWidget {
  final Color color;
  const _SealBadge({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 54, height: 54,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Center(
        child: Icon(Icons.workspace_premium_rounded, size: 26, color: color),
      ),
    );
  }
}

// ── Circuit trace CustomPainter (top-right corner ornament) ──────────────────
class _CircuitTracePainter extends CustomPainter {
  final Color color;
  const _CircuitTracePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Horizontal traces from right edge
    canvas.drawLine(Offset(size.width, 10), Offset(size.width - 30, 10), paint);
    canvas.drawLine(Offset(size.width - 30, 10), Offset(size.width - 30, 26), paint);
    canvas.drawLine(Offset(size.width - 30, 26), Offset(size.width - 48, 26), paint);
    // Branch
    canvas.drawLine(Offset(size.width, 28), Offset(size.width - 16, 28), paint);
    canvas.drawLine(Offset(size.width - 16, 28), Offset(size.width - 16, 50), paint);
    canvas.drawLine(Offset(size.width - 16, 50), Offset(size.width - 32, 50), paint);
    // Vertical from top
    canvas.drawLine(Offset(size.width - 50, 0), Offset(size.width - 50, 20), paint);
    canvas.drawLine(Offset(size.width - 50, 20), Offset(size.width - 62, 20), paint);

    // Contact dots
    final dotPaint = Paint()..color = color..style = PaintingStyle.fill;
    for (final pt in [
      Offset(size.width - 30, 10),
      Offset(size.width - 30, 26),
      Offset(size.width - 16, 28),
      Offset(size.width - 50, 20),
    ]) {
      canvas.drawCircle(pt, 2.5, dotPaint);
    }
  }

  @override
  bool shouldRepaint(_CircuitTracePainter old) => old.color != color;
}

// ── Skeleton card ─────────────────────────────────────────────────────────────
class _SkeletonCard extends StatelessWidget {
  final AnimationController ctrl;
  const _SkeletonCard({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ctrl,
      builder: (ctx, _) {
        final shimmer = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: const [Color(0xFFEFE9D8), Color(0xFFFAF6EC), Color(0xFFEFE9D8)],
          stops: [
            (ctrl.value - 0.3).clamp(0.0, 1.0),
            ctrl.value.clamp(0.0, 1.0),
            (ctrl.value + 0.3).clamp(0.0, 1.0),
          ],
        );

        return Container(
          height: 110,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _T.cardBorder),
            gradient: shimmer,
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Seal placeholder
                Container(
                  width: 54, height: 54,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _T.cardBorder,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(height: 10, width: 60, color: _T.cardBorder,
                          margin: const EdgeInsets.only(bottom: 8)),
                      Container(height: 14, width: double.infinity, color: _T.cardBorder,
                          margin: const EdgeInsets.only(bottom: 6)),
                      Container(height: 10, width: 100, color: _T.cardBorder),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
