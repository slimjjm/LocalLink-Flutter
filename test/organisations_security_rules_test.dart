import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String rules;

  setUpAll(() {
    rules = File('firestore.rules').readAsStringSync();
  });

  test('rules include self-service organisation creation', () {
    expect(rules, contains('validSelfServiceOrganisationCreate'));
    expect(rules, contains("request.resource.data.ownerId == uid()"));
    expect(
      rules,
      contains('request.resource.data.adminUserIds.hasAll([uid()])'),
    );
    expect(rules, contains("'latitude'"));
    expect(rules, contains("'longitude'"));
    expect(
      rules,
      contains("request.resource.data.listingOwnershipStatus == 'claimed'"),
    );
  });

  test('rules separate organisation authority from group leadership', () {
    expect(rules, contains('isOrganisationOwnerOrAdmin'));
    expect(rules, contains('isOrganisationManager'));
    expect(
      rules,
      contains("isActiveOrganisationRole(organisationId, 'secretary')"),
    );
    expect(rules, contains('isGroupLeader'));
    expect(rules, contains('isOrganisationOrGroupManager'));
  });

  test('rules protect private member lists and join request review', () {
    expect(rules, contains('match /members/{userId}'));
    expect(rules, contains('allow list: if isOrganisationOrGroupManager'));
    expect(rules, contains('validJoinRequestReview'));
  });

  test('rules support open membership and approval-required membership', () {
    expect(rules, contains('validOpenGroupMemberCreate'));
    expect(rules, contains("membershipMode == 'open'"));
    expect(rules, contains('validJoinRequestCreate'));
    expect(rules, contains("membershipMode == 'approval_required'"));
  });

  test('group member counts are tied to membership writes', () {
    expect(rules, contains('validGroupMemberCountAdjustment'));
    expect(rules, contains('existsAfter(memberPath)'));
    expect(rules, contains('getAfter(memberPath).data.status'));
    expect(rules, isNot(contains("'memberCount',\n          'updatedBy'")));
  });

  test('client-side organisation settings cannot edit raw admin user ids', () {
    final start = rules.indexOf('function validOrganisationOwnerUpdate');
    final end = rules.indexOf(
      'function validOrganisationLinkedOpportunityCreate',
    );
    expect(start, isNonNegative);
    expect(end, greaterThan(start));

    final helper = rules.substring(start, end);
    expect(helper, isNot(contains("'adminUserIds'")));
  });

  test('people invitations and announcements are backend managed', () {
    expect(rules, contains('match /invitations/{invitationId}'));
    expect(rules, contains('allow create, update, delete: if false;'));
    expect(rules, contains('match /announcements/{announcementId}'));
    expect(rules, contains('canReadOrganisationAnnouncement'));
  });

  test('organisation membership requires an authorised group membership', () {
    final organisationStart = rules.indexOf(
      'match /organisations/{organisationId}',
    );
    final start = rules.indexOf('match /members/{userId}', organisationStart);
    final end = rules.indexOf('match /invitations/{invitationId}');
    expect(organisationStart, isNonNegative);
    expect(start, isNonNegative);
    expect(end, greaterThan(start));

    final helper = rules.substring(start, end);
    expect(helper, contains('validDerivedOrganisationMembership'));
    expect(rules, contains('getAfter(memberPath)'));
    expect(rules, contains("data.role == (existed ? old.role : 'member')"));
  });
}
