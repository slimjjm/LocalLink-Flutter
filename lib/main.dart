import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import 'package:firebase_messaging/firebase_messaging.dart';

import 'core/auth_gate.dart';
import 'firebase_options.dart';
import 'services/notification_service.dart';

// =====================================================
// BACKGROUND NOTIFICATION HANDLER
// =====================================================

Future<void> firebaseMessagingBackgroundHandler(
  RemoteMessage message,
) async {

  print(
    '🔔 Background message: '
    '${message.messageId}',
  );
}

// =====================================================
// MAIN
// =====================================================

void main() async {

  WidgetsFlutterBinding.ensureInitialized();

  // =====================================================
  // FIREBASE
  // =====================================================

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // =====================================================
  // FIREBASE MESSAGING
  // =====================================================

  FirebaseMessaging.onBackgroundMessage(
    firebaseMessagingBackgroundHandler,
  );

  await NotificationService.initialize();

  // =====================================================
  // STRIPE
  // =====================================================

  Stripe.publishableKey =
      'pk_live_51SglXVK5HcMhAFOzHoPh0x9g7I2Ed8OAQIelZ7ztksqbHLXTfycT9WCNz57II3R2tQLfsr2J9Wqw8ni2aB36oaxf001VDk8azd';

  await Stripe.instance.applySettings();

  // =====================================================
  // RUN APP
  // =====================================================

  runApp(const MyApp());
}

// =====================================================
// APP
// =====================================================

class MyApp extends StatelessWidget {

  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {

    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: AuthGate(),
    );
  }
}