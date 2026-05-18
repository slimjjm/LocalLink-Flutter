import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'customer_booking_detail_screen.dart';

class CustomerBookingsScreen extends StatelessWidget {

  const CustomerBookingsScreen({
    super.key,
  });

  // =====================================================
  // FORMAT DATE
  // =====================================================

  String formatDate(Timestamp timestamp) {

    final date = timestamp.toDate().toLocal();

    return
        '${date.day}/${date.month}/${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }

  // =====================================================
  // STATUS COLOR
  // =====================================================

  Color statusColor(String status) {

    switch (status) {

      case 'confirmed':
        return Colors.green;

      case 'pending_payment':
        return Colors.orange;

      case 'completed':
        return Colors.blue;

      case 'cancelled_by_customer':
      case 'cancelled_by_business':
      case 'payment_failed':
        return Colors.red;

      default:
        return Colors.grey;
    }
  }

  // =====================================================
  // IS ACTIVE BOOKING
  // =====================================================

  bool isActiveBooking(String status) {

    return
        status == 'confirmed' ||
        status == 'pending_payment';
  }

  // =====================================================
  // UI
  // =====================================================

  @override
  Widget build(BuildContext context) {

    final user =
        FirebaseAuth.instance.currentUser;

    if (user == null) {

      return Scaffold(

        appBar: AppBar(
          title: const Text('My Bookings'),
        ),

        body: const Center(
          child:
              Text('Not logged in'),
        ),
      );
    }

    return Scaffold(

      appBar: AppBar(
        title: const Text('My Bookings'),
      ),

      body:
          StreamBuilder<QuerySnapshot>(

        stream:
            FirebaseFirestore.instance
                .collection('bookings')
                .where(
                  'customerId',
                  isEqualTo: user.uid,
                )
                .orderBy(
                  'startTime',
                  descending: false,
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
                'No bookings yet',
                style: TextStyle(
                  fontSize: 18,
                ),
              ),
            );
          }

          final upcoming =
              docs.where((doc) {

            final data =
                doc.data()
                    as Map<String, dynamic>;

            final status =
                data['status'] ??
                    '';

            return isActiveBooking(
              status,
            );

          }).toList();

          final past =
              docs.where((doc) {

            final data =
                doc.data()
                    as Map<String, dynamic>;

            final status =
                data['status'] ??
                    '';

            return !isActiveBooking(
              status,
            );

          }).toList();

          return ListView(

            padding:
                const EdgeInsets.all(16),

            children: [

              // =====================================
              // UPCOMING
              // =====================================

              if (upcoming.isNotEmpty) ...

              [

                const Text(
                  'Upcoming',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 16),

                ...upcoming.map((doc) {

                  final data =
                      doc.data()
                          as Map<String, dynamic>;

                  return bookingCard(
                    context,
                    doc.id,
                    data,
                  );
                }),
              ],

              // =====================================
              // PAST
              // =====================================

              if (past.isNotEmpty) ...

              [

                const SizedBox(height: 30),

                const Text(
                  'Past',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 16),

                ...past.map((doc) {

                  final data =
                      doc.data()
                          as Map<String, dynamic>;

                  return bookingCard(
                    context,
                    doc.id,
                    data,
                  );
                }),
              ],
            ],
          );
        },
      ),
    );
  }

  // =====================================================
  // BOOKING CARD
  // =====================================================

  Widget bookingCard(
    BuildContext context,
    String bookingId,
    Map<String, dynamic> data,
  ) {

    final serviceName =
        data['serviceName'] ??
            'Service';

    final businessName =
        data['businessName'] ??
            'Business';

    final staffName =
        data['staffName'] ??
            'Staff';

    final status =
        data['status'] ??
            'unknown';

    final startTime =
        data['startTime']
            as Timestamp?;

    return Card(

      margin:
          const EdgeInsets.only(
        bottom: 14,
      ),

      child: InkWell(

        borderRadius:
            BorderRadius.circular(12),

        onTap: () {

          Navigator.push(

            context,

            MaterialPageRoute(

              builder: (_) =>
                  CustomerBookingDetailScreen(
                bookingId: bookingId,
              ),
            ),
          );
        },

        child: Padding(

          padding:
              const EdgeInsets.all(16),

          child: Column(

            crossAxisAlignment:
                CrossAxisAlignment.start,

            children: [

              Row(

                children: [

                  Expanded(

                    child: Text(
                      serviceName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                  ),

                  Container(

                    padding:
                        const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),

                    decoration: BoxDecoration(
                      color:
                          statusColor(status),
                      borderRadius:
                          BorderRadius.circular(20),
                    ),

                    child: Text(

                      status.replaceAll(
                        '_',
                        ' ',
                      ),

                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight:
                            FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              Text(
                businessName,
                style: const TextStyle(
                  fontSize: 16,
                ),
              ),

              const SizedBox(height: 6),

              Text(
                'Staff: $staffName',
              ),

              const SizedBox(height: 6),

              Text(
                startTime == null
                    ? 'Unknown date'
                    : formatDate(startTime),
              ),
            ],
          ),
        ),
      ),
    );
  }
}