import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

typedef CommentDebugLog =
    void Function(String stage, Map<String, Object?> details);

class CommentService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<QuerySnapshot> commentsStream(String opportunityId) {
    return _firestore
        .collection('opportunities')
        .doc(opportunityId)
        .collection('comments')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  DocumentReference<Map<String, dynamic>> newCommentReference(
    String opportunityId,
  ) {
    return _firestore
        .collection('opportunities')
        .doc(opportunityId)
        .collection('comments')
        .doc();
  }

  Future<String> addComment({
    required String opportunityId,
    required String userId,
    required String userName,
    required String text,
    String? commentId,
    String? imageUrl,
    String? imagePath,
    bool createChallengeEntry = false,
    CommentDebugLog? debugLog,
  }) async {
    final opportunityRef = _firestore
        .collection('opportunities')
        .doc(opportunityId);
    final commentRef = commentId == null || commentId.trim().isEmpty
        ? newCommentReference(opportunityId)
        : opportunityRef.collection('comments').doc(commentId.trim());
    final entryRef = opportunityRef.collection('entries').doc(userId);

    await _firestore.runTransaction((transaction) async {
      _debug(debugLog, 'COMP_ENTRY_TRANSACTION_READ_OPPORTUNITY_START', {
        'path': 'opportunities/$opportunityId',
      });
      final opportunityDoc = await transaction.get(opportunityRef);
      final opportunity = opportunityDoc.data();
      _debug(debugLog, 'COMP_ENTRY_TRANSACTION_READ_OPPORTUNITY_OK', {
        'path': 'opportunities/$opportunityId',
        'exists': opportunityDoc.exists,
        'activityKind': opportunity?['activityKind']?.toString(),
        'isActive': opportunity?['isActive'],
        'hasCommentCount': opportunity?.containsKey('commentCount') ?? false,
        'commentCountType': opportunity?['commentCount']?.runtimeType
            .toString(),
      });

      if (createChallengeEntry) {
        final isChallenge =
            opportunity?['activityKind'] == 'community_challenge';
        final closesAt = opportunity?['challengeClosesAt'];
        final closed =
            closesAt is Timestamp && closesAt.toDate().isBefore(DateTime.now());
        _debug(debugLog, 'COMP_ENTRY_TRANSACTION_READ_ENTRY_START', {
          'path': 'opportunities/$opportunityId/entries/<current-user>',
        });
        final existingEntry = await transaction.get(entryRef);
        _debug(debugLog, 'COMP_ENTRY_TRANSACTION_READ_ENTRY_OK', {
          'path': 'opportunities/$opportunityId/entries/<current-user>',
          'exists': existingEntry.exists,
        });

        if (!isChallenge) {
          throw StateError('This activity does not accept challenge entries.');
        }
        if (closed) {
          throw StateError('Entries are closed for this challenge.');
        }
        if (existingEntry.exists) {
          throw StateError('You have already entered this challenge.');
        }
      }

      final commentData = <String, Object?>{
        'userId': userId,
        'userName': userName,
        'text': text,
        'createdAt': Timestamp.now(),
        if (imageUrl != null && imageUrl.trim().isNotEmpty)
          'imageUrl': imageUrl.trim(),
        if (imagePath != null && imagePath.trim().isNotEmpty)
          'imagePath': imagePath.trim(),
        if (createChallengeEntry) 'isChallengeEntry': true,
      };

      _debug(debugLog, 'COMP_ENTRY_COMMENT_CREATE_START', {
        'path': 'opportunities/$opportunityId/comments/${commentRef.id}',
        'fields': commentData.keys.toList(growable: false),
        'hasImageUrl': commentData.containsKey('imageUrl'),
        'hasImagePath': commentData.containsKey('imagePath'),
      });
      transaction.set(commentRef, commentData);
      _debug(debugLog, 'COMP_ENTRY_PARENT_UPDATE_START', {
        'path': 'opportunities/$opportunityId',
        'fields': ['commentCount'],
      });
      transaction.update(opportunityRef, {
        'commentCount': FieldValue.increment(1),
      });

      if (createChallengeEntry) {
        final entryData = {
          'userId': userId,
          'commentId': commentRef.id,
          'imageUrl': imageUrl?.trim(),
          'imagePath': imagePath?.trim(),
          'caption': text,
          'createdAt': Timestamp.now(),
          'eligible': true,
          'status': 'active',
        };
        _debug(debugLog, 'COMP_ENTRY_ENTRY_CREATE_START', {
          'path': 'opportunities/$opportunityId/entries/<current-user>',
          'fields': entryData.keys.toList(growable: false),
          'imageUrlIsNull': entryData['imageUrl'] == null,
          'imagePathIsNull': entryData['imagePath'] == null,
        });
        transaction.set(entryRef, entryData);
      }
      _debug(debugLog, 'COMP_ENTRY_TRANSACTION_CALLBACK_COMPLETE', {
        'path': 'opportunities/$opportunityId',
      });
    });
    _debug(debugLog, 'COMP_ENTRY_TRANSACTION_COMMITTED', {
      'path': 'opportunities/$opportunityId',
      'commentId': commentRef.id,
    });

    return commentRef.id;
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
        .update({'text': text});
  }

  Future<void> deleteComment({
    required String opportunityId,
    required String commentId,
  }) async {
    final opportunityRef = _firestore
        .collection('opportunities')
        .doc(opportunityId);
    final commentRef = opportunityRef.collection('comments').doc(commentId);
    String? imagePath;

    await _firestore.runTransaction((transaction) async {
      final commentDoc = await transaction.get(commentRef);
      final data = commentDoc.data();
      imagePath = data?['imagePath']?.toString().trim();
      transaction.delete(commentRef);
      transaction.update(opportunityRef, {
        'commentCount': FieldValue.increment(-1),
      });

      if (data?['isChallengeEntry'] == true) {
        final userId = data?['userId']?.toString().trim();
        if (userId != null && userId.isNotEmpty) {
          transaction.delete(opportunityRef.collection('entries').doc(userId));
        }
      }
    });

    if (imagePath != null && imagePath!.isNotEmpty) {
      try {
        await FirebaseStorage.instance.ref(imagePath).delete();
      } on FirebaseException catch (error) {
        if (error.code != 'object-not-found') rethrow;
      }
    }
  }

  void _debug(
    CommentDebugLog? debugLog,
    String stage,
    Map<String, Object?> details,
  ) {
    debugLog?.call(stage, details);
  }
}
