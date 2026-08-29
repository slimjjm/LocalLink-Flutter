import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'profile_screen.dart';

class FollowersScreen extends StatelessWidget {
  final String userId;

  const FollowersScreen({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Followers')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('followers')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return const Center(child: Text('No followers yet'));
          }

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;

              return ListTile(
                leading: data['photoUrl'] != null
                    ? CircleAvatar(
                        backgroundImage: NetworkImage(data['photoUrl']),
                        onBackgroundImageError: (exception, stackTrace) {},
                      )
                    : const CircleAvatar(child: Icon(Icons.person)),

                title: Text(data['userName'] ?? 'User'),

                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProfileScreen(
                        userId: data['userId'],
                        userName: data['userName'] ?? 'User',
                        photoUrl: data['photoUrl'],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
