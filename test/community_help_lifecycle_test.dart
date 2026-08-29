import 'package:flutter_test/flutter_test.dart';
import 'package:locallink_flutter/services/community_help_lifecycle.dart';

void main() {
  final now = DateTime(2026, 8, 16, 12);

  Map<String, dynamic> post({
    String type = 'lost_found',
    String mode = 'lost',
    String category = 'Keys',
    DateTime? expiresAt,
    String status = CommunityHelpLifecycle.activeStatus,
    bool isActive = true,
    String createdBy = 'owner',
    double lat = 52.68,
    double lng = -1.83,
    List<String> keywords = const ['keys', 'chasewater'],
  }) {
    return {
      'type': type,
      'mode': mode,
      'itemCategory': category,
      'expiresAt': expiresAt ?? now.add(const Duration(days: 1)),
      'status': status,
      'isActive': isActive,
      'createdBy': createdBy,
      'approxLatitude': lat,
      'approxLongitude': lng,
      'discoveryRadiusMiles':
          CommunityHelpLifecycle.defaultDiscoveryRadiusMiles(
            type: type,
            mode: mode,
            itemCategory: category,
          ),
      'publicLocation': 'Chasewater',
      'keywords': keywords,
    };
  }

  test('lost pet gets correct expiry', () {
    final expiry = CommunityHelpLifecycle.expiresAt(
      now: now,
      type: 'lost_found',
      mode: 'lost',
      itemCategory: 'Pet',
    );

    expect(expiry, now.add(const Duration(days: 7)));
  });

  test('lost object gets correct expiry', () {
    final expiry = CommunityHelpLifecycle.expiresAt(
      now: now,
      type: 'lost_found',
      mode: 'lost',
      itemCategory: 'Keys',
    );

    expect(expiry, now.add(const Duration(days: 7)));
  });

  test('found object gets correct expiry', () {
    final expiry = CommunityHelpLifecycle.expiresAt(
      now: now,
      type: 'lost_found',
      mode: 'found',
      itemCategory: 'Keys',
    );

    expect(expiry, now.add(const Duration(days: 14)));
  });

  test('free item gets correct expiry', () {
    final expiry = CommunityHelpLifecycle.expiresAt(
      now: now,
      type: 'free_item',
      mode: 'offering',
      itemCategory: 'Free item',
    );

    expect(expiry, now.add(const Duration(days: 3)));
  });

  test('active post appears in active discovery', () {
    expect(CommunityHelpLifecycle.isActiveForDiscovery(post(), now), isTrue);
  });

  test('expired post does not appear in active discovery', () {
    expect(
      CommunityHelpLifecycle.isActiveForDiscovery(
        post(expiresAt: now.subtract(const Duration(minutes: 1))),
        now,
      ),
      isFalse,
    );
  });

  test('resolved post does not appear in active discovery', () {
    expect(
      CommunityHelpLifecycle.isActiveForDiscovery(
        post(status: CommunityHelpLifecycle.resolvedStatus),
        now,
      ),
      isFalse,
    );
  });

  test('owner can renew', () {
    expect(
      CommunityHelpLifecycle.canMutate(currentUserId: 'owner', post: post()),
      isTrue,
    );
  });

  test('renewal produces correct new expiry', () {
    final renewed = CommunityHelpLifecycle.expiresAt(
      now: now,
      type: 'lost_found',
      mode: 'found',
      itemCategory: 'Wallet',
    );

    expect(renewed, now.add(const Duration(days: 14)));
  });

  test('owner can resolve', () {
    expect(
      CommunityHelpLifecycle.canMutate(currentUserId: 'owner', post: post()),
      isTrue,
    );
  });

  test("another user cannot resolve another user's post", () {
    expect(
      CommunityHelpLifecycle.canMutate(
        currentUserId: 'someone_else',
        post: post(),
      ),
      isFalse,
    );
  });

  test('expired and resolved posts are excluded from matching', () {
    final lost = post();
    final expiredFound = post(
      mode: 'found',
      expiresAt: now.subtract(const Duration(minutes: 1)),
    );
    final resolvedFound = post(
      mode: 'found',
      status: CommunityHelpLifecycle.resolvedStatus,
    );

    expect(
      CommunityHelpLifecycle.shouldMatch(lost, expiredFound, now),
      isFalse,
    );
    expect(
      CommunityHelpLifecycle.shouldMatch(lost, resolvedFound, now),
      isFalse,
    );
  });

  test('lost to found candidate matching respects distance', () {
    final lost = post(mode: 'lost', category: 'Keys');
    final nearFound = post(
      mode: 'found',
      category: 'Keys',
      lat: 52.681,
      lng: -1.831,
    );
    final farFound = post(
      mode: 'found',
      category: 'Keys',
      lat: 53.7,
      lng: -2.7,
    );

    expect(CommunityHelpLifecycle.shouldMatch(lost, nearFound, now), isTrue);
    expect(CommunityHelpLifecycle.shouldMatch(lost, farFound, now), isFalse);
  });

  test('old documents without lifecycle fields do not crash', () {
    final legacy = {
      'type': 'lost_found',
      'mode': 'lost',
      'itemCategory': 'Keys',
      'status': 'missing',
      'isActive': true,
      'publicLocation': 'Chasewater',
      'keywords': ['keys'],
    };

    expect(CommunityHelpLifecycle.isActiveForDiscovery(legacy, now), isTrue);
    expect(CommunityHelpLifecycle.friendlyStatus(legacy, now), 'Missing');
  });

  test('free item lifecycle works', () {
    final freeItem = post(
      type: 'free_item',
      mode: 'offering',
      category: 'Free item',
    );

    expect(CommunityHelpLifecycle.friendlyStatus(freeItem, now), 'Available');
    expect(
      CommunityHelpLifecycle.resolveActionLabel(
        type: 'free_item',
        mode: 'offering',
        itemCategory: 'Free item',
      ),
      'Mark as collected',
    );
  });

  test('messaging response action prepares private handoff payload', () {
    final intent = CommunityHelpLifecycle.messagingIntent(
      postId: 'post-1',
      post: post(),
      responderId: 'responder',
      responderName: 'Alex',
      message: 'I may have seen these keys.',
    );

    expect(intent['postOwnerId'], 'owner');
    expect(intent['responderId'], 'responder');
    expect(intent.containsKey('phone'), isFalse);
    expect(intent.containsKey('email'), isFalse);
    expect(intent.containsKey('approxLatitude'), isFalse);
    expect(intent.containsKey('approxLongitude'), isFalse);
  });
}
