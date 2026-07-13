import 'package:cloud_firestore/cloud_firestore.dart';

class TrustSafetyService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> submitReport({
    required String reportType,
    required String targetId,
    required String reportedUserId,
    required String reporterUserId,
    required String reason,
    String? description,
    String? targetPath,
    String? parentId,
    String? targetPreview,
  }) async {
    await _firestore.collection('reports').add({
      'reportType': reportType,
      'targetId': targetId,
      'targetPath': targetPath,
      'parentId': parentId,
      'targetPreview': targetPreview,
      'reportedUserId': reportedUserId,
      'reporterUserId': reporterUserId,
      'reason': reason,
      'description': description?.trim(),
      'createdAt': Timestamp.now(),
      'status': 'open',
    });
  }

  Future<bool> isBlocked({
    required String currentUserId,
    required String blockedUserId,
  }) async {
    final doc = await _firestore
        .collection('users')
        .doc(currentUserId)
        .collection('blockedUsers')
        .doc(blockedUserId)
        .get();

    return doc.exists;
  }

  Future<void> blockUser({
    required String currentUserId,
    required String blockedUserId,
    required String blockedUserName,
    String? blockedPhotoUrl,
  }) async {
    await _firestore
        .collection('users')
        .doc(currentUserId)
        .collection('blockedUsers')
        .doc(blockedUserId)
        .set({
          'blockedUserId': blockedUserId,
          'blockedUserName': blockedUserName,
          'blockedPhotoUrl': blockedPhotoUrl,
          'createdAt': Timestamp.now(),
        });
  }
}
