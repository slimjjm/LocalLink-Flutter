import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CustomerUnreadViewModel {

  final FirebaseFirestore _db =
      FirebaseFirestore.instance;

  final FirebaseAuth _auth =
      FirebaseAuth.instance;

  StreamSubscription? _subscription;

  int unreadCount = 0;

  Function()? onUpdated;

  void startListening() {

    final uid =
        _auth.currentUser?.uid;

    if (uid == null) return;

    _subscription = _db
        .collection('businessChats')
        .where(
          'customerId',
          isEqualTo: uid,
        )
        .snapshots()
        .listen((snapshot) {

      int total = 0;

      for (final doc in snapshot.docs) {

        final data = doc.data();

        total +=
            (data['customerUnreadCount'] ?? 0)
                as int;
      }

      unreadCount = total;
      print('CUSTOMER UNREAD: $unreadCount');

      onUpdated?.call();
    });
  }

  void dispose() {

    _subscription?.cancel();
  }
}