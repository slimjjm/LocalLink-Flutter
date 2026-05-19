import 'package:cloud_firestore/cloud_firestore.dart';

class ChatMessage {

  final String id;

  final String senderId;
  final String senderRole;

  final String text;

  final Timestamp? createdAt;

  ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderRole,
    required this.text,
    required this.createdAt,
  });

  factory ChatMessage.fromDoc(
    DocumentSnapshot doc,
  ) {

    final data =
        doc.data() as Map<String, dynamic>;

    return ChatMessage(

      id: doc.id,

      senderId:
          data['senderId'] ?? '',

      senderRole:
          data['senderRole'] ?? '',

      text:
          data['text'] ?? '',

      createdAt:
          data['createdAt'],
    );
  }
}