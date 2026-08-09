import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/auth_provider.dart';
import '../../core/permission_engine.dart';
import '../../core/theme.dart';
import '../../core/constants.dart';
import '../../models/app_models.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/liquid_glass_nav_bar.dart';
import 'certificate_issuance_screen.dart';
import '../attendance/attendance_report_screen.dart';
import 'package:provider/provider.dart';

class EventListScreen extends StatefulWidget {
  final int? folderId;
  const EventListScreen({super.key, this.folderId});

  @override
  State<EventListScreen> createState() => _EventListScreenState();
}

class _EventListScreenState extends State<EventListScreen> {
  List<EventModel> _events = [];
  final Map<String, String> _creatorRoles = {};
  bool _isLoading = true;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  CalendarFormat _calendarFormat = CalendarFormat.twoWeeks;

  RealtimeChannel? _eventsChannel;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _loadEvents();
    _setupRealtime();
  }

  void _setupRealtime() {
    _eventsChannel = Supabase.instance.client.channel('public:events');
    _eventsChannel!.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'events',
      callback: (payload) {
        if (!mounted) return;
        final eventType = payload.eventType;
        if (eventType == PostgresChangeEvent.insert) {
          final newEvent = EventModel.fromJson(payload.newRecord);
          setState(() {
            _events.insert(0, newEvent);
          });
        } else if (eventType == PostgresChangeEvent.update) {
          final updatedEvent = EventModel.fromJson(payload.newRecord);
          setState(() {
            final index = _events.indexWhere((e) => e.id == updatedEvent.id);
            if (index != -1) _events[index] = updatedEvent;
          });
        } else if (eventType == PostgresChangeEvent.delete) {
          final deletedId = payload.oldRecord['id'] as int;
          setState(() {
            _events.removeWhere((e) => e.id == deletedId);
          });
        }
      },
    ).subscribe();
  }

  @override
  void dispose() {
    _eventsChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadEvents() async {
    try {
      var query = Supabase.instance.client
          .from('events')
          .select();
          
      if (widget.folderId != null) {
        query = query.eq('execom_id', widget.folderId!);
      }

      final data = await query
          .order('date', ascending: false)
          .range(0, 100); // Lazy loading the first 100 events
          
      final userIds = (data as List).map((e) => e['created_by']).where((id) => id != null).toSet().toList();
      if (userIds.isNotEmpty) {
        final usersData = await Supabase.instance.client.from('profiles').select('id, role').inFilter('id', userIds);
        for(var u in usersData) {
          _creatorRoles[u['id']] = u['role'];
        }
      }

      _events = (data as List).map((e) => EventModel.fromJson(e)).toList();
    } catch (e) {
      debugPrint('Error: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  bool _canDeleteEvent(EventModel event, PermissionEngine perms) {
    if (perms.isEffectivelyTier1) return true;
    if (event.createdBy != null && event.createdBy == perms.user.id) return true;
    
    if (event.createdBy != null) {
      final creatorRoleStr = _creatorRoles[event.createdBy];
      if (creatorRoleStr != null) {
        final creatorRole = AppRole.fromString(creatorRoleStr);
        if (perms.role > creatorRole) return true;
      }
    }
    return false;
  }

  Future<void> _deleteEvent(EventModel event) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Event'),
        content: const Text('Are you sure you want to delete this event?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await Supabase.instance.client.from('events').delete().eq('id', event.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Event deleted')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete: $e'), backgroundColor: Colors.red));
      }
    }
  }

  List<EventModel> _getEventsForDay(DateTime day) {
    return _events.where((e) => e.date != null && isSameDay(e.date!, day)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final perms = context.read<AuthProvider>().permissions;
    if (perms == null) return const Scaffold();

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F111A) : const Color(0xFFF8FAF8),
      extendBody: true,
      appBar: AppBar(
        title: Text('Upcoming Events', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold)),
        actions: [
          if (perms.isAtLeastTier2 || (widget.folderId != null && perms.canDoInFolder(widget.folderId!, 'create_events')))
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () => context.push('/events/create${widget.folderId != null ? '?folder=${widget.folderId}' : ''}'),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildCalendar(isDark),
                const SizedBox(height: 12),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadEvents,
                    child: _buildEventList(),
                  ),
                ),
              ],
            ),
      bottomNavigationBar: LiquidGlassNavBar(
        selectedIndex: 1,
        onItemSelected: (i) {
          if (i == 1) return;
          switch (i) {
            case 0: context.go('/home'); break;
            case 2: context.push('/chat'); break;
            case 3: context.push('/settings'); break;
          }
        },
        items: [
          LiquidNavItem(icon: Icons.grid_view_outlined, selectedIcon: Icons.grid_view, label: 'Home'),
          LiquidNavItem(
            icon: perms.isAtLeastTier2 ? Icons.account_balance_wallet_outlined : Icons.calendar_today_outlined,
            selectedIcon: perms.isAtLeastTier2 ? Icons.account_balance_wallet : Icons.calendar_today,
            label: perms.isAtLeastTier2 ? 'Budget' : 'Events',
          ),
          LiquidNavItem(icon: Icons.chat_bubble_outline, selectedIcon: Icons.chat_bubble, label: 'Chat'),
          LiquidNavItem(icon: Icons.person_outline, selectedIcon: Icons.person, label: 'Profile'),
        ],
      ),
    );
  }

  Widget _buildCalendar(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: TableCalendar(
          firstDay: DateTime.utc(2024, 1, 1),
          lastDay: DateTime.utc(2030, 12, 31),
          focusedDay: _focusedDay,
          calendarFormat: _calendarFormat,
          selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
          onDaySelected: (selectedDay, focusedDay) {
            setState(() {
              _selectedDay = selectedDay;
              _focusedDay = focusedDay;
            });
          },
          onFormatChanged: (format) {
            setState(() {
              _calendarFormat = format;
            });
          },
          eventLoader: _getEventsForDay,
          calendarStyle: CalendarStyle(
            todayDecoration: BoxDecoration(
              color: AppTheme.secondary.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.secondary.withValues(alpha: 0.5)),
            ),
            selectedDecoration: const BoxDecoration(
              color: AppTheme.secondary,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: AppTheme.secondary, blurRadius: 10, offset: Offset(0, 2)),
              ],
            ),
            selectedTextStyle: const TextStyle(color: AppTheme.darkGreen, fontWeight: FontWeight.bold),
            todayTextStyle: const TextStyle(color: AppTheme.secondary, fontWeight: FontWeight.bold),
            markerDecoration: const BoxDecoration(color: AppTheme.secondary, shape: BoxShape.circle),
            outsideDaysVisible: false,
            defaultTextStyle: TextStyle(color: isDark ? Colors.white : Colors.black87),
            weekendTextStyle: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
          ),
          headerStyle: HeaderStyle(
            formatButtonVisible: true,
            titleCentered: true,
            titleTextStyle: GoogleFonts.spaceGrotesk(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: isDark ? Colors.white : AppTheme.darkGreen,
            ),
            formatButtonDecoration: BoxDecoration(
              color: AppTheme.secondary.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.secondary.withValues(alpha: 0.3)),
            ),
            formatButtonTextStyle: TextStyle(
              color: isDark ? AppTheme.secondary : AppTheme.darkGreen,
              fontWeight: FontWeight.bold,
            ),
            leftChevronIcon: Icon(Icons.chevron_left, color: isDark ? Colors.white54 : Colors.grey),
            rightChevronIcon: Icon(Icons.chevron_right, color: isDark ? Colors.white54 : Colors.grey),
          ),
          daysOfWeekStyle: DaysOfWeekStyle(
            weekdayStyle: TextStyle(color: isDark ? Colors.white54 : Colors.grey),
            weekendStyle: const TextStyle(color: AppTheme.secondary),
          ),
        ),
      ),
    );
  }

  Widget _buildEventList() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final selectedEvents = _getEventsForDay(_selectedDay ?? _focusedDay);
    final perms = context.read<AuthProvider>().permissions!;
    
    if (selectedEvents.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_busy_outlined, size: 64, color: AppTheme.secondary.withValues(alpha: 0.1)),
            const SizedBox(height: 16),
            Text(
              'No events on this day',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white38 : Colors.grey,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      itemCount: selectedEvents.length,
      itemBuilder: (context, index) {
        final event = selectedEvents[index];
        final timeStr = event.date != null ? '${event.date!.hour}:${event.date!.minute.toString().padLeft(2, '0')}' : 'TBD';

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          child: GlassCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (event.posterUrl != null)
                  Container(
                    height: 140,
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.black12,
                    ),
                    clipBehavior: Clip.hardEdge,
                    child: CachedNetworkImage(
                      imageUrl: event.posterUrl!,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => const Center(child: CircularProgressIndicator()),
                      errorWidget: (context, url, error) => const Center(child: Icon(Icons.image_not_supported, color: Colors.grey)),
                    ),
                  ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.secondary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.secondary.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        event.type?.toUpperCase() ?? 'EVENT',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.secondary,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Icon(Icons.access_time, size: 14, color: isDark ? Colors.white54 : Colors.grey),
                        const SizedBox(width: 4),
                        Text(
                          timeStr,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                        if (_canDeleteEvent(event, perms)) ...[
                          const SizedBox(width: 12),
                          GestureDetector(
                            onTap: () => _deleteEvent(event),
                            child: Icon(Icons.delete_outline, size: 18, color: Colors.red[400]),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  event.title,
                  style: GoogleFonts.spaceGrotesk(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                if (event.description != null && event.description!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    event.description!,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: isDark ? Colors.white60 : Colors.grey[700],
                      height: 1.5,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => context.push('/scan?event=${event.id}'),
                        icon: const Icon(Icons.qr_code_scanner_rounded, size: 16),
                        label: Text('Scan', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.secondary,
                          side: BorderSide(color: AppTheme.secondary.withValues(alpha: 0.4)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CertificateIssuanceScreen(event: event),
                          ),
                        ),
                        icon: const Icon(Icons.workspace_premium_rounded, size: 16),
                        label: Text('Publish Certs', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Attendance Report button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AttendanceReportScreen(
                          eventId:    event.id,
                          eventTitle: event.title,
                          numDays:    event.numDays,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.people_alt_outlined, size: 16),
                    label: Text(
                      event.numDays > 1
                          ? 'Attendance Report (${event.numDays} days)'
                          : 'Attendance Report',
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blueAccent.shade100,
                      side: BorderSide(color: Colors.blueAccent.withValues(alpha: 0.35)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
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
