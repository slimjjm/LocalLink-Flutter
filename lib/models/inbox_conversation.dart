import 'package:cloud_firestore/cloud_firestore.dart';

class InboxConversation {

  final String id;

  final String businessId;
  final String customerId;

  final String customerName;
  final String businessName;

  final String lastMessage;

  final Timestamp? lastMessageAt;

  final int businessUnreadCount;
  final int customerUnreadCount;

  InboxConversation({
    required this.id,
    required this.businessId,
    required this.customerId,
    required this.customerName,
    required this.businessName,
    required this.lastMessage,
    required this.lastMessageAt,
    required this.businessUnreadCount,
    required this.customerUnreadCount,
  });

  factory InboxConversation.fromDoc(
    DocumentSnapshot doc,
  ) {

    final data =
        doc.data() as Map<String, dynamic>;

    return InboxConversation(

      id: doc.id,

      businessId:
          data['businessId'] ?? '',

      customerId:
          data['customerId'] ?? '',

      customerName:
          data['customerName'] ?? 'Customer',

      businessName:
          data['businessName'] ?? 'Business',

      lastMessage:
          data['lastMessage'] ?? '',

      lastMessageAt:
          data['lastMessageAt'],

      businessUnreadCount:
          data['businessUnreadCount'] ?? 0,

      customerUnreadCount:
          data['customerUnreadCount'] ?? 0,
    );
  }
}