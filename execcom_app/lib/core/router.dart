import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'auth_provider.dart';
import 'constants.dart';

import '../screens/splash_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/execom/execom_list_screen.dart';
import '../screens/execom/execom_detail_screen.dart';
import '../screens/execom/execom_permissions_screen.dart';
import '../screens/execom/add_execom_member_screen.dart';
import '../screens/members/member_list_screen.dart';
import '../screens/members/member_detail_screen.dart';
import '../screens/members/add_member_screen.dart';
import '../screens/events/event_list_screen.dart';
import '../screens/events/event_form_screen.dart';
import '../screens/budget/budget_overview_screen.dart';
import '../screens/budget/budget_request_screen.dart';
import '../screens/reports/report_upload_screen.dart';
import '../screens/reports/report_list_screen.dart';
import '../screens/announcements/announcement_screen.dart';
import '../screens/chat/chat_list_screen.dart';
import '../screens/chat/chat_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/settings/permission_manager_screen.dart';
import '../screens/more/more_screen.dart';
// New screens
import '../screens/tasks/task_list_screen.dart';
import '../screens/tasks/task_detail_screen.dart';
import '../screens/tasks/task_create_screen.dart';
import '../screens/tasks/subtask_detail_screen.dart';
import '../screens/attendance/qr_scanner_screen.dart';
import '../screens/registrations/registration_queue_screen.dart';

class AppRouter {
  final AuthProvider authProvider;

  AppRouter(this.authProvider);

  late final router = GoRouter(
    refreshListenable: authProvider,
    initialLocation: '/splash',
    redirect: (context, state) {
      final isLoading = authProvider.isLoading || authProvider.isShowingSplash;
      final isAuthed = authProvider.isAuthenticated;
      final loc = state.matchedLocation;

      if (isLoading) return loc == '/splash' ? null : '/splash';
      if (!isAuthed) return loc == '/login' ? null : '/login';
      if (loc == '/splash' || loc == '/login') return '/home';

      // Route-level guards
      final role = authProvider.role;
      final perms = authProvider.permissions;

      // Budget overview: vice_chairman+ (or core with toggle)
      if (loc == '/budget' && role < AppRole.forumExeccom) return '/home';

      // Member management: canAddMembers check
      if (loc.startsWith('/members-enroll') && !(perms?.canAddMembers ?? false)) return '/home';
      if (loc == '/members' && role < AppRole.forumExeccom) return '/home';

      // Execom permissions management
      if (loc.contains('/execom/') && loc.contains('/permissions') && !(perms?.canManageExecomPermissions ?? false)) return '/home';

      // Global Permission Manager management
      if (loc == '/settings/permissions' && !(perms?.canManageGlobalPermissions ?? false)) return '/home';

      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),

      // Execoms
      GoRoute(path: '/execom', builder: (_, __) => const ExecomListScreen()),
      GoRoute(
        path: '/execom/:id',
        builder: (_, state) => ExecomDetailScreen(
          execomId: int.parse(state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/execom/:id/permissions',
        builder: (_, state) => ExecomPermissionsScreen(
          execomId: int.parse(state.pathParameters['id']!),
        ),
      ),

      // Member Management
      GoRoute(
        path: '/members',
        builder: (context, state) => const MemberListScreen(),
        routes: [
          GoRoute(
            path: ':id',
            builder: (context, state) => MemberDetailScreen(userId: state.pathParameters['id']!),
          ),
        ],
      ),
      GoRoute(
        path: '/members-enroll',
        builder: (context, state) => const AddMemberScreen(),
      ),

      // Events
      GoRoute(
        path: '/events', 
        builder: (_, state) => EventListScreen(
          execomId: int.tryParse(state.uri.queryParameters['folder'] ?? ''),
        ),
      ),
      GoRoute(
        path: '/events/create',
        builder: (_, state) => EventFormScreen(
          execomId: int.tryParse(state.uri.queryParameters['folder'] ?? ''),
        ),
      ),

      // Budget
      GoRoute(
        path: '/budget',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return CustomTransitionPage(
            key: state.pageKey,
            child: BudgetOverviewScreen(initialTab: extra?['tab'] as int?),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return ScaleTransition(
                scale: Tween<double>(begin: 0.95, end: 1.0).animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                    reverseCurve: Curves.easeInCubic,
                  ),
                ),
                child: FadeTransition(
                  opacity: animation,
                  child: child,
                ),
              );
            },
          );
        },
      ),
      GoRoute(
        path: '/budget/request',
        builder: (_, state) => BudgetRequestScreen(
          execomId: int.tryParse(state.uri.queryParameters['folder'] ?? ''),
          mode: state.uri.queryParameters['mode'],
        ),
      ),

      // Reports
      GoRoute(path: '/reports/upload', builder: (_, __) => const ReportUploadScreen()),
      GoRoute(path: '/reports', builder: (_, __) => const ReportListScreen()),

      // Announcements
      GoRoute(path: '/announcements', builder: (_, __) => const AnnouncementScreen()),

      // Chat
      GoRoute(
        path: '/chat', 
        builder: (_, state) {
          final execomId = int.tryParse(state.uri.queryParameters['execomId'] ?? '');
          final userId = state.uri.queryParameters['userId'];
          
          if (execomId != null) return ChatScreen(execomId: execomId);
          if (userId != null) return ChatScreen(otherUserId: userId);
          return const ChatListScreen();
        }
      ),
      GoRoute(
        path: '/chat/:userId',
        builder: (_, state) => ChatScreen(
          otherUserId: state.pathParameters['userId']!,
        ),
      ),

      // Settings
      GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
      GoRoute(path: '/settings/permissions', builder: (_, __) => const PermissionManagerScreen()),

      // More
      GoRoute(path: '/more', builder: (_, __) => const MoreScreen()),

      // ── Task Management ──────────────────────────────────────────────────
      GoRoute(path: '/tasks', builder: (_, __) => const TaskListScreen()),
      GoRoute(
        path: '/tasks/create',
        builder: (_, __) => const TaskCreateScreen(),
      ),
      GoRoute(
        path: '/tasks/:id',
        builder: (_, state) => TaskDetailScreen(
          taskId: int.parse(state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/tasks/:taskId/subtasks/create',
        builder: (_, state) => TaskCreateScreen(
          taskId: int.parse(state.pathParameters['taskId']!),
        ),
      ),
      GoRoute(
        path: '/tasks/:taskId/subtasks/:subtaskId',
        builder: (_, state) => SubtaskDetailScreen(
          taskId: int.parse(state.pathParameters['taskId']!),
          subtaskId: int.parse(state.pathParameters['subtaskId']!),
        ),
      ),

      // ── QR Attendance Scanner ─────────────────────────────────────────
      GoRoute(
        path: '/scan',
        builder: (_, state) => QrScannerScreen(
          eventId: int.tryParse(state.uri.queryParameters['event'] ?? ''),
        ),
      ),

      // ── Registration Queue ────────────────────────────────────────────
      GoRoute(path: '/registrations', builder: (_, __) => const RegistrationQueueScreen()),
    ],
  );
}
