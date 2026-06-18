import 'package:cloud_firestore/cloud_firestore.dart';

class ReviewService {
  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  Stream<QuerySnapshot> reviewsStream(
    String userId,
  ) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('reviews')
        .orderBy(
          'createdAt',
          descending: true,
        )
        .snapshots();
  }

  Future<bool> hasReviewed({
    required String organiserId,
    required String reviewerId,
  }) async {
    final review =
        await _firestore
            .collection('users')
            .doc(organiserId)
            .collection('reviews')
            .doc(reviewerId)
            .get();

    return review.exists;
  }

  Future<void> addReview({
    required String organiserId,
    required String reviewerId,
    required String reviewerName,
    required int rating,
    required String text,
  }) async {
    await _firestore
        .collection('users')
        .doc(organiserId)
        .collection('reviews')
        .doc(reviewerId)
        .set({

      'rating': rating,
      'text': text,
      'reviewerId': reviewerId,
      'reviewerName': reviewerName,
      'createdAt': Timestamp.now(),

    });

    final userRef =
        _firestore
            .collection('users')
            .doc(organiserId);

    await _firestore.runTransaction(
      (transaction) async {

        final snapshot =
            await transaction.get(
          userRef,
        );

        final data =
            snapshot.data() ?? {};

        final reviewCount =
            (data['reviewCount'] ?? 0)
                as int;

        final ratingTotal =
            (data['ratingTotal'] ?? 0)
                as int;

        final newReviewCount =
            reviewCount + 1;

        final newRatingTotal =
            ratingTotal + rating;

        transaction.update(
          userRef,
          {

            'reviewCount':
                newReviewCount,

            'ratingTotal':
                newRatingTotal,

            'averageRating':
                newRatingTotal /
                    newReviewCount,

          },
        );
      },
    );
  }
}