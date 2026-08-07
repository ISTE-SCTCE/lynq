import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme.dart';

class EventListScreen extends ConsumerStatefulWidget {
  const EventListScreen({super.key});

  @override
  ConsumerState<EventListScreen> createState() => _EventListScreenState();
}

class _EventListScreenState extends ConsumerState<EventListScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _events = [];
  bool _isLoading = true;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    setState(() => _isLoading = true);
    try {
      final authState = ref.read(authProvider);
      final String userRole = authState.role;

      // Map 'user' (guest / not-iste member) → 'restricted' for event visibility,
      // since allowed_roles uses 'restricted' as the lowest member-facing tier.
      final String effectiveRole =
          (userRole.isEmpty || userRole == 'user') ? 'restricted' : userRole;

      // Fetch all events and filter client-side so we can also show events that
      // have no allowed_roles restriction at all (null / empty array = visible to everyone).
      final data = await _supabase
          .from('events')
          .select()
          .order('date', ascending: true);

      final all = (data as List).cast<Map<String, dynamic>>();

      final visible = all.where((e) {
        final roles = (e['allowed_roles'] as List?)?.cast<String>() ?? [];
        // No restriction → show to everyone
        if (roles.isEmpty) return true;
        // Show if the event is open to this user's effective role
        return roles.contains(effectiveRole);
      }).toList();

      if (mounted) {
        setState(() {
          _events = visible;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Filter events matching selected calendar date
  List<Map<String, dynamic>> get _eventsForSelectedDate {
    final dateStr = "${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}";
    return _events.where((e) {
      final eventDate = e['date'] as String? ?? '';
      final eventDateOnly = eventDate.split('T').first;
      return eventDateOnly == dateStr;
    }).toList();
  }

  // Helper to check if a specific date has any registered events
  bool _dateHasEvents(DateTime date) {
    final dateStr = "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
    return _events.any((e) {
      final eventDate = e['date'] as String? ?? '';
      final eventDateOnly = eventDate.split('T').first;
      return eventDateOnly == dateStr;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Determine if we should shrink based on number of events today
    final bool shouldShrink = _eventsForSelectedDate.length > 2;

    // Generate dates
    List<DateTime> daysToShow;
    if (shouldShrink) {
      // 2 weeks view
      daysToShow = List.generate(14, (i) {
        return _selectedDate.subtract(Duration(days: _selectedDate.weekday - 1)).add(Duration(days: i));
      });
    } else {
      // Full month view (42 days to cover all possible month spans)
      final firstDayOfMonth = DateTime(_selectedDate.year, _selectedDate.month, 1);
      final firstCalendarDay = firstDayOfMonth.subtract(Duration(days: firstDayOfMonth.weekday - 1));
      daysToShow = List.generate(42, (i) => firstCalendarDay.add(Duration(days: i)));
    }

    return Scaffold(
      backgroundColor: MemberTheme.mBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 10.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top circular Back Arrow
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: const BoxDecoration(
                    color: MemberTheme.mDarkCharcoal,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_back_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
              
              const SizedBox(height: 28),

              // Title "Course Schedule"
              Text(
                'Course Schedule',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  color: MemberTheme.mDarkCharcoal,
                ),
              ),

              const SizedBox(height: 12),

              // Month switcher header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _monthYearString(_selectedDate),
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: MemberTheme.mDarkCharcoal.withOpacity(0.85),
                    ),
                  ),
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedDate = DateTime(_selectedDate.year, _selectedDate.month - 1, 1);
                          });
                        },
                        child: const Icon(Icons.chevron_left_rounded, size: 28, color: MemberTheme.mDarkCharcoal),
                      ),
                      const SizedBox(width: 16),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedDate = DateTime(_selectedDate.year, _selectedDate.month + 1, 1);
                          });
                        },
                        child: const Icon(Icons.chevron_right_rounded, size: 28, color: MemberTheme.mDarkCharcoal),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Horizontal Calendar grid view
              _buildCalendarView(daysToShow, shouldShrink),

              const SizedBox(height: 28),

              // Active Schedule Header
              Text(
                'Today\'s Classes & Events',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: MemberTheme.mDarkCharcoal,
                ),
              ),

              const SizedBox(height: 16),

              // Detailed events list cards
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: MemberTheme.mSlate))
                    : _eventsForSelectedDate.isEmpty
                        ? _buildEmptyState()
                        : ListView.builder(
                            physics: const BouncingScrollPhysics(),
                            itemCount: _eventsForSelectedDate.length,
                            itemBuilder: (ctx, i) => _buildScheduleCard(_eventsForSelectedDate[i], ref.watch(authProvider).membershipId.isNotEmpty),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCalendarView(List<DateTime> days, bool isShrunk) {
    const weekdaysLabels = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.5),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: MemberTheme.mDarkCharcoal.withOpacity(0.06)),
      ),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 7,
          mainAxisSpacing: 10,
          crossAxisSpacing: 4,
          childAspectRatio: 0.8,
        ),
        itemCount: days.length,
        itemBuilder: (context, index) {
          final date = days[index];
          final isSelected = date.day == _selectedDate.day && date.month == _selectedDate.month && date.year == _selectedDate.year;
          final isToday = date.day == DateTime.now().day && date.month == DateTime.now().month && date.year == DateTime.now().year;
          final isCurrentMonth = date.month == _selectedDate.month;
          final hasEvents = _dateHasEvents(date);

          return GestureDetector(
            onTap: () => setState(() => _selectedDate = date),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (index < 7)
                  Text(
                    weekdaysLabels[date.weekday - 1],
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: MemberTheme.mDarkCharcoal.withOpacity(0.4),
                    ),
                  ),
                if (index < 7) const SizedBox(height: 6),
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected
                        ? MemberTheme.mDarkCharcoal
                        : hasEvents
                            ? MemberTheme.mLightSlate
                            : Colors.transparent,
                    border: isToday && !isSelected
                        ? Border.all(color: MemberTheme.mDarkCharcoal, style: BorderStyle.solid, width: 1.5)
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      '${date.day}',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isSelected
                            ? Colors.white
                            : (isCurrentMonth ? MemberTheme.mDarkCharcoal : MemberTheme.mDarkCharcoal.withOpacity(0.2)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildScheduleCard(Map<String, dynamic> event, bool isMember) {
    final location = event['location'] as String? ?? event['venue'] as String? ?? 'Seminar Hall';
    final isPaid = event['is_paid'] == true;
    final price = isPaid ? (isMember ? event['member_price'] : event['non_member_price']) : 0;
    final priceStr = isPaid ? '₹$price' : 'Free';

    return GestureDetector(
      onTap: () => context.push('/events/${event['id']}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: MemberTheme.mSlate,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: MemberTheme.mDarkCharcoal, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: MemberTheme.mSlate.withOpacity(0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                // Circular White Icon Shield
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.school_rounded,
                    color: MemberTheme.mSlate,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                
                // Details Column
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event['title'] as String? ?? 'Workshop',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$location • $priceStr',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.75),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            
            // Up-Right Arrow Indicator
            const Icon(
              Icons.north_east_rounded,
              color: Colors.white,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.6),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.event_note_rounded, size: 48, color: MemberTheme.mSlate),
          ),
          const SizedBox(height: 16),
          Text(
            'No courses or events scheduled',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: MemberTheme.mDarkCharcoal.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap another date on the calendar above',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: MemberTheme.mDarkCharcoal.withOpacity(0.4),
            ),
          ),
        ],
      ),
    );
  }

  String _monthYearString(DateTime date) {
    const months = [
      'Januar', 'Februar', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${months[date.month - 1]} ${date.year}';
  }
}
