import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationService {

  static final FirebaseMessaging _messaging =
      FirebaseMessaging.instance;

  // =====================================================
  // INITIALISE
  // =====================================================

  static Future<void> initialize() async {

    // ==========================================
    // REQUEST PERMISSION
    // ==========================================

    NotificationSettings settings =
        await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    print(
      '🔔 Notification permission: '
      '${settings.authorizationStatus}',
    );

    // ==========================================
    // GET TOKEN
    // ==========================================

    final token =
        await _messaging.getToken();

    print('📲 FCM TOKEN: $token');

    if (token != null) {
      await saveToken(token);
    }

    // ==========================================
    // TOKEN REFRESH
    // ==========================================

    FirebaseMessaging.instance
        .onTokenRefresh
        .listen((newToken) async {

      print('🔄 Token refreshed');

      await saveToken(newToken);
    });

    // ==========================================
    // FOREGROUND HANDLING
    // ==========================================

    FirebaseMessaging.onMessage.listen((
      RemoteMessage message,
    ) {

      print(
        '📩 Foreground notification: '
        '${message.notification?.title}',
      );
    });

    // ==========================================
    // BACKGROUND OPEN
    // ==========================================

    FirebaseMessaging.onMessageOpenedApp
        .listen((RemoteMessage message) {

      print(
        '📬 Notification opened app',
      );
    });

    // ==========================================
    // iOS FOREGROUND OPTIONS
    // ==========================================

    if (Platform.isIOS) {

      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    }
  }

  // =====================================================
  // SAVE TOKEN
  // =====================================================

  static Future<void> saveToken(
    String token,
  ) async {

    final user =
        FirebaseAuth.instance.currentUser;

    if (user == null) return;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .set({

      'fcmTokens': FieldValue.arrayUnion(
        [token],
      ),

    }, SetOptions(merge: true));
  }
}