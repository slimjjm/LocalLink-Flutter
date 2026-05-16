import 'package:flutter/material.dart';

import 'business_list_screen.dart';
import 'my_bookings_screen.dart';
import 'business_gate_screen.dart';
import 'business_staff_screen.dart';

class CustomerHomeScreen extends StatelessWidget {

  const CustomerHomeScreen({
    super.key,
  });

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      appBar: AppBar(
        title: const Text('LocalLink'),
      ),

      body: Padding(

        padding: const EdgeInsets.all(20),

        child: Column(

          crossAxisAlignment:
              CrossAxisAlignment.stretch,

          children: [

            const SizedBox(height: 20),

            // =========================================
            // TITLE
            // =========================================

            const Text(

              'Welcome to LocalLink',

              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 10),

            const Text(

              'Book trusted local businesses near you.',

              style: TextStyle(
                fontSize: 16,
              ),
            ),

            const SizedBox(height: 40),

            // =========================================
            // BROWSE BUSINESSES
            // =========================================

            ElevatedButton(

              onPressed: () {

                Navigator.push(

                  context,

                  MaterialPageRoute(

                    builder: (_) =>
                        const BusinessListScreen(),
                  ),
                );
              },

              child: const Text(
                'Browse Businesses',
              ),
            ),

            const SizedBox(height: 16),

            // =========================================
            // MY BOOKINGS
            // =========================================

            ElevatedButton(

              onPressed: () {

                Navigator.push(

                  context,

                  MaterialPageRoute(

                    builder: (_) =>
                        const MyBookingsScreen(),
                  ),
                );
              },

              child: const Text(
                'My Bookings',
              ),
            ),

            const SizedBox(height: 16),

            // =========================================
            // BUSINESS DASHBOARD
            // =========================================

            ElevatedButton(

              onPressed: () {

                Navigator.push(

                  context,

                  MaterialPageRoute(

                    builder: (_) =>
                        const BusinessGateScreen(),
                  ),
                );
              },

              child: const Text(
                'Business Dashboard',
              ),
            ),
          ],
        ),
      ),
    );
  }
}