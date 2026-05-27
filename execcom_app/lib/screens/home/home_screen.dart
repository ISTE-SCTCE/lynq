import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/auth_provider.dart';
import '../../core/permission_engine.dart';
import '../../core/theme.dart';
import '../../models/user_model.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/liquid_glass_nav_bar.dart';
import '../../core/notification_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isFinancialLoading = false;
  double _totalIncome = 0;
  double _totalSpent = 0;
  List<Map<String, dynamic>> _ledgerEntries = [];
  List<Map<String, dynamic>> _allCategories = [];
  List<Map<String, dynamic>> _upcomingEvents = [];
  List<Map<String, dynamic>> _pendingTasks = [];
  int _selectedIndex = 0;
  int _membersCount = 73;
  int _eventsCount = 1;
  int _execomCount = 5;

  // Real-time update/red badge flags
  bool _hasNewRegistrations = false;
  bool _hasNewTasks = false;
  bool _hasNewEvents = false;
  bool _hasNewChats = false;
  bool _hasNewBudgets = false;
  bool _hasNewReports = false;
  final List<RealtimeChannel> _realtimeChannels = [];

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
    _initRealtimeSubscriptions();
  }

  @override
  void dispose() {
    for (final channel in _realtimeChannels) {
      Supabase.instance.client.removeChannel(channel);
    }
    super.dispose();
  }

  void _initRealtimeSubscriptions() {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return;

    final authProvider = context.read<AuthProvider>();
    final perms = authProvider.permissions;

    // 1. Registrations Realtime
    if (perms?.isAtLeastTier1 ?? false) {
      final chReg = client.channel('home_reg_changes').onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'registration_queue',
        callback: (payload) {
          if (!mounted) return;
          setState(() => _hasNewRegistrations = true);
          final newRecord = payload.newRecord;
          final name = newRecord['name'] ?? 'Someone';
          NotificationService().showNotification(
            title: 'New Registration Intake',
            body: '$name has registered for review.',
          );
        },
      );
      chReg.subscribe();
      _realtimeChannels.add(chReg);
    }

    // 2. Tasks Realtime
    final chTasks = client.channel('home_tasks_changes').onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'tasks',
      callback: (payload) {
        if (!mounted) return;
        final newRecord = payload.newRecord;
        if (newRecord.isEmpty) return;
        
        final assignedTo = newRecord['assigned_to'] as List?;
        if (assignedTo != null && assignedTo.contains(user.id)) {
          setState(() => _hasNewTasks = true);
          if (payload.eventType == PostgresChangeEvent.insert) {
            NotificationService().showNotification(
              title: 'Task Assigned',
              body: 'New task "${newRecord['title']}" has been assigned to you.',
            );
          } else if (payload.eventType == PostgresChangeEvent.update) {
            NotificationService().showNotification(
              title: 'Task Updated',
              body: 'Your assigned task "${newRecord['title']}" has been updated.',
            );
          }
        }
      },
    );
    chTasks.subscribe();
    _realtimeChannels.add(chTasks);

    // 3. Events Realtime
    final chEvents = client.channel('home_events_changes').onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'events',
      callback: (payload) {
        if (!mounted) return;
        setState(() => _hasNewEvents = true);
        final newRecord = payload.newRecord;
        NotificationService().showNotification(
          title: 'New Event Scheduled',
          body: 'Event "${newRecord['title']}" is set for ${newRecord['date']}.',
        );
      },
    );
    chEvents.subscribe();
    _realtimeChannels.add(chEvents);

    // 4. Chat Messages Realtime
    if (perms?.canAccessChat ?? false) {
      final chMessages = client.channel('home_messages_changes').onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'messages',
        callback: (payload) {
          if (!mounted) return;
          final newRecord = payload.newRecord;
          if (newRecord.isEmpty) return;

          if (newRecord['receiver_id'] == user.id) {
            setState(() => _hasNewChats = true);
            NotificationService().showNotification(
              title: 'New Chat Alert',
              body: 'You received a new private message.',
            );
          }
        },
      );
      chMessages.subscribe();
      _realtimeChannels.add(chMessages);
    }

    // 5. Budget Realtime
    if (perms?.canRequestBudget ?? false) {
      final chBudget = client.channel('home_budget_changes').onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'budget_requests',
        callback: (payload) {
          if (!mounted) return;
          setState(() => _hasNewBudgets = true);
          final newRecord = payload.newRecord;
          if (payload.eventType == PostgresChangeEvent.insert) {
            NotificationService().showNotification(
              title: 'New Budget Request',
              body: 'A budget request for ${newRecord['amount']} was submitted.',
            );
          } else if (payload.eventType == PostgresChangeEvent.update) {
            NotificationService().showNotification(
              title: 'Budget Request Update',
              body: 'Budget request status is now: ${newRecord['status']}.',
            );
          }
        },
      );
      chBudget.subscribe();
      _realtimeChannels.add(chBudget);
    }

    // 6. Reports Realtime
    final chReports = client.channel('home_reports_changes').onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'files',
      callback: (payload) {
        if (!mounted) return;
        setState(() => _hasNewReports = true);
        final newRecord = payload.newRecord;
        NotificationService().showNotification(
          title: 'New Report Uploaded',
          body: 'A new file "${newRecord['name']}" has been uploaded to execom.',
        );
      },
    );
    chReports.subscribe();
    _realtimeChannels.add(chReports);
  }

  Future<void> _loadDashboardData() async {
    if (!mounted) return;
    setState(() => _isFinancialLoading = true);
    final authProvider = context.read<AuthProvider>();
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        if (mounted) setState(() => _isFinancialLoading = false);
        return;
      }

      final today = DateTime.now().toIso8601String();
      
      final futureLedger = Supabase.instance.client
          .from('financial_ledger')
          .select()
          .order('transaction_date', ascending: false)
          .limit(20);

      final futureEvents = Supabase.instance.client
          .from('events')
          .select('id, title, date')
          .gte('date', today)
          .order('date', ascending: true)
          .limit(3);

      final futureTasks = Supabase.instance.client
          .from('tasks')
          .select('id, title, deadline, status')
          .neq('status', 'completed')
          .contains('assigned_to', [user.id])
          .order('deadline', ascending: true)
          .limit(3);

      final futureMembers = Supabase.instance.client.from('users').select('id');
      final futureEventsCount = Supabase.instance.client.from('events').select('id');
      final futureExecoms = Supabase.instance.client.from('execom').select('id');

      final results = await Future.wait([
        futureLedger,
        futureEvents,
        futureTasks,
        futureMembers,
        futureEventsCount,
        futureExecoms,
      ]);
      final ledgerData = results[0];
      final eventsData = results[1];
      final tasksData = results[2];
      final membersData = results[3];
      final allEventsData = results[4];
      final execomData = results[5];

      final ledgerEntries = (ledgerData as List)
          .map((entry) => Map<String, dynamic>.from(entry as Map))
          .toList();

      double income = 0;
      double spent = 0;
      for (final entry in ledgerEntries) {
        final rawAmount = entry['amount'];
        final amt = rawAmount is num
            ? rawAmount.toDouble()
            : double.tryParse('$rawAmount') ?? 0;
        if (entry['type'] == 'Income') {
          income += amt;
        } else {
          spent += amt;
        }
      }

      var allCategories = _allCategories;
      final perms = authProvider.permissions;
      if (perms?.canManageBudget ?? false) {
        final catData = await Supabase.instance.client
            .from('budget_categories')
            .select()
            .order('name');
        allCategories = (catData as List)
            .map((entry) => Map<String, dynamic>.from(entry as Map))
            .toList();
      }

      if (!mounted) return;
      setState(() {
        _ledgerEntries = ledgerEntries;
        _allCategories = allCategories;
        _upcomingEvents = (eventsData as List).cast<Map<String, dynamic>>();
        _pendingTasks = (tasksData as List).cast<Map<String, dynamic>>();
        _totalIncome = income;
        _totalSpent = spent;
        _membersCount = (membersData as List).length;
        _eventsCount = (allEventsData as List).length;
        _execomCount = (execomData as List).length;
        _isFinancialLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading home financial data: $e');
      if (mounted) setState(() => _isFinancialLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;
    final perms = auth.permissions;

    if (user == null || perms == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: Stack(
        children: [
          // Background Decorative Shapes
          Positioned(
            top: -100,
            right: -50,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppTheme.secondary.withValues(alpha: isDark ? 0.15 : 0.2),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 100,
            left: -80,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppTheme.primaryDark.withValues(alpha: isDark ? 0.1 : 0.15),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          RefreshIndicator(
            onRefresh: _loadDashboardData,
            color: AppTheme.secondary,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              slivers: [
                _buildSliverAppBar(context, user),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20.0,
                      vertical: 24.0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildWelcomeSection(context, user),
                        const SizedBox(height: 28),
                        
                        _buildSectionHeader('Upcoming Board'),
                        const SizedBox(height: 16),
                        _buildUpcomingBoard(context),
                        const SizedBox(height: 32),

                        _buildSectionHeader('Actions'),
                        const SizedBox(height: 20),
                        _buildQuickActionsGrid(context, perms),

                        const SizedBox(height: 40),
                        _buildSectionHeader('Network Overview'),
                        const SizedBox(height: 16),
                        _buildOverviewCards(context),

                        // Removed Financial Overview as per user request

                        const SizedBox(height: 40),
                        _buildSectionHeader(
                          'Active Forums',
                          () => context.push('/execom'),
                        ),
                        const SizedBox(height: 16),
                        _buildForumCards(context, perms),
                        const SizedBox(height: 120), // Bottom padding for nav bar
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(context, perms),
      extendBody: true,
    );
  }

  Widget _buildSliverAppBar(BuildContext context, UserModel user) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SliverAppBar(
      expandedHeight: 80,
      floating: false,
      pinned: true,
      stretch: false,
      backgroundColor: theme.scaffoldBackgroundColor.withValues(alpha: 0.9),
      elevation: 0,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          color: theme.scaffoldBackgroundColor,
        ),
        titlePadding: const EdgeInsets.only(left: 20, bottom: 12),
        title: Row(
          children: [
            Image.asset(
              'assets/images/logo.png',
              height: 32,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              errorBuilder: (context, error, stackTrace) => const SizedBox(),
            ),
          ],
        ),
      ),
      actions: [
        IconButton(
          icon: Icon(
            Icons.notifications_outlined,
            color: isDark ? Colors.white : AppTheme.darkGreen,
          ),
          onPressed: () => context.push('/announcements'),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 16, left: 8),
          child: CircleAvatar(
            radius: 18,
            backgroundColor: AppTheme.secondary,
            child: Text(
              user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWelcomeSection(BuildContext context, UserModel user) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Good Day,',
          style: GoogleFonts.inter(
            fontSize: 16,
            color: Colors.grey[500],
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          '${user.name.split(' ').first}!',
          style: GoogleFonts.spaceGrotesk(
            fontSize: 36,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : AppTheme.darkGreen,
            letterSpacing: -1.5,
            height: 1.1,
          ),
        ),
      ],
    );
  }

  Widget _buildUpcomingBoard(BuildContext context) {
    if (_upcomingEvents.isEmpty && _pendingTasks.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark 
              ? Colors.white.withValues(alpha: 0.05) 
              : Colors.black.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: Text('No upcoming events or tasks. All caught up!', style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    return Column(
      children: [
        if (_upcomingEvents.isNotEmpty) ...[
          ..._upcomingEvents.map((event) => _buildUpcomingItem(
            icon: Icons.event, 
            title: event['title'] ?? 'Event', 
            subtitle: event['date'] != null ? event['date'].split('T').first : 'TBD',
            onTap: () => context.push('/events'),
          )),
        ],
        if (_pendingTasks.isNotEmpty) ...[
          const SizedBox(height: 8),
          ..._pendingTasks.map((task) => _buildUpcomingItem(
            icon: Icons.assignment_outlined, 
            title: task['title'] ?? 'Task', 
            subtitle: 'Due: ${task['deadline'] ?? 'No deadline'}',
            onTap: () => context.push('/tasks'),
          )),
        ],
      ],
    );
  }

  Widget _buildUpcomingItem({required IconData icon, required String title, required String subtitle, required VoidCallback onTap}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.secondary.withValues(alpha: 0.2)),
          boxShadow: isDark ? [] : [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.secondary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppTheme.secondary, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14)),
                  Text(subtitle, style: GoogleFonts.inter(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey[400], size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, [VoidCallback? onSeeAll]) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title.toUpperCase(),
          style: GoogleFonts.spaceGrotesk(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
            color: isDark ? Colors.grey[400] : AppTheme.darkGreen,
          ),
        ),
        if (onSeeAll != null)
          GestureDetector(
            onTap: onSeeAll,
            child: Icon(
              Icons.arrow_forward_rounded,
              size: 16,
              color: Colors.grey[500],
            ),
          ),
      ],
    );
  }

  Widget _buildQuickActionsGrid(BuildContext context, PermissionEngine perms) {
    final actions = <_ActionItem>[];
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    actions.add(
      _ActionItem(
        Icons.event_note_rounded,
        'Events',
        () {
          setState(() => _hasNewEvents = false);
          context.push('/events');
        },
        AppTheme.primaryDark,
        showBadge: _hasNewEvents,
      ),
    );

    if (perms.canUploadReports) {
      actions.add(
        _ActionItem(
          Icons.upload_file_rounded,
          'Upload Report',
          () {
            setState(() => _hasNewReports = false);
            context.push('/reports/upload');
          },
          const Color(0xFF5277B8),
          showBadge: _hasNewReports,
        ),
      );
    }
    
    actions.add(
      _ActionItem(
        Icons.article_rounded,
        'Reports',
        () {
          setState(() => _hasNewReports = false);
          context.push('/reports');
        },
        const Color(0xFF4A7C6E),
        showBadge: _hasNewReports,
      ),
    );

    actions.add(
      _ActionItem(
        Icons.people_alt_rounded,
        'Members',
        () => context.push('/members'),
        AppTheme.darkGreen,
      ),
    );
    if (perms.canRequestBudget || perms.canManageBudget) {
      actions.add(
        _ActionItem(
          Icons.wallet_rounded,
          'Budget',
          () {
            setState(() => _hasNewBudgets = false);
            context.push('/budget');
          },
          const Color(0xFF6A8B54),
          showBadge: _hasNewBudgets,
        ),
      );
    }
    if (perms.canAccessChat) {
      actions.add(
        _ActionItem(
          Icons.chat_bubble_rounded,
          'Chat',
          () {
            setState(() => _hasNewChats = false);
            context.push('/chat');
          },
          const Color(0xFF2E8A77),
          showBadge: _hasNewChats,
        ),
      );
    }

    actions.add(
      _ActionItem(
        Icons.folder_open_rounded,
        'Execom Teams',
        () => context.push('/execom'),
        const Color(0xFFE4A252),
      ),
    );

    if (perms.canManagePermissions) {
      actions.add(
        _ActionItem(
          Icons.admin_panel_settings_rounded,
          'Permissions',
          () => context.push('/settings/permissions'),
          const Color(0xFF8B546A),
        ),
      );
    }

    // New actions — Phase 1 additions
    actions.add(
      _ActionItem(
        Icons.task_alt_rounded,
        'Tasks',
        () {
          setState(() => _hasNewTasks = false);
          context.push('/tasks');
        },
        const Color(0xFFD97D55),
        showBadge: _hasNewTasks,
      ),
    );

    actions.add(
      _ActionItem(
        Icons.qr_code_scanner_rounded,
        'Scanner',
        () => context.push('/scan'),
        const Color(0xFF6FA4AF),
      ),
    );

    if (perms.isAtLeastTier1) {
      actions.add(
        _ActionItem(
          Icons.how_to_reg_rounded,
          'Registrations',
          () {
            setState(() => _hasNewRegistrations = false);
            context.push('/registrations');
          },
          const Color(0xFFB8C4A9).withValues(alpha: 1),
          showBadge: _hasNewRegistrations,
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 8,
        mainAxisSpacing: 24,
        childAspectRatio: 0.75,
      ),
      itemCount: actions.length,
      itemBuilder: (context, index) {
        final action = actions[index];
        return InkWell(
          onTap: action.onTap,
          borderRadius: BorderRadius.circular(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: action.color.withValues(alpha: isDark ? 0.15 : 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Icon(action.icon, color: action.color, size: 26),
                    ),
                  ),
                  if (action.showBadge)
                    Positioned(
                      top: -2,
                      right: -2,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isDark ? theme.scaffoldBackgroundColor : Colors.white,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                action.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  height: 1.1,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOverviewCards(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _statCard(context, 'Members', '$_membersCount', Icons.people_outline),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _statCard(
            context,
            'Event',
            '$_eventsCount',
            Icons.event_available_outlined,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _statCard(context, 'Execom Teams', '$_execomCount', Icons.group_work_outlined),
        ),
      ],
    );
  }

  Widget _statCard(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return GlassCard(
      padding: const EdgeInsets.all(16),
      borderRadius: 24,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (isDark ? AppTheme.secondary : AppTheme.darkGreen)
                  .withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Icon(
                icon,
                size: 22,
                color: isDark ? AppTheme.secondary : AppTheme.darkGreen,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.0,
              height: 1,
              color: isDark ? Colors.white : AppTheme.darkGreen,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label.toUpperCase(),
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 8,
              color: Colors.grey[500],
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFinancialCharts() {
    if (_isFinancialLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: CircularProgressIndicator(),
        ),
      );
    }

    final remaining = _totalIncome - _totalSpent;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: GlassCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(
                      'BALANCE',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '\u20B9${remaining.toStringAsFixed(0)}',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.secondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        GlassCard(
          padding: const EdgeInsets.fromLTRB(16, 32, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Financial Trends',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Income, Expense & Cumulative Total',
                style: GoogleFonts.inter(fontSize: 11, color: Colors.grey),
              ),
              const SizedBox(height: 24),
              _buildUnifiedChart(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildUnifiedChart() {
    final Map<String, double> incomeMap = {};
    final Map<String, double> expenseMap = {};
    final List<String> last10Days = [];

    for (int i = 9; i >= 0; i--) {
      final date = DateTime.now()
          .subtract(Duration(days: i))
          .toIso8601String()
          .split('T')[0];
      last10Days.add(date);
      incomeMap[date] = 0;
      expenseMap[date] = 0;
    }

    for (var entry in _ledgerEntries) {
      final date = (entry['transaction_date'] as String).split('T')[0];
      if (last10Days.contains(date)) {
        final amt = (entry['amount'] as num).toDouble();
        if (entry['type'] == 'Income') {
          incomeMap[date] = (incomeMap[date] ?? 0) + amt;
        } else {
          expenseMap[date] = (expenseMap[date] ?? 0) + amt;
        }
      }
    }

    double runningBalance = 0;
    List<FlSpot> balanceSpots = [];
    List<FlSpot> incomeSpots = [];
    List<FlSpot> expenseSpots = [];

    for (int i = 0; i < 10; i++) {
      final date = last10Days[i];
      final inc = incomeMap[date]!;
      final exp = expenseMap[date]!;
      runningBalance += (inc - exp);

      balanceSpots.add(FlSpot(i.toDouble(), runningBalance));
      incomeSpots.add(FlSpot(i.toDouble(), inc));
      expenseSpots.add(FlSpot(i.toDouble(), exp));
    }

    return Column(
      children: [
        SizedBox(
          height: 180,
          child: LineChart(
            LineChartData(
              gridData: const FlGridData(show: false),
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      if (value < 0 || value >= 10 || value % 3 != 0) {
                        return const SizedBox();
                      }
                      final date = last10Days[value.toInt()];
                      return Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          date.split('-').last,
                          style: GoogleFonts.inter(
                            fontSize: 9,
                            color: Colors.grey,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                leftTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
              ),
              borderData: FlBorderData(show: false),
              lineBarsData: [
                LineChartBarData(
                  spots: balanceSpots,
                  isCurved: true,
                  color: AppTheme.secondary,
                  barWidth: 3,
                  isStrokeCapRound: true,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: AppTheme.secondary.withValues(alpha: 0.05),
                  ),
                ),
                LineChartBarData(
                  spots: incomeSpots,
                  isCurved: true,
                  color: Colors.greenAccent,
                  barWidth: 1.5,
                  dotData: const FlDotData(show: false),
                ),
                LineChartBarData(
                  spots: expenseSpots,
                  isCurved: true,
                  color: Colors.redAccent,
                  barWidth: 1.5,
                  dotData: const FlDotData(show: false),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _chartLegend('Balance', AppTheme.secondary),
            const SizedBox(width: 12),
            _chartLegend('Income', Colors.greenAccent),
            const SizedBox(width: 12),
            _chartLegend('Expense', Colors.redAccent),
          ],
        ),
      ],
    );
  }

  Widget _chartLegend(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[700]),
          ),
        ],
      ),
    );
  }

  Widget _buildForumCards(BuildContext context, PermissionEngine perms) {
    return InkWell(
      onTap: () => context.push('/execom'),
      borderRadius: BorderRadius.circular(20),
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.rocket_launch_outlined, color: AppTheme.darkGreen),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Explore All Forums',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Join the discussion in 5 active forums',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNav(BuildContext context, PermissionEngine perms) {
    return LiquidGlassNavBar(
      selectedIndex: _selectedIndex,
      onItemSelected: (i) {
        if (!mounted) return;
        setState(() => _selectedIndex = i);
        switch (i) {
          case 0:
            break; // Stay on home
          case 1:
            if (perms.canRequestBudget || perms.canManageBudget) {
              context.push('/budget');
            } else {
              context.push('/events');
            }
            break;
          case 2:
            context.push('/chat');
            break;
          case 3:
            context.push('/settings');
            break;
        }
      },
      items: [
        LiquidNavItem(
          icon: Icons.grid_view_outlined,
          selectedIcon: Icons.grid_view_rounded,
          label: 'Home',
        ),
        LiquidNavItem(
          icon: (perms.canRequestBudget || perms.canManageBudget)
              ? Icons.account_balance_wallet_outlined
              : Icons.calendar_today_outlined,
          selectedIcon: (perms.canRequestBudget || perms.canManageBudget)
              ? Icons.account_balance_wallet_rounded
              : Icons.calendar_today_rounded,
          label: (perms.canRequestBudget || perms.canManageBudget) ? 'Budget' : 'Events',
        ),
        LiquidNavItem(
          icon: Icons.chat_bubble_outline_rounded,
          selectedIcon: Icons.chat_bubble_rounded,
          label: 'Chat',
        ),
        LiquidNavItem(
          icon: Icons.person_outline,
          selectedIcon: Icons.person,
          label: 'Profile',
        ),
      ],
    );
  }

  // --- Navigation & Routing ---
}

class _ActionItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  final bool showBadge;

  _ActionItem(this.icon, this.label, this.onTap, this.color, {this.showBadge = false});
}
