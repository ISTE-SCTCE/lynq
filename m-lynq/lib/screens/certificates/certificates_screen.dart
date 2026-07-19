import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/providers/auth_provider.dart';

class CertificatesScreen extends ConsumerStatefulWidget {
  const CertificatesScreen({super.key});

  @override
  ConsumerState<CertificatesScreen> createState() => _CertificatesScreenState();
}

class _CertificatesScreenState extends ConsumerState<CertificatesScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _certificates = [];
  bool _isLoading = true;

  static const _terracotta = Color(0xFFD97D55);
  static const _cream = Color(0xFFF4E9D7);
  static const _gold = Color(0xFFD4AF37);
  static const _bg = Color(0xFF141414);
  static const _surface = Color(0xFF1E1E1E);
  static const _teal = Color(0xFF6FA4AF);

  @override
  void initState() {
    super.initState();
    _loadCertificates();
  }

  Future<void> _loadCertificates() async {
    final auth = ref.read(authProvider);
    try {
      final data = await _supabase
          .from('certificates')
          .select('*, events(title, date)')
          .eq('user_id', auth.user?.id ?? '')
          .order('issued_at', ascending: false);
      if (mounted) {
        setState(() {
          _certificates = (data as List).map((item) {
            final map = Map<String, dynamic>.from(item as Map);
            // Use joined event title as description if description field is empty
            if ((map['description'] == null || (map['description'] as String).isEmpty) &&
                map['events'] != null) {
              final event = map['events'] as Map<String, dynamic>;
              map['description'] = 'Awarded for attending ${event['title'] ?? ''}';
            }
            // Use event title as certificate title if missing
            if ((map['title'] == null || (map['title'] as String).isEmpty) &&
                map['events'] != null) {
              final event = map['events'] as Map<String, dynamic>;
              map['title'] = 'Certificate of Participation – ${event['title'] ?? 'Event'}';
            }
            return map;
          }).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('My Certificates',
            style: GoogleFonts.spaceGrotesk(color: _cream, fontWeight: FontWeight.bold)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _terracotta))
          : _certificates.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.workspace_premium_rounded,
                          size: 80, color: Colors.white12),
                      const SizedBox(height: 20),
                      Text('No certificates yet',
                          style: GoogleFonts.inter(color: Colors.white38, fontSize: 16)),
                      const SizedBox(height: 8),
                      Text('Attend events to earn certificates',
                          style: GoogleFonts.inter(color: Colors.white24, fontSize: 13)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _certificates.length,
                  itemBuilder: (ctx, i) => _buildCertCard(_certificates[i]),
                ),
    );
  }

  Widget _buildCertCard(Map<String, dynamic> cert) {
    final issuedAt = DateTime.tryParse(cert['issued_at'] as String? ?? '');

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _gold.withValues(alpha: 0.1),
            _surface.withValues(alpha: 0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _gold.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          // Gold seal
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [_gold.withValues(alpha: 0.3), _gold.withValues(alpha: 0.05)],
              ),
              border: Border.all(color: _gold.withValues(alpha: 0.5), width: 1.5),
            ),
            child: const Center(
              child: Icon(Icons.workspace_premium_rounded, size: 24, color: _gold),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(cert['title'] as String? ?? 'Certificate',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 15, fontWeight: FontWeight.w700, color: _cream)),
                const SizedBox(height: 4),
                Text(cert['description'] as String? ?? '',
                    style: GoogleFonts.inter(fontSize: 12, color: Colors.white38),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                if (issuedAt != null)
                  Text(
                    'Issued ${issuedAt.day} ${_monthFull(issuedAt.month)} ${issuedAt.year}',
                    style: GoogleFonts.inter(fontSize: 11, color: Colors.white24),
                  ),
              ],
            ),
          ),
          if (cert['file_url'] != null) ...
            [
              IconButton(
                onPressed: () => launchUrl(Uri.parse(cert['file_url'] as String),
                    mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.download_rounded, color: _gold),
                style: IconButton.styleFrom(
                  backgroundColor: _gold.withValues(alpha: 0.1),
                ),
                tooltip: 'Download',
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: () => Share.share(
                  'My certificate from ISTE: ${cert['file_url']}',
                  subject: cert['title'] as String? ?? 'ISTE Certificate',
                ),
                icon: const Icon(Icons.share_rounded, color: _teal),
                style: IconButton.styleFrom(
                  backgroundColor: _teal.withValues(alpha: 0.1),
                ),
                tooltip: 'Share',
              ),
            ],
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
