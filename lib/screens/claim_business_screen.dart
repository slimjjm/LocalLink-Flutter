import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../services/analytics_service.dart';
import 'business_home_screen.dart';
import 'login_screen.dart';

class ClaimBusinessScreen extends StatefulWidget {
  const ClaimBusinessScreen({super.key});

  @override
  State<ClaimBusinessScreen> createState() => _ClaimBusinessScreenState();
}

class _ClaimBusinessScreenState extends State<ClaimBusinessScreen> {
  // =====================================================
  // CONTROLLERS
  // =====================================================

  final TextEditingController claimCodeController = TextEditingController();

  // =====================================================
  // STATE
  // =====================================================

  bool isLoading = false;

  String? errorMessage;
  String? successMessage;

  Map<String, dynamic>? businessData;

  String? businessId;

  // =====================================================
  // SEARCH
  // =====================================================

  Future<void> searchBusiness() async {
    final code = claimCodeController.text.trim().toUpperCase();

    if (code.isEmpty) {
      return;
    }

    setState(() {
      isLoading = true;

      errorMessage = null;
      successMessage = null;

      businessData = null;
      businessId = null;
    });

    try {
      final result = await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('findBusinessClaim')
          .call(<String, dynamic>{'claimCode': code});
      final data = Map<String, dynamic>.from(result.data as Map);

      setState(() {
        businessData = data;
        businessId = data['businessId']?.toString();
      });
    } catch (e) {
      setState(() {
        errorMessage = 'Failed to search business.';
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  // =====================================================
  // CLAIM BUSINESS
  // =====================================================

  Future<void> claimBusiness() async {
    final user = FirebaseAuth.instance.currentUser;

    // =====================================================
    // LOGIN REQUIRED
    // =====================================================

    if (user == null || user.isAnonymous) {
      if (!mounted) return;

      Navigator.push(
        context,

        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );

      return;
    }

    if (businessId == null || businessData == null) {
      return;
    }

    setState(() {
      isLoading = true;

      errorMessage = null;
      successMessage = null;
    });
    await LocalLinkAnalytics.instance.logEvent('business_claim_started', {
      'source': 'claim_code',
    });

    try {
      final result = await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('claimBusinessByCode')
          .call(<String, dynamic>{
            'claimCode': claimCodeController.text.trim().toUpperCase(),
          });
      final claimed = Map<String, dynamic>.from(result.data as Map);
      businessId = claimed['businessId']?.toString() ?? businessId;

      setState(() {
        successMessage = 'Business claimed successfully 🎉';
      });
      await LocalLinkAnalytics.instance.logEvent('business_claim_completed', {
        'source': 'claim_code',
      });

      if (!mounted) return;
      final navigator = Navigator.of(context);

      Future.delayed(const Duration(milliseconds: 700), () {
        navigator.pushReplacement(
          MaterialPageRoute(
            builder: (_) => BusinessHomeScreen(businessId: businessId!),
          ),
        );
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        errorMessage =
            'We could not claim this business. Please check the details and try again.';
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  // =====================================================
  // UI
  // =====================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Claim Business')),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,

          children: [
            const SizedBox(height: 20),

            // =================================================
            // HEADER
            // =================================================
            const Icon(Icons.business, size: 70),

            const SizedBox(height: 20),

            const Text(
              'Claim your business',

              textAlign: TextAlign.center,

              style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 10),

            const Text(
              'Enter the claim code provided by LocalLink.',

              textAlign: TextAlign.center,

              style: TextStyle(fontSize: 16),
            ),

            const SizedBox(height: 40),

            // =================================================
            // CLAIM CODE
            // =================================================
            TextField(
              controller: claimCodeController,

              textCapitalization: TextCapitalization.characters,

              decoration: const InputDecoration(
                labelText: 'Claim Code',

                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 20),

            // =================================================
            // SEARCH
            // =================================================
            ElevatedButton(
              onPressed: isLoading ? null : searchBusiness,

              child: isLoading
                  ? const CircularProgressIndicator()
                  : const Text('Find Business'),
            ),

            const SizedBox(height: 20),

            // =================================================
            // ERROR
            // =================================================
            if (errorMessage != null)
              Container(
                padding: const EdgeInsets.all(14),

                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(12),
                ),

                child: Text(
                  errorMessage!,

                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

            // =================================================
            // SUCCESS
            // =================================================
            if (successMessage != null)
              Container(
                padding: const EdgeInsets.all(14),

                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(12),
                ),

                child: Text(
                  successMessage!,

                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

            // =================================================
            // BUSINESS RESULT
            // =================================================
            if (businessData != null) ...[
              const SizedBox(height: 30),

              Container(
                padding: const EdgeInsets.all(20),

                decoration: BoxDecoration(
                  color: Colors.grey.shade100,

                  borderRadius: BorderRadius.circular(16),
                ),

                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    Text(
                      businessData!['businessName'] ?? 'Business',

                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 8),

                    Text(businessData!['category']?.toString() ?? ''),

                    const SizedBox(height: 4),

                    Text(businessData!['address']?.toString() ?? ''),

                    const SizedBox(height: 20),

                    SizedBox(
                      width: double.infinity,

                      child: ElevatedButton(
                        onPressed: isLoading ? null : claimBusiness,

                        child: const Text('Claim This Business'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
