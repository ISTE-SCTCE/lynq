import 'package:flutter/material.dart';
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

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: notifier,
    redirect: (context, state) {
      final authState = ref.read(authProvider);
      final loc = state.matchedLocation;
      if (authState.isLoading) return loc == '/splash' ? null : '/splash';
      if (!authState.isAuthenticated) return loc == '/login' ? null : '/login';
      if (loc == '/splash' || loc == '/login') return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/link-web', builder: (_, __) => const WebLinkScreen()),
      GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
      GoRoute(path: '/membership', builder: (_, __) => const MembershipCardScreen()),
      GoRoute(path: '/events', builder: (_, __) => const EventListScreen()),
      GoRoute(
        path: '/events/:id',
        builder: (_, state) => EventDetailScreen(
          eventId: int.parse(state.pathParameters['id']!),
        ),
      ),
      GoRoute(path: '/qr', builder: (_, __) => const QrDisplayScreen()),
      GoRoute(path: '/certificates', builder: (_, __) => const CertificatesScreen()),
      GoRoute(path: '/notifications', builder: (_, __) => const NotificationsScreen()),
    ],
  );
});
