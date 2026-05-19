import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/inbox_conversation.dart';

class InboxViewModel {

  final FirebaseFirestore _db =
      FirebaseFirestore.instance;

  final FirebaseAuth _auth =
      FirebaseAuth.instance;

  StreamSubscription? _subscription;

  List<InboxConversation> conversations = [];

  Function()? onUpdated;

  void startListening({
    required String role,
    required String businessId,
  }) {

    Query query;

    if (role == 'business') {

      query = _db
          .collection('businessChats')
          .where(
            'businessId',
            isEqualTo: businessId,
          )
          .orderBy(
            'lastMessageAt',
            descending: true,
          );

    } else {

      final uid =
          _auth.currentUser!.uid;

      query = _db
          .collection('businessChats')
          .where(
            'customerId',
            isEqualTo: uid,
          )
          .orderBy(
            'lastMessageAt',
            descending: true,
          );
    }

    _subscription =
        query.snapshots().listen((snapshot) {

      conversations = snapshot.docs
          .map(
            (doc) =>
                InboxConversation.fromDoc(doc),
          )
          .toList();

      onUpdated?.call();
    });
  }

  void stopListening() {
    _subscription?.cancel();
  }
}