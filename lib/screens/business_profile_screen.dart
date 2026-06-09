import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../theme/app_colors.dart';
import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';

class BusinessProfileScreen
    extends StatefulWidget {

  final String businessId;

  const BusinessProfileScreen({
    super.key,
    required this.businessId,
  });

  @override
  State<BusinessProfileScreen>
      createState() =>
          _BusinessProfileScreenState();
}

class _BusinessProfileScreenState
    extends State<BusinessProfileScreen> {

bool isUploadingPhoto = false;

List<String> photoURLs = [];

final ImagePicker picker =
    ImagePicker();
  // =====================================================
  // CONTROLLERS
  // =====================================================

  final businessNameController =
      TextEditingController();

  final addressController =
      TextEditingController();

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

      final doc =
          await FirebaseFirestore.instance
              .collection('businesses')
              .doc(widget.businessId)
              .get();

      final data = doc.data() ?? {};

      businessNameController.text =
          data['businessName'] ?? '';

      addressController.text =
          data['address'] ?? '';

      selectedCategory =
          data['category'];

      serviceMode =
          data['serviceMode'] ??
              'premises';

      serviceRadiusMiles =
          ((data['serviceRadiusMiles']
                      ?? 10)
                  as num)
              .toDouble();

      final methods =
          List<String>.from(
        data['paymentMethods'] ?? [],
      );

      acceptsCash =
          methods.contains('cash');

      acceptsStripe =
          methods.contains('stripe');

          photoURLs = List<String>.from(
  data['photoURLs'] ?? [],
);

    } catch (e) {

      debugPrint(
        'PROFILE LOAD ERROR: $e',
      );

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

    final paymentMethods =
        <String>[];

    if (acceptsCash) {
      paymentMethods.add('cash');
    }

    if (acceptsStripe) {
      paymentMethods.add('stripe');
    }

    try {

      await FirebaseFirestore.instance
          .collection('businesses')
          .doc(widget.businessId)
          .update({

        'businessName':
            businessNameController.text
                .trim(),

        'address':
            addressController.text
                .trim(),

        'category':
            selectedCategory,

        'serviceMode':
            serviceMode,

        'serviceRadiusMiles':
            serviceRadiusMiles,

        'paymentMethods':
            paymentMethods,
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(

        const SnackBar(
          content: Text(
            'Business updated',
          ),
        ),
      );

    } catch (e) {

      ScaffoldMessenger.of(context)
          .showSnackBar(

        SnackBar(
          content: Text(
            'Failed: $e',
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

      ScaffoldMessenger.of(context)
          .showSnackBar(

        const SnackBar(
          content: Text(
            'Maximum 5 photos allowed',
          ),
        ),
      );

      return;
    }

    final picked =
        await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 75,
    );

    if (picked == null) return;

    setState(() {
      isUploadingPhoto = true;
    });

    final file = File(picked.path);

    final fileName =
        '${DateTime.now().millisecondsSinceEpoch}.jpg';

    final ref = FirebaseStorage.instance
        .ref()
        .child(
          'businessPhotos/${widget.businessId}/$fileName',
        );

    await ref.putFile(

      file,

      SettableMetadata(

        contentType: 'image/jpeg',

       customMetadata: {
  'ownerId':
      FirebaseAuth
          .instance
          .currentUser!
          .uid,
},
      ),
    );

    final url =
        await ref.getDownloadURL();

    photoURLs.add(url);

    await FirebaseFirestore.instance
        .collection('businesses')
        .doc(widget.businessId)
        .update({

      'photoURLs': photoURLs,
    });

    setState(() {});

  } catch (e) {

    ScaffoldMessenger.of(context)
        .showSnackBar(

      SnackBar(
        content: Text(
          'Upload failed: $e',
        ),
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
Future<void> deletePhoto(
  int index,
) async {

  try {

    photoURLs.removeAt(index);

    await FirebaseFirestore.instance
        .collection('businesses')
        .doc(widget.businessId)
        .update({

      'photoURLs': photoURLs,
    });

    setState(() {});

  } catch (e) {

    ScaffoldMessenger.of(context)
        .showSnackBar(

      SnackBar(
        content: Text(
          'Delete failed: $e',
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

    if (isLoading) {

      return const Scaffold(

        body: Center(
          child:
              CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(

      backgroundColor:
          AppColors.background,

      appBar: AppBar(

        backgroundColor:
            AppColors.background,

        elevation: 0,

        foregroundColor:
            AppColors.charcoal,

        title: const Text(
          'Business Profile',
        ),
      ),

      body: SingleChildScrollView(

        padding:
            const EdgeInsets.all(20),

        child: Column(

          crossAxisAlignment:
              CrossAxisAlignment.start,

          children: [

            // =================================================
            // HEADER
            // =================================================

            Container(

              width: double.infinity,

              padding:
                  const EdgeInsets.all(
                24,
              ),

              decoration: BoxDecoration(

                gradient:
                    const LinearGradient(

                  colors: [
                    AppColors.primary,
                    Color(0xFFE65100),
                  ],
                ),

                borderRadius:
                    BorderRadius.circular(
                  28,
                ),
              ),

              child: const Column(

                crossAxisAlignment:
                    CrossAxisAlignment.start,

                children: [

                  Text(

                    'Business Settings',

                    style: TextStyle(

                      color:
                          Colors.white,

                      fontSize: 30,

                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),

                  SizedBox(height: 10),

                  Text(

                    'Manage your LocalLink profile.',

                    style: TextStyle(
                      color:
                          Colors.white70,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),

            // =================================================
            // BUSINESS NAME
            // =================================================

            _SectionTitle(
              title: 'Business Name',
            ),

            const SizedBox(height: 10),

            TextField(

              controller:
                  businessNameController,

              decoration:
                  _inputDecoration(
                'Business name',
              ),
            ),

            const SizedBox(height: 24),


_SectionTitle(
  title: 'Business Photos',
),

const SizedBox(height: 14),

SizedBox(

  height: 120,

  child: ListView.separated(

    scrollDirection: Axis.horizontal,

    itemCount:
        photoURLs.length + 1,

    separatorBuilder:
        (_, __) =>
            const SizedBox(width: 12),

    itemBuilder:
        (context, index) {

      // ADD PHOTO BUTTON

      if (index ==
          photoURLs.length) {

        return GestureDetector(

          onTap:
              isUploadingPhoto
                  ? null
                  : pickAndUploadPhoto,

          child: Container(

            width: 120,

            decoration:
                BoxDecoration(

              color: Colors.white,

              borderRadius:
                  BorderRadius.circular(
                22,
              ),

              border: Border.all(
                color:
                    Colors.grey.shade300,
              ),
            ),

            child: Center(

              child:
                  isUploadingPhoto

                      ? const CircularProgressIndicator()

                      : Column(

                          mainAxisAlignment:
                              MainAxisAlignment.center,

                          children: const [

                            Icon(
                              Icons.add_a_photo,
                              size: 32,
                              color:
                                  AppColors.primary,
                            ),

                            SizedBox(height: 8),

                            Text(
                              'Add Photo',
                            ),
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

            borderRadius:
                BorderRadius.circular(
              22,
            ),

            child: Image.network(

              photoURLs[index],

              width: 120,
              height: 120,

              fit: BoxFit.cover,
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

                padding:
                    const EdgeInsets.all(
                  6,
                ),

                decoration:
                    const BoxDecoration(

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

                padding:
                    const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),

                decoration:
                    BoxDecoration(

                  color:
                      Colors.black54,

                  borderRadius:
                      BorderRadius.circular(
                    12,
                  ),
                ),

                child: const Text(

                  'Cover',

                  style: TextStyle(
                    color:
                        Colors.white,
                    fontSize: 12,
                    fontWeight:
                        FontWeight.bold,
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

            _SectionTitle(
              title: 'Address',
            ),

            const SizedBox(height: 10),

            TextField(

              controller:
                  addressController,

              decoration:
                  _inputDecoration(
                'Business address',
              ),
            ),

            const SizedBox(height: 24),

            // =================================================
            // CATEGORY
            // =================================================

            _SectionTitle(
              title: 'Category',
            ),

            const SizedBox(height: 10),

            DropdownButtonFormField<String>(

              value: selectedCategory,

              decoration:
                  _inputDecoration(
                'Select category',
              ),

              items: categories.map(
                (category) {

                  return DropdownMenuItem(

                    value: category,

                    child: Text(
                      category,
                    ),
                  );
                },
              ).toList(),

              onChanged: (value) {

                setState(() {
                  selectedCategory =
                      value;
                });
              },
            ),

            const SizedBox(height: 24),

            // =================================================
            // SERVICE MODE
            // =================================================

            _SectionTitle(
              title: 'Business Type',
            ),

            const SizedBox(height: 12),

            SegmentedButton<String>(

              segments: const [

                ButtonSegment(
                  value: 'premises',
                  label:
                      Text('Premises'),
                ),

                ButtonSegment(
                  value: 'mobile',
                  label:
                      Text('Mobile'),
                ),

                ButtonSegment(
                  value: 'hybrid',
                  label:
                      Text('Both'),
                ),
              ],

              selected: {
                serviceMode,
              },

              onSelectionChanged:
                  (selection) {

                setState(() {

                  serviceMode =
                      selection.first;
                });
              },
            ),

            // =================================================
            // RADIUS
            // =================================================

            if (serviceMode ==
                    'mobile' ||
                serviceMode ==
                    'hybrid') ...[

              const SizedBox(
                height: 24,
              ),

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

                value:
                    serviceRadiusMiles,

                min: 1,
                max: 50,

                divisions: 49,

                activeColor:
                    AppColors.primary,

                label:
                    '${serviceRadiusMiles.toInt()}',

                onChanged: (value) {

                  setState(() {

                    serviceRadiusMiles =
                        value;
                  });
                },
              ),
            ],

            const SizedBox(height: 30),

            // =================================================
            // PAYMENTS
            // =================================================

            _SectionTitle(
              title: 'Payment Methods',
            ),

            CheckboxListTile(

              value: acceptsCash,

              activeColor:
                  AppColors.primary,

              title:
                  const Text(
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

              activeColor:
                  AppColors.primary,

              title:
                  const Text(
                'Accept Card Payments',
              ),

              onChanged: (value) {

                setState(() {

                  acceptsStripe =
                      value ?? false;
                });
              },
            ),

            const SizedBox(height: 40),

            // =================================================
            // SAVE BUTTON
            // =================================================

            SizedBox(

              width: double.infinity,

              child: ElevatedButton(

                onPressed:
                    isSaving
                        ? null
                        : saveProfile,

                style:
                    ElevatedButton.styleFrom(

                  backgroundColor:
                      AppColors.primary,

                  foregroundColor:
                      Colors.white,

                  padding:
                      const EdgeInsets.symmetric(
                    vertical: 18,
                  ),

                  shape:
                      RoundedRectangleBorder(

                    borderRadius:
                        BorderRadius.circular(
                      18,
                    ),
                  ),
                ),

                child:
                    isSaving

                        ? const SizedBox(

                            height: 22,
                            width: 22,

                            child:
                                CircularProgressIndicator(
                              color:
                                  Colors.white,
                            ),
                          )

                        : const Text(

                            'Save Changes',

                            style: TextStyle(
                              fontSize: 16,
                              fontWeight:
                                  FontWeight.bold,
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

  InputDecoration _inputDecoration(
    String label,
  ) {

    return InputDecoration(

      labelText: label,

      filled: true,

      fillColor: Colors.white,

      border: OutlineInputBorder(

        borderRadius:
            BorderRadius.circular(
          18,
        ),

        borderSide: BorderSide.none,
      ),
    );
  }
}

// =====================================================
// SECTION TITLE
// =====================================================

class _SectionTitle
    extends StatelessWidget {

  final String title;

  const _SectionTitle({
    required this.title,
  });

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