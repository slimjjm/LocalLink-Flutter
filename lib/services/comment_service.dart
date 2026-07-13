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
final opportunityDoc =
    await _firestore
        .collection('opportunities')
        .doc(opportunityId)
        .get();

final opportunity =
    opportunityDoc.data();

final organiserId =
    opportunity?['createdBy'];
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
    if (organiserId != null &&
    organiserId != userId) {

  await _firestore
      .collection('users')
      .doc(organiserId)
      .collection('notifications')
      .add({

    'type':
        'opportunity_comment',

    'title':
        'New comment',

    'body':
        '$userName commented on your opportunity',

    'opportunityId':
        opportunityId,

    'userId':
        userId,

    'isRead':
        false,

    'createdAt':
        Timestamp.now(),
  });
}
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