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
  RealtimeChannel? _eventsChannel;

  @override
  void initState() {
    super.initState();
    _loadEvents();
    _setupRealtime();
  }

  void _setupRealtime() {
    _eventsChannel = _supabase.channel('public:events_mlynq');
    _eventsChannel!.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'events',
      callback: (_) {
        if (mounted) _loadEvents();
      },
    ).subscribe();
  }

  @override
  void dispose() {
    _eventsChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadEvents() async {
    setState(() => _isLoading = true);
    try {
      final authState = ref.read(authProvider);
      final String userRole = authState.role.toLowerCase();

      // Fetch all events ordered by date
      final data = await _supabase
          .from('events')
          .select()
          .order('date', ascending: true);

      final all = (data as List).cast<Map<String, dynamic>>();

      // Filter events visible to members (matching home screen behavior)
      final visible = all.where((e) {
        final roles = (e['allowed_roles'] as List?)?.map((r) => r.toString().toLowerCase()).toList() ?? [];
        // No restriction or empty list → visible to everyone
        if (roles.isEmpty) return true;
        // Visible if open to user's role or standard member tiers
        if (roles.contains('member') || roles.contains('restricted') || roles.contains('user')) return true;
        if (userRole.isNotEmpty && roles.contains(userRole)) return true;
        return true; // Default to visible so execom-created events are shown
      }).toList();

      if (mounted) {
        setState(() {
          _events = visible;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading events: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Robust date comparison handling ISO timestamps, UTC/local conversion, and YYYY-MM-DD strings
  bool _isSameCalendarDay(dynamic rawDate, DateTime targetDay) {
    if (rawDate == null) return false;
    final String s = rawDate.toString().trim();
    if (s.isEmpty) return false;

    // 1. Parse DateTime if possible
    final dt = DateTime.tryParse(s);
    if (dt != null) {
      final local = dt.toLocal();
      if (local.year == targetDay.year && local.month == targetDay.month && local.day == targetDay.day) {
        return true;
      }
      if (dt.year == targetDay.year && dt.month == targetDay.month && dt.day == targetDay.day) {
        return true;
      }
    }

    // 2. YYYY-MM-DD string match fallback
    final dateOnly = s.split('T').first.split(' ').first;
    final monthStr = targetDay.month.toString().padLeft(2, '0');
    final dayStr = targetDay.day.toString().padLeft(2, '0');
    final targetFormatted = "${targetDay.year}-$monthStr-$dayStr";
    return dateOnly == targetFormatted;
  }

  // Filter events matching selected calendar date
  List<Map<String, dynamic>> get _eventsForSelectedDate {
    return _events.where((e) => _isSameCalendarDay(e['date'], _selectedDate)).toList();
  }

  // Helper to check if a specific date has any registered events
  bool _dateHasEvents(DateTime date) {
    return _events.any((e) => _isSameCalendarDay(e['date'], date));
  }

  @override
  Widget build(BuildContext context) {
    // Generate full month view (42 days)
    final firstDayOfMonth = DateTime(_selectedDate.year, _selectedDate.month, 1);
    final firstCalendarDay = firstDayOfMonth.subtract(Duration(days: firstDayOfMonth.weekday - 1));
    final List<DateTime> daysToShow = List.generate(42, (i) => firstCalendarDay.add(Duration(days: i)));

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
                      color: MemberTheme.mDarkCharcoal.withValues(alpha: 0.85),
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
              _buildCalendarView(daysToShow),

              const SizedBox(height: 28),

              // Active Schedule Header
              Text(
                'Events for ${_selectedDate.day} ${_monthYearString(_selectedDate).split(' ').first}',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: MemberTheme.mDarkCharcoal,
                ),
              ),

              const SizedBox(height: 16),

              // Detailed events list cards with RefreshIndicator
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _loadEvents,
                  color: MemberTheme.mSlate,
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator(color: MemberTheme.mSlate))
                      : _eventsForSelectedDate.isEmpty
                          ? _buildEmptyState()
                          : ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                              itemCount: _eventsForSelectedDate.length,
                              itemBuilder: (ctx, i) => _buildScheduleCard(
                                _eventsForSelectedDate[i],
                                ref.watch(authProvider).membershipId.isNotEmpty,
                              ),
                            ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCalendarView(List<DateTime> days) {
    const weekdaysLabels = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: MemberTheme.mDarkCharcoal.withValues(alpha: 0.06)),
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
                      color: MemberTheme.mDarkCharcoal.withValues(alpha: 0.4),
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
                            : (isCurrentMonth ? MemberTheme.mDarkCharcoal : MemberTheme.mDarkCharcoal.withValues(alpha: 0.2)),
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
              color: MemberTheme.mSlate.withValues(alpha: 0.2),
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
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event['title'] as String? ?? 'Workshop',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$location • $priceStr',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.75),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
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
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      children: [
        const SizedBox(height: 40),
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.event_note_rounded, size: 48, color: MemberTheme.mSlate),
              ),
              const SizedBox(height: 16),
              Text(
                'No events scheduled for this day',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: MemberTheme.mDarkCharcoal.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Tap highlighted dates on the calendar above',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: MemberTheme.mDarkCharcoal.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _monthYearString(DateTime date) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${months[date.month - 1]} ${date.year}';
  }
}
