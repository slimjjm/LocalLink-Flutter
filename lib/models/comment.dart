

import 'package:cloud_firestore/cloud_firestore.dart';

class Comment {
  final String id;
  final String userId;
  final String userName;
  final String text;
  final Timestamp createdAt;

  Comment({
    required this.id,
    required this.userId,
    required this.userName,
    required this.text,
    required this.createdAt,
  });

  factory Comment.fromFirestore(
    String id,
    Map<String, dynamic> data,
  ) {
    return Comment(
      id: id,
      userId: data['userId'] ?? '',
      userName: data['userName'] ?? '',
      text: data['text'] ?? '',
      createdAt:
          data['createdAt'] ?? Timestamp.now(),
    );
  }
}