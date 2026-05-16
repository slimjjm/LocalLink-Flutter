import 'package:cloud_firestore/cloud_firestore.dart';

class NextAvailableService {

  static Future<DateTime?> getNextAvailableSlot(
    String businessId,
  ) async {

    final now = DateTime.now();

    final snapshot =
        await FirebaseFirestore.instance
            .collectionGroup('availableSlots')
            .where(
              'businessId',
              isEqualTo: businessId,
            )
            .where(
              'startTime',
              isGreaterThan: Timestamp.fromDate(now),
            )
            .orderBy('startTime')
            .limit(1)
            .get();

    if (snapshot.docs.isEmpty) {
      return null;
    }

    final data =
        snapshot.docs.first.data();

    final timestamp =
        data['startTime'] as Timestamp?;

    return timestamp?.toDate();
  }
}