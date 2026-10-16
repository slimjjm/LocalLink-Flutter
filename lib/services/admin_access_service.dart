import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AdminAccessService {
  static const approvedAdminEmails = {
    'jae19882011@hotmail.co.uk',
    'founder@locallinkapp.co.uk',
  };

  static bool hasEffectiveAdminFlag(
    Map<String, dynamic>? publicData,
    Map<String, dynamic>? accessData,
  ) => hasAdminProfileFlag(accessData ?? publicData);
  AdminAccessService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  static bool hasAdminProfileFlag(Map<String, dynamic>? userData) {
    return userData?['isAdmin'] == true;
  }

  Future<bool> isCurrentUserAdmin() async {
    final user = _auth.currentUser;

    if (user == null) {
      return false;
    }

    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    final userData = userDoc.data();
    final accessDoc = await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('private')
        .doc('access')
        .get();

    final hasAdminFlag = hasEffectiveAdminFlag(
      userData,
      accessDoc.exists ? accessDoc.data() ?? {} : null,
    );
    if (hasAdminFlag) {
      return true;
    }

    final email = user.email?.trim().toLowerCase();

    if (email == null || !approvedAdminEmails.contains(email)) {
      return false;
    }

    final emailDoc = await _firestore
        .collection('adminEmails')
        .doc(email)
        .get();

    return emailDoc.exists && emailDoc.data()?['enabled'] != false;
  }
}
