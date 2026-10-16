import 'package:flutter_test/flutter_test.dart';
import 'package:locallink_flutter/models/organisation_role.dart';
import 'package:locallink_flutter/services/my_locallink_organisation_service.dart';

void main() {
  const uid = 'user-1';

  test(
    'self-created approved organisation appears without listing ownership field',
    () {
      final entries = MyLocalLinkOrganisationService.entriesFromCandidateData(
        uid: uid,
        organisationDataById: {
          'org-1': {
            'name': 'Self Created Group',
            'createdBy': uid,
            'adminUserIds': [uid],
            'claimStatus': 'approved',
            'createdByModerator': false,
            'isActive': true,
          },
        },
      );

      expect(entries, hasLength(1));
      expect(entries.single.organisation.id, 'org-1');
      expect(entries.single.organisation.name, 'Self Created Group');
      expect(entries.single.role, organisationRoleOwner);
    },
  );

  test(
    'claimed owner, admin, secretary and group leader routes are unioned',
    () {
      final entries = MyLocalLinkOrganisationService.entriesFromCandidateData(
        uid: uid,
        organisationDataById: {
          'owner-org': {
            'name': 'Owner Org',
            'ownerId': uid,
            'claimStatus': 'approved',
            'isActive': true,
          },
          'admin-org': {
            'name': 'Admin Org',
            'adminUserIds': [uid],
            'listingOwnershipStatus': 'claimed',
            'isActive': true,
          },
          'secretary-org': {
            'name': 'Secretary Org',
            'listingOwnershipStatus': 'claimed',
            'isActive': true,
          },
          'leader-org': {
            'name': 'Leader Org',
            'listingOwnershipStatus': 'claimed',
            'isActive': true,
          },
          'member-org': {
            'name': 'Member Org',
            'listingOwnershipStatus': 'claimed',
            'isActive': true,
          },
        },
        rolesById: const {
          'secretary-org': organisationRoleSecretary,
          'leader-org': organisationRoleGroupLeader,
          'member-org': organisationRoleMember,
        },
      );

      expect(entries.map((entry) => entry.organisation.id).toSet(), {
        'owner-org',
        'admin-org',
        'secretary-org',
        'leader-org',
      });
      expect(
        entries.any((entry) => entry.organisation.id == 'member-org'),
        isFalse,
      );
    },
  );

  test('inactive or unapproved organisations are not shown', () {
    final entries = MyLocalLinkOrganisationService.entriesFromCandidateData(
      uid: uid,
      organisationDataById: {
        'inactive': {
          'name': 'Inactive',
          'createdBy': uid,
          'claimStatus': 'approved',
          'isActive': false,
        },
        'unapproved': {
          'name': 'Unapproved',
          'createdBy': uid,
          'claimStatus': 'pending',
          'isActive': true,
        },
      },
    );

    expect(entries, isEmpty);
  });

  test(
    'unrelated user cannot gain organisation access from compatibility data',
    () {
      final entries = MyLocalLinkOrganisationService.entriesFromCandidateData(
        uid: uid,
        organisationDataById: {
          'other-user-org': {
            'name': 'Other User Org',
            'createdBy': 'someone-else',
            'ownerId': 'someone-else',
            'adminUserIds': ['someone-else'],
            'claimStatus': 'approved',
            'listingOwnershipStatus': 'claimed',
            'isActive': true,
          },
          'member-only-org': {
            'name': 'Member Only Org',
            'claimStatus': 'approved',
            'listingOwnershipStatus': 'claimed',
            'isActive': true,
          },
        },
        rolesById: const {'member-only-org': organisationRoleMember},
      );

      expect(entries, isEmpty);
    },
  );

  test(
    'multiple active owner organisations appear while archived is separated',
    () {
      final organisationData = {
        'litter-pickers-test-3': {
          'name': 'Litter Pickers test 3',
          'ownerId': uid,
          'createdBy': uid,
          'adminUserIds': [uid],
          'claimStatus': 'approved',
          'listingOwnershipStatus': 'claimed',
          'isActive': true,
        },
        'little-litter-pickers': {
          'name': 'Little Litter Pickers',
          'ownerId': uid,
          'createdBy': uid,
          'adminUserIds': [uid],
          'claimStatus': 'approved',
          'listingOwnershipStatus': 'claimed',
          'isActive': true,
        },
        'litter': {
          'name': 'litter',
          'ownerId': uid,
          'createdBy': uid,
          'adminUserIds': [uid],
          'claimStatus': 'approved',
          'listingOwnershipStatus': 'claimed',
          'isActive': true,
        },
        'archived-litter': {
          'name': 'Archived litter',
          'ownerId': uid,
          'createdBy': uid,
          'adminUserIds': [uid],
          'claimStatus': 'approved',
          'listingOwnershipStatus': 'claimed',
          'isActive': false,
        },
      };

      final active = MyLocalLinkOrganisationService.entriesFromCandidateData(
        uid: uid,
        organisationDataById: organisationData,
      );
      final archived = MyLocalLinkOrganisationService.entriesFromCandidateData(
        uid: uid,
        organisationDataById: organisationData,
        includeArchived: true,
      );

      expect(active.map((entry) => entry.organisation.name).toList(), [
        'Litter Pickers test 3',
        'Little Litter Pickers',
        'litter',
      ]);
      expect(
        active.every((entry) => entry.role == organisationRoleOwner),
        isTrue,
      );
      expect(archived.map((entry) => entry.organisation.name), [
        'Archived litter',
      ]);
    },
  );

  test('broad createdBy and adminUserIds lookups are active-only', () {
    expect(
      MyLocalLinkOrganisationService.usesCreatedByLookup(
        includeArchived: false,
      ),
      isTrue,
    );
    expect(
      MyLocalLinkOrganisationService.usesCreatedByLookup(includeArchived: true),
      isFalse,
    );
    expect(
      MyLocalLinkOrganisationService.usesAdminUserIdsLookup(
        includeArchived: false,
      ),
      isTrue,
    );
    expect(
      MyLocalLinkOrganisationService.usesAdminUserIdsLookup(
        includeArchived: true,
      ),
      isFalse,
    );
  });

  test(
    'archived admin and role-managed organisations load through role data',
    () {
      final entries = MyLocalLinkOrganisationService.entriesFromCandidateData(
        uid: uid,
        includeArchived: true,
        organisationDataById: {
          'archived-admin': {
            'name': 'Archived Admin Org',
            'adminUserIds': [uid],
            'listingOwnershipStatus': 'claimed',
            'isActive': false,
          },
          'archived-secretary': {
            'name': 'Archived Secretary Org',
            'listingOwnershipStatus': 'claimed',
            'isActive': false,
          },
          'archived-unrelated': {
            'name': 'Archived Unrelated Org',
            'listingOwnershipStatus': 'claimed',
            'isActive': false,
          },
        },
        rolesById: const {
          'archived-secretary': organisationRoleSecretary,
          'archived-unrelated': organisationRoleMember,
        },
      );

      expect(entries.map((entry) => entry.organisation.id).toSet(), {
        'archived-admin',
        'archived-secretary',
      });
    },
  );
}
