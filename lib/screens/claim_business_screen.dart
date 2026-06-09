import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'business_home_screen.dart';
import 'login_screen.dart';

class ClaimBusinessScreen extends StatefulWidget {

  const ClaimBusinessScreen({
    super.key,
  });

  @override
  State<ClaimBusinessScreen> createState() =>
      _ClaimBusinessScreenState();
}

class _ClaimBusinessScreenState
    extends State<ClaimBusinessScreen> {

  // =====================================================
  // CONTROLLERS
  // =====================================================

  final TextEditingController
      claimCodeController =
          TextEditingController();

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

    final code =
        claimCodeController.text
            .trim()
            .toUpperCase();

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

      final snapshot =
          await FirebaseFirestore.instance
              .collection('businesses')
              .where(
                'claimCode',
                isEqualTo: code,
              )
              .limit(1)
              .get();

      if (snapshot.docs.isEmpty) {

        setState(() {

          errorMessage =
              'No business found for that code.';
        });

        return;
      }

      final doc =
          snapshot.docs.first;

      final data = doc.data();

      setState(() {

        businessData = data;
        businessId = doc.id;
      });

    } catch (e) {

      setState(() {

        errorMessage =
            'Failed to search business.';
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

    final user =
        FirebaseAuth.instance.currentUser;

    // =====================================================
    // LOGIN REQUIRED
    // =====================================================

    if (user == null ||
        user.isAnonymous) {

      if (!mounted) return;

      Navigator.push(

        context,

        MaterialPageRoute(

          builder: (_) =>
              const LoginScreen(),
        ),
      );

      return;
    }

    if (businessId == null ||
        businessData == null) {
      return;
    }

    setState(() {

      isLoading = true;

      errorMessage = null;
      successMessage = null;
    });

    try {

      final ref =
          FirebaseFirestore.instance
              .collection('businesses')
              .doc(businessId);

      await FirebaseFirestore.instance
          .runTransaction((transaction) async {

        final snapshot =
            await transaction.get(ref);

        final data =
            snapshot.data() ?? {};

        final ownerId =
            data['ownerId'] ?? '';

        final claimEmail =
            (data['claimEmail'] ?? '')
                .toString()
                .toLowerCase();

        final userEmail =
            (user.email ?? '')
                .toLowerCase();

        // =========================================
        // ALREADY CLAIMED
        // =========================================

        if (ownerId.toString().isNotEmpty) {

          throw Exception(
            'This business has already been claimed.',
          );
        }

        // =========================================
        // EMAIL CHECK
        // =========================================

        if (claimEmail.isNotEmpty &&
            claimEmail != userEmail) {

          throw Exception(
            'This business was assigned to a different email.',
          );
        }

        // =========================================
        // CLAIM
        // =========================================

        transaction.update(ref, {

          'ownerId': user.uid,

          'isClaimed': true,

          'claimedAt':
              FieldValue.serverTimestamp(),

          'claimEmail':
              FieldValue.delete(),
        });
      });

      // =====================================================
      // CREATE OWNER STAFF RECORD
      // =====================================================

      await FirebaseFirestore.instance
          .collection('businesses')
          .doc(businessId)
          .collection('staff')
          .doc(user.uid)
          .set({

        'name': 'Owner',

        'email': user.email,

        'isActive': true,

        'seatRank': 0,

        'createdAt':
            FieldValue.serverTimestamp(),
      });

      setState(() {

        successMessage =
            'Business claimed successfully 🎉';
      });

      if (!mounted) return;

      Future.delayed(
        const Duration(milliseconds: 700),
        () {

          Navigator.pushReplacement(

            context,

            MaterialPageRoute(

              builder: (_) =>
                  BusinessHomeScreen(
                businessId: businessId!,
              ),
            ),
          );
        },
      );

    } catch (e) {

      setState(() {

        errorMessage =
            e.toString().replaceAll(
                  'Exception: ',
                  '',
                );
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

      appBar: AppBar(
        title: const Text(
          'Claim Business',
        ),
      ),

      body: SingleChildScrollView(

        padding: const EdgeInsets.all(20),

        child: Column(

          crossAxisAlignment:
              CrossAxisAlignment.stretch,

          children: [

            const SizedBox(height: 20),

            // =================================================
            // HEADER
            // =================================================

            const Icon(
              Icons.business,
              size: 70,
            ),

            const SizedBox(height: 20),

            const Text(

              'Claim your business',

              textAlign: TextAlign.center,

              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 10),

            const Text(

              'Enter the claim code provided by LocalLink.',

              textAlign: TextAlign.center,

              style: TextStyle(
                fontSize: 16,
              ),
            ),

            const SizedBox(height: 40),

            // =================================================
            // CLAIM CODE
            // =================================================

            TextField(

              controller:
                  claimCodeController,

              textCapitalization:
                  TextCapitalization.characters,

              decoration: const InputDecoration(

                labelText: 'Claim Code',

                border:
                    OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 20),

            // =================================================
            // SEARCH
            // =================================================

            ElevatedButton(

              onPressed:
                  isLoading
                      ? null
                      : searchBusiness,

              child:
                  isLoading

                      ? const CircularProgressIndicator()

                      : const Text(
                          'Find Business',
                        ),
            ),

            const SizedBox(height: 20),

            // =================================================
            // ERROR
            // =================================================

            if (errorMessage != null)

              Container(

                padding:
                    const EdgeInsets.all(14),

                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius:
                      BorderRadius.circular(12),
                ),

                child: Text(

                  errorMessage!,

                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
              ),

            // =================================================
            // SUCCESS
            // =================================================

            if (successMessage != null)

              Container(

                padding:
                    const EdgeInsets.all(14),

                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius:
                      BorderRadius.circular(12),
                ),

                child: Text(

                  successMessage!,

                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
              ),

            // =================================================
            // BUSINESS RESULT
            // =================================================

            if (businessData != null) ...[

              const SizedBox(height: 30),

              Container(

                padding:
                    const EdgeInsets.all(20),

                decoration: BoxDecoration(

                  color: Colors.grey.shade100,

                  borderRadius:
                      BorderRadius.circular(16),
                ),

                child: Column(

                  crossAxisAlignment:
                      CrossAxisAlignment.start,

                  children: [

                    Text(

                      businessData!['businessName']
                          ?? 'Business',

                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 8),

                    Text(
                      businessData!['category']
                              ?.toString() ??
                          '',
                    ),

                    const SizedBox(height: 4),

                    Text(
                      businessData!['address']
                              ?.toString() ??
                          '',
                    ),

                    const SizedBox(height: 20),

                    SizedBox(

                      width: double.infinity,

                      child: ElevatedButton(

                        onPressed:
                            isLoading
                                ? null
                                : claimBusiness,

                        child: const Text(
                          'Claim This Business',
                        ),
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