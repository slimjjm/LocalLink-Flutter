import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../widgets/booking_message_button.dart';
import '../widgets/booking_status_chip.dart';

class BusinessBookingDetailScreen extends StatefulWidget {
  final String bookingId;

  const BusinessBookingDetailScreen({super.key, required this.bookingId});

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

    return '${date.day}/${date.month}/${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
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
            'completedAt': FieldValue.serverTimestamp(),
          });

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Booking marked completed')));
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('We could not update this booking. Please try again.'),
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
    final confirm = await showDialog<bool>(
      context: context,

      builder: (_) {
        return AlertDialog(
          title: const Text('Cancel booking?'),

          content: const Text('This action cannot be undone.'),

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

              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),

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
      final callable = FirebaseFunctions.instance.httpsCallable(
        'cancelBooking',
      );

      await callable.call({'bookingId': widget.bookingId});

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Booking cancelled')));
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('We could not cancel this booking. Please try again.'),
        ),
      );
    }

    if (mounted) {
      setState(() {
        isUpdating = false;
      });
    }
  }

  Future<void> acceptShortNoticeBooking() async {
    setState(() {
      isUpdating = true;
    });

    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'acceptShortNoticeBooking',
      );

      await callable.call({'bookingId': widget.bookingId});

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Booking accepted')));
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('We could not accept this booking. Please try again.'),
        ),
      );
    }

    if (mounted) {
      setState(() {
        isUpdating = false;
      });
    }
  }

  Future<void> declineShortNoticeBooking() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('Decline booking?'),
          content: const Text(
            'The customer will be notified and any card payment will be refunded.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Decline'),
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
      final callable = FirebaseFunctions.instance.httpsCallable(
        'declineShortNoticeBooking',
      );

      await callable.call({'bookingId': widget.bookingId});

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Booking declined')));
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('We could not decline this booking. Please try again.'),
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

  Widget infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),

      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          SizedBox(
            width: 110,

            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),

          Expanded(child: Text(value)),
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
      appBar: AppBar(title: const Text('Booking Details')),

      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('bookings')
            .doc(widget.bookingId)
            .snapshots(),

        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.data!.exists) {
            return const Center(child: Text('Booking not found'));
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;

          final serviceName = data['serviceName'] ?? 'Service';

          final businessName = data['businessName'] ?? 'Business';

          final customerName = data['customerName'] ?? 'Customer';

          final customerAddress = data['customerAddress'] ?? '';

          final staffName = data['staffName'] ?? 'Team member';

          final paymentMethod = data['paymentMethod'] ?? 'Unknown';

          final status = data['status'] ?? 'unknown';

          final duration = data['durationMinutes'];

          final startTime =
              (data['startDate'] ?? data['startTime']) as Timestamp?;

          final canManage =
              status == 'confirmed' || status == 'pending_payment';

          final canConfirmShortNotice =
              status == 'pending_business_confirmation';

          final canMessage =
              status == 'confirmed' ||
              status == 'pending_business_confirmation' ||
              status == 'completed';
          final conversationId =
              (data['conversationId'] as String?) ?? widget.bookingId;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),

            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                // =====================================
                // HEADER
                // =====================================
                Text(
                  serviceName,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 8),

                Text(businessName, style: const TextStyle(fontSize: 18)),

                const SizedBox(height: 16),

                BookingStatusChip(status: status),

                const SizedBox(height: 30),

                // =====================================
                // BOOKING INFO
                // =====================================
                const Text(
                  'Booking Info',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 16),

                infoRow('Customer', customerName),

                infoRow('With', staffName),

                infoRow(
                  'Date',
                  startTime == null ? 'Unknown' : formatDate(startTime),
                ),

                infoRow(
                  'Duration',
                  duration == null ? 'Unknown' : '$duration mins',
                ),

                infoRow(
                  'Payment',
                  paymentMethod.toString().toLowerCase() == 'stripe'
                      ? 'Card'
                      : 'Cash',
                ),

                const SizedBox(height: 30),

                // =====================================
                // CUSTOMER DETAILS
                // =====================================
                const Text(
                  'Customer Details',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 16),

                infoRow('Name', customerName),

                infoRow('Address', customerAddress),

                const SizedBox(height: 40),

                // =====================================
                // ACTIONS
                // =====================================
                if (canMessage) ...[
                  BookingMessageButton(
                    bookingId: conversationId,
                    viewerType: 'business',
                    label: 'Message Customer',
                    enabled: canMessage,
                    onPressed: () {
                      Navigator.pushNamed(
                        context,
                        '/booking-conversation',
                        arguments: {
                          'bookingId': widget.bookingId,
                          'conversationId': conversationId,
                          'viewerType': 'business',
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                ],

                if (canConfirmShortNotice) ...[
                  const Text(
                    'This short-notice booking needs your confirmation before it becomes final.',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isUpdating ? null : acceptShortNoticeBooking,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                      ),
                      child: isUpdating
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Accept Booking'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isUpdating ? null : declineShortNoticeBooking,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                      child: const Text('Decline Booking'),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                if (canManage) ...[
                  SizedBox(
                    width: double.infinity,

                    child: ElevatedButton(
                      onPressed: isUpdating ? null : markCompleted,

                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                      ),

                      child: isUpdating
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Mark Completed'),
                    ),
                  ),

                  const SizedBox(height: 12),

                  SizedBox(
                    width: double.infinity,

                    child: ElevatedButton(
                      onPressed: isUpdating ? null : cancelBooking,

                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),

                      child: const Text('Cancel Booking'),
                    ),
                  ),
                ],

                const SizedBox(height: 12),

                if (!canMessage)
                  SizedBox(
                    width: double.infinity,

                    child: OutlinedButton(
                      onPressed: null,

                      child: const Text('Message Customer'),
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
