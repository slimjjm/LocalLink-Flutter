import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'profile_screen.dart';
import 'opportunity_detail_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    super.key,
  });

  @override
  State<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState
    extends State<NotificationsScreen> {

        @override
void initState() {
  super.initState();
  _markAllAsRead();
}

Future<void> _markAllAsRead() async {
  final uid =
      FirebaseAuth.instance.currentUser?.uid;

  if (uid == null) return;

  final unread =
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('notifications')
          .where(
            'isRead',
            isEqualTo: false,
          )
          .get();

  final batch =
      FirebaseFirestore.instance.batch();

  for (final doc in unread.docs) {
    batch.update(
      doc.reference,
      {
        'isRead': true,
      },
    );
  }

  await batch.commit();
}

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
          decoration:
              const BoxDecoration(
            color: Colors.orange,
            shape: BoxShape.circle,
          ),
        ),
      ),
  ],
),

          onTap: () async {

  await docs[index]
      .reference
      .update({
    'isRead': true,
  });

  final type =
      data['type'];
if (type == 'review') {

  final reviewerId =
      data['reviewerId'];

  if (reviewerId == null) return;

  final userDoc =
      await FirebaseFirestore.instance
          .collection('users')
          .doc(reviewerId)
          .get();

  if (!userDoc.exists) return;

  final userData =
      userDoc.data()!;

  if (!context.mounted) return;

  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) =>
          ProfileScreen(
        userId: reviewerId,
        userName:
            userData['userName'] ??
            'User',
        photoUrl:
            userData['photoUrl'],
      ),
    ),
  );
}

  else if (type == 'follow') {

    final followerId =
        data['followerId'];

    if (followerId == null) return;

    final userDoc =
        await FirebaseFirestore.instance
            .collection('users')
            .doc(followerId)
            .get();

    if (!userDoc.exists) return;

    final userData =
        userDoc.data()!;

    if (!context.mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ProfileScreen(
          userId:
              followerId,
          userName:
              userData['userName'] ??
              'User',
          photoUrl:
              userData['photoUrl'],
        ),
      ),
    );
  }

  if (type ==
          'opportunity_join' ||
      type ==
          'opportunity_comment') {

    final opportunityId =
        data['opportunityId'];

    if (opportunityId == null) {
      return;
    }

    final doc =
        await FirebaseFirestore.instance
            .collection(
              'opportunities',
            )
            .doc(
              opportunityId,
            )
            .get();

    if (!doc.exists) return;

    if (!context.mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            OpportunityDetailScreen(
          opportunityId:
              opportunityId,
          opportunity:
              doc.data()!,
        ),
      ),
    );
  }
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
