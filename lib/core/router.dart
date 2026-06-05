import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:go_router/go_router.dart';
import 'auth_provider.dart';
import 'constants.dart';

import '../screens/splash_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/wrong_app_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/folders/folder_list_screen.dart';
import '../screens/folders/folder_detail_screen.dart';
import '../screens/folders/folder_permissions_screen.dart';
import '../screens/folders/add_folder_member_screen.dart';
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
import '../screens/registrations/registration_summary_screen.dart';
import '../models/task_models.dart';

class AppRouter {
  final AuthProvider authProvider;

  AppRouter(this.authProvider);

  static Page<dynamic> _page({required GoRouterState state, required Widget child}) {
    return CupertinoPage<dynamic>(
      key: state.pageKey,
      child: child,
    );
  }

  late final router = GoRouter(
    refreshListenable: authProvider,
    initialLocation: '/splash',
    redirect: (context, state) {
      final isLoading = authProvider.isLoading || authProvider.isShowingSplash;
      final isAuthed = authProvider.isAuthenticated;
      final loc = state.matchedLocation;

      if (isLoading) return loc == '/splash' ? null : '/splash';
      if (!isAuthed) return loc == '/login' ? null : '/login';
      if (loc == '/splash' || loc == '/login') {
        // Guard: general members must use m-lynq, not this execom app
        if (authProvider.role == AppRole.member) return '/wrong-app';
        return '/home';
      }
      // Already on wrong-app screen — keep them there
      if (loc == '/wrong-app') return null;
      // If they navigated elsewhere but are a general member, redirect
      if (authProvider.role == AppRole.member) return '/wrong-app';

      // Route-level guards
      final role = authProvider.role;
      final perms = authProvider.permissions;

      // Budget overview: vice_chairman+ (or core with toggle)
      if (loc == '/budget' && role < AppRole.forumExeccom) return '/home';

      // Member management: canAddMembers check
      if (loc.startsWith('/members-enroll') && !(perms?.canAddMembers ?? false)) return '/home';
      if (loc == '/members' && role < AppRole.forumExeccom) return '/home';

      // Folder permissions management
      if (loc.contains('/folders/') && loc.contains('/permissions') && !(perms?.canManageFolderPermissions ?? false)) return '/home';

      // Global Permission Manager management
      if (loc == '/settings/permissions' && !(perms?.canManageGlobalPermissions ?? false)) return '/home';

      return null;
    },
    routes: [
      GoRoute(path: '/splash', pageBuilder: (_, state) => _page(state: state, child: const SplashScreen())),
      GoRoute(path: '/login', pageBuilder: (_, state) => _page(state: state, child: const LoginScreen())),
      GoRoute(path: '/wrong-app', pageBuilder: (_, state) => _page(state: state, child: const WrongAppScreen())),
      GoRoute(path: '/home', pageBuilder: (_, state) => _page(state: state, child: const HomeScreen())),

      // Folders
      GoRoute(path: '/folders', pageBuilder: (_, state) => _page(state: state, child: const FolderListScreen())),
      GoRoute(
        path: '/folders/:id',
        pageBuilder: (_, state) => _page(
          state: state,
          child: FolderDetailScreen(
            folderId: int.parse(state.pathParameters['id']!),
          ),
        ),
      ),
      GoRoute(
        path: '/folders/:id/permissions',
        pageBuilder: (_, state) => _page(
          state: state,
          child: FolderPermissionsScreen(
            folderId: int.parse(state.pathParameters['id']!),
          ),
        ),
      ),
      GoRoute(
        path: '/folders/:id/add_member',
        pageBuilder: (_, state) => _page(
          state: state,
          child: AddFolderMemberScreen(
            folderId: int.parse(state.pathParameters['id']!),
          ),
        ),
      ),

      // Member Management
      GoRoute(
        path: '/members',
        pageBuilder: (context, state) => _page(state: state, child: const MemberListScreen()),
        routes: [
          GoRoute(
            path: ':id',
            pageBuilder: (context, state) => _page(
              state: state,
              child: MemberDetailScreen(userId: state.pathParameters['id']!),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/members-enroll',
        pageBuilder: (context, state) => _page(state: state, child: const AddMemberScreen()),
      ),

      // Events
      GoRoute(
        path: '/events', 
        pageBuilder: (_, state) => _page(
          state: state,
          child: EventListScreen(
            folderId: int.tryParse(state.uri.queryParameters['folder'] ?? ''),
          ),
        ),
      ),
      GoRoute(
        path: '/events/create',
        pageBuilder: (_, state) => _page(
          state: state,
          child: EventFormScreen(
            folderId: int.tryParse(state.uri.queryParameters['folder'] ?? ''),
          ),
        ),
      ),

      // Budget
      GoRoute(
        path: '/budget',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return _page(
            state: state,
            child: BudgetOverviewScreen(initialTab: extra?['tab'] as int?),
          );
        },
      ),
      GoRoute(
        path: '/budget/request',
        pageBuilder: (_, state) => _page(
          state: state,
          child: BudgetRequestScreen(
            folderId: int.tryParse(state.uri.queryParameters['folder'] ?? ''),
            mode: state.uri.queryParameters['mode'],
          ),
        ),
      ),

      // Reports
      GoRoute(path: '/reports/upload', pageBuilder: (_, state) => _page(state: state, child: const ReportUploadScreen())),
      GoRoute(path: '/reports', pageBuilder: (_, state) => _page(state: state, child: const ReportListScreen())),

      // Announcements
      GoRoute(path: '/announcements', pageBuilder: (_, state) => _page(state: state, child: const AnnouncementScreen())),

      // Chat
      GoRoute(
        path: '/chat', 
        pageBuilder: (_, state) {
          final forumId = int.tryParse(state.uri.queryParameters['forumId'] ?? '');
          final userId = state.uri.queryParameters['userId'];
          
          if (forumId != null) return _page(state: state, child: ChatScreen(forumId: forumId));
          if (userId != null) return _page(state: state, child: ChatScreen(otherUserId: userId));
          return _page(state: state, child: const ChatListScreen());
        }
      ),
      GoRoute(
        path: '/chat/:userId',
        pageBuilder: (_, state) => _page(
          state: state,
          child: ChatScreen(
            otherUserId: state.pathParameters['userId']!,
          ),
        ),
      ),

      // Settings
      GoRoute(path: '/settings', pageBuilder: (_, state) => _page(state: state, child: const SettingsScreen())),
      GoRoute(path: '/settings/permissions', pageBuilder: (_, state) => _page(state: state, child: const PermissionManagerScreen())),

      // More
      GoRoute(path: '/more', pageBuilder: (_, state) => _page(state: state, child: const MoreScreen())),

      // ── Task Management ──────────────────────────────────────────────────
      GoRoute(path: '/tasks', pageBuilder: (_, state) => _page(state: state, child: const TaskListScreen())),
      GoRoute(
        path: '/tasks/create',
        pageBuilder: (_, state) => _page(state: state, child: const TaskCreateScreen()),
      ),
      GoRoute(
        path: '/tasks/:id',
        pageBuilder: (_, state) => _page(
          state: state,
          child: TaskDetailScreen(
            taskId: int.parse(state.pathParameters['id']!),
          ),
        ),
      ),
      GoRoute(
        path: '/tasks/:taskId/subtasks/create',
        pageBuilder: (_, state) => _page(
          state: state,
          child: TaskCreateScreen(
            taskId: int.parse(state.pathParameters['taskId']!),
          ),
        ),
      ),
      GoRoute(
        path: '/tasks/:taskId/subtasks/:subtaskId',
        pageBuilder: (_, state) => _page(
          state: state,
          child: SubtaskDetailScreen(
            taskId: int.parse(state.pathParameters['taskId']!),
            subtaskId: int.parse(state.pathParameters['subtaskId']!),
          ),
        ),
      ),

      // ── QR Attendance Scanner ─────────────────────────────────────────
      GoRoute(
        path: '/scan',
        pageBuilder: (_, state) => _page(
          state: state,
          child: QrScannerScreen(
            eventId: int.tryParse(state.uri.queryParameters['event'] ?? ''),
          ),
        ),
      ),

      // ── Registration Queue ────────────────────────────────────────────
      GoRoute(path: '/registrations', pageBuilder: (_, state) => _page(state: state, child: const RegistrationSummaryScreen())),
      GoRoute(
        path: '/registrations/queue',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return _page(
            state: state,
            child: RegistrationQueueScreen(
              initialIndex: extra?['initialIndex'] as int? ?? 0,
              initialGroupedData: extra?['groupedData'] as Map<String, List<RegistrationQueueModel>>?,
            ),
          );
        },
      ),
    ],
  );
}
