import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'core/auth_gate.dart';
import 'firebase_options.dart';
import 'services/notification_service.dart';

import 'screens/inbox_screen.dart';
import 'screens/enquiry_chat_screen.dart';
import 'screens/customer_bookings_screen.dart';
import 'screens/customer_booking_detail_screen.dart';
import 'screens/business_booking_detail_screen.dart';
import 'screens/claim_business_screen.dart';

// =====================================================
// BACKGROUND NOTIFICATION HANDLER
// =====================================================

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(
  RemoteMessage message,
) async {

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

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

  await NotificationService.shared.initialise();

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

    return MaterialApp(

      navigatorKey: navigatorKey,

      debugShowCheckedModeBanner: false,

     home: const AuthGate(),

      routes: {

  '/home': (_) =>
      const AuthGate(),

      '/claim-business': (_) =>
    const ClaimBusinessScreen(),

  // =====================================================
  // INBOX
  // =====================================================

 '/inbox': (_) =>

    InboxScreen(
      currentRole: 'customer',
    ),

  // =====================================================
  // BOOKINGS
  // =====================================================

  '/bookings': (_) =>
      const CustomerBookingsScreen(),

  // =====================================================
  // CHAT
  // =====================================================

  '/chat': (context) {

    final args =
        ModalRoute.of(context)!
            .settings
            .arguments
            as Map<String, dynamic>;

    return EnquiryChatScreen(

      businessId:
          args['businessId'],

      customerId:
          args['customerId'],
    );
  },

  // =====================================================
  // BOOKING DETAIL
  // =====================================================

  '/booking': (context) {

    final args =
        ModalRoute.of(context)!
            .settings
            .arguments
            as Map<String, dynamic>;

    final bookingId =
        args['bookingId'];

    final businessId =
        args['businessId'];

    // If businessId exists,
    // assume business-side detail screen

    if (businessId != null) {

      return BusinessBookingDetailScreen(
        bookingId: bookingId,
      );
    }

    // Otherwise customer detail screen

    return CustomerBookingDetailScreen(
      bookingId: bookingId,
    );
  },
},
    );
  }
}