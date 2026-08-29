import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink_flutter/models/inbox_conversation.dart';

void main() {
  group('InboxConversation', () {
    test('parses canonical service enquiry conversations', () {
      final lastMessageAt = Timestamp.fromDate(DateTime(2026, 8, 28, 10));

      final conversation = InboxConversation.fromMap('conversation-1', {
        'conversationType': 'service_enquiry',
        'conversationStatus': 'enquiry',
        'customerId': 'customer-1',
        'businessId': 'business-1',
        'businessOwnerId': 'owner-1',
        'participants': ['customer-1', 'owner-1'],
        'serviceId': 'service-1',
        'serviceName': 'Interior Painting',
        'originatingServiceName': 'Interior Painting',
        'bookingId': '',
        'staffId': '',
        'lastMessage': 'Could you quote for a hallway?',
        'lastMessageAt': lastMessageAt,
        'unreadBusinessCount': 1,
        'unreadCustomerCount': 0,
      });

      expect(conversation.id, 'conversation-1');
      expect(conversation.businessId, 'business-1');
      expect(conversation.businessOwnerId, 'owner-1');
      expect(conversation.customerId, 'customer-1');
      expect(conversation.bookingId, isEmpty);
      expect(conversation.serviceName, 'Interior Painting');
      expect(conversation.lastMessageAt, lastMessageAt);
      expect(conversation.businessUnreadCount, 1);
      expect(conversation.customerUnreadCount, 0);
    });

    test('parses legacy enquiry fields without throwing', () {
      final conversation = InboxConversation.fromMap('legacy-1', {
        'conversationStatus': 'enquiry',
        'customerId': 'customer-1',
        'businessId': 'business-1',
        'ownerId': 'owner-1',
        'participantIds': ['customer-1', 'owner-1'],
        'originatingServiceName': 'Exterior Painting Quote',
        'lastMessage': 'Can I ask about Friday?',
        'lastMessageAt': 'not-a-timestamp',
        'businessUnreadCount': '2',
        'customerUnreadCount': '0',
      });

      expect(conversation.businessOwnerId, 'owner-1');
      expect(conversation.serviceName, 'Exterior Painting Quote');
      expect(conversation.lastMessageAt, isNull);
      expect(conversation.businessUnreadCount, 2);
      expect(conversation.customerUnreadCount, 0);
    });
  });
}
