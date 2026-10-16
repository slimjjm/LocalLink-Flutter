import 'package:flutter_test/flutter_test.dart';
import 'package:locallink_flutter/models/organisation.dart';
import 'package:locallink_flutter/models/organisation_group.dart';
import 'package:locallink_flutter/models/organisation_role.dart';
import 'package:locallink_flutter/screens/organisation_group_screens.dart';
import 'package:locallink_flutter/screens/create_opportunity_screen.dart';
import 'package:locallink_flutter/services/activity_relationships.dart';
import 'package:locallink_flutter/services/my_locallink_organisation_service.dart';
import 'package:locallink_flutter/services/organisation_service.dart';

void main() {
  final organisation = Organisation.fromMap('org-1', {
    'name': 'Burntwood Rugby Club',
    'category': 'Fitness & Sport',
    'subcategories': ['Rugby'],
    'ownerId': 'owner-1',
    'adminUserIds': ['admin-1'],
    'listingOwnershipStatus': 'claimed',
    'claimStatus': 'approved',
  });

  final group = OrganisationGroup.fromMap('group-1', 'org-1', {
    'name': 'Under 8s',
    'description': 'Junior rugby group.',
    'displayType': 'team',
    'category': 'Fitness & Sport',
    'subcategory': 'Rugby',
    'ageLabel': 'Under 8s',
    'leaderUserIds': ['leader-1'],
    'membershipMode': 'approval_required',
    'visibility': 'public',
    'memberCount': 3,
  });

  test('group model reads Phase 1A fields', () {
    expect(group.name, 'Under 8s');
    expect(group.displayType, 'team');
    expect(group.ageLabel, 'Under 8s');
    expect(group.imageUrl, '');
    expect(group.leaderUserIds, ['leader-1']);
    expect(group.requiresApproval, isTrue);
    expect(group.isLedBy('leader-1'), isTrue);
    expect(group.isLedBy('admin-1'), isFalse);
  });

  test('group model reads optional image url', () {
    final group = OrganisationGroup.fromMap('group-1', 'org-1', {
      'name': 'Beginners',
      'imageUrl': 'https://example.com/group.jpg',
    });

    expect(group.imageUrl, 'https://example.com/group.jpg');
  });

  test(
    'group editor inherits organisation category when group category is blank',
    () {
      final blankCategoryGroup = OrganisationGroup.fromMap(
        'group-blank',
        'org-1',
        {'name': 'Saturday volunteers', 'category': ''},
      );

      expect(
        groupEditorCategoryValue(
          organisation: organisation,
          group: blankCategoryGroup,
        ),
        'Fitness & Sport',
      );
      expect(
        groupEditorCategoryValue(organisation: organisation, group: group),
        'Fitness & Sport',
      );
    },
  );

  test('group leader names come from existing membership data', () {
    final people = [
      const OrganisationMembership(
        userId: 'leader-1',
        userName: 'Alex Leader',
        status: 'active',
        role: organisationRoleGroupLeader,
        groupIds: ['group-1'],
      ),
      const OrganisationMembership(
        userId: 'leader-2',
        userName: 'Sam Coach',
        status: 'active',
        role: organisationRoleGroupLeader,
        groupIds: ['group-1'],
      ),
      const OrganisationMembership(
        userId: 'inactive-leader',
        userName: 'Inactive Leader',
        status: 'removed',
        role: organisationRoleGroupLeader,
        groupIds: ['group-1'],
      ),
      const OrganisationMembership(
        userId: 'member-1',
        userName: 'Member',
        status: 'active',
        role: organisationRoleMember,
        groupIds: ['group-1'],
      ),
    ];

    expect(groupLeaderDisplayNames(group: group, people: people), [
      'Alex Leader',
      'Sam Coach',
    ]);
  });

  test('organisation capability defaults remain backwards compatible', () {
    final sportsOrganisation = Organisation.fromMap('sport-org', {
      'name': 'Burntwood Rugby Club',
      'category': 'Fitness & Sport',
      'subcategories': ['Rugby'],
    });
    final communityOrganisation = Organisation.fromMap('community-org', {
      'name': 'Litter Pickers',
      'category': 'Community',
    });

    expect(sportsOrganisation.capabilities.groups, isTrue);
    expect(sportsOrganisation.capabilities.sessions, isTrue);
    expect(sportsOrganisation.capabilities.fixtures, isTrue);
    expect(communityOrganisation.capabilities.groups, isTrue);
    expect(communityOrganisation.capabilities.sessions, isTrue);
    expect(communityOrganisation.capabilities.fixtures, isFalse);
  });

  test('explicit organisation capabilities override category defaults', () {
    final organisation = Organisation.fromMap('org-1', {
      'name': 'Custom Club',
      'category': 'Fitness & Sport',
      'capabilities': {'groups': true, 'sessions': true, 'fixtures': false},
    });

    expect(organisation.capabilities.fixtures, isFalse);
  });

  test('organisation owner and admins can manage groups', () {
    expect(
      OrganisationService.canManageGroup(
        organisation: organisation,
        group: group,
        uid: 'owner-1',
      ),
      isTrue,
    );
    expect(
      OrganisationService.canManageGroup(
        organisation: organisation,
        group: group,
        uid: 'admin-1',
      ),
      isTrue,
    );
    expect(
      OrganisationService.canManageGroup(
        organisation: organisation,
        group: group,
        uid: 'secretary-1',
        organisationRole: organisationRoleSecretary,
      ),
      isTrue,
    );
  });

  test('group leader can manage only their assigned group', () {
    final otherGroup = OrganisationGroup.fromMap('group-2', 'org-1', {
      'name': 'Under 10s',
      'leaderUserIds': ['other-leader'],
    });

    expect(
      OrganisationService.canManageGroup(
        organisation: organisation,
        group: group,
        uid: 'leader-1',
      ),
      isTrue,
    );
    expect(
      OrganisationService.canManageGroup(
        organisation: organisation,
        group: otherGroup,
        uid: 'leader-1',
      ),
      isFalse,
    );
  });

  test('organisation admin is not automatically a group member', () {
    expect(
      OrganisationService.canManageGroup(
        organisation: organisation,
        group: group,
        uid: 'admin-1',
      ),
      isTrue,
    );
    expect(
      OrganisationService.isAuthorityAlsoMembership(
        organisation: organisation,
        group: group,
        uid: 'admin-1',
        hasMembership: false,
      ),
      isFalse,
    );
  });

  test('youth and family groups default to approval required', () {
    expect(
      defaultMembershipModeFor(
        category: 'Fitness & Sport',
        subcategory: 'Rugby',
        ageLabel: 'Under 8s',
      ),
      'approval_required',
    );
    expect(
      defaultMembershipModeFor(
        category: 'Community',
        subcategory: 'Running',
        ageLabel: 'Adults',
      ),
      'open',
    );
  });

  test(
    'existing standalone activity remains valid without organisation fields',
    () {
      final data = ActivityRelationshipFields.build();

      expect(data['activityContext'], 'standalone');
      expect(data['activityKind'], 'activity');
      expect(data.containsKey('organisationId'), isFalse);
      expect(data.containsKey('groupId'), isFalse);
      expect(data.containsKey('activityAudienceScope'), isFalse);
      expect(data.containsKey('isPubliclyDiscoverable'), isFalse);
    },
  );

  test(
    'existing organisation-linked activity remains valid without groupId',
    () {
      final data = ActivityRelationshipFields.build(organisation: organisation);

      expect(data['activityContext'], 'organisation');
      expect(data['organisationId'], 'org-1');
      expect(data['organisationName'], 'Burntwood Rugby Club');
      expect(data.containsKey('groupId'), isFalse);
      expect(data['activityAudienceScope'], 'everyone');
      expect(data['isPubliclyDiscoverable'], isTrue);
    },
  );

  test('whole organisation activity is private to the organisation', () {
    final data = ActivityRelationshipFields.build(
      organisation: organisation,
      audienceScope: 'organisation',
    );

    expect(data['activityContext'], 'organisation');
    expect(data['organisationId'], 'org-1');
    expect(data['activityAudienceScope'], 'organisation');
    expect(data['isPubliclyDiscoverable'], isFalse);
  });

  test('group-linked session keeps organisation and group context', () {
    final data = ActivityRelationshipFields.build(
      organisation: organisation,
      group: group,
      activityKind: 'session',
    );

    expect(data['activityContext'], 'group');
    expect(data['activityKind'], 'session');
    expect(data['organisationId'], 'org-1');
    expect(data['groupId'], 'group-1');
    expect(data['groupName'], 'Under 8s');
    expect(data['groupLeaderUserIds'], ['leader-1']);
    expect(data['activityAudienceScope'], 'group');
    expect(data['isPubliclyDiscoverable'], isFalse);
  });

  test('lightweight fixture fields are captured without a fixture system', () {
    final data = ActivityRelationshipFields.build(
      organisation: organisation,
      group: group,
      activityKind: 'fixture',
      opponentName: 'Lichfield',
      fixtureVenue: 'away',
    );

    expect(data['activityKind'], 'fixture');
    expect(data['opponentName'], 'Lichfield');
    expect(data['fixtureVenue'], 'away');
  });

  test('fixture activity option is capability gated', () {
    final communityOrganisation = Organisation.fromMap('community-org', {
      'name': 'Litter Pickers',
      'category': 'Community',
      'listingOwnershipStatus': 'claimed',
      'claimStatus': 'approved',
    });
    final communityGroup = OrganisationGroup.fromMap(
      'group-1',
      'community-org',
      {
        'name': 'Saturday volunteers',
        'displayType': 'group',
        'category': 'Community',
      },
    );

    expect(canShowFixtureActivityOption(organisation), isTrue);
    expect(canShowFixtureActivityOption(communityOrganisation), isFalse);
    expect(communityGroup.id, 'group-1');
  });

  test(
    'recurring group session compatibility uses normal opportunity fields',
    () {
      final relationship = ActivityRelationshipFields.build(
        organisation: organisation,
        group: group,
        activityKind: 'session',
      );
      final opportunityData = {
        ...relationship,
        'isRecurring': true,
        'repeatType': 'weekly',
        'seriesId': 'opportunity-1',
      };

      expect(opportunityData['groupId'], 'group-1');
      expect(opportunityData['isRecurring'], isTrue);
      expect(opportunityData['repeatType'], 'weekly');
      expect(opportunityData['seriesId'], 'opportunity-1');
    },
  );

  test('membership modes normalise to safe defaults', () {
    expect(normaliseMembershipMode('open'), 'open');
    expect(normaliseMembershipMode('approval_required'), 'approval_required');
    expect(normaliseMembershipMode('invite_only'), 'invite_only');
    expect(normaliseMembershipMode('unexpected'), 'open');
  });

  test('self-service organisation payload makes creator owner and admin', () {
    final data = OrganisationService.selfServiceOrganisationData(
      user: const OrganisationCurrentUser(
        uid: 'user-1',
        email: 'user@example.com',
      ),
      name: 'Burntwood Rugby Club',
      category: 'Sport & fitness',
      location: 'Community Hall, High Street',
      description: 'A weekly social running group.',
      latitude: 52.1,
      longitude: -1.9,
    );

    expect(data['name'], 'Burntwood Rugby Club');
    expect(data['category'], 'Sport & fitness');
    expect(data['location'], 'Community Hall, High Street');
    expect(data['publicLocation'], 'Community Hall, High Street');
    expect(data['area'], 'Community Hall, High Street');
    expect(data['latitude'], 52.1);
    expect(data['longitude'], -1.9);
    expect(data['ownerId'], 'user-1');
    expect(data['adminUserIds'], ['user-1']);
    expect(data['createdBy'], 'user-1');
    expect(data['createdByModerator'], isFalse);
    expect(data['listingOwnershipStatus'], 'claimed');
    expect(data['claimStatus'], 'approved');
    expect(data['isActive'], isTrue);
    expect(data['capabilities'], {
      'groups': true,
      'sessions': true,
      'fixtures': true,
    });
  });

  test('archived organisations are excluded from normal managed list', () {
    expect(
      MyLocalLinkOrganisationService.isManageableOrganisationData(
        {
          'name': 'Archived Club',
          'ownerId': 'user-1',
          'adminUserIds': ['user-1'],
          'listingOwnershipStatus': 'claimed',
          'claimStatus': 'approved',
          'isActive': false,
        },
        'user-1',
        role: organisationRoleOwner,
      ),
      isFalse,
    );
    expect(
      MyLocalLinkOrganisationService.isManageableOrganisationData(
        {
          'name': 'Archived Club',
          'ownerId': 'user-1',
          'adminUserIds': ['user-1'],
          'listingOwnershipStatus': 'claimed',
          'claimStatus': 'approved',
          'isActive': false,
        },
        'user-1',
        role: organisationRoleOwner,
        includeArchived: true,
      ),
      isTrue,
    );
  });

  test('Phase 1B organisation roles have plain English labels', () {
    expect(organisationRoleLabel(organisationRoleOwner), 'Owner');
    expect(organisationRoleLabel(organisationRoleAdmin), 'Organisation admin');
    expect(organisationRoleLabel(organisationRoleSecretary), 'Secretary');
    expect(organisationRoleLabel(organisationRoleGroupLeader), 'Group leader');
    expect(organisationRoleLabel(organisationRoleMember), 'Member');
  });

  test('organisation-wide manager roles exclude group leaders and members', () {
    expect(isOrganisationWideManagerRole(organisationRoleOwner), isTrue);
    expect(isOrganisationWideManagerRole(organisationRoleAdmin), isTrue);
    expect(isOrganisationWideManagerRole(organisationRoleSecretary), isTrue);
    expect(isOrganisationWideManagerRole(organisationRoleGroupLeader), isFalse);
    expect(isOrganisationWideManagerRole(organisationRoleMember), isFalse);
  });
}
