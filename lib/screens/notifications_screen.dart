import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NotificationsScreen extends StatelessWidget {
const NotificationsScreen({super.key});

@override
Widget build(BuildContext context) {
final uid =
FirebaseAuth.instance.currentUser?.uid;


if (uid == null) {
  return const Scaffold(
    body: Center(
      child: Text('Not logged in'),
    ),
  );
}

return Scaffold(
  appBar: AppBar(
    title: const Text(
      'Notifications',
    ),
  ),
  body: StreamBuilder<QuerySnapshot>(
    stream: FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .orderBy(
          'createdAt',
          descending: true,
        )
        .snapshots(),
    builder: (
      context,
      snapshot,
    ) {
      if (snapshot.hasError) {
        return Center(
          child: Text(
            'Error: ${snapshot.error}',
          ),
        );
      }

      if (!snapshot.hasData) {
        return const Center(
          child:
              CircularProgressIndicator(),
        );
      }

      final docs =
          snapshot.data!.docs;

      if (docs.isEmpty) {
        return const Center(
          child: Text(
            'No notifications yet',
          ),
        );
      }

      return ListView.builder(
        itemCount: docs.length,
        itemBuilder: (
          context,
          index,
        ) {
          final data =
              docs[index].data()
                  as Map<String, dynamic>;

          final isRead =
              data['isRead'] ?? false;

          final type =
              data['type'] ?? '';

          IconData icon =
              Icons.notifications;

          if (type == 'follow') {
            icon =
                Icons.person_add;
          }

          if (type ==
              'new_message') {
            icon =
                Icons.chat_bubble;
          }

          if (type ==
                  'booking_confirmed' ||
              type ==
                  'booking_cancelled') {
            icon =
                Icons.calendar_today;
          }

          return ListTile(
            tileColor:
                isRead
                    ? null
                    : Colors.orange
                        .withOpacity(
                        0.08,
                      ),

            leading:
                Icon(icon),

            onTap: () async {
              await docs[index]
                  .reference
                  .update({
                'isRead': true,
              });
            },

            title: Text(
              data['title'] ??
                  'Notification',
              style:
                  TextStyle(
                fontWeight:
                    isRead
                        ? FontWeight
                            .normal
                        : FontWeight
                            .bold,
              ),
            ),

            subtitle: Text(
              data['body'] ??
                  '',
            ),
          );
        },
      );
    },
  ),
);

}
}
