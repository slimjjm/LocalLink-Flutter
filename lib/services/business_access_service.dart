import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class BusinessAccessService {
  BusinessAccessService._();

  static Future<DocumentSnapshot<Map<String, dynamic>>?>
  loadLinkedBusiness() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return null;

    final firestore = FirebaseFirestore.instance;
    final directFields = [
      'ownerId',
      'businessOwnerId',
      'ownerUid',
      'claimedBy',
      'createdBy',
    ];

    for (final field in directFields) {
      final snapshot = await firestore
          .collection('businesses')
          .where(field, isEqualTo: user.uid)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        return snapshot.docs.first;
      }
    }

    try {
      final staffSnapshot = await firestore
          .collectionGroup('staff')
          .where(FieldPath.documentId, isEqualTo: user.uid)
          .where('isActive', isEqualTo: true)
          .limit(1)
          .get();

      if (staffSnapshot.docs.isEmpty) return null;

      final businessRef = staffSnapshot.docs.first.reference.parent.parent;
      return businessRef?.get();
    } on FirebaseException {
      return null;
    }
  }

  static Future<bool> canPostForBusiness({
    required String businessId,
    required Map<String, dynamic> businessData,
  }) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return false;

    if (_valueMatchesUser(businessData['ownerId'], user.uid) ||
        _valueMatchesUser(businessData['businessOwnerId'], user.uid) ||
        _valueMatchesUser(businessData['ownerUid'], user.uid) ||
        _valueMatchesUser(businessData['claimedBy'], user.uid) ||
        _valueMatchesUser(businessData['createdBy'], user.uid) ||
        _listContainsUser(businessData['ownerIds'], user.uid) ||
        _listContainsUser(businessData['adminUserIds'], user.uid)) {
      return true;
    }

    final staffDoc = await FirebaseFirestore.instance
        .collection('businesses')
        .doc(businessId)
        .collection('staff')
        .doc(user.uid)
        .get();

    final staffData = staffDoc.data();
    return staffDoc.exists && staffData?['isActive'] == true;
  }

  static bool _valueMatchesUser(Object? value, String uid) {
    return value?.toString() == uid;
  }

  static bool _listContainsUser(Object? value, String uid) {
    if (value is Iterable) {
      return value.map((item) => item.toString()).contains(uid);
    }

    return false;
  }
}
