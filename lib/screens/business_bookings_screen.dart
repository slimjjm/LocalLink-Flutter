import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../widgets/booking_status_chip.dart';

class BusinessBookingsScreen extends StatelessWidget {
  final String businessId;

  const BusinessBookingsScreen({super.key, required this.businessId});

  String formatPrice(dynamic price) {
    if (price == null) {
      return '£0.00';
    }

    final pounds = (price as num) / 100;

    return '£${pounds.toStringAsFixed(2)}';
  }

  String formatDate(Timestamp timestamp) {
    final date = timestamp.toDate();

    return '${date.day}/${date.month}/${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bookings')),

      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('bookings')
            .where('businessId', isEqualTo: businessId)
            .orderBy('startDate')
            .snapshots(),

        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return const Center(
              child: Text("We couldn't load your bookings. Please try again."),
            );
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return const Center(child: Text('No bookings yet'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),

            itemCount: docs.length,

            itemBuilder: (context, index) {
              final doc = docs[index];

              final booking = doc.data() as Map<String, dynamic>;

              final customerName = booking['customerName'] ?? 'Customer';

              final serviceName = booking['serviceName'] ?? 'Service';

              final status = booking['status'] ?? 'unknown';

              final paymentMethod = booking['paymentMethod'] ?? 'unknown';

              final price = booking['price'];

              final startDate = booking['startDate'] as Timestamp?;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),

                child: Padding(
                  padding: const EdgeInsets.all(16),

                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,

                    children: [
                      // =========================
                      // HEADER
                      // =========================
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,

                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,

                              children: [
                                Text(
                                  customerName,

                                  style: const TextStyle(
                                    fontSize: 18,

                                    fontWeight: FontWeight.bold,
                                  ),
                                ),

                                const SizedBox(height: 4),

                                Text(
                                  serviceName,
                                  style: const TextStyle(fontSize: 16),
                                ),

                                const SizedBox(height: 6),

                                if (startDate != null)
                                  Text(formatDate(startDate)),
                              ],
                            ),
                          ),

                          // =========================
                          // STATUS CHIP
                          // =========================
                          Flexible(
                            child: BookingStatusChip(
                              status: status,
                              compact: true,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // =========================
                      // PRICE + PAYMENT
                      // =========================
                      Row(
                        children: [
                          Text(
                            formatPrice(price),

                            style: const TextStyle(
                              fontWeight: FontWeight.bold,

                              fontSize: 16,
                            ),
                          ),

                          const SizedBox(width: 10),

                          Text(paymentMethod.toUpperCase()),
                        ],
                      ),

                      const SizedBox(height: 14),

                      // =========================
                      // ACTION BUTTONS
                      // =========================
                      if (status == 'confirmed')
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.check_circle),

                                label: const Text('Complete'),

                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                ),

                                onPressed: () async {
                                  await FirebaseFirestore.instance
                                      .collection('bookings')
                                      .doc(doc.id)
                                      .update({'status': 'completed'});
                                },
                              ),
                            ),

                            const SizedBox(width: 10),

                            Expanded(
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.cancel),

                                label: const Text('Cancel'),

                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                ),

                                onPressed: () async {
                                  await FirebaseFirestore.instance
                                      .collection('bookings')
                                      .doc(doc.id)
                                      .update({
                                        'status': 'cancelled_by_business',
                                      });
                                },
                              ),
                            ),
                          ],
                        ),

                      if (status == 'completed')
                        const Text(
                          'Completed ✅',
                          style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                      if (status == 'cancelled_by_business' ||
                          status == 'cancelled_by_customer')
                        const Text(
                          'Cancelled ❌',
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
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
