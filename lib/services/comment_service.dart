import 'package:cloud_firestore/cloud_firestore.dart';

class CommentService {
  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  Stream<QuerySnapshot> commentsStream(
    String opportunityId,
  ) {
    return _firestore
        .collection('opportunities')
        .doc(opportunityId)
        .collection('comments')
        .orderBy(
          'createdAt',
          descending: true,
        )
        .snapshots();
  }

  Future<void> addComment({
    required String opportunityId,
    required String userId,
    required String userName,
    required String text,
  }) async {

    await _firestore
        .collection('opportunities')
        .doc(opportunityId)
        .collection('comments')
        .add({

      'userId': userId,
      'userName': userName,
      'text': text,
      'createdAt': Timestamp.now(),

    });

    await _firestore
        .collection('opportunities')
        .doc(opportunityId)
        .update({

      'commentCount':
          FieldValue.increment(1),

    });
  }
Future<void> updateComment({
  required String opportunityId,
  required String commentId,
  required String text,
}) async {

  await _firestore
      .collection('opportunities')
      .doc(opportunityId)
      .collection('comments')
      .doc(commentId)
      .update({

    'text': text,

  });
}

  Future<void> deleteComment({
    required String opportunityId,
    required String commentId,
  }) async {

    await _firestore
        .collection('opportunities')
        .doc(opportunityId)
        .collection('comments')
        .doc(commentId)
        .delete();

    await _firestore
        .collection('opportunities')
        .doc(opportunityId)
        .update({

      'commentCount':
          FieldValue.increment(-1),

    });
  }
}