import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../theme/app_colors.dart';
import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';

class BusinessProfileScreen extends StatefulWidget {
  final String businessId;

  const BusinessProfileScreen({super.key, required this.businessId});

  @override
  State<BusinessProfileScreen> createState() => _BusinessProfileScreenState();
}

class _BusinessProfileScreenState extends State<BusinessProfileScreen> {
  bool isUploadingPhoto = false;

  List<String> photoURLs = [];

  final ImagePicker picker = ImagePicker();
  // =====================================================
  // CONTROLLERS
  // =====================================================

  final businessNameController = TextEditingController();

  final addressController = TextEditingController();

  @override
  void dispose() {
    businessNameController.dispose();
    addressController.dispose();
    super.dispose();
  }

  // =====================================================
  // STATE
  // =====================================================

  bool isLoading = true;
  bool isSaving = false;

  String? selectedCategory;

  String serviceMode = 'premises';

  double serviceRadiusMiles = 10;

  bool acceptsCash = true;
  bool acceptsStripe = false;
  bool acceptingLeads = true;
  bool stripeReady = false;
  bool stripeSetupInProgress = false;

  final categories = [
    'Aesthetics',
    'Beauty',
    'Brows & Lashes',
    'Hair Salon',
    'Barber',
    'Nails',
    'Massage',
    'Skin Clinic',

    'Cleaner',
    'Dog Groomer',
    'Dog Walker',
    'Gardener',
    'Handyman',
    'Mobile Valeting',
    'Pressure Washing',

    'Specialist Services',
  ];

  // =====================================================
  // INIT
  // =====================================================

  @override
  void initState() {
    super.initState();

    loadBusiness();
  }

  // =====================================================
  // LOAD
  // =====================================================

  Future<void> loadBusiness() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('businesses')
          .doc(widget.businessId)
          .get();

      final data = doc.data() ?? {};

      businessNameController.text = data['businessName'] ?? '';

      addressController.text = data['address'] ?? '';

      selectedCategory = data['category'];

      serviceMode = data['serviceMode'] ?? 'premises';

      serviceRadiusMiles = ((data['serviceRadiusMiles'] ?? 10) as num)
          .toDouble();

      final methods = List<String>.from(data['paymentMethods'] ?? []);
      final legacyMethod = data['paymentMethod']?.toString();
      if (methods.isEmpty && legacyMethod != null && legacyMethod.isNotEmpty) {
        methods.add(legacyMethod);
      }
      stripeReady =
          data['stripeConnected'] == true &&
          data['stripeChargesEnabled'] == true;

      acceptsCash = methods.contains('cash');

      acceptsStripe =
          methods.contains('stripe') || data['stripeRequested'] == true;

      acceptingLeads = data['acceptingLeads'] != false;

      photoURLs = List<String>.from(data['photoURLs'] ?? []);
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  // =====================================================
  // SAVE
  // =====================================================

