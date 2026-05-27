import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EventListScreen extends ConsumerStatefulWidget {
  const EventListScreen({super.key});

  @override
  ConsumerState<EventListScreen> createState() => _EventListScreenState();
}

class _EventListScreenState extends ConsumerState<EventListScreen>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  late TabController _tabController;
  List<Map<String, dynamic>> _events = [];
  bool _isLoading = true;

  static const _terracotta = Color(0xFFD97D55);
  static const _cream = Color(0xFFF4E9D7);
  static const _teal = Color(0xFF6FA4AF);
  static const _bg = Color(0xFF141414);
  static const _surface = Color(0xFF1E1E1E);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadEvents();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadEvents() async {
    setState(() => _isLoading = true);
    try {
      final data = await _supabase
          .from('events')
          .select()
          .order('date', ascending: true);
      if (mounted) {
        setState(() {
          _events = (data as List).cast<Map<String, dynamic>>();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _upcoming => _events.where((e) {
    final d = DateTime.tryParse(e['date'] as String? ?? '');
    return d != null && d.isAfter(DateTime.now());
  }).toList();

  List<Map<String, dynamic>> get _past => _events.where((e) {
    final d = DateTime.tryParse(e['date'] as String? ?? '');
    return d != null && d.isBefore(DateTime.now());
  }).toList();

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
        title: Text('Events',
            style: GoogleFonts.spaceGrotesk(color: _cream, fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tabController,
          dividerColor: Colors.transparent,
          indicator: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: _terracotta.withValues(alpha: 0.2),
            border: Border.all(color: _terracotta.withValues(alpha: 0.4)),
          ),
          labelColor: _terracotta,
          unselectedLabelColor: Colors.white38,
          labelStyle: GoogleFonts.spaceGrotesk(fontSize: 13, fontWeight: FontWeight.w700),
          tabs: const [Tab(text: 'Upcoming'), Tab(text: 'Past')],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _terracotta))
          : RefreshIndicator(
              onRefresh: _loadEvents,
              color: _terracotta,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildList(_upcoming),
                  _buildList(_past, isPast: true),
                ],
              ),
            ),
    );
  }

  Widget _buildList(List<Map<String, dynamic>> events, {bool isPast = false}) {
    if (events.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_busy_rounded, size: 64, color: Colors.white12),
            const SizedBox(height: 16),
            Text(isPast ? 'No past events' : 'No upcoming events',
                style: GoogleFonts.inter(color: Colors.white24, fontSize: 16)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      itemCount: events.length,
      itemBuilder: (ctx, i) => _buildEventCard(events[i], isPast: isPast),
    );
  }

  Widget _buildEventCard(Map<String, dynamic> event, {bool isPast = false}) {
    final date = DateTime.tryParse(event['date'] as String? ?? '');
    final daysLeft = date != null ? date.difference(DateTime.now()).inDays : null;

    return GestureDetector(
      onTap: () => context.push('/events/${event['id']}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _surface.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isPast
                ? Colors.white.withValues(alpha: 0.04)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          children: [
            // Date block
            Container(
              width: 52, height: 56,
              decoration: BoxDecoration(
                color: isPast
                    ? Colors.white.withValues(alpha: 0.04)
                    : _terracotta.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: date != null ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('${date.day}',
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 20, fontWeight: FontWeight.bold,
                          color: isPast ? Colors.white38 : _terracotta)),
                  Text(_monthAbbr(date.month),
                      style: GoogleFonts.inter(
                          fontSize: 10,
                          color: isPast ? Colors.white24 : _terracotta.withValues(alpha: 0.7))),
                ],
              ) : const Icon(Icons.calendar_today_rounded, color: Colors.white38),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(event['title'] as String? ?? '',
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 15, fontWeight: FontWeight.w700,
                          color: isPast ? Colors.white54 : _cream),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.location_on_rounded, size: 12, color: Colors.white24),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(event['venue'] as String? ?? '',
                            style: GoogleFonts.inter(fontSize: 12, color: Colors.white38),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (daysLeft != null && !isPast)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: daysLeft == 0
                      ? _terracotta.withValues(alpha: 0.2)
                      : _teal.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  daysLeft == 0 ? 'Today!' : daysLeft < 0 ? 'Ended' : '${daysLeft}d',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 12, fontWeight: FontWeight.bold,
                      color: daysLeft == 0 ? _terracotta : _teal),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _monthAbbr(int month) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return months[month - 1];
  }
}
