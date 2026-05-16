import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AddServiceScreen extends StatefulWidget {

  final String businessId;

  // NEW
  final String? serviceId;
  final Map<String, dynamic>? existingService;

  const AddServiceScreen({
    super.key,
    required this.businessId,
    this.serviceId,
    this.existingService,
  });

  @override
  State<AddServiceScreen> createState() =>
      _AddServiceScreenState();
}

class _AddServiceScreenState
    extends State<AddServiceScreen> {

  final nameController =
      TextEditingController();

  final priceController =
      TextEditingController();

  final durationController =
      TextEditingController();

  final detailsController =
      TextEditingController();

  bool isSaving = false;

  bool get isEditing =>
      widget.serviceId != null;

  // =====================================
  // INIT
  // =====================================

  @override
  void initState() {
    super.initState();

    final service =
        widget.existingService;

    if (service != null) {

      nameController.text =
          service['name'] ?? '';

      detailsController.text =
          service['details'] ?? '';

      final price =
          ((service['price'] ?? 0)
                  as num)
              .toDouble() /
              100;

      priceController.text =
          price.toStringAsFixed(2);

      durationController.text =
          (service['durationMinutes']
                  ?? 30)
              .toString();
    }
  }

  // =====================================
  // SAVE SERVICE
  // =====================================

  Future<void> saveService() async {

    final name =
        nameController.text.trim();

    final details =
        detailsController.text.trim();

    final pounds =
        double.tryParse(
          priceController.text.trim(),
        );

    final duration =
        int.tryParse(
          durationController.text.trim(),
        );

    if (name.isEmpty ||
        pounds == null ||
        duration == null) {

      ScaffoldMessenger.of(context)
          .showSnackBar(

        const SnackBar(
          content: Text(
            'Complete all fields',
          ),
        ),
      );

      return;
    }

    setState(() {
      isSaving = true;
    });

    try {

      final priceInPence =
          (pounds * 100).round();

      final data = {

        'name': name,

        'details': details,

        'price': priceInPence,

        'durationMinutes': duration,

        'isActive': true,
      };

      final servicesRef =
          FirebaseFirestore.instance
              .collection('businesses')
              .doc(widget.businessId)
              .collection('services');

      // =====================================
      // EDIT
      // =====================================

      if (isEditing) {

        await servicesRef
            .doc(widget.serviceId)
            .update(data);

      }

      // =====================================
      // ADD
      // =====================================

      else {

        await servicesRef.add({

          ...data,

          'createdAt':
              Timestamp.now(),
        });
      }

      if (!mounted) return;

      Navigator.pop(context);

    } catch (e) {

      ScaffoldMessenger.of(context)
          .showSnackBar(

        SnackBar(
          content: Text(
            'Error: $e',
          ),
        ),
      );
    }

    if (mounted) {

      setState(() {
        isSaving = false;
      });
    }
  }

  // =====================================
  // UI
  // =====================================

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      appBar: AppBar(
        title: Text(
          isEditing
              ? 'Edit Service'
              : 'Add Service',
        ),
      ),

      body: Padding(

        padding:
            const EdgeInsets.all(20),

        child: Column(

          children: [

            TextField(

              controller:
                  nameController,

              decoration:
                  const InputDecoration(
                labelText:
                    'Service Name',
              ),
            ),

            const SizedBox(height: 20),

            TextField(

              controller:
                  detailsController,

              decoration:
                  const InputDecoration(
                labelText:
                    'Service Details',
              ),
            ),

            const SizedBox(height: 20),

            TextField(

              controller:
                  priceController,

              keyboardType:
                  TextInputType.number,

              decoration:
                  const InputDecoration(
                labelText:
                    'Price (£)',
              ),
            ),

            const SizedBox(height: 20),

            TextField(

              controller:
                  durationController,

              keyboardType:
                  TextInputType.number,

              decoration:
                  const InputDecoration(
                labelText:
                    'Duration (mins)',
              ),
            ),

            const SizedBox(height: 30),

            SizedBox(

              width: double.infinity,

              child: ElevatedButton(

                onPressed:
                    isSaving
                        ? null
                        : saveService,

                child:
                    isSaving

                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child:
                                CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )

                        : Text(
                            isEditing
                                ? 'Update Service'
                                : 'Save Service',
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}