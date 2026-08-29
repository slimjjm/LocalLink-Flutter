import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/notification_router.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      return const Scaffold(body: Center(child: Text('Not logged in')));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('notifications')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text(
                "We couldn't load your notifications. Please try again.",
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  "You're all caught up. Booking updates, messages and activity alerts will appear here.",
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;

              final isRead = data['isRead'] ?? false;

              final type = data['type'] ?? '';

              IconData icon = Icons.notifications;

              if (type == 'follow') {
                icon = Icons.person_add;
              }

              if (type == 'new_message') {
                icon = Icons.chat_bubble;
              }

              if (type == 'community_alert' ||
                  type == 'community_help_match' ||
                  type == 'community_help_update' ||
                  type == 'community_help_resolved' ||
                  type == 'community_help_expiry' ||
                  type == 'community_help_response' ||
                  type == 'community_help_sighting' ||
                  type == 'community_help_message' ||
                  type == 'community_help_lookout') {
                icon = Icons.volunteer_activism;
              }

              if (type == 'new_booking' ||
                  type == 'last_minute_request' ||
                  type == 'booking_confirmed' ||
                  type == 'booking_cancelled' ||
                  type == 'booking_declined' ||
                  type == 'booking_expired' ||
                  type == 'payment_failed') {
                icon = Icons.calendar_today;
              }

              return ListTile(
                tileColor: isRead
                    ? null
                    : Colors.orange.withValues(alpha: 0.08),

                leading: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(icon),

                    if (!isRead)
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: Colors.orange,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),

                onTap: () async {
                  await docs[index].reference.update({'isRead': true});
                  if (!context.mounted) return;
                  await NotificationRouter.routeFromData(context, data);
                },

                title: Text(
                  data['title'] ?? 'Notification',
                  style: TextStyle(
                    fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                  ),
                ),

                subtitle: Text(data['body'] ?? ''),
              );
            },
          );
        },
      ),
    );
  }
}
