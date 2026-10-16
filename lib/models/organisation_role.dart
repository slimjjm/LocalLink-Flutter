const organisationRoleOwner = 'owner';
const organisationRoleAdmin = 'organisation_admin';
const organisationRoleSecretary = 'secretary';
const organisationRoleGroupLeader = 'group_leader';
const organisationRoleMember = 'member';

const organisationManageRoles = {
  organisationRoleOwner,
  organisationRoleAdmin,
  organisationRoleSecretary,
};

const organisationInviteRoles = [
  organisationRoleAdmin,
  organisationRoleSecretary,
  organisationRoleGroupLeader,
  organisationRoleMember,
];

String organisationRoleLabel(String role) {
  return switch (role) {
    organisationRoleOwner => 'Owner',
    organisationRoleAdmin => 'Organisation admin',
    organisationRoleSecretary => 'Secretary',
    organisationRoleGroupLeader => 'Group leader',
    _ => 'Member',
  };
}

String normaliseOrganisationRole(String role) {
  return organisationInviteRoles.contains(role) ? role : organisationRoleMember;
}

bool isOrganisationWideManagerRole(String role) {
  return organisationManageRoles.contains(role);
}
