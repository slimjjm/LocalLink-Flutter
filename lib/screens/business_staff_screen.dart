import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'business_availability_screen.dart';
import 'staff_services_screen.dart';
import 'staff_day_blocks_screen.dart';
import 'business_subscription_screen.dart';

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

    final entitlementsSnap =
        await FirebaseFirestore.instance
            .collection('businesses')
            .doc(widget.businessId)
            .collection('entitlements')
            .doc('default')
            .get();

    final entitlementData =
        entitlementsSnap.data() ?? {};

    final freeSeats =
        entitlementData['freeStaffSlots'] ?? 1;

    final extraSeats =
        entitlementData['extraStaffSlots'] ?? 0;

    final allowedSeats =
        freeSeats + extraSeats;

    final restrictionMode =
        entitlementData['restrictionMode'] ?? false;

    if (restrictionMode) {

      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(

        const SnackBar(
          content: Text(
            'Restriction mode active.',
          ),
        ),
      );

      return;
    }

    final activeStaffSnap =
        await FirebaseFirestore.instance
            .collection('businesses')
            .doc(widget.businessId)
            .collection('staff')
            .where(
              'isActive',
              isEqualTo: true,
            )
            .get();

    final activeStaffCount =
        activeStaffSnap.docs.length;

    if (activeStaffCount >= allowedSeats) {

      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(

        const SnackBar(
          content: Text(
            'Staff limit reached. Upgrade required.',
          ),
        ),
      );

      return;
    }

    final existingStaff =
        await FirebaseFirestore.instance
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

          shape: RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(22),
          ),

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
                  labelText: 'Name',
                ),
              ),

              const SizedBox(height: 16),

              TextField(

                controller:
                    roleController,

                decoration:
                    const InputDecoration(
                  labelText: 'Role',
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

              style:
                  ElevatedButton.styleFrom(

                backgroundColor:
                    const Color(0xFFF26A2E),
              ),

              onPressed: addStaff,

              child: const Text(
                'Add',
                style: TextStyle(
                  color: Colors.white,
                ),
              ),
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

      'isActive': !currentValue,
    });
  }

  // =====================================================
  // UI
  // =====================================================

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      backgroundColor:
          const Color(0xFFF9F6F2),

      floatingActionButton:
          FloatingActionButton(

        backgroundColor:
            const Color(0xFFF26A2E),

        onPressed:
            showAddStaffDialog,

        child:
            const Icon(Icons.add),
      ),

      appBar: AppBar(

        elevation: 0,

        backgroundColor:
            const Color(0xFFF9F6F2),

        title: const Text(

          'Staff',

          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
      ),

      body:
          StreamBuilder<DocumentSnapshot>(

        stream:
            FirebaseFirestore.instance
                .collection('businesses')
                .doc(widget.businessId)
                .collection('entitlements')
                .doc('default')
                .snapshots(),

        builder: (
          context,
          entitlementSnapshot,
        ) {

          if (!entitlementSnapshot.hasData) {

            return const Center(
              child:
                  CircularProgressIndicator(),
            );
          }

          final entitlementData =
              entitlementSnapshot.data!.data()
                  as Map<String, dynamic>? ?? {};

          final freeSeats =
              entitlementData['freeStaffSlots'] ?? 1;

          final extraSeats =
              entitlementData['extraStaffSlots'] ?? 0;

          final allowedSeats =
              freeSeats + extraSeats;

          final restrictionMode =
              entitlementData['restrictionMode'] ?? false;

          return StreamBuilder<QuerySnapshot>(

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

              final activeStaff =
                  docs.where((doc) {

                final data =
                    doc.data()
                        as Map<String, dynamic>;

                return data['isActive'] != false;

              }).length;

              final lockedCount =
                  activeStaff > allowedSeats
                      ? activeStaff - allowedSeats
                      : 0;

              if (docs.isEmpty) {

                return Center(

                  child: Column(

                    mainAxisAlignment:
                        MainAxisAlignment.center,

                    children: [

                      Icon(
                        Icons.people_outline,
                        size: 70,
                        color: Colors.grey.shade400,
                      ),

                      const SizedBox(height: 18),

                      const Text(

                        'No staff yet',

                        style: TextStyle(
                          fontSize: 22,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 8),

                      Text(

                        'Add your first team member to begin taking bookings.',

                        textAlign:
                            TextAlign.center,

                        style: TextStyle(
                          color:
                              Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return Column(

                children: [

                  // =====================================
                  // RESTRICTION MODE
                  // =====================================

                  if (restrictionMode)

                    Container(

                      width: double.infinity,

                      margin:
                          const EdgeInsets.all(16),

                      padding:
                          const EdgeInsets.all(16),

                      decoration: BoxDecoration(

                        color:
                            const Color(0xFFFFF3E0),

                        borderRadius:
                            BorderRadius.circular(22),
                      ),

                      child: const Row(

                        children: [

                          Icon(
                            Icons.warning_amber_rounded,
                            color: Color(0xFFE65100),
                          ),

                          SizedBox(width: 12),

                          Expanded(

                            child: Text(

                              'Restriction mode active. Adding staff is temporarily disabled.',

                              style: TextStyle(
                                fontWeight:
                                    FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // =====================================
                  // CAPACITY CARD
                  // =====================================

                  Container(

                    width: double.infinity,

                    margin:
                        const EdgeInsets.symmetric(
                      horizontal: 16,
                    ),

                    padding:
                        const EdgeInsets.all(18),

                    decoration: BoxDecoration(

                      color: Colors.white,

                      borderRadius:
                          BorderRadius.circular(22),

                      boxShadow: [

                        BoxShadow(

                          color:
                              Colors.black.withOpacity(0.04),

                          blurRadius: 10,

                          offset:
                              const Offset(0, 4),
                        ),
                      ],
                    ),

                    child: Column(

                      crossAxisAlignment:
                          CrossAxisAlignment.start,

                      children: [

                        const Text(

                          'Staff Capacity',

                          style: TextStyle(
                            fontSize: 18,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),

                        const SizedBox(height: 8),

                        Text(
                          '$activeStaff / $allowedSeats seats used',
                        ),

                        const SizedBox(height: 18),

                        Row(

                          children: [

                            Expanded(

                              child: _buildStatCard(
                                'Active',
                                '$activeStaff',
                                Icons.people,
                              ),
                            ),

                            const SizedBox(width: 12),

                            Expanded(

                              child: _buildStatCard(
                                'Locked',
                                '$lockedCount',
                                Icons.lock,
                              ),
                            ),

                            const SizedBox(width: 12),

                            Expanded(

                              child: _buildStatCard(
                                'Free',
                                '${allowedSeats - activeStaff < 0 ? 0 : allowedSeats - activeStaff}',
                                Icons.event_available,
                              ),
                            ),
                          ],
                        ),

                        if (activeStaff >= allowedSeats)

                          Padding(

                            padding:
                                const EdgeInsets.only(
                              top: 18,
                            ),

                            child: SizedBox(

                              width: double.infinity,

                              height: 48,

                              child: ElevatedButton(

                                style:
                                    ElevatedButton.styleFrom(

                                  backgroundColor:
                                      const Color(0xFFF26A2E),

                                  shape:
                                      RoundedRectangleBorder(

                                    borderRadius:
                                        BorderRadius.circular(14),
                                  ),
                                ),

                                onPressed: () {

                                  Navigator.push(

                                    context,

                                    MaterialPageRoute(

                                      builder: (_) =>
                                          BusinessSubscriptionScreen(

                                        businessId:
                                            widget.businessId,
                                      ),
                                    ),
                                  );
                                },

                                child: const Text(

                                  'Upgrade Plan',

                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight:
                                        FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // =====================================
                  // STAFF LIST
                  // =====================================

                  Expanded(

                    child: RefreshIndicator(

                      onRefresh: () async {
                        setState(() {});
                      },

                      child: ListView.builder(

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
                              data['name'] ?? 'Staff';

                          final role =
                              data['role'] ?? 'Role';

                          final isActive =
                              data['isActive'] ?? true;

                          final isLocked =
                              index >= allowedSeats;

                          final bookingCount =
                              data['bookingCount'] ?? 0;

                          return Opacity(

                            opacity:
                                isLocked ? 0.5 : 1,

                            child: Container(

                              margin:
                                  const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),

                              decoration: BoxDecoration(

                                color: Colors.white,

                                borderRadius:
                                    BorderRadius.circular(22),

                                border: Border.all(

                                  color:
                                      isLocked
                                          ? Colors.orange.shade200
                                          : Colors.transparent,
                                ),

                                boxShadow: [

                                  BoxShadow(

                                    color:
                                        Colors.black.withOpacity(0.04),

                                    blurRadius: 10,

                                    offset:
                                        const Offset(0, 4),
                                  ),
                                ],
                              ),

                              child: InkWell(

                                borderRadius:
                                    BorderRadius.circular(22),

                                onTap:
                                    isLocked
                                        ? null
                                        : () {

                                            showModalBottomSheet(

                                              context: context,

                                              shape:
                                                  const RoundedRectangleBorder(

                                                borderRadius:
                                                    BorderRadius.vertical(
                                                  top: Radius.circular(28),
                                                ),
                                              ),

                                              builder: (_) {

                                                return SafeArea(

                                                  child: Column(

                                                    mainAxisSize:
                                                        MainAxisSize.min,

                                                    children: [

                                                      ListTile(

                                                        leading:
                                                            const Icon(Icons.schedule),

                                                        title:
                                                            const Text('Availability'),

                                                        onTap: () {

                                                          Navigator.pop(context);

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
                                                      ),

                                                      ListTile(

                                                        leading:
                                                            const Icon(Icons.build),

                                                        title:
                                                            const Text('Services'),

                                                        onTap: () {

                                                          Navigator.pop(context);

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

                                                      ListTile(

                                                        leading:
                                                            const Icon(Icons.event_busy),

                                                        title:
                                                            const Text('Block Time'),

                                                        onTap: () {

                                                          Navigator.pop(context);

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
                                                    ],
                                                  ),
                                                );
                                              },
                                            );
                                          },

                                child: Padding(

                                  padding:
                                      const EdgeInsets.all(18),

                                  child: Column(

                                    children: [

                                      Row(

                                        children: [

                                          CircleAvatar(

                                            radius: 28,

                                            backgroundColor:
                                                const Color(0xFFF26A2E),

                                            child: Text(

                                              name
                                                  .toString()
                                                  .substring(0, 1)
                                                  .toUpperCase(),

                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight:
                                                    FontWeight.bold,
                                              ),
                                            ),
                                          ),

                                          const SizedBox(width: 14),

                                          Expanded(

                                            child: Column(

                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,

                                              children: [

                                                Row(

                                                  children: [

                                                    Expanded(

                                                      child: Text(

                                                        name,

                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 18,
                                                        ),
                                                      ),
                                                    ),

                                                    if (bookingCount >= 20)

                                                      Container(

                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                          horizontal: 10,
                                                          vertical: 4,
                                                        ),

                                                        decoration:
                                                            BoxDecoration(

                                                          color:
                                                              const Color(0xFFF26A2E),

                                                          borderRadius:
                                                              BorderRadius.circular(10),
                                                        ),

                                                        child: const Text(

                                                          'Top Performer',

                                                          style: TextStyle(
                                                            color: Colors.white,
                                                            fontSize: 11,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                          ),
                                                        ),
                                                      ),
                                                  ],
                                                ),

                                                const SizedBox(height: 4),

                                                Text(

                                                  role,

                                                  style: TextStyle(
                                                    color:
                                                        Colors.grey.shade700,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),

                                          Switch(

                                            value:
                                                isActive,

                                            onChanged: (_) {

                                              toggleActive(
                                                doc.id,
                                                isActive,
                                              );
                                            },
                                          ),
                                        ],
                                      ),

                                      const SizedBox(height: 18),

                                      Row(

                                        children: [

                                          Expanded(

                                            child: _buildMiniStat(
                                              Icons.calendar_today,
                                              '$bookingCount',
                                              'Bookings',
                                            ),
                                          ),

                                          const SizedBox(width: 12),

                                          Expanded(

                                            child: _buildMiniStat(
                                              Icons.check_circle,
                                              isActive
                                                  ? 'Active'
                                                  : 'Paused',
                                              'Status',
                                            ),
                                          ),

                                          const SizedBox(width: 12),

                                          Expanded(

                                            child: _buildMiniStat(
                                              Icons.lock_outline,
                                              isLocked
                                                  ? 'Locked'
                                                  : 'Enabled',
                                              'Access',
                                            ),
                                          ),
                                        ],
                                      ),

                                      if (isLocked)

                                        Container(

                                          width: double.infinity,

                                          margin:
                                              const EdgeInsets.only(
                                            top: 16,
                                          ),

                                          padding:
                                              const EdgeInsets.all(12),

                                          decoration: BoxDecoration(

                                            color:
                                                Colors.orange.shade100,

                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),

                                          child: const Row(

                                            children: [

                                              Icon(Icons.lock),

                                              SizedBox(width: 10),

                                              Expanded(

                                                child: Text(

                                                  'Upgrade subscription to unlock this staff member.',

                                                  style: TextStyle(
                                                    fontWeight:
                                                        FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  // =====================================================
  // STAT CARD
  // =====================================================

  Widget _buildStatCard(
    String label,
    String value,
    IconData icon,
  ) {

    return Container(

      padding:
          const EdgeInsets.all(12),

      decoration: BoxDecoration(

        color:
            const Color(0xFFF9F6F2),

        borderRadius:
            BorderRadius.circular(16),
      ),

      child: Column(

        children: [

          Icon(icon),

          const SizedBox(height: 8),

          Text(

            value,

            style: const TextStyle(
              fontSize: 20,
              fontWeight:
                  FontWeight.bold,
            ),
          ),

          const SizedBox(height: 4),

          Text(label),
        ],
      ),
    );
  }

  // =====================================================
  // MINI STAT
  // =====================================================

  Widget _buildMiniStat(
    IconData icon,
    String value,
    String label,
  ) {

    return Container(

      padding:
          const EdgeInsets.symmetric(
        vertical: 12,
      ),

      decoration: BoxDecoration(

        color:
            const Color(0xFFF9F6F2),

        borderRadius:
            BorderRadius.circular(14),
      ),

      child: Column(

        children: [

          Icon(
            icon,
            size: 18,
          ),

          const SizedBox(height: 6),

          Text(

            value,

            style: const TextStyle(
              fontWeight:
                  FontWeight.bold,
            ),
          ),

          const SizedBox(height: 2),

          Text(

            label,

            style: TextStyle(
              fontSize: 12,
              color:
                  Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }
}