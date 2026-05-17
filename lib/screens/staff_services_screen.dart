import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

class StaffServicesScreen extends StatefulWidget {

  final String businessId;
  final String staffId;
  final String staffName;

  const StaffServicesScreen({
    super.key,
    required this.businessId,
    required this.staffId,
    required this.staffName,
  });

  @override
  State<StaffServicesScreen> createState() =>
      _StaffServicesScreenState();
}

class _StaffServicesScreenState
    extends State<StaffServicesScreen> {

  List<String> selectedServiceIds = [];

  bool isLoading = true;
  bool isSaving = false;

  // =====================================================
  // LOAD STAFF SERVICES
  // =====================================================

  Future<void> loadStaffServices() async {

    final doc = await FirebaseFirestore
        .instance
        .collection('businesses')
        .doc(widget.businessId)
        .collection('staff')
        .doc(widget.staffId)
        .get();

    final data =
        doc.data() ?? {};

    final ids =
        List<String>.from(
          data['serviceIds'] ?? [],
        );

    setState(() {

      selectedServiceIds = ids;

      isLoading = false;
    });
  }

  // =====================================================
  // TOGGLE SERVICE
  // =====================================================

Future<void> toggleService(
  String serviceId,
) async {

  final isRemoving =
      selectedServiceIds.contains(serviceId);

  if (isSaving) return;

  setState(() {
    isSaving = true;
  });

  // Prevent removing last service
  if (isRemoving &&
      selectedServiceIds.length == 1) {

    ScaffoldMessenger.of(context)
        .showSnackBar(

      const SnackBar(
        content: Text(
          'Staff must have at least one service',
        ),
      ),
    );

    setState(() {
      isSaving = false;
    });

    return;
  }

  try {

    setState(() {

      if (selectedServiceIds.contains(serviceId)) {

        selectedServiceIds.remove(serviceId);

      } else {

        selectedServiceIds.add(serviceId);
      }
    });

    await FirebaseFirestore.instance
        .collection('businesses')
        .doc(widget.businessId)
        .collection('staff')
        .doc(widget.staffId)
        .update({

      'serviceIds': selectedServiceIds,
    });

    // =====================================================
    // REGENERATE AVAILABILITY
    // =====================================================

    await FirebaseFunctions.instance
        .httpsCallable(
          'regenerateAvailability',
        )
    .call({

  'businessId': widget.businessId,
  'staffId': widget.staffId,
});

    print("✅ SAVED SERVICES");
    print("📦 SERVICE IDS: $selectedServiceIds");

  } catch (e) {

    print("❌ SAVE FAILED: $e");

    ScaffoldMessenger.of(context)
        .showSnackBar(

      SnackBar(
        content: Text(
          'Failed to save services: $e',
        ),
      ),
    );

  } finally {

    setState(() {
      isSaving = false;
    });
  }
}
  // =====================================================
  // INIT
  // =====================================================

  @override
  void initState() {
    super.initState();

    loadStaffServices();
  }

  // =====================================================
  // UI
  // =====================================================

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      appBar: AppBar(
        title: Text(
          '${widget.staffName} Services',
        ),
      ),

      body: isLoading

          ? const Center(
              child:
                  CircularProgressIndicator(),
            )

          : StreamBuilder<QuerySnapshot>(

              stream: FirebaseFirestore
                  .instance
                  .collection('businesses')
                  .doc(widget.businessId)
                  .collection('services')
                  .orderBy('name')
                  .snapshots(),

              builder: (context, snapshot) {

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
                    child:
                        Text('No services yet'),
                  );
                }

                return ListView.builder(

                  itemCount:
                      docs.length,

                  itemBuilder:
                      (context, index) {

                    final doc =
                        docs[index];

                    final data =
                        doc.data()
                            as Map<String, dynamic>;

                final serviceName =
    data['name']
        ?? 'Service';

final duration =
    data['durationMinutes']
        ?? 30;

final price =
    (data['price'] ?? 0)
        .toDouble();

                    final isSelected =
                        selectedServiceIds
                            .contains(doc.id);

                 return CheckboxListTile(

  title: Text(
    serviceName,
  ),

  subtitle: Text(
    '${duration} mins • £${price.toStringAsFixed(2)}',
  ),

  value: isSelected,

  onChanged: isSaving
    ? null
    : (_) {

    toggleService(
      doc.id,
    );
  },
);
                  },
                );
              },
            ),
    );
  }
}