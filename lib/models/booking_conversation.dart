import 'package:cloud_firestore/cloud_firestore.dart';

class BookingConversation {
  final String id;
  final String bookingId;
  final String customerId;
  final String businessId;
  final String businessOwnerId;
  final String serviceId;
  final String originatingServiceId;
  final String originatingServiceName;
  final String currentBookingId;
  final String currentBookingServiceName;
  final String currentBookingStatus;
  final String businessName;
  final String customerName;
  final String serviceName;
  final String serviceImageUrl;
  final String conversationStatus;
  final String bookingStatus;
  final Timestamp? bookingStartAt;
  final String lastMessage;
  final Timestamp? lastMessageAt;
  final int unreadCustomerCount;
  final int unreadBusinessCount;
  final bool archived;
  final bool customerHasMessaged;
  final String quotationStatus;
  final String acceptedQuotationId;
  final List<String> quotationIds;

  const BookingConversation({
    required this.id,
    required this.bookingId,
    required this.customerId,
    required this.businessId,
    required this.businessOwnerId,
    required this.serviceId,
    required this.originatingServiceId,
    required this.originatingServiceName,
    required this.currentBookingId,
    required this.currentBookingServiceName,
    required this.currentBookingStatus,
    required this.businessName,
    required this.customerName,
    required this.serviceName,
    required this.serviceImageUrl,
    required this.conversationStatus,
    required this.bookingStatus,
    required this.bookingStartAt,
    required this.lastMessage,
    required this.lastMessageAt,
    required this.unreadCustomerCount,
    required this.unreadBusinessCount,
    required this.archived,
    required this.customerHasMessaged,
    required this.quotationStatus,
    required this.acceptedQuotationId,
    required this.quotationIds,
  });

  factory BookingConversation.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};

    return BookingConversation(
      id: doc.id,
      bookingId: data['bookingId'] ?? doc.id,
      customerId: data['customerId'] ?? '',
      businessId: data['businessId'] ?? '',
      businessOwnerId: data['businessOwnerId'] ?? '',
      serviceId: data['serviceId'] ?? '',
      originatingServiceId:
          data['originatingServiceId'] ?? data['serviceId'] ?? '',
      originatingServiceName:
          data['originatingServiceName'] ?? data['serviceName'] ?? 'Service',
      currentBookingId: data['currentBookingId'] ?? data['bookingId'] ?? '',
      currentBookingServiceName:
          data['currentBookingServiceName'] ?? data['serviceName'] ?? 'Service',
      currentBookingStatus:
          data['currentBookingStatus'] ?? data['bookingStatus'] ?? 'unknown',
      businessName: data['businessName'] ?? 'Business',
      customerName: data['customerName'] ?? 'Customer',
      serviceName: data['serviceName'] ?? 'Service',
      serviceImageUrl: data['serviceImageUrl'] ?? '',
      conversationStatus: data['conversationStatus'] ?? 'enquiry',
      bookingStatus: data['bookingStatus'] ?? 'unknown',
      bookingStartAt:
          data['bookingStartAt'] ?? data['startDate'] ?? data['startTime'],
      lastMessage: data['lastMessage'] ?? '',
      lastMessageAt: data['lastMessageAt'],
      unreadCustomerCount: (data['unreadCustomerCount'] as num?)?.toInt() ?? 0,
      unreadBusinessCount: (data['unreadBusinessCount'] as num?)?.toInt() ?? 0,
      archived: data['archived'] == true,
      customerHasMessaged: data['customerHasMessaged'] == true,
      quotationStatus: data['quotationStatus'] ?? 'none',
      acceptedQuotationId: data['acceptedQuotationId'] ?? '',
      quotationIds: List<String>.from(data['quotationIds'] ?? const []),
    );
  }

  int unreadCountFor(String viewerType) {
    return viewerType == 'business' ? unreadBusinessCount : unreadCustomerCount;
  }

  bool get isCommunityHelp =>
      conversationStatus == 'community_help' || serviceName == 'Community Help';
}
