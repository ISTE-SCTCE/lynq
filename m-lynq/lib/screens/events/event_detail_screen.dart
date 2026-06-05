import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme.dart';
import 'package:url_launcher/url_launcher.dart';

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

  Future<void> _loadEvent() async {
    final auth = ref.read(authProvider);
    final futures = await Future.wait([
      _supabase.from('events').select().eq('id', widget.eventId).single(),
      _supabase.from('attendance')
          .select('id')
          .eq('event_id', widget.eventId)
          .eq('user_id', auth.user?.id ?? '')
          .limit(1),
    ]);
    if (mounted) {
      setState(() {
        _event = futures[0] as Map<String, dynamic>;
        _isAttended = (futures[1] as List).isNotEmpty;
        _isLoading = false;
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
                                isMember ? 'Member Price' : 'Non-Member Price',
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
