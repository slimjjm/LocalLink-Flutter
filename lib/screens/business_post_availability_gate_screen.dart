import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/business_access_service.dart';
import 'business_onboarding_screen.dart';
import 'post_availability_screen.dart';

class BusinessPostAvailabilityGateScreen extends StatelessWidget {
  const BusinessPostAvailabilityGateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Please sign in to share when you are free.')),
      );
    }

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>?>(
      future: BusinessAccessService.loadLinkedBusiness(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final business = snapshot.data;

        if (business == null || !business.exists) {
          return const BusinessOnboardingScreen();
        }

        return PostAvailabilityScreen(businessId: business.id);
      },
    );
  }
}
