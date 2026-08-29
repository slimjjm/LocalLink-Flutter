import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:url_launcher/url_launcher.dart';

class BusinessSubscriptionScreen extends StatelessWidget {
  final String businessId;

  const BusinessSubscriptionScreen({super.key, required this.businessId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F6F2),

      appBar: AppBar(
        elevation: 0,

        backgroundColor: const Color(0xFFF9F6F2),

        foregroundColor: const Color(0xFF1E1E1E),

        title: const Text(
          'Subscription',

          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),

      body: FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance
            .collection('businesses')
            .doc(businessId)
            .collection('entitlements')
            .doc('default')
            .get(),

        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};

          final freeSeats = data['freeStaffSlots'] ?? 1;

          final extraSeats = data['extraStaffSlots'] ?? 0;

          final restrictionMode = data['restrictionMode'] ?? false;

          final stripeStatus = data['stripeStatus'] ?? 'inactive';

          final allowedSeats = freeSeats + extraSeats;

          return FutureBuilder<QuerySnapshot>(
            future: FirebaseFirestore.instance
                .collection('businesses')
                .doc(businessId)
                .collection('staff')
                .where('isActive', isEqualTo: true)
                .get(),

            builder: (context, staffSnap) {
              if (!staffSnap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final activeStaff = staffSnap.data!.docs.length;

              final lockedCount = activeStaff > allowedSeats
                  ? activeStaff - allowedSeats
                  : 0;

              final usage = allowedSeats == 0
                  ? 0.0
                  : activeStaff / allowedSeats;

              return ListView(
                padding: const EdgeInsets.all(20),

                children: [
                  // =====================================
                  // HERO
                  // =====================================
                  Container(
                    padding: const EdgeInsets.all(24),

                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFF26A2E), Color(0xFFE65100)],
                      ),

                      borderRadius: BorderRadius.circular(28),
                    ),

                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,

                      children: [
                        const Text(
                          'LocalLink Pro',

                          style: TextStyle(color: Colors.white70),
                        ),

                        const SizedBox(height: 10),

                        const Text(
                          'Subscription & Billing',

                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        const SizedBox(height: 14),

                        Text(
                          stripeStatus.toUpperCase(),

                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // =====================================
                  // STATUS CARD
                  // =====================================
                  _SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,

                      children: [
                        const Text(
                          'Subscription Status',

                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        const SizedBox(height: 20),

                        _InfoRow('Stripe Status', stripeStatus),

                        _InfoRow(
                          'Restriction Mode',
                          restrictionMode ? 'Active' : 'Inactive',
                        ),

                        _InfoRow('Included Seats', '$freeSeats'),

                        _InfoRow('Extra Seats', '$extraSeats'),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // =====================================
                  // STAFF USAGE
                  // =====================================
                  _SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,

                      children: [
                        const Text(
                          'Team Spaces',

                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        const SizedBox(height: 24),

                        ClipRRect(
                          borderRadius: BorderRadius.circular(20),

                          child: LinearProgressIndicator(
                            value: usage > 1 ? 1 : usage,

                            minHeight: 16,

                            backgroundColor: Colors.grey.shade300,

                            valueColor: AlwaysStoppedAnimation<Color>(
                              usage >= 1
                                  ? Colors.red
                                  : usage > 0.7
                                  ? Colors.orange
                                  : Colors.green,
                            ),
                          ),
                        ),

                        const SizedBox(height: 14),

                        Text(
                          '$activeStaff of $allowedSeats team spaces used',

                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),

                        if (lockedCount > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),

                            child: Text(
                              '$lockedCount locked team members',

                              style: const TextStyle(
                                color: Colors.orange,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // =====================================
                  // RESTRICTION WARNING
                  // =====================================
                  if (restrictionMode)
                    _SectionCard(
                      color: const Color(0xFFFFF3E0),

                      child: Row(
                        children: [
                          const Icon(Icons.warning, color: Color(0xFFE65100)),

                          const SizedBox(width: 14),

                          const Expanded(
                            child: Text(
                              'Restriction mode is active. Existing bookings remain operational, but expansion features are temporarily limited.',

                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 24),

                  // =====================================
                  // UPGRADE BUTTON
                  // =====================================
                  SizedBox(
                    height: 58,

                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF26A2E),

                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),

                      onPressed: () async {
                        try {
                          final callable = FirebaseFunctions.instance
                              .httpsCallable('createStripePortalLink');

                          final result = await callable.call({
                            'businessId': businessId,
                          });

                          final url = result.data['url'];

                          if (url == null) return;

                          final uri = Uri.parse(url);

                          await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );
                        } catch (e) {
                          if (!context.mounted) return;

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Failed to open billing portal: $e',
                              ),
                            ),
                          );
                        }
                      },

                      child: const Text(
                        'Manage Subscription',

                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 40),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

// =====================================
// SECTION CARD
// =====================================

class _SectionCard extends StatelessWidget {
  final Widget child;
  final Color? color;

  const _SectionCard({required this.child, this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),

      decoration: BoxDecoration(
        color: color ?? Colors.white,

        borderRadius: BorderRadius.circular(24),

        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),

            blurRadius: 10,

            offset: const Offset(0, 4),
          ),
        ],
      ),

      child: child,
    );
  }
}

// =====================================
// INFO ROW
// =====================================

class _InfoRow extends StatelessWidget {
  final String title;
  final String value;

  const _InfoRow(this.title, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),

      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),

          Text(value, style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}
