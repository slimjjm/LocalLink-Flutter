import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/chat_message.dart';

class EnquiryChatViewModel {

  final FirebaseFirestore _db =
      FirebaseFirestore.instance;

  final FirebaseAuth _auth =
      FirebaseAuth.instance;

  StreamSubscription? _subscription;

  List<ChatMessage> messages = [];

  Function()? onUpdated;

  String get conversationId =>
      '${businessId}_$customerId';

  late String businessId;
  late String customerId;

  // ==================================================
  // START LISTENING
  // ==================================================

  void startListening({
    required String businessId,
    required String customerId,
  }) {

    this.businessId = businessId;
    this.customerId = customerId;

    _subscription = _db
        .collection('businessChats')
        .doc(conversationId)
        .collection('messages')
        .orderBy(
          'createdAt',
          descending: false,
        )
        .snapshots()
        .listen((snapshot) {

      messages = snapshot.docs
          .map(
            (doc) =>
                ChatMessage.fromDoc(doc),
          )
          .toList();

      onUpdated?.call();
    });

    _resetUnreadCount();
  }

  // ==================================================
  // RESET UNREAD
  // ==================================================

  Future<void> _resetUnreadCount() async {

    final uid =
        _auth.currentUser?.uid;

    if (uid == null) return;

    final conversationRef = _db
        .collection('businessChats')
        .doc(conversationId);

    final isCustomer =
        uid == customerId;

    await conversationRef.set(
      {

        if (isCustomer)
          'customerUnreadCount': 0,

        if (!isCustomer)
          'businessUnreadCount': 0,
      },
      SetOptions(merge: true),
    );
  }

  // ==================================================
  // FETCH BUSINESS NAME
  // ==================================================

  Future<String> _fetchBusinessName() async {

    final doc = await _db
        .collection('businesses')
        .doc(businessId)
        .get();

    final data =
        doc.data();

    return
        data?['businessName']
            ?? 'Business';
  }

  // ==================================================
  // FETCH CUSTOMER NAME
  // ==================================================

  Future<String> _fetchCustomerName() async {

    final doc = await _db
        .collection('users')
        .doc(customerId)
        .get();

    final data =
        doc.data();

    return
        data?['name']
            ?? 'Customer';
  }

  // ==================================================
  // SEND MESSAGE
  // ==================================================

  Future<void> sendMessage(
    String text,
  ) async {

    final trimmed = text.trim();

    if (trimmed.isEmpty) return;

    final uid =
        _auth.currentUser?.uid;

    if (uid == null) return;

    // ==================================================
    // ROLE
    // ==================================================

    final senderRole =
        uid == customerId
            ? 'customer'
            : 'business';

    // ==================================================
    // FETCH NAMES
    // ==================================================

    final businessName =
        await _fetchBusinessName();

    final customerName =
        await _fetchCustomerName();

    // ==================================================
    // CONVERSATION REF
    // ==================================================

    final conversationRef = _db
        .collection('businessChats')
        .doc(conversationId);

    // ==================================================
    // CREATE / UPDATE CONVERSATION
    // ==================================================

    await conversationRef.set(
      {

        'businessId':
            businessId,

        'customerId':
            customerId,

        'businessName':
            businessName,

        'customerName':
            customerName,

        'lastMessage':
            trimmed,

        'lastMessageAt':
            FieldValue.serverTimestamp(),

        'updatedAt':
            FieldValue.serverTimestamp(),

        'lastSenderId':
            uid,

        'lastSenderRole':
            senderRole,

        if (senderRole == 'customer')
          'businessUnreadCount':
              FieldValue.increment(1),

        if (senderRole == 'business')
          'customerUnreadCount':
              FieldValue.increment(1),
      },
      SetOptions(merge: true),
    );

    // ==================================================
    // CREATE MESSAGE
    // ==================================================

    await conversationRef
        .collection('messages')
        .add(
      {

        'senderId': uid,

        'senderRole':
            senderRole,

        'text': trimmed,

        'createdAt':
            FieldValue.serverTimestamp(),
      },
    );
  }

  // ==================================================
  // DISPOSE
  // ==================================================

  void dispose() {

    _subscription?.cancel();
  }
}