import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

class ReviewService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<QuerySnapshot> reviewsStream(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('reviews')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Future<bool> hasReviewed({
    required String organiserId,
    required String reviewerId,
  }) async {
    final review = await _firestore
        .collection('users')
        .doc(organiserId)
        .collection('reviews')
        .doc(reviewerId)
        .get();

    return review.exists;
  }

  Future<void> addReview({
    required String opportunityId,
    required String organiserId,
    required String reviewerId,
    required String reviewerName,
    required int rating,
    required String text,
  }) async {
    await FirebaseFunctions.instanceFor(
      region: 'us-central1',
    ).httpsCallable('submitOrganiserReview').call({
      'opportunityId': opportunityId,
      'organiserId': organiserId,
      'rating': rating,
      'text': text,
    });
  }
}
