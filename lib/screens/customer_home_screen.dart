import 'package:flutter/material.dart';

import '../viewmodels/customer_unread_view_model.dart';

import 'business_list_screen.dart';
import 'my_bookings_screen.dart';
import 'business_gate_screen.dart';
import 'inbox_screen.dart';

class CustomerHomeScreen extends StatefulWidget {

  const CustomerHomeScreen({
    super.key,
  });

  @override
  State<CustomerHomeScreen> createState() =>
      _CustomerHomeScreenState();
}

class _CustomerHomeScreenState
    extends State<CustomerHomeScreen> {

  final CustomerUnreadViewModel
      unreadViewModel =
          CustomerUnreadViewModel();

  @override
  void initState() {
    super.initState();

    unreadViewModel.onUpdated = () {

      if (mounted) {
        setState(() {});
      }
    };

    unreadViewModel.startListening();
  }

  @override
  void dispose() {

    unreadViewModel.dispose();

    super.dispose();
  }

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
            // MESSAGES
            // =========================================

            ElevatedButton(

              onPressed: () {

                Navigator.push(

                  context,

                  MaterialPageRoute(

                    builder: (_) =>
                        const InboxScreen(
                      currentRole: 'customer',
                    ),
                  ),
                );
              },

              child: Row(

                mainAxisAlignment:
                    MainAxisAlignment.center,

                children: [

                  const Text(
                    'Messages',
                  ),

                  if (unreadViewModel.unreadCount >
                      0) ...[

                    const SizedBox(width: 8),

                    Container(

                      padding:
                          const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),

                      decoration: BoxDecoration(

                        color: Colors.red,

                        borderRadius:
                            BorderRadius.circular(20),
                      ),

                      child: Text(

                        unreadViewModel
                            .unreadCount
                            .toString(),

                        style: const TextStyle(

                          color: Colors.white,

                          fontSize: 12,

                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
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