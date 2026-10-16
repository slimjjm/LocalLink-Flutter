import 'package:cloud_firestore/cloud_firestore.dart';

class CommunityHelpFollowingService {
  CommunityHelpFollowingService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Stream<List<DocumentSnapshot<Map<String, dynamic>>>> watchFollowing(
    String userId,
  ) {
    return _firestore
        .collectionGroup('followers')
        .where('userId', isEqualTo: userId)
        .where('notificationState', isEqualTo: 'active')
        .where('postId', isGreaterThan: '')
        .snapshots()
        .asyncMap((snapshot) async {
          final activeRelations = snapshot.docs.where(
            (doc) => doc.data()['notificationState'] == 'active',
          );
          final postRefs = activeRelations
              .map((relation) => relation.reference.parent.parent)
              .whereType<DocumentReference<Map<String, dynamic>>>();
          final postSnapshots = await Future.wait(
            postRefs.map((postRef) => postRef.get()),
          );
          return postSnapshots
              .whereType<DocumentSnapshot<Map<String, dynamic>>>()
              .where((post) => post.exists)
              .toList();
        });
  }

  static Set<String> followingPostIds({
    required Iterable<Map<String, dynamic>> relations,
    Iterable<String> ownedPostIds = const [],
  }) {
    final owned = ownedPostIds.toSet();
    return relations
        .where((relation) => relation['notificationState'] == 'active')
        .map((relation) => relation['postId']?.toString().trim() ?? '')
        .where((postId) => postId.isNotEmpty && !owned.contains(postId))
        .toSet();
  }
}
