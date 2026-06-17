import 'package:cloud_firestore/cloud_firestore.dart';

class AttendeeService {
  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  Stream<QuerySnapshot> attendeesStream(
    String opportunityId,
  ) {
    return _firestore
        .collection('opportunities')
        .doc(opportunityId)
        .collection('attendees')
        .orderBy(
          'joinedAt',
          descending: false,
        )
        .snapshots();
  }
}