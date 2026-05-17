import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'business_availability_screen.dart';
import 'staff_services_screen.dart';
import 'staff_day_blocks_screen.dart';

class BusinessStaffScreen extends StatefulWidget {

  final String businessId;

  const BusinessStaffScreen({
    super.key,
    required this.businessId,
  });

  @override
  State<BusinessStaffScreen> createState() =>
      _BusinessStaffScreenState();
}

class _BusinessStaffScreenState
    extends State<BusinessStaffScreen> {

  final nameController =
      TextEditingController();

  final roleController =
      TextEditingController();

  // =====================================================
  // ADD STAFF
  // =====================================================

  Future<void> addStaff() async {

    final name =
        nameController.text.trim();

    final role =
        roleController.text.trim();

    if (name.isEmpty) return;

    final existingStaff = await FirebaseFirestore
    .instance
    .collection('businesses')
    .doc(widget.businessId)
    .collection('staff')
    .get();

final seatRank =
    existingStaff.docs.length;

await FirebaseFirestore.instance
    .collection('businesses')
    .doc(widget.businessId)
    .collection('staff')
    .add({

  'name': name,

  'role':
      role.isEmpty
          ? 'Staff'
          : role,

  'isActive': true,

  'canTakeBookings': true,

  'bookingCount': 0,

  'seatRank': seatRank,

   'photoUrl': '',

   'serviceIds': [],

  'createdAt': Timestamp.now(),
});

    nameController.clear();
    roleController.clear();

    if (!mounted) return;

    Navigator.pop(context);
  }

  // =====================================================
  // ADD STAFF DIALOG
  // =====================================================

  void showAddStaffDialog() {

    showDialog(

      context: context,

      builder: (_) {

        return AlertDialog(

          title:
              const Text('Add Staff'),

          content: Column(

            mainAxisSize:
                MainAxisSize.min,

            children: [

              TextField(
                controller:
                    nameController,

                decoration:
                    const InputDecoration(
                  labelText:
                      'Name',
                ),
              ),

              const SizedBox(height: 16),

              TextField(
                controller:
                    roleController,

                decoration:
                    const InputDecoration(
                  labelText:
                      'Role',
                ),
              ),
            ],
          ),

          actions: [

            TextButton(

              onPressed: () {
                Navigator.pop(context);
              },

              child:
                  const Text('Cancel'),
            ),

            ElevatedButton(

              onPressed: addStaff,

              child:
                  const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  // =====================================================
  // TOGGLE ACTIVE
  // =====================================================

  Future<void> toggleActive(
    String staffId,
    bool currentValue,
  ) async {

    await FirebaseFirestore.instance
        .collection('businesses')
        .doc(widget.businessId)
        .collection('staff')
        .doc(staffId)
        .update({

      'isActive':
          !currentValue,
    });
  }

  // =====================================================
  // UI
  // =====================================================

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      appBar: AppBar(
        title:
            const Text('Staff'),
      ),

      floatingActionButton:
          FloatingActionButton(

        onPressed:
            showAddStaffDialog,

        child:
            const Icon(Icons.add),
      ),

      body:
          StreamBuilder<QuerySnapshot>(

        stream:
            FirebaseFirestore.instance
                .collection('businesses')
                .doc(widget.businessId)
                .collection('staff')
               .orderBy('seatRank')
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
                  Text('No staff yet'),
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

              final name =
                  data['name']
                      ?? 'Staff';

              final role =
                  data['role']
                      ?? 'Role';

              final isActive =
                  data['isActive']
                      ?? true;

                           return Card(

                margin:
                    const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),

                child: ListTile(

                  leading: CircleAvatar(
                    child: Text(
                      name
                          .toString()
                          .substring(0, 1)
                          .toUpperCase(),
                    ),
                  ),

                  title: Text(name),

                  subtitle: Text(role),

                  onTap: () {

                    Navigator.push(

                      context,

                      MaterialPageRoute(

                        builder: (_) =>
                            BusinessAvailabilityScreen(

                          businessId:
                              widget.businessId,

                          staffId:
                              doc.id,

                          staffName:
                              name,
                        ),
                      ),
                    );
                  },

                  trailing: Row(

                    mainAxisSize:
                        MainAxisSize.min,

                    children: [

                      // =====================================
                      // STAFF SERVICES
                      // =====================================

                      IconButton(

                        icon:
                            const Icon(Icons.build),

                        onPressed: () {

                          Navigator.push(

                            context,

                            MaterialPageRoute(

                              builder: (_) =>
                                  StaffServicesScreen(

                                businessId:
                                    widget.businessId,

                                staffId:
                                    doc.id,

                                staffName:
                                    name,
                              ),
                            ),
                          );
                        },
                      ),

                      // =====================================
                      // STAFF BLOCKS
                      // =====================================

                      IconButton(

                        icon:
                            const Icon(Icons.event_busy),

                        onPressed: () {

                          Navigator.push(

                            context,

                            MaterialPageRoute(

                              builder: (_) =>
                                  StaffDayBlocksScreen(

                                businessId:
                                    widget.businessId,

                                staffId:
                                    doc.id,

                                staffName:
                                    name,
                              ),
                            ),
                          );
                        },
                      ),

                      // =====================================
                      // ACTIVE SWITCH
                      // =====================================

                      Switch(

                        value: isActive,

                        onChanged: (_) {

                          toggleActive(
                            doc.id,
                            isActive,
                          );
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}