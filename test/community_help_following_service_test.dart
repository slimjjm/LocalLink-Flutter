import 'package:flutter_test/flutter_test.dart';
import 'package:locallink_flutter/services/community_help_following_service.dart';

void main() {
  test('following contains active lookout relationships only', () {
    final ids = CommunityHelpFollowingService.followingPostIds(
      relations: const [
        {'postId': 'followed', 'notificationState': 'active'},
        {'postId': 'stopped', 'notificationState': 'inactive'},
      ],
    );

    expect(ids, {'followed'});
  });

  test('reported-by-user posts stay separate from following', () {
    final ids = CommunityHelpFollowingService.followingPostIds(
      relations: const [
        {'postId': 'owned', 'notificationState': 'active'},
        {'postId': 'followed', 'notificationState': 'active'},
      ],
      ownedPostIds: const ['owned'],
    );

    expect(ids, {'followed'});
  });
}
