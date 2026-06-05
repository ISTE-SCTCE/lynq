import 'dart:ui';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme.dart';
import '../../shared/mlynq_illustrations.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _supabase = Supabase.instance.client;
  int _selectedIndex = 0;
  List<Map<String, dynamic>> _ongoingEvents = [];
  List<Map<String, dynamic>> _upcomingEvents = [];
  List<Map<String, dynamic>> _pastEvents = [];
  List<Map<String, dynamic>> _announcements = [];
  bool _isLoading = true;
  String _selectedCategory = 'All';

  // Cached section widgets — rebuilt only when data or category changes
  List<Widget>? _cachedSections;
  String? _cachedSectionsCategory;

  final List<String> _categories = ['All', 'Announcements', 'Workshops', 'Tech Talks', 'Hackathons', 'Meetups', 'Seminars'];

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
            .select('id, title, date, location, type, description, poster_url, is_paid, member_price')
            .order('date', ascending: true),
        _supabase
            .from('announcements')
            .select('id, title, description, content, status, created_at')
            .eq('status', 'active')
            .order('created_at', ascending: false),
        _supabase
            .from('attendance')
            .select('id')
            .eq('user_id', auth.user?.id ?? ''),
      ]);
      if (mounted) {
        final allEvents = (futures[0] as List).cast<Map<String, dynamic>>();
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);

        final ongoing = <Map<String, dynamic>>[];
        final upcoming = <Map<String, dynamic>>[];
        final past = <Map<String, dynamic>>[];

        for (var e in allEvents) {
          final eDate = DateTime.parse(e['date']).toLocal();
          final eventDay = DateTime(eDate.year, eDate.month, eDate.day);
          if (eventDay.isAtSameMomentAs(today)) {
            ongoing.add(e);
          } else if (eventDay.isAfter(today)) {
            upcoming.add(e);
          } else {
            past.add(e);
          }
        }

        setState(() {
          _ongoingEvents = ongoing;
          _upcomingEvents = upcoming;
          _pastEvents = past.reversed.toList(); // most recent past first
          _announcements = (futures[1] as List).cast<Map<String, dynamic>>();
          // futures[2] = attendance count (reserved for future badge display)
          _isLoading = false;
          _cachedSections = null; // invalidate section cache on data refresh
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _cachedSections = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final firstName = auth.name.isNotEmpty ? auth.name.split(' ').first : 'Member';
    final membershipValid = auth.isMembershipValid;

    return Scaffold(
      backgroundColor: MemberTheme.mBackground,
      body: Stack(
        children: [
          // Background soft design halo
          Positioned(
            top: -50,
            left: -50,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFC5D9EB).withOpacity(0.3),
              ),
            ),
          ),
          
          SafeArea(
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                // Top Custom Header (Avatar + Greetings)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Greetings & Avatar Row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  firstName,
                                  style: GoogleFonts.spaceGrotesk(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                    color: MemberTheme.mDarkCharcoal,
                                  ),
                                ),
                                Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: const BoxDecoration(
                                        color: Colors.green,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      membershipValid ? 'Basic Plan' : 'Expired Plan',
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        color: MemberTheme.mDarkCharcoal.withOpacity(0.5),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            
                            // User Avatar Profile Picture
                            GestureDetector(
                              onTap: () => context.push('/membership'),
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: MemberTheme.mDarkCharcoal, width: 2),
                                ),
                                child: CircleAvatar(
                                  radius: 22,
                                  backgroundColor: MemberTheme.mLightSlate,
                                  backgroundImage: Platform.environment.containsKey('FLUTTER_TEST')
                                      ? null
                                      : NetworkImage('https://api.dicebear.com/7.x/notionists/png?seed=${auth.name.isNotEmpty ? auth.name : "Member"}') as ImageProvider,
                                ),
                              ),
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 28),
                        
                        // "What would you like to explore today?" title
                        Text(
                          'What would you like\nto explore today?',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
                            color: MemberTheme.mDarkCharcoal,
                            height: 1.15,
                          ),
                        ),
                        
                        const SizedBox(height: 24),
                        
                        // Horizontal category pill row
                        _buildCategoryRow(),
                        
                        const SizedBox(height: 28),
                      ],
                    ),
                  ),
                ),

                // Main Card Illustration List
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  sliver: Builder(builder: (context) {
                    // Rebuild sections only when category changes or data reloads
                    if (_cachedSections == null || _cachedSectionsCategory != _selectedCategory) {
                      _cachedSections = _buildSections();
                      _cachedSectionsCategory = _selectedCategory;
                    }
                    final sections = _cachedSections!;
                    return SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => index < sections.length ? sections[index] : null,
                        childCount: sections.length,
                      ),
                    );
                  }),
                ),
                // Spacer for Bottom Nav padding
                const SliverToBoxAdapter(child: SizedBox(height: 120)),
              ],
            ),
          ),

          // Floating capsule navigation bar
          Positioned(
            bottom: 20,
            left: 24,
            right: 24,
            child: _buildFloatingBottomNav(),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildSections() {
    if (_isLoading) {
      return [const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))];
    }
    
    final styles = [
      {
        'bg': MemberTheme.mSlate,
        'text': Colors.white,
        'btn': Colors.white,
        'btnText': MemberTheme.mDarkCharcoal,
        'illustration': const MlynqDeskIllustration(baseColor: Color(0xFFFBE4D5)),
      },
      {
        'bg': MemberTheme.mPastelLavender,
        'text': MemberTheme.mDarkCharcoal,
        'btn': MemberTheme.mDarkCharcoal,
        'btnText': Colors.white,
        'illustration': const MlynqDeskIllustration(baseColor: MemberTheme.mSlate),
      },
      {
        'bg': MemberTheme.mPastelPeach,
        'text': MemberTheme.mDarkCharcoal,
        'btn': MemberTheme.mDarkCharcoal,
        'btnText': Colors.white,
        'illustration': const MlynqDeskIllustration(baseColor: Colors.orangeAccent),
      },
    ];

    List<Widget> widgets = [];
    int styleIdx = 0;

    void addEventList(String title, List<Map<String, dynamic>> items, bool isAnnouncement) {
      final filtered = _selectedCategory == 'All' 
          ? items 
          : (isAnnouncement 
              ? (_selectedCategory == 'Announcements' ? items : [])
              : items.where((e) => e['type'] == _selectedCategory || (e['type'] as String?)?.toLowerCase() == _selectedCategory.toLowerCase()).toList());

      if (filtered.isEmpty) return;

      widgets.add(Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 16),
        child: Text(
          title,
          style: GoogleFonts.spaceGrotesk(fontSize: 20, fontWeight: FontWeight.bold, color: MemberTheme.mDarkCharcoal),
        ),
      ));

      for (var e in filtered) {
        final s = styles[styleIdx % styles.length];
        styleIdx++;
        
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: isAnnouncement
              ? _buildPromoCard(
                  title: e['title'] ?? 'Announcement',
                  subtitle: e['description'] ?? 'Updates & Info',
                  backgroundColor: s['bg'] as Color,
                  textColor: s['text'] as Color,
                  btnLabel: 'View Details',
                  btnColor: s['btn'] as Color,
                  btnTextColor: s['btnText'] as Color,
                  illustration: s['illustration'] as Widget,
                  onTap: () {},
                )
              : _buildEventPromoCard(
                  title: e['title'] ?? 'Event',
                  subtitle: e['type'] ?? 'General Event',
                  backgroundColor: s['bg'] as Color,
                  textColor: s['text'] as Color,
                  illustration: s['illustration'] as Widget,
                  onMoreDetails: () => context.push('/events/${e['id']}'),
                  // Register Now navigates to the same detail screen
                  // where the user can see registration options
                  onRegister: () => context.push('/events/${e['id']}'),
                ),
        ));
      }
    }

    if (_selectedCategory == 'All' || _selectedCategory == 'Announcements') {
      addEventList('Latest Announcements', _announcements, true);
    }
    
    if (_selectedCategory != 'Announcements') {
      addEventList('Ongoing Events', _ongoingEvents, false);
      addEventList('Upcoming Events', _upcomingEvents, false);
      addEventList('Past Events', _pastEvents, false);
    }

    if (widgets.isEmpty) {
      widgets.add(Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Text('No events found for $_selectedCategory', style: GoogleFonts.inter(color: Colors.grey)),
        ),
      ));
    }

    return widgets;
  }

  Widget _buildCategoryRow() {
    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final cat = _categories[index];
          final isSelected = _selectedCategory == cat;
          return GestureDetector(
            onTap: () => setState(() => _selectedCategory = cat),
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? MemberTheme.mWhite : Colors.transparent,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: isSelected ? MemberTheme.mDarkCharcoal : MemberTheme.mDarkCharcoal.withOpacity(0.08),
                  width: isSelected ? 1.8 : 1,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: MemberTheme.mDarkCharcoal.withOpacity(0.06),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        )
                      ]
                    : null,
              ),
              child: Center(
                child: Text(
                  cat,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: MemberTheme.mDarkCharcoal,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEventPromoCard({
    required String title,
    required String subtitle,
    required Color backgroundColor,
    required Color textColor,
    required Widget illustration,
    required VoidCallback onMoreDetails,
    required VoidCallback onRegister,
  }) {
    return Container(
      width: double.infinity,
      height: 230,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: MemberTheme.mDarkCharcoal, width: 2),
      ),
      child: Stack(
        children: [
          // Illustration alignment
          Positioned(
            bottom: 20,
            right: 14,
            child: Opacity(
              opacity: 0.8,
              child: SizedBox(
                width: 140,
                height: 140,
                child: illustration,
              ),
            ),
          ),
          
          // Content Left side
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: textColor,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: textColor.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
                
                // Two Buttons (More Details & Register Now)
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: onMoreDetails,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: MemberTheme.mDarkCharcoal, width: 1.5),
                          ),
                          child: Center(
                            child: Text(
                              'More Details',
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: MemberTheme.mDarkCharcoal,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        onTap: onRegister,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: MemberTheme.mDarkCharcoal,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: MemberTheme.mDarkCharcoal, width: 1.5),
                          ),
                          child: Center(
                            child: Text(
                              'Register Now',
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPromoCard({
    required String title,
    required String subtitle,
    required Color backgroundColor,
    required Color textColor,
    required String btnLabel,
    required Color btnColor,
    required Color btnTextColor,
    required Widget illustration,
    required VoidCallback onTap,
  }) {
    return Container(
      width: double.infinity,
      height: 230,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: MemberTheme.mDarkCharcoal, width: 2),
      ),
      child: Stack(
        children: [
          // Illustration alignment
          Positioned(
            bottom: 20,
            right: 14,
            child: illustration,
          ),
          
          // Content Left side
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: textColor,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: textColor.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
                
                // Bottom Button and Icon Action row
                Row(
                  children: [
                    // Pill CTA label
                    GestureDetector(
                      onTap: onTap,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                        decoration: BoxDecoration(
                          color: btnColor,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: MemberTheme.mDarkCharcoal, width: 1.5),
                        ),
                        child: Text(
                          btnLabel,
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: btnTextColor,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    
                    // Black Play button circle
                    GestureDetector(
                      onTap: onTap,
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(
                          color: MemberTheme.mDarkCharcoal,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.arrow_forward_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingBottomNav() {
    final items = [
      _BottomNavItem(Icons.home_filled, 'Home', '/home'),
      _BottomNavItem(Icons.calendar_month_rounded, 'Schedule', '/events'),
      _BottomNavItem(Icons.qr_code_2_rounded, 'QR Code', '/qr'),
      _BottomNavItem(Icons.workspace_premium_rounded, 'Certificates', '/certificates'),
    ];

    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 74,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.85),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: MemberTheme.mDarkCharcoal.withOpacity(0.12), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: MemberTheme.mDarkCharcoal.withOpacity(0.08),
                blurRadius: 20,
                offset: const Offset(0, 10),
              )
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: items.asMap().entries.map((entry) {
                final idx = entry.key;
                final item = entry.value;
                final isSelected = _selectedIndex == idx;

                return GestureDetector(
                  onTap: () {
                    setState(() => _selectedIndex = idx);
                    if (item.route != '/home') {
                      context.push(item.route);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isSelected ? MemberTheme.mDarkCharcoal : Colors.transparent,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      item.icon,
                      size: 24,
                      color: isSelected ? Colors.white : MemberTheme.mDarkCharcoal.withOpacity(0.5),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomNavItem {
  final IconData icon;
  final String label;
  final String route;
  const _BottomNavItem(this.icon, this.label, this.route);
}
