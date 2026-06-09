import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

import '../theme/app_colors.dart';
import 'package:geolocator/geolocator.dart';

class CreateOpportunityScreen extends StatefulWidget {
  const CreateOpportunityScreen({super.key});

  @override
  State<CreateOpportunityScreen> createState() =>
      _CreateOpportunityScreenState();
}

class _CreateOpportunityScreenState
    extends State<CreateOpportunityScreen> {

  final titleController =
      TextEditingController();

  final descriptionController =
      TextEditingController();

  final locationController =
      TextEditingController();

  final ImagePicker picker =
      ImagePicker();

  File? selectedImage;

  String category = 'Social';

  bool saving = false;

  DateTime? selectedDate;
TimeOfDay? selectedTime;
double? selectedLatitude;
double? selectedLongitude;

Future<void> pickDate() async {
  final picked = await showDatePicker(
    context: context,
    initialDate: DateTime.now(),
    firstDate: DateTime.now(),
    lastDate: DateTime(2035),
  );

  if (picked == null) return;

  setState(() {
    selectedDate = picked;
  });
}

Future<void> pickTime() async {
  final picked = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.now(),
  );

  if (picked == null) return;

  setState(() {
    selectedTime = picked;
  });
}

  @override
  void dispose() {
    titleController.dispose();
    descriptionController.dispose();
    locationController.dispose();
    super.dispose();
  }

  Future<void> pickImage() async {

    final picked =
        await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 75,
    );

    if (picked == null) return;

    setState(() {
      selectedImage =
          File(picked.path);
    });
  }

  Future<void> saveOpportunity() async {

    if (titleController.text
    .trim()
    .isEmpty) {
  return;
}

if (locationController.text
    .trim()
    .isEmpty) {

  ScaffoldMessenger.of(context)
      .showSnackBar(
    const SnackBar(
      content: Text(
        'Please select a location',
      ),
    ),
  );

  return;
}

    setState(() {
      saving = true;
    });

    try {

      final user =
          FirebaseAuth.instance.currentUser;

        final latitude =
    selectedLatitude;

final longitude =
    selectedLongitude;

      String? photoUrl;

      if (selectedImage != null) {

        final fileName =
            '${DateTime.now().millisecondsSinceEpoch}.jpg';

        final ref =
            FirebaseStorage.instance
                .ref()
                .child(
                  'opportunityPhotos/$fileName',
                );

        await ref.putFile(
          selectedImage!,
          SettableMetadata(
            contentType:
                'image/jpeg',
            customMetadata: {
              'ownerId':
                  user?.uid ?? '',
            },
          ),
        );

        photoUrl =
            await ref.getDownloadURL();
      }

    await FirebaseFirestore.instance
    .collection('opportunities')
    .add({

  'title':
      titleController.text.trim(),

  'description':
      descriptionController.text.trim(),

  'location':
      locationController.text.trim(),

  'category':
      category,

  'attendeeCount': 0,

  'organiserName':
      user?.email ?? 'LocalLink',

  'createdBy':
      user?.uid,

  'photoUrl':
      photoUrl,

  'latitude':
      latitude,

  'longitude':
      longitude,

      'eventDate':
    selectedDate,

'eventTime':
    selectedTime == null
        ? null
        : selectedTime!.format(
            context,
          ),
          

  'isActive': true,

  'createdAt':
      Timestamp.now(),
});

      if (!mounted) return;

      Navigator.pop(context);

    } catch (e) {

      if (!mounted) return;

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
          saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Create Opportunity',
        ),
      ),
      body: SingleChildScrollView(
        padding:
            const EdgeInsets.all(20),
        child: Column(
          children: [

            TextField(
              controller:
                  titleController,
              decoration:
                  const InputDecoration(
                labelText: 'Title',
              ),
            ),

            const SizedBox(height: 16),

            TextField(
              controller:
                  descriptionController,
              maxLines: 4,
              decoration:
                  const InputDecoration(
                labelText:
                    'Description',
              ),
            ),

            const SizedBox(height: 16),

            TextField(
              controller:
                  locationController,
              decoration:
                  const InputDecoration(
                labelText:
                    'Where Is it?',
              ),
            ),

            const SizedBox(height: 16),

            GestureDetector(
  onTap: pickDate,
  child: Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      border: Border.all(
        color: Colors.grey.shade400,
      ),
      borderRadius:
          BorderRadius.circular(8),
    ),
    child: Text(
      selectedDate == null
          ? 'Select Date'
          : '${selectedDate!.day}/${selectedDate!.month}/${selectedDate!.year}',
    ),
  ),
),

const SizedBox(height: 16),

GestureDetector(
  onTap: pickTime,
  child: Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      border: Border.all(
        color: Colors.grey.shade400,
      ),
      borderRadius:
          BorderRadius.circular(8),
    ),
    child: Text(
      selectedTime == null
          ? 'Select Time'
          : selectedTime!.format(context),
    ),
  ),
),

const SizedBox(height: 16),

            DropdownButtonFormField<String>(
              value: category,
              items: const [

             DropdownMenuItem(
  value: 'Fitness & Sport',
  child: Text('Fitness & Sport'),
),
DropdownMenuItem(
  value: 'Family',
  child: Text('Family'),
),
DropdownMenuItem(
  value: 'Pets',
  child: Text('Pets'),
),
DropdownMenuItem(
  value: 'Hobbies',
  child: Text('Hobbies'),
),
DropdownMenuItem(
  value: 'Social',
  child: Text('Social'),
),
DropdownMenuItem(
  value: 'Volunteering',
  child: Text('Volunteering'),
),
DropdownMenuItem(
  value: 'Learning',
  child: Text('Learning'),
),
DropdownMenuItem(
  value: 'Local Deals',
  child: Text('Local Deals'),
),
              ],
              onChanged: (value) {

                if (value == null) {
                  return;
                }

                setState(() {
                  category = value;
                });
              },
            ),

            const SizedBox(height: 20),

            GestureDetector(
              onTap: pickImage,
              child: Container(
                height: 180,
                width: double.infinity,
                decoration:
                    BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius
                          .circular(
                    20,
                  ),
                  border: Border.all(
                    color: Colors.grey
                        .shade300,
                  ),
                ),
                child:
                    selectedImage == null

                        ? const Column(
                            mainAxisAlignment:
                                MainAxisAlignment.center,
                            children: [

                              Icon(
                                Icons
                                    .image_outlined,
                                size: 50,
                              ),

                              SizedBox(
                                height: 10,
                              ),

                              Text(
                                'Add Photo (Optional)',
                              ),
                            ],
                          )

                        : ClipRRect(
                            borderRadius:
                                BorderRadius.circular(
                              20,
                            ),
                            child:
                                Image.file(
                              selectedImage!,
                              fit: BoxFit.cover,
                            ),
                          ),
              ),
            ),

            const SizedBox(height: 30),

            SizedBox(
              width: double.infinity,
              child:
                  ElevatedButton(
                onPressed:
                    saving
                        ? null
                        : saveOpportunity,
                style:
                    ElevatedButton.styleFrom(
                  backgroundColor:
                      AppColors.primary,
                  foregroundColor:
                      Colors.white,
                ),
                child: Text(
                  saving
                      ? 'Saving...'
                      : 'Create Opportunity',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}