import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Background message handler
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint("Handling a background message: ${message.messageId}");
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final _supabase = Supabase.instance.client;
  FirebaseMessaging? _fcm;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // 1. Initialize Firebase core
      await Firebase.initializeApp();
      
      // Initialize FCM instance after core is initialized
      _fcm = FirebaseMessaging.instance;

      // 2. Set background message handler
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      // 3. Setup foreground notification channel for Android
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'iste_alerts_channel', // id
        'ISTE Alerts & Notifications', // title
        description: 'This channel is used for real-time announcements and event updates.', // description
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      );

      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);

      // 4. Initialize Local Notifications Plugin
      const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );

      const InitializationSettings initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _localNotifications.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse details) {
          debugPrint("Local notification clicked: ${details.payload}");
        },
      );

      // 5. Request User Permissions (highly dynamic)
      if (_fcm != null) {
        NotificationSettings settings = await _fcm!.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
        );

        if (settings.authorizationStatus == AuthorizationStatus.authorized) {
          debugPrint('FCM Push Notification permissions authorized!');
          
          // Subscribe to standard global topics
          await _fcm!.subscribeToTopic('all_organizers');
          await _fcm!.subscribeToTopic('announcements');
          await _fcm!.subscribeToTopic('events');
        } else {
          debugPrint('FCM Push Notification permissions declined or restricted.');
        }
      }

      // 6. Handle Foreground messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint("Received a foreground message: ${message.notification?.title}");
        
        RemoteNotification? notification = message.notification;

        if (notification != null) {
          _localNotifications.show(
            id: notification.hashCode,
            title: notification.title,
            body: notification.body,
            notificationDetails: NotificationDetails(
              android: AndroidNotificationDetails(
                channel.id,
                channel.name,
                channelDescription: channel.description,
                importance: Importance.max,
                priority: Priority.high,
                icon: '@mipmap/ic_launcher',
              ),
              iOS: const DarwinNotificationDetails(
                presentAlert: true,
                presentBadge: true,
                presentSound: true,
              ),
            ),
            payload: message.data.toString(),
          );
        }
      });

      // 7. Handle app opening from notification when app is in background but active
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint("App opened via FCM notification click: ${message.data}");
      });

      // 8. Retrieve and synchronize FCM token
      _syncFcmToken();

      _isInitialized = true;
      debugPrint("Notification Service successfully initialized!");
    } catch (e) {
      debugPrint("FCM Initialization warning: $e. Setup might require firebase config file.");
    }
  }

  Future<void> _syncFcmToken() async {
    try {
      if (_fcm == null) return;
      final token = await _fcm!.getToken();
      if (token == null) return;
      debugPrint("Retrieve active FCM registration token: $token");

      final currentUser = _supabase.auth.currentUser;
      if (currentUser != null) {
        // Upsert FCM token to Supabase profiles
        await _supabase.from('profiles').update({
          'fcm_token': token,
          'last_active': DateTime.now().toIso8601String(),
        }).eq('id', currentUser.id);
        debugPrint("FCM Registration token successfully synchronized with Supabase database!");
      }
    } catch (dbErr) {
      // In case database trigger or RLS locks column, degrade gracefully without blocking app
      debugPrint("FCM token DB synchronization note: $dbErr");
    }
  }

  Future<void> showNotification({required String title, required String body, String? payload}) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'iste_alerts_channel',
      'ISTE Alerts & Notifications',
      channelDescription: 'This channel is used for real-time announcements and event updates.',
      importance: Importance.max,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    await _localNotifications.show(
      id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      ),
      payload: payload,
    );
  }
}
