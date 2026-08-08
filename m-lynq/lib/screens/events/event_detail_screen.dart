import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:flutter_html_to_pdf/flutter_html_to_pdf.dart';

class EventDetailScreen extends ConsumerStatefulWidget {
  final int eventId;
  const EventDetailScreen({super.key, required this.eventId});

  @override
  ConsumerState<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends ConsumerState<EventDetailScreen> {
  final _supabase = Supabase.instance.client;
  Map<String, dynamic>? _event;
  bool _isAttended = false;
  bool _isLoading = true;
  Map<String, dynamic>? _certificate;
  bool _finalized = false;
  bool _isDownloadingCert = false;

  Future<void> _downloadTemplatePdf(String url) async {
    if (_isDownloadingCert) return;
    setState(() => _isDownloadingCert = true);
    try {
      final templatePath = url.replaceFirst('template:', '');
      
      String templateHtmlUrl = templatePath;
      if (!templatePath.startsWith('http')) {
        templateHtmlUrl = await _supabase.storage.from('event_posters').createSignedUrl(templatePath, 60);
      }
      
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(templateHtmlUrl));
      final response = await request.close();
      String html = await response.transform(utf8.decoder).join();
      
      final eventTitle = _event?['title'] as String? ?? 'Event';
      final issuedAt = _certificate?['issued_at'] != null ? DateTime.tryParse(_certificate!['issued_at']) : null;
      final dateLabel = issuedAt != null ? '${issuedAt.day} ${_monthFull(issuedAt.month)} ${issuedAt.year}' : '';
      
      final auth = ref.read(authProvider);
      final userId = auth.user?.id ?? '';
      final certId = 'ISTE-${widget.eventId}-${userId.replaceAll('-', '').substring(0, 6).toUpperCase()}';

      // ── Resolve real student name from DB ─────────────────────────────────
      String resolvedName = '';

      // Priority 1: always fetch fresh from users table
      if (userId.isNotEmpty) {
        try {
          final userRow = await _supabase
              .from('users')
              .select('name')
              .eq('id', userId)
              .maybeSingle();
          final dbName = userRow?['name'] as String?;
          if (dbName != null && dbName.trim().isNotEmpty) {
            resolvedName = dbName.trim();
          }
        } catch (_) {}
      }

      // Priority 2: student_name stored in certificate row at issuance time
      if (resolvedName.isEmpty) {
        final certStudentName = _certificate?['student_name'] as String?;
        if (certStudentName != null && certStudentName.trim().isNotEmpty && certStudentName != 'Member') {
          resolvedName = certStudentName.trim();
        }
      }

      // Priority 3: auth profile name
      if (resolvedName.isEmpty && auth.name.isNotEmpty) {
        resolvedName = auth.name;
      }

      if (resolvedName.isEmpty) resolvedName = 'Member';
      // ─────────────────────────────────────────────────────────────────────
      
      html = html.replaceAll('{{student_name}}', resolvedName);
      html = html.replaceAll('{{event_name}}', eventTitle);
      html = html.replaceAll('{{date}}', dateLabel);
      html = html.replaceAll('{{certificate_id}}', certId);
      
      final dir = await getApplicationDocumentsDirectory();
      final targetPath = dir.path;
      final targetFileName = 'Certificate_${eventTitle.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}';
      
      final generatedPdfFile = await FlutterHtmlToPdf.convertFromHtmlContent(
        html, 
        targetPath, 
        targetFileName
      );
      
      await OpenFile.open(generatedPdfFile.path);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to generate PDF: $e')));
    } finally {
      if (mounted) setState(() => _isDownloadingCert = false);
    }
  }


  static const _terracotta = Color(0xFFD97D55);
  static const _cream = Color(0xFFF4E9D7);
  static const _bg = Color(0xFF141414);
  static const _surface = Color(0xFF1E1E1E);

  Color _getThemeColor(String? type) {
    if (type == null) return _terracotta;
    final t = type.toLowerCase();
    if (t.contains('workshop') || t.contains('basics')) return MemberTheme.mSlate;
    if (t.contains('tech talk') || t.contains('seminar') || t.contains('geometry')) return MemberTheme.mPastelLavender;
    if (t.contains('meetup') || t.contains('summit') || t.contains('hackathon')) return MemberTheme.mPastelPeach;
    return _terracotta;
  }

  @override
  void initState() {
    super.initState();
    _loadEvent();
  }

  // Whether the current user's role permits viewing this event.
  // null means still loading; true means allowed; false means blocked.
  bool? _isAllowed;

