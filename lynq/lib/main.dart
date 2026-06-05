import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/theme.dart';
import 'core/theme_provider.dart';
import 'core/auth_provider.dart';
import 'core/router.dart';
import 'core/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Supabase.initialize(
      url: 'https://vwxbgklgkcbwrvtwypfs.supabase.co',
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZ3eGJna2xna2Nid3J2dHd5cGZzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE5OTkxNjIsImV4cCI6MjA4NzU3NTE2Mn0.DcBZJcNw3V0cCmzyZcipfQLYxq7j_PzbEc2UOM3z9FA',
    );
  } catch (e) {
    debugPrint("Supabase initialization error: $e");
  }

  // Initialize push notification services (FCM + Local Notifications)
  try {
    await NotificationService().initialize();
  } catch (e) {
    debugPrint("Notification initialization error: $e");
  }

  final authProvider = AuthProvider();
  final themeProvider = ThemeProvider();
  final appRouter = AppRouter(authProvider);

  runApp(ExeccomApp(
    authProvider: authProvider, 
    themeProvider: themeProvider,
    appRouter: appRouter,
  ));
}

class ExeccomApp extends StatelessWidget {
  final AuthProvider authProvider;
  final ThemeProvider themeProvider;
  final AppRouter appRouter;

  const ExeccomApp({
    super.key, 
    required this.authProvider, 
    required this.themeProvider, 
    required this.appRouter,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authProvider),
        ChangeNotifierProvider.value(value: themeProvider),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeManager, child) {
          return MaterialApp.router(
            title: 'ISTE Execcom',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeManager.themeMode,
            routerConfig: appRouter.router,
          );
        },
      ),
    );
  }
}
