import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'providers/auth_provider.dart';
import '../screens/splash/splash_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/membership/membership_card_screen.dart';
import '../screens/events/event_list_screen.dart';
import '../screens/events/event_detail_screen.dart';
import '../screens/qr/qr_display_screen.dart';
import '../screens/certificates/certificates_screen.dart';
import '../screens/notifications/notifications_screen.dart';
import '../screens/auth/web_link_screen.dart';

class RouterNotifier extends ChangeNotifier {
  final Ref ref;
  RouterNotifier(this.ref) {
    ref.listen(authProvider, (_, __) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = RouterNotifier(ref);

  Page<dynamic> page(GoRouterState state, Widget child) {
    return CupertinoPage<dynamic>(
      key: state.pageKey,
      child: child,
    );
  }

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: notifier,
    redirect: (context, state) {
      final authState = ref.read(authProvider);
      final loc = state.uri.path;
      if (authState.isLoading) return loc == '/splash' ? null : '/splash';
      if (!authState.isAuthenticated) {
        // Allow unauthenticated users to see splash screen for onboarding
        if (loc == '/splash') return null;
        return loc == '/login' ? null : '/login';
      }
      if (loc == '/splash' || loc == '/login') return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', pageBuilder: (_, state) => page(state, const SplashScreen())),
      GoRoute(path: '/login', pageBuilder: (_, state) => page(state, const LoginScreen())),
      GoRoute(path: '/link-web', pageBuilder: (_, state) => page(state, const WebLinkScreen())),
      GoRoute(path: '/home', pageBuilder: (_, state) => page(state, const HomeScreen())),
      GoRoute(path: '/membership', pageBuilder: (_, state) => page(state, const MembershipCardScreen())),
      GoRoute(path: '/events', pageBuilder: (_, state) => page(state, const EventListScreen())),
      GoRoute(
        path: '/events/:id',
        pageBuilder: (_, state) => page(
          state,
          EventDetailScreen(
            eventId: int.parse(state.pathParameters['id']!),
          ),
        ),
      ),
      GoRoute(path: '/qr', pageBuilder: (_, state) => page(state, const QrDisplayScreen())),
      GoRoute(path: '/certificates', pageBuilder: (_, state) => page(state, const CertificatesScreen())),
      GoRoute(path: '/notifications', pageBuilder: (_, state) => page(state, const NotificationsScreen())),
    ],
  );
});
