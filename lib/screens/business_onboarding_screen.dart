import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/address_result.dart';
import '../services/address_search_service.dart';
import '../theme/app_colors.dart';
import 'business_home_screen.dart';

class BusinessOnboardingScreen extends StatefulWidget {
  final bool isAssisted;

  const BusinessOnboardingScreen({super.key, this.isAssisted = false});

  @override
  State<BusinessOnboardingScreen> createState() =>
      _BusinessOnboardingScreenState();
}

class _BusinessOnboardingScreenState extends State<BusinessOnboardingScreen> {
  // =====================================================
  // CONTROLLERS
  // =====================================================

  final businessNameController = TextEditingController();

  final claimEmailController = TextEditingController();

  final addressController = TextEditingController();
  final addressService = AddressSearchService();

  List<AddressResult> addressSuggestions = [];
  bool isSearchingAddress = false;
  int addressSearchRequest = 0;
  double? selectedLatitude;
  double? selectedLongitude;

  @override
  void dispose() {
    businessNameController.dispose();
    claimEmailController.dispose();
    addressController.dispose();
    super.dispose();
  }

  // =====================================================
  // FORM STATE
  // =====================================================

  String? selectedCategory;

  final categories = [
    'Cleaner',
    'Dog Walker',
    'Hair Salon',
    'Barber',
    'Dog Groomer',
    'Gardener',
    'Nails',
    'Personal Trainer',
    'Mobile Valeting',
    'Massage',
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
    return businessNameController.text.trim().isNotEmpty &&
        addressController.text.trim().isNotEmpty &&
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

  Future<void> searchAddresses(String value) async {
    selectedLatitude = null;
    selectedLongitude = null;

    final query = value.trim();
    final request = ++addressSearchRequest;

    if (query.length < 3) {
      setState(() {
        addressSuggestions = [];
        isSearchingAddress = false;
      });
      return;
    }

    setState(() => isSearchingAddress = true);

    final results = await addressService.search(query);

    if (!mounted || request != addressSearchRequest) return;

    setState(() {
      addressSuggestions = results;
      isSearchingAddress = false;
    });
  }

  Future<void> selectAddress(AddressResult suggestion) async {
    final request = ++addressSearchRequest;

    setState(() {
      addressController.text = suggestion.description;
      addressSuggestions = [];
      isSearchingAddress = true;
    });

    final coords = await addressService.getCoordinates(suggestion.placeId);

    if (!mounted || request != addressSearchRequest) return;

    setState(() {
      selectedLatitude = coords?['lat'];
      selectedLongitude = coords?['lng'];
      isSearchingAddress = false;
    });
  }

  String generateClaimCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

    return List.generate(
      6,
      (index) =>
          chars[(chars.length * (index + DateTime.now().millisecond)) %
              chars.length],
    ).join();
  }

  // =====================================================
  // CREATE BUSINESS
  // =====================================================

  Future<void> createBusiness() async {
    if (!formIsValid) return;

    if (selectedPaymentMethods.isEmpty) {
      setState(() {
        bannerMessage = 'Choose at least one way customers can pay.';
      });
      return;
    }

    final user = FirebaseAuth.instance.currentUser;

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
      final userRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid);
      final userSnapshot = await userRef.get();

      final batch = FirebaseFirestore.instance.batch();
      final docRef = FirebaseFirestore.instance.collection('businesses').doc();

      final claimCode = generateClaimCode();

      final data = {
        'businessName': businessNameController.text.trim(),

        'address': addressController.text.trim(),

        'latitude': selectedLatitude,

        'longitude': selectedLongitude,

        'category': selectedCategory,

        'createdBy': user.uid,

        'ownerId': widget.isAssisted ? '' : user.uid,

        'claimEmail': widget.isAssisted
            ? claimEmailController.text.trim()
            : null,

        'isClaimed': !widget.isAssisted,

        'claimCode': claimCode,

        'isActive': true,

        'acceptingLeads': true,

        'createdAt': FieldValue.serverTimestamp(),

        'paymentMethods': selectedPaymentMethods,
        'stripeRequested': acceptsStripe,

        'stripeConnected': false,

        'stripeChargesEnabled': false,

        'serviceMode': serviceMode,

        'serviceRadiusMiles': serviceRadiusMiles,

        'schedulingMode': 'simple',
      };

      assert(() {
        debugPrint('CREATE BUSINESS path=${docRef.path}');
        return true;
      }());

