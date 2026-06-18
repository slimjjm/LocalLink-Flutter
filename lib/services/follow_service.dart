import 'package:cloud_firestore/cloud_firestore.dart';

class FollowService {
  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  Future<void> followUser({
    required String currentUserId,
    required String currentUserName,
    required String? currentPhotoUrl,
    required String targetUserId,
    required String targetUserName,
    required String? targetPhotoUrl,
  }) async {
    final batch = _firestore.batch();

    final followingRef = _firestore
        .collection('users')
        .doc(currentUserId)
        .collection('following')
        .doc(targetUserId);

    final followerRef = _firestore
        .collection('users')
        .doc(targetUserId)
        .collection('followers')
        .doc(currentUserId);

    batch.set(
      followingRef,
      {
        'userId': targetUserId,
        'userName': targetUserName,
        'photoUrl': targetPhotoUrl,
        'createdAt': Timestamp.now(),
      },
    );

    batch.set(
      followerRef,
      {
        'userId': currentUserId,
        'userName': currentUserName,
        'photoUrl': currentPhotoUrl,
        'createdAt': Timestamp.now(),
      },
    );

    await batch.commit();
  }

  Future<void> unfollowUser({
    required String currentUserId,
    required String targetUserId,
  }) async {
    final batch = _firestore.batch();

    final followingRef = _firestore
        .collection('users')
        .doc(currentUserId)
        .collection('following')
        .doc(targetUserId);

    final followerRef = _firestore
        .collection('users')
        .doc(targetUserId)
        .collection('followers')
        .doc(currentUserId);

    batch.delete(followingRef);
    batch.delete(followerRef);

    await batch.commit();
  }

  Stream<int> followersCount(
    String userId,
  ) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('followers')
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.length,
        );
  }

  Stream<int> followingCount(
    String userId,
  ) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('following')
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.length,
        );
  }

 Future<bool> isFollowing({
  required String currentUserId,
  required String targetUserId,
}) async {
  final doc =
      await _firestore
          .collection('users')
          .doc(currentUserId)
          .collection('following')
          .doc(targetUserId)
          .get();

  return doc.exists;
}
}