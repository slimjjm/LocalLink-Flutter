import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AdminAccessService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<bool> isCurrentUserAdmin() async {
    final user = _auth.currentUser;

    if (user == null) {
      return false;
    }

    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    final userData = userDoc.data();

    if (userData?['isAdmin'] == true) {
      return true;
    }

    final email = user.email?.trim().toLowerCase();

    if (email == null || email.isEmpty) {
      return false;
    }

    final emailDoc = await _firestore
        .collection('adminEmails')
        .doc(email)
        .get();

    return emailDoc.exists && emailDoc.data()?['enabled'] != false;
  }
}