      if (!userSnapshot.exists) {
        batch.set(userRef, {
          'name': user.displayName ?? '',
          'userName': user.displayName ?? '',
          'photoUrl': user.photoURL ?? '',
          'bio': '',
          'reviewCount': 0,
          'ratingTotal': 0,
          'averageRating': 0.0,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      batch.set(docRef, data);

      final staffRef = docRef.collection('staff').doc(user.uid);
      final staffData = {
        'name': 'Owner',

        'email': user.email,

        'isActive': true,

        'seatRank': 0,

        'createdAt': FieldValue.serverTimestamp(),
      };

      assert(() {
        debugPrint('CREATE OWNER STAFF path=${staffRef.path}');
        return true;
      }());

      batch.set(staffRef, staffData);
      await batch.commit();

      assert(() {
        debugPrint('CREATE BUSINESS write succeeded path=${docRef.path}');
        debugPrint('CREATE OWNER STAFF write succeeded path=${staffRef.path}');
        return true;
      }());

      if (!mounted) return;

      if (acceptsStripe && !widget.isAssisted) {
        await _startStripeOnboarding(docRef.id);
        if (!mounted) return;
      }

      Navigator.pushReplacement(
        context,

        MaterialPageRoute(
          builder: (_) => BusinessHomeScreen(businessId: docRef.id),
        ),
      );
    } on FirebaseException catch (error) {
      assert(() {
        debugPrint('CREATE BUSINESS FirebaseException code=${error.code}');
        debugPrint('CREATE BUSINESS FirebaseException plugin=${error.plugin}');
        return true;
      }());

      if (!mounted) return;

      setState(() {
        bannerMessage =
            'We could not create your business profile. Please try again.';
      });
    } catch (error) {
      assert(() {
        debugPrint('CREATE BUSINESS error=$error');
        return true;
      }());

      if (!mounted) return;

      setState(() {
        bannerMessage =
            'We could not create your business profile. Please try again.';
      });
    } finally {
      setState(() {
        isSaving = false;
      });
    }
  }

  Future<void> _startStripeOnboarding(String businessId) async {
    try {
      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      await functions.httpsCallable('createConnectedAccount').call({
        'businessId': businessId,
      });
      final linkResult = await functions
          .httpsCallable('createAccountLink')
          .call({'businessId': businessId});
      final linkData = Map<String, dynamic>.from(linkResult.data as Map);
      final url = linkData['url']?.toString();

      if (url == null || url.isEmpty) {
        throw Exception('Stripe onboarding link was empty.');
      }

      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );

      if (!opened) {
        throw Exception('Stripe onboarding link could not be opened.');
      }
    } catch (error) {
      assert(() {
        debugPrint('Stripe onboarding start failed: $error');
        return true;
      }());

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Business saved. You can finish card payment setup from Page details.',
          ),
        ),
      );
    }
  }

  // =====================================================
  // UI
  // =====================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              // =====================================
              // HEADER
              // =====================================
              Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                    },

                    child: Container(
                      padding: const EdgeInsets.all(12),

                      decoration: BoxDecoration(
                        color: Colors.white,

                        borderRadius: BorderRadius.circular(16),

                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),

                            blurRadius: 10,

                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),

                      child: const Icon(Icons.arrow_back),
                    ),
                  ),

                  const SizedBox(width: 14),

                  const Expanded(
                    child: Text(
                      'LocalLink',

                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        color: AppColors.charcoal,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // =====================================
              // HERO CARD
              // =====================================
              Container(
                width: double.infinity,

                padding: const EdgeInsets.all(24),

                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, Color(0xFFFF7A3D)],
                  ),

                  borderRadius: BorderRadius.circular(30),

                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.25),

                      blurRadius: 22,

                      offset: const Offset(0, 12),
                    ),
                  ],
                ),

                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    const Text(
                      'LOCAL LINK',

                      style: TextStyle(
                        color: Colors.white70,
                        letterSpacing: 3,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),

                    const SizedBox(height: 12),

                    Text(
                      widget.isAssisted
                          ? 'Add a business'
                          : 'Launch your business nearby',

                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                      ),
                    ),

                    const SizedBox(height: 10),

                    const Text(
                      'Start taking bookings, appear in nearby searches, and grow your customer base.',

                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 30),

              // =====================================
              // BUSINESS DETAILS
              // =====================================
              const _SectionTitle('Business Details'),

              const SizedBox(height: 16),

              _ModernField(
                controller: businessNameController,
                hint: 'Business Name',
                icon: Icons.storefront_outlined,
              ),

              const SizedBox(height: 16),

              if (widget.isAssisted)
                Column(
                  children: [
                    _ModernField(
                      controller: claimEmailController,
                      hint: 'Owner Email',
                      icon: Icons.email_outlined,
                    ),

                    const SizedBox(height: 16),
                  ],
                ),

              Column(
                children: [
                  _ModernField(
                    controller: addressController,
                    hint: 'Business Address',
                    icon: Icons.location_on_outlined,
                    onChanged: searchAddresses,
                    isLoading: isSearchingAddress,
                  ),

                  if (addressSuggestions.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.grey.shade200),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 14,
                            offset: const Offset(0, 7),
                          ),
                        ],
                      ),
                      child: Column(
                        children: addressSuggestions.map((suggestion) {
                          return ListTile(
                            leading: const Icon(
                              Icons.place_outlined,
                              color: AppColors.primary,
                            ),
                            title: Text(
                              suggestion.description,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            onTap: () => selectAddress(suggestion),
                          );
                        }).toList(),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 28),

              // =====================================
              // CATEGORY
              // =====================================
              const _SectionTitle('Choose Category'),

              const SizedBox(height: 14),

              Wrap(
                spacing: 10,
                runSpacing: 10,

                children: categories.map((category) {
                  final selected = selectedCategory == category;

                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        selectedCategory = category;
                      });
                    },

                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),

                      decoration: BoxDecoration(
                        color: selected ? AppColors.primary : Colors.white,

                        borderRadius: BorderRadius.circular(999),

                        border: Border.all(
                          color: selected
                              ? AppColors.primary
                              : Colors.grey.shade200,
                        ),
                      ),

                      child: Text(
                        category,

                        style: TextStyle(
                          fontWeight: FontWeight.w700,

                          color: selected ? Colors.white : AppColors.charcoal,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 34),

              // =====================================
              // SERVICE MODE
              // =====================================
              const _SectionTitle('How customers book you'),

              const SizedBox(height: 16),

              Container(
                padding: const EdgeInsets.all(18),

                decoration: BoxDecoration(
                  color: Colors.white,

                  borderRadius: BorderRadius.circular(24),

                  border: Border.all(color: Colors.grey.shade200),
                ),

                child: Column(
                  children: [
                    SegmentedButton<String>(
                      style: ButtonStyle(visualDensity: VisualDensity.compact),

                      segments: const [
                        ButtonSegment(
                          value: 'premises',
                          icon: Icon(Icons.store),
                          label: Text('Shop'),
                        ),

                        ButtonSegment(
                          value: 'mobile',
                          icon: Icon(Icons.near_me),
                          label: Text('Mobile'),
                        ),

                        ButtonSegment(
                          value: 'hybrid',
                          icon: Icon(Icons.sync),
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

                    const SizedBox(height: 16),

                    Text(
                      serviceMode == 'premises'
                          ? 'Customers visit your business.'
                          : serviceMode == 'mobile'
                          ? 'You travel directly to customers.'
                          : 'Customers can visit you or book mobile services.',

                      textAlign: TextAlign.center,

                      style: TextStyle(
                        color: Colors.grey.shade700,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),

              // =====================================
              // RADIUS
              // =====================================
              if (serviceMode == 'mobile' || serviceMode == 'hybrid')
                Column(
                  children: [
                    const SizedBox(height: 28),

                    Container(
                      padding: const EdgeInsets.all(20),

                      decoration: BoxDecoration(
                        color: Colors.white,

                        borderRadius: BorderRadius.circular(24),

                        border: Border.all(color: Colors.grey.shade200),
                      ),

                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,

                        children: [
                          Row(
                            children: [
                              const Text(
                                'Travel Radius',

                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18,
                                ),
                              ),

                              const Spacer(),

                              Text(
                                '${serviceRadiusMiles.toInt()} miles',

                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 10),

                          Text(
                            'You’ll appear to customers within your selected service area.',

                            style: TextStyle(color: Colors.grey.shade700),
                          ),

                          Slider(
                            value: serviceRadiusMiles,

                            min: 1,
                            max: 50,

                            divisions: 49,

                            activeColor: AppColors.primary,

                            label: '${serviceRadiusMiles.toInt()}',

                            onChanged: (value) {
                              setState(() {
                                serviceRadiusMiles = value;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

              const SizedBox(height: 32),

              // =====================================
              // PAYMENTS
              // =====================================
              const _SectionTitle('How would you like customers to pay?'),

              const SizedBox(height: 14),

              _PaymentCard(
                title: 'Cash Payments',

                subtitle: 'Accept cash in person',

                icon: Icons.payments_outlined,

                selected: acceptsCash,

                onTap: () {
                  setState(() {
                    acceptsCash = !acceptsCash;
                  });
                },
              ),

              const SizedBox(height: 12),

              _PaymentCard(
                title: 'Card Payments',

                subtitle: 'Take secure Stripe payments after setup',

                icon: Icons.credit_card_outlined,

                selected: acceptsStripe,

                onTap: () {
                  setState(() {
                    acceptsStripe = !acceptsStripe;
                  });
                },
              ),

              const SizedBox(height: 30),

              // =====================================
              // SUMMARY
              // =====================================
              Container(
                width: double.infinity,

                padding: const EdgeInsets.all(20),

                decoration: BoxDecoration(
                  color: Colors.white,

                  borderRadius: BorderRadius.circular(24),

                  border: Border.all(color: Colors.grey.shade200),
                ),

                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    const Text(
                      'Business Summary',

                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: AppColors.charcoal,
                      ),
                    ),

                    const SizedBox(height: 14),

                    _SummaryRow('Category', selectedCategory ?? 'Not selected'),

                    _SummaryRow(
                      'Business Type',

                      serviceMode == 'premises'
                          ? 'SHOP'
                          : serviceMode == 'mobile'
                          ? 'MOBILE'
                          : 'BOTH',
                    ),

                    if (serviceMode == 'mobile' || serviceMode == 'hybrid')
                      _SummaryRow(
                        'Travel Radius',
                        '${serviceRadiusMiles.toInt()} miles',
                      ),

                    _SummaryRow(
                      'Payments',
                      selectedPaymentMethods.join(', ').toUpperCase(),
                    ),
                  ],
                ),
              ),

              // =====================================
              // ERROR
              // =====================================
              if (bannerMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 20),

                  child: Container(
                    padding: const EdgeInsets.all(16),

                    decoration: BoxDecoration(
                      color: AppColors.error,

                      borderRadius: BorderRadius.circular(18),
                    ),

                    child: Text(
                      bannerMessage!,

                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),

              const SizedBox(height: 34),

              // =====================================
              // CTA
              // =====================================
              SizedBox(
                width: double.infinity,

                child: ElevatedButton(
                  onPressed: isSaving ? null : createBusiness,

                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,

                    foregroundColor: Colors.white,

                    elevation: 0,

                    padding: const EdgeInsets.symmetric(vertical: 20),

                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                  ),

                  child: isSaving
                      ? const SizedBox(
                          width: 24,
                          height: 24,

                          child: CircularProgressIndicator(color: Colors.white),
                        )
                      : Text(
                          widget.isAssisted
                              ? 'Add Business'
                              : 'Create My Business',

                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =====================================================
// MODERN FIELD
// =====================================================

class _ModernField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final ValueChanged<String>? onChanged;
  final bool isLoading;

  const _ModernField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.onChanged,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(22),

        border: Border.all(color: Colors.grey.shade200),

        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),

            blurRadius: 14,

            offset: const Offset(0, 7),
          ),
        ],
      ),

      child: TextField(
        controller: controller,
        onChanged: onChanged,

        decoration: InputDecoration(
          hintText: hint,

          prefixIcon: Icon(icon),

          suffixIcon: isLoading
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : null,

          border: InputBorder.none,

          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 20,
          ),
        ),
      ),
    );
  }
}

// =====================================================
// SECTION TITLE
// =====================================================

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title,

      style: const TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w900,
        color: AppColors.charcoal,
      ),
    );
  }
}

// =====================================================
// PAYMENT CARD
// =====================================================

class _PaymentCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _PaymentCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,

      child: Container(
        padding: const EdgeInsets.all(18),

        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.08)
              : Colors.white,

          borderRadius: BorderRadius.circular(22),

          border: Border.all(
            color: selected ? AppColors.primary : Colors.grey.shade200,
          ),
        ),

        child: Row(
          children: [
            Icon(icon, color: selected ? AppColors.primary : Colors.black54),

            const SizedBox(width: 16),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,

                children: [
                  Text(
                    title,

                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),

                  const SizedBox(height: 4),

                  Text(subtitle, style: TextStyle(color: Colors.grey.shade600)),
                ],
              ),
            ),

            Icon(
              selected ? Icons.check_circle : Icons.circle_outlined,

              color: selected ? AppColors.primary : Colors.grey,
            ),
          ],
        ),
      ),
    );
  }
}

// =====================================================
// SUMMARY ROW
// =====================================================

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),

      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(color: Colors.grey.shade700)),
          ),

          Text(
            value,

            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: AppColors.charcoal,
            ),
          ),
        ],
      ),
    );
  }
}
