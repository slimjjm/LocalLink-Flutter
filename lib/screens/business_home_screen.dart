import 'package:flutter/material.dart';

import 'business_bookings_screen.dart';
import 'business_services_screen.dart';
import 'business_availability_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'business_staff_screen.dart';

class BusinessHomeScreen extends StatelessWidget {

  final String businessId;

  const BusinessHomeScreen({
    super.key,
    required this.businessId,
  });

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      appBar: AppBar(
        title: const Text('Business Dashboard'),
      ),

      body: Padding(

        padding: const EdgeInsets.all(20),

        child: Column(

          crossAxisAlignment:
              CrossAxisAlignment.stretch,

          children: [

            const SizedBox(height: 20),

            // =====================================
            // HEADER
            // =====================================

            const Text(

              'Business Tools',

              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 10),

            const Text(
              'Manage your bookings and services.',
            ),

            const SizedBox(height: 40),

            // =====================================
            // BOOKINGS
            // =====================================

            ElevatedButton(

              onPressed: () {

                Navigator.push(

                  context,

                  MaterialPageRoute(

                    builder: (_) =>
                        BusinessBookingsScreen(
                      businessId: businessId,
                    ),
                  ),
                );
              },

              child: const Text(
                'View Bookings',
              ),
            ),

            const SizedBox(height: 16),
            ElevatedButton(

  onPressed: () {

    Navigator.push(

      context,

      MaterialPageRoute(

        builder: (_) =>
            BusinessStaffScreen(
          businessId: businessId,
        ),
      ),
    );
  },

  child: const Text('Manage Staff'),
),

ElevatedButton(

  onPressed: () {

    Navigator.push(

      context,

      MaterialPageRoute(

       builder: (_) =>
    BusinessAvailabilityScreen(
  businessId: businessId,
  staffId:
      FirebaseAuth
          .instance
          .currentUser!
          .uid,
),
      ),
    );
  },

  child: const Text(
    'Manage Availability',
  ),
),
            // =====================================
            // SERVICES
            // =====================================

            ElevatedButton(

              onPressed: () {

                Navigator.push(

                  context,

                  MaterialPageRoute(

                    builder: (_) =>
                        BusinessServicesScreen(
                      businessId: businessId,
                    ),
                  ),
                );
              },

              child: const Text(
                'Manage Services',
              ),
            ),
          ],
        ),
      ),
    );
  }
}