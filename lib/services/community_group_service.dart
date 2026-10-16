import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

class CommunityGroupService {
  CommunityGroupService({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _functions =
           functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  Stream<DocumentSnapshot<Map<String, dynamic>>> followState({
    required String opportunityId,
    required String userId,
  }) {
    return _firestore
        .collection('opportunities')
        .doc(opportunityId)
        .collection('followers')
        .doc(userId)
        .snapshots();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> followRequestState({
    required String opportunityId,
    required String userId,
  }) {
    return _firestore
        .collection('opportunities')
        .doc(opportunityId)
        .collection('followRequests')
        .doc(userId)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> followRequests(
    String opportunityId,
  ) {
    return _firestore
        .collection('opportunities')
        .doc(opportunityId)
        .collection('followRequests')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> announcements(
    String opportunityId,
  ) {
    return _firestore
        .collection('opportunities')
        .doc(opportunityId)
        .collection('announcements')
        .orderBy('createdAt', descending: true)
        .limit(10)
        .snapshots();
  }

  Future<String> follow({
    required String opportunityId,
    String reason = '',
    String explanation = '',
  }) async {
    final result = await _functions
        .httpsCallable('followOpportunityGroup')
        .call({
          'opportunityId': opportunityId,
          'reason': reason,
          'explanation': explanation,
        });

    final data = Map<String, dynamic>.from(result.data as Map);
    return data['status']?.toString() ?? 'approved';
  }

  Future<void> unfollow({required String opportunityId}) async {
    await _functions.httpsCallable('unfollowOpportunityGroup').call({
      'opportunityId': opportunityId,
    });
  }

  Future<void> reviewFollowRequest({
    required String opportunityId,
    required String followerId,
    required bool approve,
  }) async {
    await _functions.httpsCallable('reviewOpportunityFollowRequest').call({
      'opportunityId': opportunityId,
      'followerId': followerId,
      'approve': approve,
    });
  }

  Future<void> publishAnnouncement({
    required String opportunityId,
    required String title,
    required String body,
    required bool important,
  }) async {
    await _functions.httpsCallable('publishOpportunityAnnouncement').call({
      'opportunityId': opportunityId,
      'title': title,
      'body': body,
      'importance': important ? 'important' : 'normal',
    });
  }
}
