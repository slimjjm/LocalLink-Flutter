import '../models/organisation.dart';
import '../models/organisation_group.dart';
import '../models/organisation_role.dart';

class OrganisationPermissions {
  const OrganisationPermissions._();

  static bool isDirectOwnerOrAdmin(Organisation organisation, String? uid) {
    return organisation.isManagedBy(uid);
  }

  static bool isOrganisationManagerRole(String role) {
    return isOrganisationWideManagerRole(role);
  }

  static bool canManageGroup({
    required Organisation organisation,
    required OrganisationGroup group,
    required String? uid,
    String organisationRole = '',
  }) {
    return isDirectOwnerOrAdmin(organisation, uid) ||
        isOrganisationManagerRole(organisationRole) ||
        group.isLedBy(uid);
  }

  static bool supportsFixtures(Organisation organisation) {
    return organisation.capabilities.fixtures;
  }
}
