import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/theme.dart';
import 'core/router.dart';

const _supabaseUrl = 'https://vwxbgklgkcbwrvtwypfs.supabase.co';
const _supabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZ3eGJna2xna2Nid3J2dHd5cGZzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE5OTkxNjIsImV4cCI6MjA4NzU3NTE2Mn0.DcBZJcNw3V0cCmzyZcipfQLYxq7j_PzbEc2UOM3z9FA';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: _supabaseUrl,
    anonKey: _supabaseAnonKey,
  );

  // Handle deep links — when user taps the magic link in OTP email
  _initDeepLinks();

  runApp(
    const ProviderScope(
      child: MemberApp(),
    ),
  );
}

void _initDeepLinks() {
  final appLinks = AppLinks();

  // Handle deep links when app is already open
  appLinks.uriLinkStream.listen((uri) {
    _handleDeepLink(uri);
  });

  // Handle deep link that launched the app (cold start)
  appLinks.getInitialLink().then((uri) {
    if (uri != null) _handleDeepLink(uri);
  });
}

void _handleDeepLink(Uri uri) {
  // Supabase will detect the #access_token fragment and set the session
  Supabase.instance.client.auth.getSessionFromUrl(uri);
}

class MemberApp extends ConsumerWidget {
  const MemberApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'ISTE Member',
      debugShowCheckedModeBanner: false,
      theme: MemberTheme.darkTheme,
      routerConfig: router,
    );
  }
}
