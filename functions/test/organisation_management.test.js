"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const {
  ORGANISATION_ROLES,
  buildOrganisationInvitationEmail,
  canAssignRole,
  canManageOrganisationRole,
  invitationLink,
  invitationToken,
  isValidEmail,
  normaliseEmail,
  normaliseRole,
  roleLabel,
  tokenHash,
} = require("../organisation_management");

test("normalises organisation roles and labels safely", () => {
  assert.equal(normaliseRole("secretary"), ORGANISATION_ROLES.SECRETARY);
  assert.equal(normaliseRole("unexpected"), ORGANISATION_ROLES.MEMBER);
  assert.equal(roleLabel("organisation_admin"), "Organisation admin");
  assert.equal(roleLabel("group_leader"), "Group leader");
});

test("organisation managers come from owner, legacy admins or active manager member roles", () => {
  assert.equal(
    canManageOrganisationRole({
      uid: "owner-1",
      organisation: { ownerId: "owner-1", adminUserIds: [] },
      member: null,
    }),
    true
  );
  assert.equal(
    canManageOrganisationRole({
      uid: "admin-1",
      organisation: { ownerId: "owner-1", adminUserIds: ["admin-1"] },
      member: null,
    }),
    true
  );
  assert.equal(
    canManageOrganisationRole({
      uid: "secretary-1",
      organisation: { ownerId: "owner-1", adminUserIds: [] },
      member: { role: "secretary", status: "active" },
    }),
    true
  );
  assert.equal(
    canManageOrganisationRole({
      uid: "leader-1",
      organisation: { ownerId: "owner-1", adminUserIds: [] },
      member: { role: "group_leader", status: "active" },
    }),
    false
  );
});

test("role assignment prevents non-owners from creating owners", () => {
  assert.equal(
    canAssignRole({
      actorRole: ORGANISATION_ROLES.OWNER,
      targetRole: ORGANISATION_ROLES.ADMIN,
    }),
    true
  );
  assert.equal(
    canAssignRole({
      actorRole: ORGANISATION_ROLES.ADMIN,
      targetRole: ORGANISATION_ROLES.OWNER,
    }),
    false
  );
  assert.equal(
    canAssignRole({
      actorRole: ORGANISATION_ROLES.SECRETARY,
      targetRole: ORGANISATION_ROLES.ADMIN,
    }),
    false
  );
  assert.equal(
    canAssignRole({
      actorRole: ORGANISATION_ROLES.SECRETARY,
      targetRole: ORGANISATION_ROLES.GROUP_LEADER,
    }),
    true
  );
});

test("organisation invitation email contains a safe direct accept link", () => {
  const token = invitationToken();
  const link = invitationLink(token);
  const email = buildOrganisationInvitationEmail({
    email: "PERSON@Example.COM",
    organisationName: "<Town Club>",
    inviterName: "James",
    role: ORGANISATION_ROLES.GROUP_LEADER,
    link,
  });

  assert.equal(isValidEmail("PERSON@Example.COM"), true);
  assert.equal(normaliseEmail("PERSON@Example.COM"), "person@example.com");
  assert.equal(email.to, "person@example.com");
  assert.match(email.text, new RegExp(link));
  assert.match(email.html, /&lt;Town Club&gt;/);
  assert.notEqual(tokenHash(token), token);
});
