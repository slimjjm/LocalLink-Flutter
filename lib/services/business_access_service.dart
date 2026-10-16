import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class BusinessAccessService {
  BusinessAccessService._();

  static Future<DocumentSnapshot<Map<String, dynamic>>?>
  loadLinkedBusiness() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null || user.isAnonymous) return null;

    final firestore = FirebaseFirestore.instance;
    final directFields = [
      'ownerId',
      'businessOwnerId',
      'ownerUid',
      'claimedBy',
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

    final createdSnapshot = await firestore
        .collection('businesses')
        .where('createdBy', isEqualTo: user.uid)
        .limit(5)
        .get();

    for (final doc in createdSnapshot.docs) {
      if (_creatorCanManageBusiness(doc.data(), user.uid)) {
        return doc;
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

  static Future<DocumentSnapshot<Map<String, dynamic>>?>
  loadLinkedChallengeHostBusiness() async {
    final snapshot = await loadLinkedBusiness();
    final data = snapshot?.data();
    if (snapshot == null || data == null) return null;

    return canHostCommunityChallengeData(data) ? snapshot : null;
  }

  static Future<bool> canPostForBusiness({
    required String businessId,
    required Map<String, dynamic> businessData,
  }) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null || user.isAnonymous) return false;

    if (_valueMatchesUser(businessData['ownerId'], user.uid) ||
        _valueMatchesUser(businessData['businessOwnerId'], user.uid) ||
        _valueMatchesUser(businessData['ownerUid'], user.uid) ||
        _valueMatchesUser(businessData['claimedBy'], user.uid) ||
        _listContainsUser(businessData['ownerIds'], user.uid) ||
        _listContainsUser(businessData['adminUserIds'], user.uid)) {
      return true;
    }

    if (_creatorCanManageBusiness(businessData, user.uid)) {
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

  static bool canHostCommunityChallengeData(Map<String, dynamic> businessData) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return false;

    final claimed =
        businessData['isClaimed'] == true ||
        businessData['listingOwnershipStatus']?.toString() == 'claimed' ||
        businessData['claimStatus']?.toString() == 'approved';
    if (!claimed) return false;

    return _valueMatchesUser(businessData['ownerId'], user.uid) ||
        _valueMatchesUser(businessData['businessOwnerId'], user.uid) ||
        _valueMatchesUser(businessData['ownerUid'], user.uid) ||
        _valueMatchesUser(businessData['claimedBy'], user.uid) ||
        _listContainsUser(businessData['ownerIds'], user.uid) ||
        _listContainsUser(businessData['adminUserIds'], user.uid) ||
        _creatorCanManageBusiness(businessData, user.uid);
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

  static bool _creatorCanManageBusiness(Map<String, dynamic> data, String uid) {
    if (!_valueMatchesUser(data['createdBy'], uid)) {
      return false;
    }

    final isClaimed =
        data['isClaimed'] == true ||
        data['listingOwnershipStatus']?.toString() == 'claimed';
    final moderatorSeeded = data['createdByModerator'] == true;

    return !(moderatorSeeded && isClaimed);
  }
}
