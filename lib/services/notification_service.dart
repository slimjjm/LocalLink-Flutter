import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../screens/notifications_screen.dart';

import '../screens/opportunity_detail_screen.dart';
import '../screens/profile_screen.dart';

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

    if (!Platform.isIOS || !kDebugMode) {
      await saveFcmTokenForCurrentUser();
    }

    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _routeFromPayload(message.data);
    });

    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();

    if (initialMessage != null) {
      Future.delayed(const Duration(milliseconds: 500), () {
        _routeFromPayload(initialMessage.data);
      });
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
        _routeFromPayload(data);
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
  }

  void _routeFromPayload(Map<String, dynamic> data) {
    final type = data['type'];

    switch (type) {
      case 'new_message':
        _openChat(data);
        break;

      case 'new_booking':
      case 'booking_confirmed':
      case 'booking_cancelled':
      case 'payment_failed':
        _openBooking(data);
        break;

      case 'follow':
      case 'review':
        _openProfile(data);
        break;

      case 'opportunity_join':
      case 'opportunity_comment':
      case 'opportunity_reminder':
        _openOpportunity(data);
        break;

      default:
        navigatorKey.currentState?.pushNamed('/home');
    }
  }

  void _openChat(Map<String, dynamic> data) {
    final businessId = data['businessId'];
    final customerId = data['customerId'];

    if (businessId == null || customerId == null) {
      navigatorKey.currentState?.pushNamed('/inbox');
      return;
    }

    navigatorKey.currentState?.pushNamed(
      '/chat',
      arguments: {'businessId': businessId, 'customerId': customerId},
    );
  }

  void _openBooking(Map<String, dynamic> data) {
    final bookingId = data['bookingId'];
    final businessId = data['businessId'];

    if (bookingId == null) {
      navigatorKey.currentState?.pushNamed('/bookings');
      return;
    }

    navigatorKey.currentState?.pushNamed(
      '/booking',
      arguments: {'bookingId': bookingId, 'businessId': businessId},
    );
  }

  Future<void> _openOpportunity(Map<String, dynamic> data) async {
    final opportunityId = data['opportunityId'];

    if (opportunityId == null) {
      navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => const NotificationsScreen()),
      );
      return;
    }

    final doc = await FirebaseFirestore.instance
        .collection('opportunities')
        .doc(opportunityId)
        .get();

    if (!doc.exists) {
      return;
    }

    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => OpportunityDetailScreen(
          opportunityId: opportunityId,
          opportunity: doc.data()!,
        ),
      ),
    );
  }

  Future<void> _openProfile(Map<String, dynamic> data) async {
    final userId = data['followerId'] ?? data['reviewerId'];

    if (userId == null) {
      return;
    }

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .get();

    if (!doc.exists) {
      return;
    }

    final userData = doc.data()!;

    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => ProfileScreen(
          userId: userId,
          userName: userData['userName'] ?? 'User',
          photoUrl: userData['photoUrl'],
        ),
      ),
    );
  }
}
