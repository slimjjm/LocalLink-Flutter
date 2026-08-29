import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../config/firestore_collections.dart';
import '../models/inbox_conversation.dart';
import '../services/business_access_service.dart';

class InboxViewModel {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  final FirebaseAuth _auth = FirebaseAuth.instance;

  final List<StreamSubscription<QuerySnapshot>> _subscriptions = [];

  final List<Map<String, InboxConversation>> _conversationBuckets = [];

  int _pendingInitialLoads = 0;

  List<InboxConversation> conversations = [];

  bool isLoading = true;

  String? errorMessage;

  Function()? onUpdated;

  void startListening({required String role, required String businessId}) {
    stopListening();
    isLoading = true;
    errorMessage = null;
    conversations = [];

    final user = _auth.currentUser;

    if (user == null) {
      isLoading = false;
      errorMessage = 'Please sign in to view your messages.';
      onUpdated?.call();
      return;
    }

    if (role == 'all') {
      _listenToCustomerInbox(user.uid, businessId.trim());
      _listenToCommunityHelpInbox(user.uid, businessId.trim());
      BusinessAccessService.loadLinkedBusiness()
          .then((business) {
            final resolvedBusinessId = business?.exists == true
                ? business!.id
                : '';
            if (resolvedBusinessId.isEmpty) return;

            _listenToBusinessInbox(
              user.uid,
              resolvedBusinessId,
              isSupplemental: true,
            );
          })
          .catchError((error, stackTrace) {
            _debugLog(
              'Linked business lookup failed for universal inbox.',
              error,
              stackTrace is StackTrace ? stackTrace : null,
              authenticatedUid: user.uid,
              selectedBusinessId: businessId.trim(),
              queryName: 'linked business lookup',
            );
          });
      return;
    }

    if (role == 'business') {
      final resolvedBusinessId = businessId.trim();

      _listenToBusinessInbox(user.uid, resolvedBusinessId);
    } else {
      _listenToCustomerInbox(user.uid, businessId.trim());
    }

    _listenToCommunityHelpInbox(user.uid, businessId.trim());
  }

  void _listenToCustomerInbox(String uid, String selectedBusinessId) {
    _listenToQuery(
      _db
          .collection(FirestoreCollections.conversations)
          .where('customerId', isEqualTo: uid)
          .orderBy('lastMessageAt', descending: true),
      queryName: 'customerId inbox',
      authenticatedUid: uid,
      selectedBusinessId: selectedBusinessId,
    );
  }

  void _listenToBusinessInbox(
    String uid,
    String selectedBusinessId, {
    bool isSupplemental = false,
  }) {
    _listenToQuery(
      _db
          .collection(FirestoreCollections.conversations)
          .where('businessOwnerId', isEqualTo: uid)
          .orderBy('lastMessageAt', descending: true),
      queryName: 'businessOwnerId inbox',
      authenticatedUid: uid,
      selectedBusinessId: selectedBusinessId,
      isSupplemental: isSupplemental,
      includeConversation: selectedBusinessId.isEmpty
          ? null
          : (conversation) => conversation.businessId == selectedBusinessId,
    );
  }

  void _listenToCommunityHelpInbox(String uid, String selectedBusinessId) {
    _listenToQuery(
      _db
          .collection(FirestoreCollections.conversations)
          .where('conversationType', isEqualTo: 'community_help')
          .where('communityHelpParticipantIds', arrayContains: uid),
      queryName: 'communityHelpParticipantIds inbox',
      authenticatedUid: uid,
      selectedBusinessId: selectedBusinessId,
      isSupplemental: true,
    );
  }

  void _listenToQuery(
    Query query, {
    required String queryName,
    required String authenticatedUid,
    required String selectedBusinessId,
    bool isSupplemental = false,
    bool Function(InboxConversation conversation)? includeConversation,
  }) {
    final bucket = <String, InboxConversation>{};
    var hasLoaded = false;

    _conversationBuckets.add(bucket);
    _pendingInitialLoads += 1;

    final subscription = query.snapshots().listen(
      (snapshot) {
        bucket.clear();
        for (final doc in snapshot.docs) {
          try {
            final conversation = InboxConversation.fromDoc(doc);
            if (includeConversation == null ||
                includeConversation(conversation)) {
              bucket[doc.id] = conversation;
            }
          } catch (error, stackTrace) {
            _debugLog(
              'Skipping malformed inbox conversation ${doc.id} from $queryName.',
              error,
              stackTrace,
              authenticatedUid: authenticatedUid,
              selectedBusinessId: selectedBusinessId,
              queryName: queryName,
            );
          }
        }

        if (!hasLoaded) {
          hasLoaded = true;
          _pendingInitialLoads -= 1;
        }

        _publishMergedConversations();
        isLoading = _pendingInitialLoads > 0;
        errorMessage = null;
        onUpdated?.call();
      },
      onError: (error, stackTrace) {
        _debugLog(
          'Inbox conversation query failed.',
          error,
          stackTrace,
          authenticatedUid: authenticatedUid,
          selectedBusinessId: selectedBusinessId,
          queryName: queryName,
        );
        if (isSupplemental) {
          if (!hasLoaded) {
            hasLoaded = true;
            _pendingInitialLoads -= 1;
          }
          bucket.clear();
          _publishMergedConversations();
          isLoading = _pendingInitialLoads > 0;
          onUpdated?.call();
          return;
        }
        conversations = [];
        isLoading = false;
        errorMessage = 'We could not load your messages. Please try again.';
        onUpdated?.call();
      },
    );

    _subscriptions.add(subscription);
  }

  void _publishMergedConversations() {
    final merged = <String, InboxConversation>{};

    for (final bucket in _conversationBuckets) {
      merged.addAll(bucket);
    }

    conversations = merged.values.toList()
      ..sort((a, b) {
        final aMillis = a.lastMessageAt?.millisecondsSinceEpoch ?? 0;
        final bMillis = b.lastMessageAt?.millisecondsSinceEpoch ?? 0;
        return bMillis.compareTo(aMillis);
      });
  }

  void stopListening() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    _conversationBuckets.clear();
    _pendingInitialLoads = 0;
  }

  void _debugLog(
    String message,
    Object? error,
    StackTrace? stackTrace, {
    required String authenticatedUid,
    required String selectedBusinessId,
    required String queryName,
  }) {
    if (!kDebugMode) return;

    debugPrint(
      'InboxViewModel: $message query=$queryName '
      'uid=$authenticatedUid selectedBusinessId=$selectedBusinessId',
    );
    if (error is FirebaseException) {
      debugPrint(
        'InboxViewModel FirebaseException code=${error.code} plugin=${error.plugin} message=${error.message}',
      );
    } else if (error != null) {
      debugPrint('InboxViewModel error=$error');
    }
    if (stackTrace != null) {
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}
