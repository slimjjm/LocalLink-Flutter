import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/helpers.dart';
import 'booking_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'enquiry_chat_screen.dart';

class BusinessDetailScreen extends StatelessWidget {
  final String businessId;

  const BusinessDetailScreen({
    super.key,
    required this.businessId,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('businesses')
          .doc(businessId)
          .get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final businessData =
            snapshot.data!.data() as Map<String, dynamic>? ?? {};

        final name = safeText(businessData['name'], 'Business');
        final category = safeText(businessData['category'], 'No category');
        final paymentMethods = resolvePaymentMethods(businessData);

        return Scaffold(
          appBar: AppBar(title: Text(name)),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 🔹 Simple header (replaces BusinessHeader)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(category),
                    const SizedBox(height: 4),
                    Text('Payment: ${paymentMethods.join(", ")}'),
                    const SizedBox(height: 16),

SizedBox(

  width: double.infinity,

  child: ElevatedButton.icon(

    icon: const Icon(
      Icons.chat_bubble_outline,
    ),

    label: const Text(
      'Ask a Question',
    ),

    onPressed: () {

      final customerId =
          FirebaseAuth
              .instance
              .currentUser
              ?.uid;

      if (customerId == null) {
        return;
      }

      Navigator.push(

        context,

        MaterialPageRoute(
          builder: (_) =>
              EnquiryChatScreen(

            businessId:
                businessId,

            customerId:
                customerId,
          ),
        ),
      );
    },
  ),
),
                  ],
                ),
              ),

              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text(
                  'Services',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('businesses')
                      .doc(businessId)
                      .collection('services')
.where('isActive', isEqualTo: true)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(),
                      );
                    }

                    final services = snapshot.data?.docs ?? [];

                    if (services.isEmpty) {
                      return const Center(
                        child: Text('No services yet'),
                      );
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: services.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final data =
                            (services[index].data()
                                    as Map<String, dynamic>?) ??
                                {};

                        return ServiceCard(
  businessId: businessId,
  businessName: name,
  serviceId: services[index].id,
  serviceData: data,
  paymentMethods: paymentMethods,
);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// =====================================================
// 🔹 SERVICE CARD (SELF-CONTAINED)
// =====================================================

class ServiceCard extends StatelessWidget {
  final String businessId;
  final String serviceId;
  final Map<String, dynamic> serviceData;
  final List<String> paymentMethods;
    final String businessName;

  const ServiceCard({
  super.key,
  required this.businessId,
  required this.businessName,
  required this.serviceId,
    required this.serviceData,
    required this.paymentMethods,
  });

  @override
  Widget build(BuildContext context) {

    final name =
        safeText(serviceData['name'], 'No name');

    final price =
        formatPrice(serviceData['price']);

    final duration =
        serviceData['durationMinutes'];

    return Card(
      elevation: 1,

      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),

      child: ListTile(
        contentPadding:
            const EdgeInsets.all(16),

        title: Text(
          name,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),

        subtitle: Text(
          duration == null
              ? price
              : '$price • ${duration} mins',
        ),

        trailing:
            const Icon(Icons.chevron_right),

        onTap: () {

          Navigator.push(
            context,

            MaterialPageRoute(
              builder: (_) => BookingScreen(
                businessId: businessId,
                businessName: businessName,
                serviceId: serviceId,
                serviceData: serviceData,
                paymentMethods: paymentMethods,
              ),
            ),
          );
        },
      ),
    );
  }
}