import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/providers/auth_provider.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _supabase = Supabase.instance.client;
  int _selectedIndex = 0;
  List<Map<String, dynamic>> _upcomingEvents = [];
  int _attendanceCount = 0;
  bool _isLoading = true;

  static const _terracotta = Color(0xFFD97D55);
  static const _cream = Color(0xFFF4E9D7);
  static const _sage = Color(0xFFB8C4A9);
  static const _teal = Color(0xFF6FA4AF);
  static const _bg = Color(0xFF141414);
  static const _surface = Color(0xFF1E1E1E);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final auth = ref.read(authProvider);
      final futures = await Future.wait([
        _supabase
            .from('events')
            .select('id, title, date, venue, type')
            .gte('date', DateTime.now().toIso8601String())
            .order('date', ascending: true)
            .limit(5),
        _supabase
            .from('attendance')
            .select('id')
            .eq('user_id', auth.user?.id ?? ''),
      ]);
      if (mounted) {
        setState(() {
          _upcomingEvents = (futures[0] as List).cast<Map<String, dynamic>>();
          _attendanceCount = (futures[1] as List).length;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final firstName = auth.name.split(' ').first;
    final membershipValid = auth.isMembershipValid;

    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          // Background
          Positioned(
            top: -80, right: -60,
            child: Container(
              width: 250, height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  _terracotta.withValues(alpha: 0.1), Colors.transparent,
                ]),
              ),
            ),
          ),
          // Main content
          CustomScrollView(
            slivers: [
              _buildSliverHeader(firstName, auth),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    if (!membershipValid) _buildMembershipWarning(),
                    const SizedBox(height: 24),
                    _buildStatsRow(auth),
                    const SizedBox(height: 28),
                    _buildQuickActions(context),
                    const SizedBox(height: 28),
                    _buildUpcomingEvents(),
                  ]),
                ),
              ),
            ],
          ),
          // Bottom Nav
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: _buildBottomNav(),
          ),
        ],
      ),
    );
  }

  SliverAppBar _buildSliverHeader(String firstName, MemberAuthState auth) {
    final daysLeft = auth.daysUntilExpiry;
    return SliverAppBar(
      expandedHeight: 180,
      pinned: true,
      backgroundColor: _bg,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          padding: const EdgeInsets.fromLTRB(24, 60, 24, 20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _terracotta.withValues(alpha: 0.15),
                _bg,
              ],
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Hello,', style: GoogleFonts.inter(fontSize: 16, color: Colors.white38)),
              Text(
                '$firstName! 👋',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 32, fontWeight: FontWeight.bold, color: _cream),
              ),
              const SizedBox(height: 4),
              if (daysLeft >= 0)
                Row(
                  children: [
                    Icon(Icons.card_membership_rounded, size: 14, color: _sage),
                    const SizedBox(width: 6),
                    Text(
                      daysLeft > 30
                          ? 'Membership valid'
                          : 'Expires in $daysLeft days',
                      style: GoogleFonts.inter(
                          fontSize: 12,
                          color: daysLeft > 30 ? _sage : _terracotta,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.notifications_outlined, color: Colors.white70),
          onPressed: () => context.push('/notifications'),
        ),
      ],
    );
  }

  Widget _buildMembershipWarning() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Your membership has expired. Contact admin to renew.',
              style: GoogleFonts.inter(fontSize: 13, color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow(MemberAuthState auth) {
    return Row(
      children: [
        Expanded(child: _statCard('Events Attended', '$_attendanceCount', Icons.event_available_rounded, _teal)),
        const SizedBox(width: 12),
        Expanded(child: _statCard('Membership', auth.isMembershipValid ? 'Active' : 'Expired',
            Icons.verified_rounded, auth.isMembershipValid ? _sage : Colors.red)),
        const SizedBox(width: 12),
        Expanded(child: _statCard('Branch', auth.profile?['branch'] as String? ?? '—',
            Icons.school_rounded, _terracotta)),
      ],
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _surface.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Column(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(height: 8),
              Text(value,
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 14, fontWeight: FontWeight.bold, color: _cream),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(label,
                  style: GoogleFonts.inter(fontSize: 9, color: Colors.white38),
                  textAlign: TextAlign.center, maxLines: 2),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    final actions = [
      _QAction('My QR', Icons.qr_code_rounded, _terracotta, () => context.push('/qr')),
      _QAction('Events', Icons.event_rounded, _teal, () => context.push('/events')),
      _QAction('Card', Icons.credit_card_rounded, _sage, () => context.push('/membership')),
      _QAction('Certs', Icons.workspace_premium_rounded, const Color(0xFFD4AF37),
          () => context.push('/certificates')),
    ];

    return Row(
      children: actions.map((a) {
        return Expanded(
          child: GestureDetector(
            onTap: a.onTap,
            child: Container(
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: a.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: a.color.withValues(alpha: 0.25)),
              ),
              child: Column(
                children: [
                  Icon(a.icon, color: a.color, size: 26),
                  const SizedBox(height: 8),
                  Text(a.label,
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 11, color: a.color, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        );
      }).toList()
        ..removeLast(), // remove last right margin
    );
  }

  Widget _buildUpcomingEvents() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Upcoming Events',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 18, fontWeight: FontWeight.bold, color: _cream)),
            TextButton(
              onPressed: () => context.push('/events'),
              child: Text('See all',
                  style: GoogleFonts.inter(color: Colors.white38, fontSize: 13)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_isLoading)
          const Center(child: CircularProgressIndicator(color: _terracotta))
        else if (_upcomingEvents.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('No upcoming events',
                  style: GoogleFonts.inter(color: Colors.white38)),
            ),
          )
        else
          ..._upcomingEvents.map((e) => _buildEventCard(e)),
      ],
    );
  }

  Widget _buildEventCard(Map<String, dynamic> event) {
    final date = DateTime.tryParse(event['date'] as String? ?? '');
    final daysLeft = date != null ? date.difference(DateTime.now()).inDays : null;

    return GestureDetector(
      onTap: () => context.push('/events/${event['id']}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _surface.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: [
            // Date block
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: _terracotta.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (date != null) ...[
                    Text('${date.day}',
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 18, fontWeight: FontWeight.bold, color: _terracotta)),
                    Text(_monthAbbr(date.month),
                        style: GoogleFonts.inter(fontSize: 10, color: _terracotta.withValues(alpha: 0.7))),
                  ] else
                    const Icon(Icons.calendar_today_rounded, size: 20, color: _terracotta),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(event['title'] as String? ?? '',
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 14, fontWeight: FontWeight.w700, color: _cream),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(event['venue'] as String? ?? '',
                      style: GoogleFonts.inter(fontSize: 12, color: Colors.white38),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (daysLeft != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: daysLeft <= 3
                      ? Colors.red.withValues(alpha: 0.15)
                      : _teal.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  daysLeft == 0 ? 'Today!' : '${daysLeft}d',
                  style: GoogleFonts.inter(
                      fontSize: 11, fontWeight: FontWeight.w700,
                      color: daysLeft <= 3 ? Colors.redAccent : _teal),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    final items = [
      _NavItem(Icons.home_rounded, 'Home'),
      _NavItem(Icons.event_rounded, 'Events'),
      _NavItem(Icons.qr_code_rounded, 'My QR'),
      _NavItem(Icons.workspace_premium_rounded, 'Certs'),
    ];

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          height: 80,
          decoration: BoxDecoration(
            color: _surface.withValues(alpha: 0.9),
            border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
          ),
          child: Row(
            children: items.asMap().entries.map((entry) {
              final idx = entry.key;
              final item = entry.value;
              final isSelected = _selectedIndex == idx;

              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() => _selectedIndex = idx);
                    switch (idx) {
                      case 0: break; // already on home
                      case 1: context.push('/events');
                      case 2: context.push('/qr');
                      case 3: context.push('/certificates');
                    }
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? _terracotta.withValues(alpha: 0.15)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          item.icon,
                          size: 22,
                          color: isSelected ? _terracotta : Colors.white38,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.label,
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? _terracotta : Colors.white24,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  String _monthAbbr(int month) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return months[month - 1];
  }
}

class _QAction {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _QAction(this.label, this.icon, this.color, this.onTap);
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem(this.icon, this.label);
}
