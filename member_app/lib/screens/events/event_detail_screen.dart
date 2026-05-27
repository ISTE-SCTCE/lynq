import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/providers/auth_provider.dart';

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
  static const _teal = Color(0xFF6FA4AF);
  static const _bg = Color(0xFF141414);
  static const _surface = Color(0xFF1E1E1E);

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
    final daysLeft = date != null ? date.difference(DateTime.now()).inDays : null;
    final isPast = daysLeft != null && daysLeft < 0;

    return Scaffold(
      backgroundColor: _bg,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            backgroundColor: _bg,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      _terracotta.withValues(alpha: 0.25),
                      _bg,
                    ],
                  ),
                ),
                child: Padding(
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
                                ? _terracotta.withValues(alpha: 0.2)
                                : _teal.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: daysLeft == 0
                                    ? _terracotta.withValues(alpha: 0.5)
                                    : _teal.withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            daysLeft == 0 ? '🔥 Today!' : '${daysLeft} days away',
                            style: GoogleFonts.inter(
                                fontSize: 12, fontWeight: FontWeight.w700,
                                color: daysLeft == 0 ? _terracotta : _teal),
                          ),
                        ),
                      const SizedBox(height: 10),
                      Text(event['title'] as String? ?? '',
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 24, fontWeight: FontWeight.bold, color: _cream)),
                    ],
                  ),
                ),
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
                          _terracotta)),
                      const SizedBox(width: 12),
                      Expanded(child: _infoCard(Icons.access_time_rounded, 'Time',
                          event['time'] as String? ?? '—', _teal)),
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
                  if (event['description'] != null) ...[
                    Text('About',
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 16, fontWeight: FontWeight.bold, color: _cream)),
                    const SizedBox(height: 10),
                    Text(event['description'] as String,
                        style: GoogleFonts.inter(fontSize: 14, color: Colors.white60, height: 1.6)),
                  ],
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
