import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/auth_provider.dart';
import '../../core/constants.dart';
import '../../core/permission_engine.dart';
import '../../core/theme.dart';
import '../../models/user_model.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/liquid_glass_nav_bar.dart';
import '../../shared/widgets/lynq_illustration_card.dart';
import '../../shared/lynq_illustrations.dart';
import '../../core/notification_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> _allCategories = [];
  List<Map<String, dynamic>> _upcomingEvents = [];
  List<Map<String, dynamic>> _pendingTasks = [];
  int _selectedIndex = 0;
  int _membersCount = 0;
  int _eventsCount = 0;
  int _foldersCount = 0;

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

    // 6. Reports — listens on event_reports (correct table; 'files' was deleted)
    final chReports = client.channel('home_reports_changes').onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'event_reports',
      callback: (payload) {
        if (!mounted) return;
        setState(() => _hasNewReports = true);
        final newRecord = payload.newRecord;
        NotificationService().showNotification(
          title: 'New Report Uploaded',
          body: 'A new report "${newRecord['title'] ?? 'Untitled'}" has been uploaded.',
        );
      },
    );
    chReports.subscribe();
    _realtimeChannels.add(chReports);
  }

  Future<void> _loadDashboardData() async {
    if (!mounted) return;
    final authProvider = context.read<AuthProvider>();
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final today = DateTime.now().toIso8601String();
      final client = Supabase.instance.client;
      final perms = authProvider.permissions;

      // Run ALL queries in parallel — budget categories included
      final results = await Future.wait([
        client
            .from('events')
            .select('id, title, date')
            .gte('date', today)
            .order('date', ascending: true)
            .limit(3),
        client
            .from('tasks')
            .select('id, title, deadline, status')
            .neq('status', 'completed')
            .contains('assigned_to', [user.id])
            .order('deadline', ascending: true)
            .limit(3),
        // Use count() to avoid downloading all rows just for .length
        client.from('users').select('id').limit(1000),
        client.from('events').select('id').limit(1000),
        client.from('folders').select('id').limit(1000),
        if (perms?.canManageBudget ?? false)
          client.from('budget_categories').select().order('name')
        else
          Future.value(<dynamic>[]),
      ]);

      if (!mounted) return;
      setState(() {
        _upcomingEvents = (results[0] as List).cast<Map<String, dynamic>>();
        _pendingTasks   = (results[1] as List).cast<Map<String, dynamic>>();
        _membersCount   = (results[2] as List).length;
        _eventsCount    = (results[3] as List).length;
        _foldersCount   = (results[4] as List).length;
        if (perms?.canManageBudget ?? false) {
          _allCategories = (results[5] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        }
      });
    } catch (e) {
      debugPrint('Error loading home data: $e');
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
                        const SizedBox(height: 24),

                        // Featured Events illustration cards
                        _buildSectionHeader(
                          'Featured Events',
                          () => context.push('/events'),
                        ),
                        const SizedBox(height: 14),
                        _buildFeaturedEventCards(context),
                        const SizedBox(height: 32),

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

                        const SizedBox(height: 40),
                        _buildSectionHeader(
                          'Active Teams',
                          () => context.push('/folders'),
                        ),
                        const SizedBox(height: 16),
                        _buildForumCards(context, perms),

                        const SizedBox(height: 40),
                        _buildSectionHeader('Your Access Level'),
                        const SizedBox(height: 16),
                        _buildTierAccessCard(context, perms),
                        const SizedBox(height: 120),
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

  /// Horizontally scrollable illustration cards for upcoming events.
  Widget _buildFeaturedEventCards(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_upcomingEvents.isEmpty) {
      return LynqIllustrationCard(
        title: 'No Upcoming Events',
        subtitle: 'Create one to get started',
        backgroundColor: LynqCardColors.slate,
        textColor: Colors.white,
        illustration: LynqPresentationIllustration(isDark: isDark),
        compact: true,
        onPrimaryTap: () => context.push('/events'),
      );
    }

    final shirtColors = [
      AppTheme.primary,
      const Color(0xFF6FA4AF),
      const Color(0xFF9B8EC4),
    ];

    return SizedBox(
      height: 175,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _upcomingEvents.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, i) {
          final event = _upcomingEvents[i];
          final title = event['title'] as String? ?? 'Event';
          final rawDate = event['date'] as String?;
          final dateStr = rawDate != null ? rawDate.split('T').first : 'TBD';
          final bgColor = LynqCardColors.atIndex(i);
          final shirtColor = shirtColors[i % shirtColors.length];

          return SizedBox(
            width: MediaQuery.of(context).size.width - 60,
            child: LynqIllustrationCard(
              title: title,
              subtitle: '📅  $dateStr',
              backgroundColor: bgColor,
              textColor: Colors.white,
              illustration: LynqWorkingIllustration(
                shirtColor: shirtColor,
                deskColor: Colors.white,
                isDark: isDark,
              ),
              primaryBtnLabel: 'View',
              onPrimaryTap: () => context.push('/events'),
            ),
          );
        },
      ),
    );
  }

  /// Tier access summary card showing the user's role + available features.
  Widget _buildTierAccessCard(BuildContext context, PermissionEngine perms) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final role = perms.role;

    // Tier label + color
    final tierLabel = switch (role) {
      AppRole.chairman => '🔴  Tier 1 — Chairman',
      AppRole.viceChairman => '🔴  Tier 1 — Vice Chairman',
      AppRole.coreExeccom => '🟠  Tier 2 — Core Execom',
      AppRole.forumExeccom => '🟡  Tier 3 — Forum Execom',
      AppRole.panel => '🟢  Tier 4 — Panel',
      AppRole.restricted => '⚪  Tier 5 — Restricted',
      _ => '⚫  Tier — Unknown',
    };
    final tierColor = switch (role) {
      AppRole.chairman || AppRole.viceChairman => const Color(0xFFE05A5A),
      AppRole.coreExeccom => const Color(0xFFD97D55),
      AppRole.forumExeccom => const Color(0xFFD4A853),
      AppRole.panel => const Color(0xFF6B9E8A),
      _ => Colors.grey,
    };

    final features = <_FeatureRow>[
      _FeatureRow(Icons.event_note_rounded, 'Events', true),
      _FeatureRow(Icons.people_alt_rounded, 'Members', perms.canViewMembers),
      _FeatureRow(Icons.wallet_rounded, 'Budget', perms.canRequestBudget || perms.canManageBudget),
      _FeatureRow(Icons.chat_bubble_rounded, 'Chat', perms.canAccessChat),
      _FeatureRow(Icons.upload_file_rounded, 'Upload Reports', perms.canUploadReports),
      _FeatureRow(Icons.article_rounded, 'View Reports', perms.canReadReports),
      _FeatureRow(Icons.manage_accounts_rounded, 'Manage Members', perms.canAddMembers),
      _FeatureRow(Icons.how_to_reg_rounded, 'Registrations', perms.isAtLeastTier1),
      _FeatureRow(Icons.security_rounded, 'Permissions', perms.canManagePermissions),
    ];

    final cardBg = isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tier badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: tierColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: tierColor.withValues(alpha: 0.3)),
            ),
            child: Text(
              tierLabel,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: tierColor,
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Feature list
          ...features.map((f) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Icon(
                      f.icon,
                      size: 16,
                      color: f.enabled
                          ? (isDark ? AppTheme.secondary : AppTheme.darkGreen)
                          : Colors.grey[400],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        f.label,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: f.enabled
                              ? (isDark ? Colors.white : const Color(0xFF1A1A1A))
                              : Colors.grey[400],
                        ),
                      ),
                    ),
                    Icon(
                      f.enabled ? Icons.check_circle_rounded : Icons.remove_circle_outline,
                      size: 16,
                      color: f.enabled ? Colors.green[400] : Colors.grey[300],
                    ),
                  ],
                ),
              )),
        ],
      ),
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
        Icons.group_work_rounded,
        'Teams',
        () => context.push('/folders'),
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

    if (perms.isAtLeastTier2) {
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
        crossAxisSpacing: 6,
        mainAxisSpacing: 16,
        childAspectRatio: 0.82,
      ),
      itemCount: actions.length,
      itemBuilder: (context, index) {
        final action = actions[index];
        return InkWell(
          onTap: action.onTap,
          borderRadius: BorderRadius.circular(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: action.color.withValues(alpha: isDark ? 0.15 : 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Icon(action.icon, color: action.color, size: 22),
                    ),
                  ),
                  if (action.showBadge)
                    Positioned(
                      top: -2,
                      right: -2,
                      child: Container(
                        width: 10,
                        height: 10,
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
              const SizedBox(height: 6),
              Text(
                action.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 10,
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
          child: _statCard(context, 'Teams', '$_foldersCount', Icons.group_work_outlined),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      borderRadius: 18,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (isDark ? AppTheme.secondary : AppTheme.darkGreen)
                  .withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Icon(
                icon,
                size: 18,
                color: isDark ? AppTheme.secondary : AppTheme.darkGreen,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.8,
              height: 1,
              color: isDark ? Colors.white : AppTheme.darkGreen,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label.toUpperCase(),
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 7.5,
              color: Colors.grey[500],
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildForumCards(BuildContext context, PermissionEngine perms) {
    return InkWell(
      onTap: () => context.push('/folders'),
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
                    'Explore All Teams',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Collaborate with your active teams',
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

class _FeatureRow {
  final IconData icon;
  final String label;
  final bool enabled;
  const _FeatureRow(this.icon, this.label, this.enabled);
}
