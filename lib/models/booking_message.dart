import 'package:cloud_firestore/cloud_firestore.dart';

class BookingMessage {
  final String id;
  final String senderId;
  final String senderType;
  final String text;
  final Timestamp? timestamp;
  final bool read;
  final bool edited;
  final bool deleted;
  final Timestamp? editedAt;
  final Timestamp? deletedAt;
  final List<Map<String, dynamic>> attachments;

  const BookingMessage({
    required this.id,
    required this.senderId,
    required this.senderType,
    required this.text,
    required this.timestamp,
    required this.read,
    required this.edited,
    required this.deleted,
    required this.editedAt,
    required this.deletedAt,
    this.attachments = const [],
  });

  factory BookingMessage.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};

    return BookingMessage(
      id: doc.id,
      senderId: data['senderId'] ?? '',
      senderType: data['senderType'] ?? '',
      text: data['text'] ?? '',
      timestamp: data['timestamp'],
      read: data['read'] == true,
      edited: data['edited'] == true,
      deleted: data['deleted'] == true,
      editedAt: data['editedAt'],
      deletedAt: data['deletedAt'],
      attachments: (data['attachments'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(),
    );
  }

  bool get canStillEdit {
    final sentAt = timestamp?.toDate();
    if (sentAt == null || deleted) return false;

    return DateTime.now().difference(sentAt).inMinutes < 5;
  }
}
