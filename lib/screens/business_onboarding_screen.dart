import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'business_home_screen.dart';

class BusinessOnboardingScreen extends StatefulWidget {

  final bool isAssisted;

  const BusinessOnboardingScreen({
    super.key,
    this.isAssisted = false,
  });

  @override
  State<BusinessOnboardingScreen> createState() =>
      _BusinessOnboardingScreenState();
}

class _BusinessOnboardingScreenState
    extends State<BusinessOnboardingScreen> {

  // =====================================================
  // CONTROLLERS
  // =====================================================

  final businessNameController =
      TextEditingController();

  final claimEmailController =
      TextEditingController();

  final addressController =
      TextEditingController();

  // =====================================================
  // FORM STATE
  // =====================================================

  String? selectedCategory;

  final categories = [
    'Cleaner',
    'Dog Walker',
    'Hairdresser',
    'Barber',
    'Dog Groomer',
    'Gardener',
    'Nails',
    'Personal Trainer',
    'Hair Salon',
  ];

  String serviceMode = 'premises';

  double serviceRadiusMiles = 10;

  bool acceptsCash = true;
  bool acceptsStripe = false;

  bool isSaving = false;

  String? bannerMessage;

  // =====================================================
  // HELPERS
  // =====================================================

  bool get formIsValid {

    return businessNameController.text
            .trim()
            .isNotEmpty &&
        addressController.text
            .trim()
            .isNotEmpty &&
        selectedCategory != null;
  }

  List<String> get selectedPaymentMethods {

    final methods = <String>[];

    if (acceptsCash) {
      methods.add('cash');
    }

    if (acceptsStripe) {
      methods.add('stripe');
    }

    return methods;
  }

  String generateClaimCode() {

    const chars =
        'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

    return List.generate(
      6,
      (index) => chars[
          (chars.length *
                  (index + DateTime.now().millisecond))
              % chars.length],
    ).join();
  }

  // =====================================================
  // CREATE BUSINESS
  // =====================================================

  Future<void> createBusiness() async {

    if (!formIsValid) {
      return;
    }

    final user =
        FirebaseAuth.instance.currentUser;

    if (user == null) {

      setState(() {
        bannerMessage = 'Please log in';
      });

      return;
    }

    setState(() {
      isSaving = true;
      bannerMessage = null;
    });

    try {

      final docRef =
          FirebaseFirestore.instance
              .collection('businesses')
              .doc();

      final claimCode =
          generateClaimCode();

      final data = {

        // =====================================
        // CORE
        // =====================================

        'businessName':
            businessNameController.text.trim(),

        'address':
            addressController.text.trim(),

        'category':
            selectedCategory,

        // =====================================
        // OWNERSHIP
        // =====================================

        'createdBy': user.uid,

        'ownerId':
            widget.isAssisted
                ? ''
                : user.uid,

        'claimEmail':
            widget.isAssisted
                ? claimEmailController.text.trim()
                : null,

        'isClaimed':
            !widget.isAssisted,

        'claimCode':
            claimCode,

        // =====================================
        // STATUS
        // =====================================

        'isActive': true,

        'createdAt':
            FieldValue.serverTimestamp(),

        // =====================================
        // PAYMENTS
        // =====================================

        'paymentMethods':
            selectedPaymentMethods,

        'stripeConnected': false,

        'stripeChargesEnabled': false,

        // =====================================
        // BUSINESS MODE
        // =====================================

        'serviceMode': serviceMode,

        'serviceRadiusMiles':
            serviceRadiusMiles,
      };

      await docRef.set(data);

      await FirebaseFirestore.instance
    .collection('businesses')
    .doc(docRef.id)
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

      if (!mounted) return;

      Navigator.pushReplacement(

        context,

        MaterialPageRoute(

          builder: (_) =>
              BusinessHomeScreen(
            businessId: docRef.id,
          ),
        ),
      );

    } catch (e) {

      setState(() {
        bannerMessage = e.toString();
      });

    } finally {

      setState(() {
        isSaving = false;
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
        title: Text(
          widget.isAssisted
              ? 'Add Business'
              : 'Create Business',
        ),
      ),

      body: SingleChildScrollView(

        padding: const EdgeInsets.all(20),

        child: Column(

          crossAxisAlignment:
              CrossAxisAlignment.stretch,

          children: [

            // =====================================
            // HEADER
            // =====================================

            Text(

              widget.isAssisted
                  ? 'Add a business'
                  : 'Create your business',

              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            const Text(
              'Start taking bookings in minutes.',
            ),

            const SizedBox(height: 30),

            // =====================================
            // BUSINESS NAME
            // =====================================

            TextField(

              controller:
                  businessNameController,

              decoration: const InputDecoration(
                labelText: 'Business Name',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 20),

            // =====================================
            // CLAIM EMAIL
            // =====================================

            if (widget.isAssisted)
              Column(

                children: [

                  TextField(

                    controller:
                        claimEmailController,

                    decoration:
                        const InputDecoration(
                      labelText:
                          'Owner Email',
                      border:
                          OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(height: 20),
                ],
              ),

            // =====================================
            // ADDRESS
            // =====================================

            TextField(

              controller:
                  addressController,

              decoration: const InputDecoration(
                labelText: 'Business Address',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 20),

            // =====================================
            // CATEGORY
            // =====================================

            DropdownButtonFormField<String>(

              value: selectedCategory,

              decoration: const InputDecoration(
                labelText: 'Category',
                border: OutlineInputBorder(),
              ),

              items: categories.map((category) {

                return DropdownMenuItem(
                  value: category,
                  child: Text(category),
                );

              }).toList(),

              onChanged: (value) {

                setState(() {
                  selectedCategory = value;
                });
              },
            ),

            const SizedBox(height: 30),

            // =====================================
            // BUSINESS TYPE
            // =====================================

            const Text(

              'Business Type',

              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 12),

            SegmentedButton<String>(

              segments: const [

                ButtonSegment(
                  value: 'premises',
                  label: Text('Premises'),
                ),

                ButtonSegment(
                  value: 'mobile',
                  label: Text('Mobile'),
                ),

                ButtonSegment(
                  value: 'hybrid',
                  label: Text('Both'),
                ),
              ],

              selected: {serviceMode},

              onSelectionChanged: (selection) {

                setState(() {
                  serviceMode = selection.first;
                });
              },
            ),

            const SizedBox(height: 12),

            Text(

              serviceMode == 'premises'
                  ? 'Customers visit your business.'
                  : serviceMode == 'mobile'
                      ? 'You travel to customers.'
                      : 'Customers can visit you or book mobile services.',

              style: TextStyle(
                color: Colors.grey.shade700,
              ),
            ),

            // =====================================
            // RADIUS
            // =====================================

            if (serviceMode == 'mobile' ||
                serviceMode == 'hybrid')
              Column(

                children: [

                  const SizedBox(height: 24),

                  Row(

                    children: [

                      const Text(
                        'Travel Radius',
                      ),

                      const Spacer(),

                      Text(
                        '${serviceRadiusMiles.toInt()} miles',
                      ),
                    ],
                  ),

                  Slider(

                    value: serviceRadiusMiles,

                    min: 1,
                    max: 50,

                    divisions: 49,

                    label:
                        '${serviceRadiusMiles.toInt()}',

                    onChanged: (value) {

                      setState(() {
                        serviceRadiusMiles = value;
                      });
                    },
                  ),
                ],
              ),

            const SizedBox(height: 30),

            // =====================================
            // PAYMENT METHODS
            // =====================================

            const Text(

              'Payment Methods',

              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),

            CheckboxListTile(

              value: acceptsCash,

              title: const Text(
                'Accept Cash',
              ),

              onChanged: (value) {

                setState(() {
                  acceptsCash =
                      value ?? false;
                });
              },
            ),

            CheckboxListTile(

              value: acceptsStripe,

              title: const Text(
                'Accept Card Payments (Stripe)',
              ),

              onChanged: (value) {

                setState(() {
                  acceptsStripe =
                      value ?? false;
                });
              },
            ),

            const SizedBox(height: 20),

            // =====================================
            // INFO BOX
            // =====================================

            Container(

              padding: const EdgeInsets.all(16),

              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius:
                    BorderRadius.circular(12),
              ),

              child: const Text(
                'Create profile • Add services • Connect payments later',
              ),
            ),

            const SizedBox(height: 20),

            // =====================================
            // ERROR / BANNER
            // =====================================

            if (bannerMessage != null)

              Container(

                padding: const EdgeInsets.all(14),

                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius:
                      BorderRadius.circular(12),
                ),

                child: Text(

                  bannerMessage!,

                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
              ),

            const SizedBox(height: 30),

            // =====================================
            // CREATE BUTTON
            // =====================================

            ElevatedButton(

              onPressed:
                  isSaving
                      ? null
                      : createBusiness,

              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(
                  vertical: 18,
                ),
              ),

              child:
                  isSaving

                      ? const CircularProgressIndicator()

                      : Text(
                          widget.isAssisted
                              ? 'Add Business'
                              : 'Create Business',
                        ),
            ),
          ],
        ),
      ),
    );
  }
}