  Future<void> saveProfile() async {
    setState(() {
      isSaving = true;
    });

    final paymentMethods = <String>[];

    if (acceptsCash) {
      paymentMethods.add('cash');
    }

    if (acceptsStripe) {
      paymentMethods.add('stripe');
    }

    if (paymentMethods.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose at least one payment method.')),
      );

      setState(() {
        isSaving = false;
      });

      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('businesses')
          .doc(widget.businessId)
          .update({
            'businessName': businessNameController.text.trim(),

            'address': addressController.text.trim(),

            'category': selectedCategory,

            'serviceMode': serviceMode,

            'serviceRadiusMiles': serviceRadiusMiles,

            'paymentMethods': paymentMethods,

            'stripeRequested': acceptsStripe,

            'acceptingLeads': acceptingLeads,
          });

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Page updated.')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'We could not save your Page details just now. Please try again.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
    }
  }

  Future<void> pickAndUploadPhoto() async {
    try {
      if (photoURLs.length >= 5) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You can add up to 5 photos.')),
        );

        return;
      }

      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 75,
      );

      if (!mounted) return;

      if (picked == null) return;

      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please sign in to upload Page photos.'),
          ),
        );
        return;
      }

      setState(() {
        isUploadingPhoto = true;
      });

      final file = File(picked.path);

      final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';

      final ref = FirebaseStorage.instance.ref().child(
        'businessPhotos/${widget.businessId}/$fileName',
      );

      await ref.putFile(
        file,

        SettableMetadata(
          contentType: 'image/jpeg',

          customMetadata: {'ownerId': user.uid},
        ),
      );

      final url = await ref.getDownloadURL();

      if (!mounted) return;

      photoURLs.add(url);

      await FirebaseFirestore.instance
          .collection('businesses')
          .doc(widget.businessId)
          .update({'photoURLs': photoURLs});

      if (!mounted) return;

      setState(() {});
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('We could not upload that photo. Please try again.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          isUploadingPhoto = false;
        });
      }
    }
  }

  Future<void> deletePhoto(int index) async {
    try {
      photoURLs.removeAt(index);

      await FirebaseFirestore.instance
          .collection('businesses')
          .doc(widget.businessId)
          .update({'photoURLs': photoURLs});

      if (!mounted) return;

      setState(() {});
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('We could not remove that photo. Please try again.'),
        ),
      );
    }
  }

  Future<void> startStripeOnboarding() async {
    setState(() {
      stripeSetupInProgress = true;
    });

    try {
      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      await functions.httpsCallable('createConnectedAccount').call({
        'businessId': widget.businessId,
      });
      final linkResult = await functions
          .httpsCallable('createAccountLink')
          .call({'businessId': widget.businessId});
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
        debugPrint('Stripe onboarding failed: $error');
        return true;
      }());

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('We could not start card payment setup just now.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          stripeSetupInProgress = false;
        });
      }
    }
  }
  // =====================================================
  // UI
  // =====================================================

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: AppColors.background,

      appBar: AppBar(
        backgroundColor: AppColors.background,

        elevation: 0,

        foregroundColor: AppColors.charcoal,

        title: const Text('Page details'),
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,

          children: [
            // =================================================
            // HEADER
            // =================================================
            Container(
              width: double.infinity,

              padding: const EdgeInsets.all(24),

              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, Color(0xFFE65100)],
                ),

                borderRadius: BorderRadius.circular(28),
              ),

              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,

                children: [
                  Text(
                    'Page details',

                    style: TextStyle(
                      color: Colors.white,

                      fontSize: 30,

                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  SizedBox(height: 10),

                  Text(
                    'Update how your Page appears locally.',

                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),

            // =================================================
            // BUSINESS NAME
            // =================================================
            _SectionTitle(title: 'Page name'),

            const SizedBox(height: 10),

            TextField(
              controller: businessNameController,

              decoration: _inputDecoration('Page name'),
            ),

            const SizedBox(height: 24),

            _SectionTitle(title: 'Page photos'),

            const SizedBox(height: 14),

            SizedBox(
              height: 120,

              child: ListView.separated(
                scrollDirection: Axis.horizontal,

                itemCount: photoURLs.length + 1,

                separatorBuilder: (context, index) => const SizedBox(width: 12),

                itemBuilder: (context, index) {
                  // ADD PHOTO BUTTON

                  if (index == photoURLs.length) {
                    return GestureDetector(
                      onTap: isUploadingPhoto ? null : pickAndUploadPhoto,

                      child: Container(
                        width: 120,

                        decoration: BoxDecoration(
                          color: Colors.white,

                          borderRadius: BorderRadius.circular(22),

                          border: Border.all(color: Colors.grey.shade300),
                        ),

                        child: Center(
                          child: isUploadingPhoto
                              ? const CircularProgressIndicator()
                              : Column(
                                  mainAxisAlignment: MainAxisAlignment.center,

                                  children: const [
                                    Icon(
                                      Icons.add_a_photo,
                                      size: 32,
                                      color: AppColors.primary,
                                    ),

                                    SizedBox(height: 8),

                                    Text('Add Photo'),
                                  ],
                                ),
                        ),
                      ),
                    );
                  }

                  // PHOTO TILE

                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(22),

                        child: Image.network(
                          photoURLs[index],

                          width: 120,
                          height: 120,

                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return Container(
                              width: 120,
                              height: 120,
                              color: AppColors.serviceGreen.withValues(
                                alpha: 0.08,
                              ),
                              child: const Center(
                                child: CircularProgressIndicator(),
                              ),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              width: 120,
                              height: 120,
                              color: AppColors.serviceGreen.withValues(
                                alpha: 0.10,
                              ),
                              child: const Icon(
                                Icons.image_not_supported_outlined,
                                color: AppColors.serviceGreen,
                              ),
                            );
                          },
                        ),
                      ),

                      Positioned(
                        top: 6,
                        right: 6,

                        child: GestureDetector(
                          onTap: () {
                            deletePhoto(index);
                          },

                          child: Container(
                            padding: const EdgeInsets.all(6),

                            decoration: const BoxDecoration(
                              color: Colors.black54,

                              shape: BoxShape.circle,
                            ),

                            child: const Icon(
                              Icons.close,

                              color: Colors.white,

                              size: 18,
                            ),
                          ),
                        ),
                      ),

                      if (index == 0)
                        Positioned(
                          left: 8,
                          bottom: 8,

                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),

                            decoration: BoxDecoration(
                              color: Colors.black54,

                              borderRadius: BorderRadius.circular(12),
                            ),

                            child: const Text(
                              'Cover',

                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),

            // =================================================
            // ADDRESS
            // =================================================
            _SectionTitle(title: 'Address'),

            const SizedBox(height: 10),

            TextField(
              controller: addressController,

              decoration: _inputDecoration('Page address'),
            ),

            const SizedBox(height: 24),

            // =================================================
            // CATEGORY
            // =================================================
            _SectionTitle(title: 'Category'),

            const SizedBox(height: 10),

            DropdownButtonFormField<String>(
              initialValue: selectedCategory,

              decoration: _inputDecoration('Select category'),

              items: categories.map((category) {
                return DropdownMenuItem(value: category, child: Text(category));
              }).toList(),

              onChanged: (value) {
                setState(() {
                  selectedCategory = value;
                });
              },
            ),

            const SizedBox(height: 24),

            // =================================================
            // SERVICE MODE
            // =================================================
            _SectionTitle(title: 'How you work'),

            const SizedBox(height: 12),

            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'premises', label: Text('Premises')),

                ButtonSegment(value: 'mobile', label: Text('Mobile')),

                ButtonSegment(value: 'hybrid', label: Text('Both')),
              ],

              selected: {serviceMode},

              onSelectionChanged: (selection) {
                setState(() {
                  serviceMode = selection.first;
                });
              },
            ),

            // =================================================
            // RADIUS
            // =================================================
            if (serviceMode == 'mobile' || serviceMode == 'hybrid') ...[
              const SizedBox(height: 24),

              Row(
                children: [
                  const Text('Travel Radius'),

                  const Spacer(),

                  Text('${serviceRadiusMiles.toInt()} miles'),
                ],
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

            const SizedBox(height: 30),

            // =================================================
            // PAYMENTS
            // =================================================
            _SectionTitle(title: 'Payment Methods'),

            CheckboxListTile(
              value: acceptsCash,

              activeColor: AppColors.primary,

              title: const Text('Accept Cash'),

              onChanged: (value) {
                setState(() {
                  acceptsCash = value ?? false;
                });
              },
            ),

            CheckboxListTile(
              value: acceptsStripe,

              activeColor: AppColors.primary,

              title: const Text('Accept Card Payments'),
              subtitle: stripeReady
                  ? null
                  : const Text('Complete Stripe onboarding to enable cards.'),

              onChanged: stripeReady
                  ? (value) {
                      setState(() {
                        acceptsStripe = value ?? false;
                      });
                    }
                  : (value) {
                      setState(() {
                        acceptsStripe = value ?? false;
                      });
                    },
            ),

            CheckboxListTile(
              value: acceptingLeads,
              activeColor: AppColors.primary,
              title: const Text('Accept customer requests'),
              subtitle: const Text(
                'Let nearby customers ask for quotes from your active services.',
              ),
              onChanged: (value) {
                setState(() {
                  acceptingLeads = value ?? true;
                });
              },
            ),

            if (!stripeReady) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: stripeSetupInProgress
                      ? null
                      : startStripeOnboarding,
                  icon: const Icon(Icons.credit_card_outlined),
                  label: Text(
                    stripeSetupInProgress
                        ? 'Opening Stripe...'
                        : 'Set up card payments',
                  ),
                ),
              ),
            ],

            const SizedBox(height: 40),

            // =================================================
            // SAVE BUTTON
            // =================================================
            SizedBox(
              width: double.infinity,

              child: ElevatedButton(
                onPressed: isSaving ? null : saveProfile,

                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,

                  foregroundColor: Colors.white,

                  padding: const EdgeInsets.symmetric(vertical: 18),

                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),

                child: isSaving
                    ? const SizedBox(
                        height: 22,
                        width: 22,

                        child: CircularProgressIndicator(color: Colors.white),
                      )
                    : const Text(
                        'Save Changes',

                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // =====================================================
  // INPUT DECORATION
  // =====================================================

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,

      filled: true,

      fillColor: Colors.white,

      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),

        borderSide: BorderSide.none,
      ),
    );
  }
}

// =====================================================
// SECTION TITLE
// =====================================================

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,

      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: AppColors.charcoal,
      ),
    );
  }
}
