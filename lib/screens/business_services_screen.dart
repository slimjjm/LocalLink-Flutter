import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'add_service_screen.dart';

class BusinessServicesScreen extends StatefulWidget {
  final String businessId;

  const BusinessServicesScreen({
    super.key,
    required this.businessId,
  });

  @override
  State<BusinessServicesScreen> createState() =>
      _BusinessServicesScreenState();
}

class _BusinessServicesScreenState
    extends State<BusinessServicesScreen> {

  // =========================================
  // CONTROLLERS
  // =========================================

  final serviceNameController =
      TextEditingController();

  final servicePriceController =
      TextEditingController();

  final durationController =
      TextEditingController();

  final detailsController =
      TextEditingController();

  bool isSaving = false;

  // =========================================
  // ADD SERVICE
  // =========================================

  Future<void> addService() async {

    final name =
        serviceNameController.text.trim();

    final priceText =
        servicePriceController.text.trim();

    final durationText =
        durationController.text.trim();

    final details =
        detailsController.text.trim();

    if (name.isEmpty ||
        priceText.isEmpty ||
        durationText.isEmpty) {
      return;
    }

    final price =
        double.tryParse(priceText);

    final duration =
        int.tryParse(durationText);

    if (price == null ||
        duration == null) {
      return;
    }

    setState(() {
      isSaving = true;
    });

    try {

      await FirebaseFirestore.instance
          .collection('businesses')
          .doc(widget.businessId)
          .collection('services')
          .add({

        'name': name,

        'details': details,

        // STORE IN PENCE
        'price':
            (price * 100).round(),

        'durationMinutes':
            duration,

        'isActive': true,

        'createdAt':
            FieldValue.serverTimestamp(),
      });

      serviceNameController.clear();
      servicePriceController.clear();
      durationController.clear();
      detailsController.clear();

      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(

        const SnackBar(
          content: Text(
            'Service added',
          ),
        ),
      );

    } catch (e) {

      ScaffoldMessenger.of(context)
          .showSnackBar(

        SnackBar(
          content: Text(
            e.toString(),
          ),
        ),
      );

    } finally {

      setState(() {
        isSaving = false;
      });
    }
  }

  // =========================================
  // DELETE SERVICE
  // =========================================

  Future<void> deleteService(
    String serviceId,
  ) async {

    await FirebaseFirestore.instance
        .collection('businesses')
        .doc(widget.businessId)
        .collection('services')
        .doc(serviceId)
        .delete();
  }

  // =========================================
  // UI
  // =========================================

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      appBar: AppBar(
        title: const Text(
          'Manage Services',
        ),
      ),

      body: Padding(

        padding: const EdgeInsets.all(16),

        child: Column(

          children: [

            // =====================================
            // ADD SERVICE FORM
            // =====================================

            TextField(

              controller:
                  serviceNameController,

              decoration:
                  const InputDecoration(
                labelText:
                    'Service Name',
              ),
            ),

            const SizedBox(height: 12),

            TextField(

              controller:
                  detailsController,

              decoration:
                  const InputDecoration(
                labelText:
                    'Service Details',
              ),
            ),

            const SizedBox(height: 12),

            TextField(

              controller:
                  servicePriceController,

              keyboardType:
                  TextInputType.number,

              decoration:
                  const InputDecoration(
                labelText:
                    'Price (£)',
              ),
            ),

            const SizedBox(height: 12),

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

            const SizedBox(height: 20),

            ElevatedButton(

              onPressed:
                  isSaving
                      ? null
                      : addService,

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

                      : const Text(
                          'Add Service',
                        ),
            ),

            const SizedBox(height: 30),

                   // =====================================
            // SERVICES LIST
            // =====================================

            Expanded(

              child:
                  StreamBuilder<QuerySnapshot>(

                stream:
                    FirebaseFirestore.instance
                        .collection('businesses')
                        .doc(widget.businessId)
                        .collection('services')
                        .orderBy(
                          'createdAt',
                          descending: true,
                        )
                        .snapshots(),

                builder:
                    (context, snapshot) {

                  if (!snapshot.hasData) {

                    return const Center(
                      child:
                          CircularProgressIndicator(),
                    );
                  }

                  final docs =
                      snapshot.data!.docs;

                  if (docs.isEmpty) {

                    return const Center(
                      child: Text(
                        'No services yet',
                      ),
                    );
                  }

                  return ListView.builder(

                    itemCount: docs.length,

                    itemBuilder:
                        (context, index) {

                      final doc =
                          docs[index];

                      final service =
                          doc.data()
                              as Map<String,
                                  dynamic>;

                      final name =
                          service['name']
                              ?? 'Service';

                      final details =
                          service['details']
                              ?? '';

                      final price =
                          ((service['price']
                                      ?? 0)
                                  as num)
                              .toDouble() /
                              100;

                      final duration =
                          service[
                                  'durationMinutes']
                              ?? 30;

                      final isActive =
                          service['isActive']
                              ?? true;

                      return Card(

                        margin:
                            const EdgeInsets.only(
                          bottom: 12,
                        ),

                        child: ListTile(

                          // ====================
                          // EDIT SERVICE
                          // ====================

                          onTap: () {

                            Navigator.push(

                              context,

                              MaterialPageRoute(

                                builder: (_) =>
                                    AddServiceScreen(

                                  businessId:
                                      widget.businessId,

                                  serviceId:
                                      doc.id,

                                  existingService:
                                      service,
                                ),
                              ),
                            );
                          },

                          // ====================
                          // TITLE + STATUS
                          // ====================

                          title: Row(

                            children: [

                              Expanded(
                                child: Text(name),
                              ),

                              GestureDetector(

                                onTap: () async {

                                  await FirebaseFirestore
                                      .instance
                                      .collection(
                                          'businesses')
                                      .doc(
                                          widget.businessId)
                                      .collection(
                                          'services')
                                      .doc(doc.id)
                                      .update({

                                    'isActive':
                                        !isActive,
                                  });
                                },

                                child: Container(

                                  padding:
                                      const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),

                                  decoration:
                                      BoxDecoration(

                                    color:
                                        isActive
                                            ? Colors.green
                                            : Colors.red,

                                    borderRadius:
                                        BorderRadius.circular(
                                      20,
                                    ),
                                  ),

                                  child: Text(

                                    isActive
                                        ? 'ACTIVE'
                                        : 'INACTIVE',

                                    style:
                                        const TextStyle(

                                      color:
                                          Colors.white,

                                      fontSize: 11,

                                      fontWeight:
                                          FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),

                          // ====================
                          // SUBTITLE
                          // ====================

                          subtitle: Column(

                            crossAxisAlignment:
                                CrossAxisAlignment.start,

                            children: [

                              Text(
                                '£${price.toStringAsFixed(2)} • $duration mins',
                              ),

                              if (details.isNotEmpty)

                                Text(

                                  details,

                                  style:
                                      const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                            ],
                          ),

                          // ====================
                          // DELETE
                          // ====================

                          trailing: IconButton(

                            icon: const Icon(
                              Icons.delete,
                            ),
onPressed: () async {

  final confirmed =
      await showDialog<bool>(

    context: context,

    builder: (context) {

      return AlertDialog(

        title: const Text(
          'Delete Service?',
        ),

        content: Text(
          'Are you sure you want to delete "$name"?',
        ),

        actions: [

          TextButton(

            onPressed: () {

              Navigator.pop(
                context,
                false,
              );
            },

            child: const Text(
              'Cancel',
            ),
          ),

          ElevatedButton(

            onPressed: () {

              Navigator.pop(
                context,
                true,
              );
            },

            child: const Text(
              'Delete',
            ),
          ),
        ],
      );
    },
  );

  if (confirmed == true) {

    deleteService(
      doc.id,
    );
  }
},
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
                      ],
        ),
      ),
    );
  }
}