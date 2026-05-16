import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import 'core/auth_gate.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // ✅ STRIPE SETUP
  Stripe.publishableKey =
      'pk_live_51SglXVK5HcMhAFOzHoPh0x9g7I2Ed8OAQIelZ7ztksqbHLXTfycT9WCNz57II3R2tQLfsr2J9Wqw8ni2aB36oaxf001VDk8azd';

  await Stripe.instance.applySettings();

  runApp(const MyApp());
}

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