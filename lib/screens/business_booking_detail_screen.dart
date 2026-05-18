import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

class BusinessBookingDetailScreen extends StatefulWidget {

  final String bookingId;

  const BusinessBookingDetailScreen({
    super.key,
    required this.bookingId,
  });

  @override
  State<BusinessBookingDetailScreen> createState() =>
      _BusinessBookingDetailScreenState();
}

class _BusinessBookingDetailScreenState
    extends State<BusinessBookingDetailScreen> {

  bool isUpdating = false;

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
  // MARK COMPLETED
  // =====================================================

  Future<void> markCompleted() async {

    setState(() {
      isUpdating = true;
    });

    try {

      await FirebaseFirestore.instance
          .collection('bookings')
          .doc(widget.bookingId)
          .update({
        'status': 'completed',
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(

        const SnackBar(
          content:
              Text('Booking marked completed'),
        ),
      );

    } catch (e) {

      ScaffoldMessenger.of(context)
          .showSnackBar(

        SnackBar(
          content:
              Text('Error: $e'),
        ),
      );
    }

    if (mounted) {

      setState(() {
        isUpdating = false;
      });
    }
  }

  // =====================================================
  // CANCEL BOOKING
  // =====================================================

  Future<void> cancelBooking() async {

    final confirm =
        await showDialog<bool>(

      context: context,

      builder: (_) {

        return AlertDialog(

          title:
              const Text('Cancel booking?'),

          content:
              const Text(
                'This action cannot be undone.',
              ),

          actions: [

            TextButton(

              onPressed: () {
                Navigator.pop(context, false);
              },

              child: const Text('No'),
            ),

            ElevatedButton(

              onPressed: () {
                Navigator.pop(context, true);
              },

              style:
                  ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
              ),

              child: const Text('Yes'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    setState(() {
      isUpdating = true;
    });

    try {

      final callable =
          FirebaseFunctions.instance
              .httpsCallable(
                'cancelBooking',
              );

      await callable.call({
        'bookingId': widget.bookingId,
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(

        const SnackBar(
          content:
              Text('Booking cancelled'),
        ),
      );

    } catch (e) {

      ScaffoldMessenger.of(context)
          .showSnackBar(

        SnackBar(
          content:
              Text('Error: $e'),
        ),
      );
    }

    if (mounted) {

      setState(() {
        isUpdating = false;
      });
    }
  }

  // =====================================================
  // INFO ROW
  // =====================================================

  Widget infoRow(
    String label,
    String value,
  ) {

    return Padding(

      padding:
          const EdgeInsets.only(
        bottom: 14,
      ),

      child: Row(

        crossAxisAlignment:
            CrossAxisAlignment.start,

        children: [

          SizedBox(

            width: 110,

            child: Text(
              label,
              style: const TextStyle(
                fontWeight:
                    FontWeight.bold,
              ),
            ),
          ),

          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // UI
  // =====================================================

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      appBar: AppBar(
        title:
            const Text('Booking Details'),
      ),

      body:
          StreamBuilder<DocumentSnapshot>(

        stream:
            FirebaseFirestore.instance
                .collection('bookings')
                .doc(widget.bookingId)
                .snapshots(),

        builder:
            (context, snapshot) {

          if (!snapshot.hasData) {

            return const Center(
              child:
                  CircularProgressIndicator(),
            );
          }

          if (!snapshot.data!.exists) {

            return const Center(
              child:
                  Text('Booking not found'),
            );
          }

          final data =
              snapshot.data!.data()
                  as Map<String, dynamic>;

          final serviceName =
              data['serviceName'] ??
                  'Service';

          final businessName =
              data['businessName'] ??
                  'Business';

          final customerName =
              data['customerName'] ??
                  'Customer';

          final customerAddress =
              data['customerAddress'] ??
                  '';

          final staffName =
              data['staffName'] ??
                  'Staff';

          final paymentMethod =
              data['paymentMethod'] ??
                  'Unknown';

          final status =
              data['status'] ??
                  'unknown';

          final duration =
              data['durationMinutes'];

          final startTime =
              data['startTime']
                  as Timestamp?;

          final canManage =
              status == 'confirmed' ||
              status == 'pending_payment';

          return SingleChildScrollView(

            padding:
                const EdgeInsets.all(20),

            child: Column(

              crossAxisAlignment:
                  CrossAxisAlignment.start,

              children: [

                // =====================================
                // HEADER
                // =====================================

                Text(
                  serviceName,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 8),

                Text(
                  businessName,
                  style: const TextStyle(
                    fontSize: 18,
                  ),
                ),

                const SizedBox(height: 16),

                Container(

                  padding:
                      const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
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
                    ),
                  ),
                ),

                const SizedBox(height: 30),

                // =====================================
                // BOOKING INFO
                // =====================================

                const Text(
                  'Booking Info',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 16),

                infoRow(
                  'Customer',
                  customerName,
                ),

                infoRow(
                  'Staff',
                  staffName,
                ),

                infoRow(
                  'Date',
                  startTime == null
                      ? 'Unknown'
                      : formatDate(startTime),
                ),

                infoRow(
                  'Duration',
                  duration == null
                      ? 'Unknown'
                      : '$duration mins',
                ),

                infoRow(
                  'Payment',
                  paymentMethod
                              .toString()
                              .toLowerCase() ==
                          'stripe'
                      ? 'Card'
                      : 'Cash',
                ),

                const SizedBox(height: 30),

                // =====================================
                // CUSTOMER DETAILS
                // =====================================

                const Text(
                  'Customer Details',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 16),

                infoRow(
                  'Name',
                  customerName,
                ),

                infoRow(
                  'Address',
                  customerAddress,
                ),

                const SizedBox(height: 40),

                // =====================================
                // ACTIONS
                // =====================================

                if (canManage) ...

                [

                  SizedBox(

                    width: double.infinity,

                    child: ElevatedButton(

                      onPressed:
                          isUpdating
                              ? null
                              : markCompleted,

                      style:
                          ElevatedButton.styleFrom(
                        backgroundColor:
                            Colors.green,
                      ),

                      child:
                          isUpdating

                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child:
                                      CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color:
                                        Colors.white,
                                  ),
                                )

                              : const Text(
                                  'Mark Completed',
                                ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  SizedBox(

                    width: double.infinity,

                    child: ElevatedButton(

                      onPressed:
                          isUpdating
                              ? null
                              : cancelBooking,

                      style:
                          ElevatedButton.styleFrom(
                        backgroundColor:
                            Colors.red,
                      ),

                      child:
                          const Text(
                            'Cancel Booking',
                          ),
                    ),
                  ),
                ],

                const SizedBox(height: 12),

                SizedBox(

                  width: double.infinity,

                  child: OutlinedButton(

                    onPressed: () {

                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(

                        const SnackBar(
                          content: Text(
                            'Customer messaging coming soon',
                          ),
                        ),
                      );
                    },

                    child:
                        const Text(
                          'Contact Customer',
                        ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}