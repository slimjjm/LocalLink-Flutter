import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'notification_router.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

class NotificationService {
  NotificationService._();

  static final NotificationService shared = NotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  String? _boundTokenUid;

  static const AndroidNotificationChannel _androidChannel =
      AndroidNotificationChannel(
        'locallink_notifications',
        'LocalLink Notifications',
        description: 'Booking and message notifications',
        importance: Importance.high,
      );

  Future<void> initialise() async {
    await _requestPermission();
    await _setupAndroidChannel();
    await _setupLocalNotifications();

    FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (_boundTokenUid != null && _boundTokenUid != user?.uid) {
        await _removeTokenFromUser(_boundTokenUid!);
      }
      if (user != null && !user.isAnonymous) {
        await saveFcmTokenForCurrentUser();
      }
    });

    await saveFcmTokenForCurrentUser();

    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _routeFromPayloadWhenReady(message.data);
    });

    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();

    if (initialMessage != null) {
      _routeFromPayloadWhenReady(initialMessage.data);
    }

    _messaging.onTokenRefresh.listen((token) async {
      await _saveToken(token);
    });
  }

  Future<void> _requestPermission() async {
    await _messaging.requestPermission(alert: true, badge: true, sound: true);
  }

  Future<void> _setupAndroidChannel() async {
    if (!Platform.isAndroid) return;

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    await androidPlugin?.createNotificationChannel(_androidChannel);
  }

  Future<void> _setupLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    const iosSettings = DarwinInitializationSettings();

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;

        if (payload == null || payload.isEmpty) return;

        final data = Uri.splitQueryString(payload);
        _routeFromPayloadWhenReady(data);
      },
    );
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final notification = message.notification;
    final data = message.data;

    final title = notification?.title ?? data['title'] ?? 'LocalLink';

    final body = notification?.body ?? data['body'] ?? 'You have a new update';

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannel.id,
          _androidChannel.name,
          channelDescription: _androidChannel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: Uri(queryParameters: data).query,
    );
  }

  Future<void> saveFcmTokenForCurrentUser() async {
    try {
      if (Platform.isIOS) {
        final apnsToken = await _waitForApnsToken();
        if (apnsToken == null) {
          if (kDebugMode) {
            debugPrint(
              'NotificationService: APNs token not ready; FCM token save deferred.',
            );
          }
          return;
        }
      }

      final token = await _messaging.getToken();

      if (token == null) return;

      await _saveToken(token);
    } catch (_) {}
  }

  Future<void> _saveToken(String token) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null || user.isAnonymous) return;

    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'fcmTokens': FieldValue.arrayUnion([token]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    _boundTokenUid = user.uid;
  }

  Future<String?> _waitForApnsToken() async {
    for (var attempt = 0; attempt < 10; attempt += 1) {
      final token = await _messaging.getAPNSToken();
      if (token != null && token.isNotEmpty) return token;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    return null;
  }

  Future<void> _removeTokenFromUser(String uid) async {
    try {
      final token = await _messaging.getToken();
      if (token == null || token.isEmpty) return;
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'fcmTokens': FieldValue.arrayRemove([token]),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      if (kDebugMode) {
        debugPrint('NotificationService: token cleanup failed for prior user.');
      }
    }
  }

  void _routeFromPayloadWhenReady(Map<String, dynamic> data) {
    Future<void>(() async {
      for (var attempt = 0; attempt < 20; attempt += 1) {
        final navigator = navigatorKey.currentState;
        if (navigator != null) {
          await NotificationRouter.routeFromNavigator(navigator, data);
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }

      if (kDebugMode) {
        debugPrint('NotificationService: navigator not ready for tap route.');
      }
    });
  }
}
