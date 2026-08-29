import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/business_access_service.dart';
import '../theme/app_colors.dart';
import 'business_home_screen.dart';
import 'business_onboarding_screen.dart';

class BusinessGateScreen extends StatelessWidget {
  const BusinessGateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Please sign in to open your business.')),
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

        if (business != null && business.exists) {
          return BusinessHomeScreen(businessId: business.id);
        }

        return const _NoLinkedBusinessScreen();
      },
    );
  }
}

class _NoLinkedBusinessScreen extends StatelessWidget {
  const _NoLinkedBusinessScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Business'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.charcoal,
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: AppColors.serviceGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.storefront_outlined,
                  color: AppColors.serviceGreen,
                  size: 30,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'No business linked yet',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.charcoal,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'You are signed in as a user. Create or claim a business when you are ready to take bookings.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, height: 1.35),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const BusinessOnboardingScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.add_business_outlined),
                  label: const Text('Set up a business'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Go back'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
