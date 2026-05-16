import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'business_home_screen.dart';
import 'business_onboarding_screen.dart';

class BusinessGateScreen extends StatelessWidget {

  const BusinessGateScreen({super.key});

  @override
  Widget build(BuildContext context) {

    final user =
        FirebaseAuth.instance.currentUser;

    if (user == null) {

      return const Scaffold(
        body: Center(
          child: Text('Not logged in'),
        ),
      );
    }

    return FutureBuilder<QuerySnapshot>(

      future: FirebaseFirestore.instance
          .collection('businesses')
          .where(
            'ownerId',
            isEqualTo: user.uid,
          )
          .limit(1)
          .get(),

      builder: (context, snapshot) {

        if (!snapshot.hasData) {

          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        final docs = snapshot.data!.docs;

        // =====================================
        // USER OWNS BUSINESS
        // =====================================

        if (docs.isNotEmpty) {

          final businessId = docs.first.id;

          return BusinessHomeScreen(
            businessId: businessId,
          );
        }

        // =====================================
        // USER DOES NOT OWN BUSINESS
        // =====================================

        return const BusinessOnboardingScreen();
      },
    );
  }
}