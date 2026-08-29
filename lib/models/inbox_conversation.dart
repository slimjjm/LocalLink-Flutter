import 'package:cloud_firestore/cloud_firestore.dart';

class InboxConversation {
  final String id;

  final String businessId;
  final String businessOwnerId;
  final String customerId;
  final String bookingId;
  final String currentBookingServiceName;

  final String customerName;
  final String businessName;
  final String originatingServiceName;
  final String serviceName;
  final String conversationType;
  final String conversationStatus;
  final String communityHelpOwnerId;
  final String communityHelpResponderId;

  final String lastMessage;

  final Timestamp? lastMessageAt;

  final int businessUnreadCount;
  final int customerUnreadCount;

  InboxConversation({
    required this.id,
    required this.businessId,
    required this.businessOwnerId,
    required this.customerId,
    required this.bookingId,
    required this.currentBookingServiceName,
    required this.customerName,
    required this.businessName,
    required this.originatingServiceName,
    required this.serviceName,
    required this.conversationType,
    required this.conversationStatus,
    required this.communityHelpOwnerId,
    required this.communityHelpResponderId,
    required this.lastMessage,
    required this.lastMessageAt,
    required this.businessUnreadCount,
    required this.customerUnreadCount,
  });

  factory InboxConversation.fromDoc(DocumentSnapshot doc) {
    final rawData = doc.data();
    final data = rawData is Map<String, dynamic>
        ? rawData
        : rawData is Map
        ? Map<String, dynamic>.from(rawData)
        : <String, dynamic>{};
    return InboxConversation.fromMap(doc.id, data);
  }

  factory InboxConversation.fromMap(String id, Map<String, dynamic> data) {
    return InboxConversation(
      id: id,

      businessId: _string(data['businessId']),

      businessOwnerId: _string(
        data['businessOwnerId'] ?? data['ownerId'] ?? data['ownerUid'],
      ),

      customerId: _string(data['customerId']),

      bookingId: _string(data['currentBookingId'] ?? data['bookingId']),

      currentBookingServiceName: _string(
        data['currentBookingServiceName'] ?? data['serviceName'],
        fallback: 'Service',
      ),

      customerName: _string(data['customerName'], fallback: 'Customer'),

      businessName: _string(data['businessName'], fallback: 'Business'),

      originatingServiceName: _string(
        data['originatingServiceName'] ?? data['serviceName'],
        fallback: 'Service',
      ),

      serviceName: _resolveServiceName(data),

      conversationType: _string(data['conversationType']),

      conversationStatus: _string(
        data['conversationStatus'],
        fallback: 'enquiry',
      ),

      communityHelpOwnerId: _string(
        data['communityHelpOwnerId'] ?? data['businessOwnerId'],
      ),

      communityHelpResponderId: _string(
        data['communityHelpResponderId'] ?? data['customerId'],
      ),

      lastMessage: _string(data['lastMessage']),

      lastMessageAt: _timestamp(data['lastMessageAt']),

      businessUnreadCount: _int(
        data['unreadBusinessCount'] ?? data['businessUnreadCount'],
      ),

      customerUnreadCount: _int(
        data['unreadCustomerCount'] ?? data['customerUnreadCount'],
      ),
    );
  }

  bool get isCommunityHelp =>
      conversationType == 'community_help' ||
      conversationStatus == 'community_help';

  bool isCommunityOwner(String? uid) {
    return uid != null &&
        uid.isNotEmpty &&
        (uid == communityHelpOwnerId || uid == businessOwnerId);
  }

  String displayNameFor(String? uid, String role) {
    if (isCommunityHelp) {
      return isCommunityOwner(uid) ? customerName : businessName;
    }

    return role == 'business' ? customerName : businessName;
  }

  String viewerTypeFor(String? uid, String role) {
    if (isCommunityHelp) {
      return isCommunityOwner(uid) ? 'business' : 'customer';
    }

    return role;
  }

  int unreadCountFor(String? uid, String role) {
    final viewerType = viewerTypeFor(uid, role);
    return viewerType == 'business' ? businessUnreadCount : customerUnreadCount;
  }

  static String _resolveServiceName(Map<String, dynamic> data) {
    if (_string(data['conversationType']) == 'community_help') {
      return _string(
        data['currentBookingServiceName'] ?? data['serviceName'],
        fallback: 'Community Help',
      );
    }

    if (_string(data['currentBookingId']).isNotEmpty) {
      return _string(
        data['currentBookingServiceName'] ?? data['serviceName'],
        fallback: 'Service',
      );
    }

    return _string(
      data['serviceName'] ?? data['originatingServiceName'],
      fallback: 'Enquiry',
    );
  }

  static String _string(Object? value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static int _int(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static Timestamp? _timestamp(Object? value) {
    return value is Timestamp ? value : null;
  }
}
