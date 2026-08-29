import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../models/booking_conversation.dart';
import '../models/booking_message.dart';
import '../config/firestore_collections.dart';

class BookingMessagingService {
  BookingMessagingService({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _functions =
           functions ?? FirebaseFunctions.instanceFor(region: functionsRegion);

  static const functionsRegion = 'us-central1';

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  DocumentReference<Map<String, dynamic>> conversationRef(
    String conversationId,
  ) {
    return _firestore
        .collection(FirestoreCollections.conversations)
        .doc(conversationId);
  }

  Stream<BookingConversation?> watchConversation(String conversationId) {
    return conversationRef(conversationId).snapshots().map((snapshot) {
      if (!snapshot.exists) {
        return null;
      }

      return BookingConversation.fromDoc(snapshot);
    });
  }

  Stream<List<BookingMessage>> watchMessages(String conversationId) {
    return conversationRef(conversationId)
        .collection(FirestoreCollections.messages)
        .orderBy('timestamp', descending: false)
        .limitToLast(80)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(BookingMessage.fromDoc).toList());
  }

  Future<String> ensureBookingConversation(String bookingId) async {
    final callable = _functions.httpsCallable('ensureBookingConversation');

    final result = await callable.call<Map<String, dynamic>>({
      'bookingId': bookingId,
    });

    return result.data['conversationId'] ?? bookingId;
  }

  Future<String> ensureConversationAccess(String conversationId) async {
    final callable = _functions.httpsCallable('ensureConversationAccess');

    final result = await callable.call<Map<String, dynamic>>({
      'conversationId': conversationId,
    });

    return result.data['conversationId'] ?? conversationId;
  }

  Future<String> createServiceEnquiry({
    required String businessId,
    required String serviceId,
    required String text,
  }) async {
    final callable = _functions.httpsCallable('createServiceEnquiry');

    if (kDebugMode) {
      debugPrint(
        'BookingMessagingService.createServiceEnquiry start '
        'region=$functionsRegion businessId=$businessId '
        'serviceId=$serviceId textLength=${text.length}',
      );
    }

    try {
      final result = await callable.call<Map<String, dynamic>>({
        'businessId': businessId,
        'serviceId': serviceId,
        'text': text,
      });

      final conversationId = result.data['conversationId'];
      if (kDebugMode) {
        debugPrint(
          'BookingMessagingService.createServiceEnquiry success '
          'conversationId=$conversationId',
        );
      }

      return conversationId;
    } on FirebaseFunctionsException catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint(
          'BookingMessagingService.createServiceEnquiry FirebaseFunctionsException '
          'code=${error.code} message=${error.message} details=${error.details}',
        );
        debugPrintStack(stackTrace: stackTrace);
      }
      rethrow;
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint(
          'BookingMessagingService.createServiceEnquiry failed: $error',
        );
        debugPrintStack(stackTrace: stackTrace);
      }
      rethrow;
    }
  }

  Future<String> createCommunityHelpConversation({
    required String postId,
    required String text,
    String? sightingPhotoUrl,
  }) async {
    final callable = _functions.httpsCallable(
      'createCommunityHelpConversation',
    );

    final result = await callable.call<Map<String, dynamic>>({
      'postId': postId,
      'text': text,
      if (sightingPhotoUrl != null && sightingPhotoUrl.trim().isNotEmpty)
        'sightingPhotoUrl': sightingPhotoUrl.trim(),
    });

    return result.data['conversationId'];
  }

  Future<void> followCommunityHelpPost(String postId) async {
    final callable = _functions.httpsCallable('followCommunityHelpPost');

    await callable.call({'postId': postId});
  }

  Future<void> unfollowCommunityHelpPost(String postId) async {
    final callable = _functions.httpsCallable('unfollowCommunityHelpPost');

    await callable.call({'postId': postId});
  }

  Future<void> publishCommunityHelpUpdate({
    required String postId,
    required String text,
  }) async {
    final callable = _functions.httpsCallable('publishCommunityHelpUpdate');

    await callable.call({'postId': postId, 'text': text});
  }

  Future<void> sendMessage({
    required String conversationId,
    required String text,
  }) async {
    final callable = _functions.httpsCallable('sendBookingMessage');

    await callable.call({'conversationId': conversationId, 'text': text});
  }

  Future<void> markRead(String conversationId) async {
    final callable = _functions.httpsCallable('markBookingConversationRead');

    await callable.call({'conversationId': conversationId});
  }

  Future<void> editMessage({
    required String conversationId,
    required String messageId,
    required String text,
  }) async {
    final callable = _functions.httpsCallable('editBookingMessage');

    await callable.call({
      'conversationId': conversationId,
      'messageId': messageId,
      'text': text,
    });
  }

  Future<void> deleteMessage({
    required String conversationId,
    required String messageId,
  }) async {
    final callable = _functions.httpsCallable('deleteBookingMessage');

    await callable.call({
      'conversationId': conversationId,
      'messageId': messageId,
    });
  }
}