  Future<void> _loadEvent() async {
    final auth = ref.read(authProvider);
    final futures = await Future.wait([
      _supabase.from('events').select().eq('id', widget.eventId).maybeSingle(),
      _supabase.from('attendance')
          .select('id')
          .eq('event_id', widget.eventId)
          .eq('user_id', auth.user?.id ?? '')
          .limit(1),
      _supabase.from('certificates')
          .select('id, certificate_url, file_url, issued_at')
          .eq('event_id', widget.eventId)
          .eq('user_id', auth.user?.id ?? '')
          .maybeSingle(),
    ]);
    if (mounted) {
      final eventData = futures[0] as Map<String, dynamic>?;
      bool allowed = true;

      if (eventData != null) {
        final allowedRoles = eventData['allowed_roles'];
        if (allowedRoles is List && allowedRoles.isNotEmpty) {
          final userRole = auth.role;
          allowed = allowedRoles
              .map((r) => r.toString())
              .contains(userRole);
        }
        // If allowed_roles is null or empty, treat as visible to all (backwards compat)
      }

      setState(() {
        _event = eventData;
        _isAttended = (futures[1] as List).isNotEmpty;
        _isAllowed = allowed;
        _isLoading = false;
        _certificate = futures[2] as Map<String, dynamic>?;
        _finalized = (_event?['attendance_finalized'] as bool?) ?? false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: _bg,
        body: const Center(child: CircularProgressIndicator(color: _terracotta)),
      );
    }

    final event = _event;
    if (event == null) return const Scaffold(backgroundColor: Color(0xFF141414));

    // Role-access guard: if the member's role isn't in allowed_roles, show denied state
    if (_isAllowed == false) {
      return Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _bg,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white12),
                  ),
                  child: const Icon(Icons.lock_outline_rounded, size: 48, color: Colors.white38),
                ),
                const SizedBox(height: 24),
                Text(
                  'Event Not Available',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 22, fontWeight: FontWeight.bold, color: _cream),
                ),
                const SizedBox(height: 12),
                Text(
                  'This event isn\'t available for your membership tier. '
                  'Contact your execom if you believe this is a mistake.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(fontSize: 14, color: Colors.white54, height: 1.6),
                ),
                const SizedBox(height: 32),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Go Back',
                      style: GoogleFonts.inter(color: _terracotta, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final date = DateTime.tryParse(event['date'] as String? ?? '');
    final daysLeft = date?.difference(DateTime.now()).inDays;
    final isPast = daysLeft != null && daysLeft < 0;
    
    final themeColor = _getThemeColor(event['type'] as String?);
    
    List<String> posters = [];
    if (event['posters'] != null) {
      posters = List<String>.from(event['posters']);
    } else if (event['poster_url'] != null) {
      posters = [event['poster_url']];
    }
    
    final String details = event['details'] as String? ?? '';
    final List<String> perks = event['perks'] != null ? List<String>.from(event['perks']) : [];

    return Scaffold(
      backgroundColor: _bg,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            backgroundColor: _bg,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (posters.isNotEmpty)
                    PageView.builder(
                      itemCount: posters.length,
                      itemBuilder: (context, index) {
                        return Image.network(posters[index], fit: BoxFit.cover);
                      },
                    ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          themeColor.withValues(alpha: posters.isNotEmpty ? 0.4 : 0.6),
                          _bg,
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 80, 24, 20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (daysLeft != null && !isPast)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: daysLeft == 0
                                  ? themeColor.withValues(alpha: 0.3)
                                  : themeColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: daysLeft == 0
                                      ? themeColor.withValues(alpha: 0.6)
                                      : themeColor.withValues(alpha: 0.4)),
                            ),
                            child: Text(
                              daysLeft == 0 ? '🔥 Today!' : '$daysLeft days away',
                              style: GoogleFonts.inter(
                                  fontSize: 12, fontWeight: FontWeight.w700,
                                  color: themeColor == MemberTheme.mPastelLavender ? Colors.white : themeColor),
                            ),
                          ),
                        const SizedBox(height: 10),
                        Text(event['title'] as String? ?? '',
                            style: GoogleFonts.spaceGrotesk(
                                fontSize: 26, fontWeight: FontWeight.bold, color: _cream,
                                shadows: [
                                  Shadow(color: Colors.black.withValues(alpha: 0.8), blurRadius: 10),
                                ])),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Info cards
                  Row(
                    children: [
                      Expanded(child: _infoCard(Icons.calendar_today_rounded, 'Date',
                          date != null
                              ? '${date.day} ${_monthFull(date.month)} ${date.year}'
                              : '—',
                          themeColor)),
                      const SizedBox(width: 12),
                      Expanded(child: _infoCard(Icons.access_time_rounded, 'Time',
                          event['time'] as String? ?? '—', themeColor)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _infoCard(Icons.location_on_rounded, 'Venue',
                          event['venue'] as String? ?? '—', const Color(0xFFD4AF37)),
                      ),
                      if (event['is_paid'] == true) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: Consumer(
                            builder: (context, ref, _) {
                              final isMember = ref.watch(authProvider).membershipId.isNotEmpty;
                              final price = isMember ? event['member_price'] : event['non_member_price'];
                              return _infoCard(
                                Icons.currency_rupee, 
                                'Price',
                                '₹$price', 
                                Colors.greenAccent
                              );
                            }
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Attendance status
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _isAttended
                          ? const Color(0xFFB8C4A9).withValues(alpha: 0.12)
                          : _surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: _isAttended
                              ? const Color(0xFFB8C4A9).withValues(alpha: 0.4)
                              : Colors.white.withValues(alpha: 0.06)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _isAttended ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                          color: _isAttended ? const Color(0xFFB8C4A9) : Colors.white38,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _isAttended ? 'You attended this event ✓' : 'Attendance not marked',
                          style: GoogleFonts.inter(
                              fontSize: 14,
                              color: _isAttended ? const Color(0xFFB8C4A9) : Colors.white38,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Certificate section
                  if (_certificate != null || (_finalized && _isAttended)) ..._buildCertificateSection(),
                  if (_certificate != null || (_finalized && _isAttended)) const SizedBox(height: 24),
                  // Description
                  if (event['description'] != null && event['description'].toString().isNotEmpty) ...[
                    Text('About',
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 18, fontWeight: FontWeight.bold, color: _cream)),
                    const SizedBox(height: 10),
                    Text(event['description'] as String,
                        style: GoogleFonts.inter(fontSize: 14, color: Colors.white70, height: 1.6)),
                    const SizedBox(height: 24),
                  ],
                  // Details
                  if (details.isNotEmpty) ...[
                    Text('Event Details',
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 18, fontWeight: FontWeight.bold, color: _cream)),
                    const SizedBox(height: 10),
                    Text(details,
                        style: GoogleFonts.inter(fontSize: 14, color: Colors.white70, height: 1.6)),
                    const SizedBox(height: 24),
                  ],
                  // Perks
                  if (perks.isNotEmpty) ...[
                    Text('Perks & Highlights',
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 18, fontWeight: FontWeight.bold, color: _cream)),
                    const SizedBox(height: 10),
                    ...perks.map((p) => Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.star, size: 16, color: themeColor),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(p, style: GoogleFonts.inter(fontSize: 14, color: Colors.white70, height: 1.4)),
                          ),
                        ],
                      ),
                    )),
                    const SizedBox(height: 24),
                  ],
                  
                  // Register Button
                  if (!isPast)
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: themeColor,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: () {
                          // Handle registration
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Registration flow not connected')));
                        },
                        child: Text(
                          'Register Now',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 16, 
                            fontWeight: FontWeight.bold, 
                            color: themeColor == MemberTheme.mPastelLavender ? MemberTheme.mDarkCharcoal : Colors.white,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildCertificateSection() {
    const goldColor = Color(0xFFC9A227);
    const navyColor = Color(0xFF1B2A4A);
    const tealColor = Color(0xFF2F6F6E);

    if (_certificate != null) {
      final certUrl = (_certificate!['certificate_url'] as String?)?.isNotEmpty == true
          ? _certificate!['certificate_url'] as String
          : _certificate!['file_url'] as String? ?? '';
      final issuedAt = DateTime.tryParse(_certificate!['issued_at'] as String? ?? '');

      return [
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [goldColor.withValues(alpha: 0.12), _surface.withValues(alpha: 0.8)],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: goldColor.withValues(alpha: 0.4)),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [goldColor.withValues(alpha: 0.35), goldColor.withValues(alpha: 0.08)],
                      ),
                      border: Border.all(color: goldColor.withValues(alpha: 0.6), width: 1.5),
                    ),
                    child: const Icon(Icons.workspace_premium_rounded, color: goldColor, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Your Certificate',
                            style: GoogleFonts.spaceGrotesk(
                                fontSize: 15, fontWeight: FontWeight.w700, color: const Color(0xFFF4E9D7))),
                        if (issuedAt != null)
                          Text(
                            'Issued ${issuedAt.day} ${_monthFull(issuedAt.month)} ${issuedAt.year}',
                            style: GoogleFonts.inter(fontSize: 11, color: Colors.white38),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (certUrl.isNotEmpty)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          if (certUrl.startsWith('template:') || certUrl.toLowerCase().contains('.html')) {
                            _downloadTemplatePdf(certUrl);
                          } else {
                            launchUrl(Uri.parse(certUrl), mode: LaunchMode.externalApplication);
                          }
                        },
                        icon: _isDownloadingCert 
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) 
                            : const Icon(Icons.visibility_rounded, size: 16),
                        label: Text(_isDownloadingCert ? 'Loading...' : 'View', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: navyColor,
                          side: BorderSide(color: navyColor.withValues(alpha: 0.5)),
                          backgroundColor: Colors.white.withValues(alpha: 0.07),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          if (certUrl.startsWith('template:') || certUrl.toLowerCase().contains('.html')) {
                            _downloadTemplatePdf(certUrl);
                          } else {
                            launchUrl(Uri.parse(certUrl), mode: LaunchMode.externalApplication);
                          }
                        },
                        icon: _isDownloadingCert
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.download_rounded, size: 16),
                        label: Text(_isDownloadingCert ? 'Loading...' : 'Download', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: tealColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ];
    } else if (_finalized) {
      return [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.amber.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              const SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Your certificate is being generated…',
                  style: GoogleFonts.inter(fontSize: 13, color: Colors.amber, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      ];
    }
    return [];
  }

  Widget _infoCard(IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: GoogleFonts.inter(fontSize: 10, color: Colors.white38)),
                Text(value,
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 13, fontWeight: FontWeight.w700, color: _cream),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _monthFull(int month) {
    const months = ['January','February','March','April','May','June',
        'July','August','September','October','November','December'];
    return months[month - 1];
  }
}
