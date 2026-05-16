import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class MyBookingsScreen extends StatelessWidget {
  const MyBookingsScreen({super.key});

  String formatDate(Timestamp timestamp) {
    final date = timestamp.toDate();

    return "${date.day}/${date.month}/${date.year}";
  }

  String formatTime(Timestamp timestamp) {
    final date = timestamp.toDate();

    return "${date.hour.toString().padLeft(2, '0')}:"
        "${date.minute.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(
        body: Center(
          child: Text('Please log in'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Bookings'),
      ),

      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('bookings')
            .where('customerId', isEqualTo: user.uid)
            .orderBy('startDate', descending: false)
            .snapshots(),

        builder: (context, snapshot) {

          if (snapshot.connectionState ==
              ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Error: ${snapshot.error}',
              ),
            );
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return const Center(
              child: Text('No bookings yet'),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,

            itemBuilder: (context, index) {

              final booking =
                  docs[index].data()
                      as Map<String, dynamic>;

              final serviceName =
                  booking['serviceName'] ?? 'Service';

              final staffName =
                  booking['staffName'] ?? 'Staff';

              final status =
                  booking['status'] ?? 'unknown';

              final startDate =
                  booking['startDate'] as Timestamp;

             final paymentMethod =
    booking['paymentMethod'] ?? 'unknown';
              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),

                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: Colors.grey.shade100,
                ),

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
                              fontWeight: FontWeight.bold,
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
                            color: status == 'confirmed'
                                ? Colors.green.shade100
                                : Colors.orange.shade100,

                            borderRadius:
                                BorderRadius.circular(20),
                          ),

                          child: Text(
                            status.replaceAll('_', ' '),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    Text(
                      "${formatDate(startDate)} at ${formatTime(startDate)}",
                    ),

                    const SizedBox(height: 6),

                    Text("With $staffName"),

                    const SizedBox(height: 6),

                    Text(
                      paymentMethod == 'cash'
                          ? 'Pay in person'
                          : 'Paid by card',
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}