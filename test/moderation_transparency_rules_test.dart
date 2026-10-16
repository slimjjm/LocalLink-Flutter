import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String rules;

  setUpAll(() {
    rules = File('firestore.rules').readAsStringSync();
  });

  test('ordinary users cannot change moderation removal fields', () {
    expect(rules, contains("'moderationStatus'"));
    expect(rules, contains("'removedAt'"));
    expect(rules, contains("'removedBy'"));
    expect(rules, contains("'removalReasonCode'"));
    expect(rules, contains("'removalReasonPublicText'"));
    expect(rules, contains("'moderatorNote'"));
  });

  test('Community Help owner updates also protect moderation fields', () {
    final helperStart = rules.indexOf(
      'function validCommunityHelpOwnerResolve()',
    );
    final helperEnd = rules.indexOf('function validGroupCreate');
    final postStart = rules.indexOf('match /communityHelpPosts/{postId}');
    final postEnd = rules.indexOf(
      'match /communityAlertSubscriptions/{userId}',
    );
    expect(helperStart, greaterThanOrEqualTo(0));
    expect(helperEnd, greaterThan(helperStart));
    expect(postStart, greaterThanOrEqualTo(0));
    expect(postEnd, greaterThan(postStart));

    final helpers = rules.substring(helperStart, helperEnd);
    final postRules = rules.substring(postStart, postEnd);
    expect(helpers, contains('changed.hasOnly(['));
    expect(helpers, contains('validCommunityHelpOwnerRenewal()'));
    expect(postRules, contains('validCommunityHelpOwnerResolve()'));
    expect(postRules, contains('validCommunityHelpOwnerRenewal()'));
  });

  test('Community Help ownership claim fields are protected', () {
    final start = rules.indexOf('match /communityHelpPosts/{postId}');
    final end = rules.indexOf('match /communityAlertSubscriptions/{userId}');
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final helper = rules.substring(start, end);
    expect(helper, contains("'createdByModerator'"));
    expect(helper, contains("'communityAdded'"));
    expect(helper, contains("'ownerId'"));
    expect(helper, contains("'claimStatus'"));
    expect(helper, contains("'claimedBy'"));
    expect(helper, contains("'claimedAt'"));
    expect(helper, contains("'claimReviewedBy'"));
    expect(helper, contains("'claimReviewedAt'"));
  });

  test('Following collection-group reads are limited to the current user', () {
    final start = rules.indexOf('match /communityHelpPosts/{postId}');
    final end = rules.indexOf('match /communityAlertSubscriptions/{userId}');
    final communityHelpRules = rules.substring(start, end);

    expect(
      communityHelpRules,
      contains('allow list: if isRegisteredOwner(resource.data.userId)'),
    );
    expect(
      communityHelpRules,
      contains("resource.data.notificationState == 'active'"),
    );
    expect(
      communityHelpRules,
      contains('allow create, update, delete: if false'),
    );
  });

  test('nearby alert state is server-written and private to its user', () {
    final usersStart = rules.indexOf('match /users/{userId}');
    final subscriptionsStart = rules.indexOf(
      'match /communityAlertSubscriptions/{userId}',
    );
    final userRules = rules.substring(usersStart, subscriptionsStart);

    expect(userRules, contains('match /{document=**}'));
    expect(
      userRules,
      contains('allow read: if isRegisteredOwner(userId) || isAdmin()'),
    );
    expect(userRules, contains('allow write: if false'));
  });
}
