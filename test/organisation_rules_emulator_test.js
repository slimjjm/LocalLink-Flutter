"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const {
  collection,
  doc,
  getDoc,
  getDocs,
  query,
  setDoc,
  updateDoc,
  where,
} = require("firebase/firestore");

const projectId = "locallink-995a5";
const host = "127.0.0.1";
const port = 8080;
const now = new Date("2026-09-15T10:00:00.000Z");
const orgPath = "organisations/org-rules";
const groupPath = `${orgPath}/groups/group-rules`;
const secondGroupPath = `${orgPath}/groups/second-group`;
const unassignedGroupPath = `${orgPath}/groups/unassigned-group`;
const publicGroupPath = `${orgPath}/groups/public-group`;
const legacyVisibilityGroupPath = `${orgPath}/groups/legacy-visibility-group`;
const malformedVisibilityGroupPath = `${orgPath}/groups/malformed-visibility-group`;
const privateGroupPath = `${orgPath}/groups/private-group`;
const invitationPath = `${orgPath}/invitations/invite-1`;

let testEnv;

function db(uid, email = `${uid}@example.com`) {
  return testEnv.authenticatedContext(uid, {
    email,
    firebase: { sign_in_provider: "password" },
  }).firestore();
}

function anonymousDb(uid = "anonymous-guest") {
  return testEnv.authenticatedContext(uid, {
    firebase: { sign_in_provider: "anonymous" },
  }).firestore();
}

async function seed(path, data) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), path), data);
  });
}

async function allow(label, promise) {
  await assertSucceeds(promise).catch((error) => {
    throw new Error(`${label} should be allowed: ${error.message}`);
  });
}

async function deny(label, promise) {
  await assertFails(promise).catch((error) => {
    throw new Error(`${label} should be denied: ${error.message}`);
  });
}

const orgUpdate = {
  name: "LocalLink Test Club",
  description: "Updated details",
  category: "Sport & fitness",
  subcategories: ["Running"],
  publicLocation: "Burntwood",
  location: "Burntwood",
  phone: "",
  email: "",
  website: "",
  imageUrl: "",
  updatedAt: now,
};

function groupCreate(name, createdBy) {
  return {
    name,
    description: "A group",
    displayType: "team",
    category: "Sport & fitness",
    subcategory: "Running",
    ageLabel: "Adults",
    leaderUserIds: [],
    membershipMode: "open",
    visibility: "public",
    memberCount: 0,
    isActive: true,
    createdBy,
    updatedBy: createdBy,
    createdAt: now,
    updatedAt: now,
  };
}

function groupUpdate({ leaderIds = ["leader"], updatedBy = "leader" } = {}) {
  return {
    name: "Updated Group",
    description: "Updated safely",
    displayType: "team",
    category: "Sport & fitness",
    subcategory: "Running",
    ageLabel: "Adults",
    leaderUserIds: leaderIds,
    membershipMode: "approval_required",
    visibility: "private",
    memberCount: 1,
    isActive: true,
    createdBy: "owner",
    updatedBy,
    createdAt: now,
    updatedAt: now,
  };
}

async function setupFixtures() {
  await testEnv.clearFirestore();
  await seed(orgPath, {
    ...orgUpdate,
    description: "Original details",
    ownerId: "owner",
    adminUserIds: ["admin"],
    createdBy: "owner",
    createdByModerator: false,
    claimStatus: "approved",
    listingOwnershipStatus: "claimed",
    isActive: true,
    createdAt: now,
  });
  await seed(groupPath, groupUpdate());
  await seed(secondGroupPath, {
    ...groupUpdate({ leaderIds: ["leader"] }),
    name: "Second Assigned Group",
  });
  await seed(unassignedGroupPath, {
    ...groupUpdate({ leaderIds: [] }),
    name: "Unassigned Group",
  });
  await seed(publicGroupPath, {
    ...groupCreate("Public Group", "owner"),
  });
  const legacyVisibilityGroup = groupCreate("Legacy Visibility Group", "owner");
  delete legacyVisibilityGroup.visibility;
  await seed(legacyVisibilityGroupPath, legacyVisibilityGroup);
  await seed(malformedVisibilityGroupPath, {
    ...groupCreate("Malformed Visibility Group", "owner"),
    visibility: "members_only",
  });
  await seed(privateGroupPath, {
    ...groupUpdate(),
    name: "Private Group",
    leaderUserIds: [],
    visibility: "private",
  });
  await seed(`${orgPath}/members/owner`, {
    userId: "owner",
    userName: "Owner",
    role: "owner",
    status: "active",
    groupIds: [],
  });
  await seed(`${orgPath}/members/admin`, {
    userId: "admin",
    userName: "Admin",
    role: "organisation_admin",
    status: "active",
    groupIds: [],
  });
  await seed(`${orgPath}/members/secretary`, {
    userId: "secretary",
    userName: "Secretary",
    role: "secretary",
    status: "active",
    groupIds: [],
  });
  await seed("users/secretary/organisationRoles/org-rules", {
    organisationId: "org-rules",
    organisationName: "LocalLink Test Club",
    role: "secretary",
    roleLabel: "Secretary",
    groupIds: [],
    status: "active",
  });
  await seed(`${orgPath}/members/leader`, {
    userId: "leader",
    userName: "Leader",
    role: "group_leader",
    status: "active",
    groupIds: ["group-rules", "second-group"],
  });
  await seed("users/leader/organisationRoles/org-rules", {
    organisationId: "org-rules",
    organisationName: "LocalLink Test Club",
    role: "group_leader",
    roleLabel: "Group leader",
    groupIds: ["group-rules", "second-group"],
    status: "active",
  });
  await seed(`${groupPath}/members/leader`, {
    userId: "leader",
    userName: "Leader",
    role: "group_leader",
    status: "active",
  });
  await seed(`${secondGroupPath}/members/leader`, {
    userId: "leader",
    userName: "Leader",
    role: "group_leader",
    status: "active",
  });
  await seed(`${orgPath}/members/member`, {
    userId: "member",
    userName: "Member",
    role: "member",
    status: "active",
    groupIds: ["group-rules"],
  });
  await seed("users/member", {
    displayName: "Member",
    name: "Member",
    createdAt: now,
  });
  await seed("users/founder", {
    displayName: "Founder",
    name: "Founder",
    isAdmin: true,
    createdAt: now,
  });
  await seed("businesses/public-business", {
    businessName: "Public Business",
    ownerId: "owner",
    createdBy: "owner",
    isActive: true,
    isClaimed: true,
    category: "Dog Grooming",
    serviceArea: "Burntwood",
    createdAt: now,
  });
  await seed("businesses/public-business/services/service-one", {
    name: "Dog grooming",
    isActive: true,
    isPublished: true,
    isEnabled: true,
    createdAt: now,
  });
  await seed(`${groupPath}/members/member`, {
    userId: "member",
    userName: "Member",
    role: "member",
    status: "active",
  });
  await seed(invitationPath, {
    email: "invitee@example.com",
    emailLower: "invitee@example.com",
    role: "member",
    status: "pending",
    tokenHash: "hashed-token",
    invitedBy: "owner",
  });
  await seed(`${orgPath}/announcements/announcement-org`, {
    message: "Hello organisation",
    targetType: "organisation",
    targetGroupId: "",
    createdBy: "owner",
  });
  await seed(`${orgPath}/announcements/announcement-group`, {
    message: "Hello group",
    targetType: "group",
    targetGroupId: "group-rules",
    createdBy: "leader",
  });
  for (const [id, name] of [
    ["owner-active-one", "Litter Pickers test 3"],
    ["owner-active-two", "Little Litter Pickers"],
    ["owner-active-three", "litter"],
  ]) {
    await seed(`organisations/${id}`, {
      ...orgUpdate,
      name,
      ownerId: "owner",
      adminUserIds: ["owner"],
      createdBy: "owner",
      createdByModerator: false,
      claimStatus: "approved",
      listingOwnershipStatus: "claimed",
      isActive: true,
    });
  }
}

async function run() {
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: {
      host,
      port,
      rules: fs.readFileSync("firestore.rules", "utf8"),
    },
  });

  await setupFixtures();

  for (const uid of ["owner", "admin", "secretary"]) {
    await allow(`${uid} updates organisation profile`, updateDoc(doc(db(uid), orgPath), orgUpdate));
    await allow(`${uid} creates group`, setDoc(doc(db(uid), `${orgPath}/groups/${uid}-created`), groupCreate(`${uid} group`, uid)));
    await allow(`${uid} reads invitations`, getDoc(doc(db(uid), invitationPath)));
    await allow(`${uid} reads organisation announcement`, getDoc(doc(db(uid), `${orgPath}/announcements/announcement-org`)));
  }

  const ownerActiveOrganisations = await assertSucceeds(getDocs(query(
    collection(db("owner"), "organisations"),
    where("ownerId", "==", "owner"),
    where("isActive", "==", true)
  )));
  assert(
    ownerActiveOrganisations.docs.length >= 4,
    "owner active organisation lookup should return multiple organisations"
  );

  const guest = anonymousDb();
  await allow("anonymous guest can read public business", getDoc(doc(guest, "businesses/public-business")));
  await allow("anonymous guest can read public business service", getDoc(doc(guest, "businesses/public-business/services/service-one")));
  await allow("anonymous guest can read active public organisation", getDoc(doc(guest, orgPath)));
  await allow("anonymous guest can read public group", getDoc(doc(guest, publicGroupPath)));
  await deny("anonymous guest cannot read private user profile", getDoc(doc(guest, "users/member")));
  await deny("anonymous guest cannot create profile document", setDoc(doc(guest, "users/anonymous-guest"), {
    displayName: "Guest",
    createdAt: now,
  }));
  await deny("anonymous guest cannot save activity", setDoc(doc(guest, "users/anonymous-guest/savedOpportunities/one"), {
    savedAt: now,
  }));
  await allow("anonymous guest can record share analytics without user id", setDoc(doc(guest, "shares/anonymous-share"), {
    itemType: "activity",
    itemId: "public-activity",
    createdAt: now,
  }));
  await deny("anonymous guest cannot attach anonymous uid to share analytics", setDoc(doc(guest, "shares/anonymous-share-with-user"), {
    itemType: "activity",
    itemId: "public-activity",
    userId: "anonymous-guest",
    createdAt: now,
  }));
  await deny("anonymous guest cannot create report", setDoc(doc(guest, "reports/anonymous-report"), {
    reporterUserId: "anonymous-guest",
    status: "open",
    createdAt: now,
  }));

  await allow("secretary can read own role index", getDocs(collection(
    db("secretary"),
    "users/secretary/organisationRoles"
  )));

  await deny("group leader cannot update organisation profile", updateDoc(doc(db("leader"), orgPath), orgUpdate));
  await deny("normal member cannot update organisation profile", updateDoc(doc(db("member"), orgPath), orgUpdate));
  await deny("non-member cannot update organisation profile", updateDoc(doc(db("outsider"), orgPath), orgUpdate));

  await allow("group leader reads assigned private group", getDoc(doc(db("leader"), groupPath)));
  const leaderMemberships = await assertSucceeds(getDocs(collection(
    db("leader"),
    "users/leader/organisationRoles"
  )));
  assert(
    leaderMemberships.docs.some((memberDoc) => memberDoc.id === "org-rules"),
    "group leader should discover their organisation role index"
  );
  assert(
    leaderMemberships.docs.some((memberDoc) => memberDoc.data().groupIds?.includes("second-group")),
    "group leader should discover multiple assigned groups on their org member record"
  );
  await deny("group leader cannot read another user's role index", getDocs(collection(
    db("leader"),
    "users/admin/organisationRoles"
  )));
  await allow("group leader updates assigned group without changing leaders", updateDoc(doc(db("leader"), groupPath), groupUpdate()));
  await allow("group leader can update assigned group image", updateDoc(doc(db("leader"), groupPath), {
    ...groupUpdate({ leaderIds: ["leader"], updatedBy: "leader" }),
    imageUrl: "https://example.com/group.jpg",
  }));
  await allow("group leader updates second assigned group", updateDoc(doc(db("leader"), secondGroupPath), {
    ...groupUpdate({ leaderIds: ["leader"], updatedBy: "leader" }),
    name: "Second Assigned Group Updated",
  }));
  await deny("group leader cannot update unassigned group", updateDoc(doc(db("leader"), unassignedGroupPath), {
    ...groupUpdate({ leaderIds: [], updatedBy: "leader" }),
    name: "Unassigned Group Updated",
  }));
  await deny("group leader cannot change leader ids", updateDoc(doc(db("leader"), groupPath), groupUpdate({ leaderIds: ["leader", "outsider"] })));
  await deny("group leader cannot create organisation groups", setDoc(doc(db("leader"), `${orgPath}/groups/leader-created`), groupCreate("Leader group", "leader")));
  await deny("group leader cannot read invitations", getDoc(doc(db("leader"), invitationPath)));
  await deny("group leader cannot make themselves admin", updateDoc(doc(db("leader"), `${orgPath}/members/leader`), {
    role: "organisation_admin",
    status: "active",
    groupIds: ["group-rules", "second-group"],
    updatedAt: now,
  }));
  await deny("group leader cannot make someone else a leader", updateDoc(doc(db("leader"), unassignedGroupPath), {
    leaderUserIds: ["leader", "member"],
    updatedAt: now,
  }));

  await allow("normal member reads own org member doc", getDoc(doc(db("member"), `${orgPath}/members/member`)));
  await deny("normal member cannot enumerate org member records", getDocs(collection(db("member"), `${orgPath}/members`)));
  await deny("normal member cannot read other org member doc", getDoc(doc(db("member"), `${orgPath}/members/admin`)));
  await allow("non-member can read public group", getDoc(doc(db("outsider"), publicGroupPath)));
  await deny("non-member cannot read an unconfirmed legacy group with missing visibility", getDoc(doc(db("outsider"), legacyVisibilityGroupPath)));
  await deny("non-member cannot read private group", getDoc(doc(db("outsider"), privateGroupPath)));
  await deny("non-member cannot read malformed visibility group", getDoc(doc(db("outsider"), malformedVisibilityGroupPath)));
  await allow("organisation manager can read malformed visibility group", getDoc(doc(db("owner"), malformedVisibilityGroupPath)));
  await deny("non-member cannot update legacy visibility group", updateDoc(doc(db("outsider"), legacyVisibilityGroupPath), {
    updatedAt: now,
  }));
  await allow("member can mark readable organisation announcement as read", setDoc(doc(db("member"), `${orgPath}/announcements/announcement-org/reads/member`), {
    userId: "member",
    readAt: now,
  }));
  await deny("member cannot mark another user's announcement read state", setDoc(doc(db("member"), `${orgPath}/announcements/announcement-org/reads/admin`), {
    userId: "admin",
    readAt: now,
  }));
  await deny("outsider cannot mark private announcement as read", setDoc(doc(db("outsider"), `${orgPath}/announcements/announcement-org/reads/outsider`), {
    userId: "outsider",
    readAt: now,
  }));

  await seed("organisations/archived-org", {
    ...orgUpdate,
    name: "Archived Club",
    ownerId: "owner",
    adminUserIds: ["admin"],
    createdBy: "owner",
    createdByModerator: false,
    claimStatus: "approved",
    listingOwnershipStatus: "claimed",
    isActive: false,
  });
  await allow("owner can read archived organisation", getDoc(doc(db("owner"), "organisations/archived-org")));
  await deny("non-member cannot read archived organisation", getDoc(doc(db("outsider"), "organisations/archived-org")));

  await deny("normal user cannot self-issue an organisation member record", setDoc(doc(db("member-self"), `${orgPath}/members/member-self`), {
    userId: "member-self",
    role: "member",
    status: "active",
  }));
  await deny("member cannot make themselves admin", setDoc(doc(db("member-admin"), `${orgPath}/members/member-admin`), {
    userId: "member-admin",
    role: "organisation_admin",
    status: "active",
  }));
  await deny("member cannot make themselves secretary", setDoc(doc(db("member-secretary"), `${orgPath}/members/member-secretary`), {
    userId: "member-secretary",
    role: "secretary",
    status: "active",
  }));
  await deny("member cannot make themselves group leader", setDoc(doc(db("member-leader"), `${orgPath}/members/member-leader`), {
    userId: "member-leader",
    role: "group_leader",
    status: "active",
  }));
  await deny("member cannot add themselves to adminUserIds", updateDoc(doc(db("member"), orgPath), {
    adminUserIds: ["admin", "member"],
    updatedAt: now,
  }));
  await deny("member cannot add themselves as group leader", updateDoc(doc(db("member"), groupPath), {
    leaderUserIds: ["leader", "member"],
    updatedAt: now,
  }));

  await deny("client cannot create invitation directly", setDoc(doc(db("owner"), `${orgPath}/invitations/member-created`), {
    email: "someone@example.com",
    emailLower: "someone@example.com",
    role: "member",
    status: "pending",
    tokenHash: "secret",
    invitedBy: "owner",
  }));
  await deny("normal member cannot read invitation", getDoc(doc(db("member"), invitationPath)));
  await seed(`${orgPath}/invitations/backend-created`, {
    email: "backend@example.com",
    emailLower: "backend@example.com",
    role: "secretary",
    status: "pending",
    tokenHash: "secret",
    invitedBy: "owner",
  });
  await seed(`${orgPath}/members/invitee`, {
    userId: "invitee",
    userName: "Invitee",
    email: "invitee@example.com",
    role: "secretary",
    status: "active",
    groupIds: [],
  });
  await allow("accepted invitee can read own role record", getDoc(doc(db("invitee"), `${orgPath}/members/invitee`)));

  const baseOpportunity = {
    title: "Saturday session",
    description: "A local activity",
    category: "Fitness & Sport",
    location: "Burntwood",
    isActive: true,
    createdAt: now,
    updatedAt: now,
  };
  const challengeTestNow = Date.now();
  const challengeFields = {
    activityKind: "community_challenge",
    challengeClosesAt: new Date(challengeTestNow + 7 * 24 * 60 * 60 * 1000),
    allowPhotoEntries: true,
  };
  await allow("founder admin can create standalone community challenge", setDoc(doc(db("founder"), "opportunities/founder-challenge"), {
    ...baseOpportunity,
    ...challengeFields,
    createdBy: "founder",
    activityAudienceScope: "everyone",
    isPubliclyDiscoverable: true,
    hostedByType: "locallink",
  }));
  await deny("founder admin cannot create a challenge with an expired deadline", setDoc(doc(db("founder"), "opportunities/expired-founder-challenge"), {
    ...baseOpportunity,
    ...challengeFields,
    challengeClosesAt: new Date(challengeTestNow - 24 * 60 * 60 * 1000),
    createdBy: "founder",
    activityAudienceScope: "everyone",
    isPubliclyDiscoverable: true,
    hostedByType: "locallink",
  }));
  await deny("ordinary member cannot create standalone community challenge", setDoc(doc(db("member"), "opportunities/member-challenge"), {
    ...baseOpportunity,
    ...challengeFields,
    createdBy: "member",
    activityAudienceScope: "everyone",
    isPubliclyDiscoverable: true,
    hostedByType: "locallink",
  }));
  await allow("claimed business owner can create hosted community challenge", setDoc(doc(db("owner"), "opportunities/business-challenge"), {
    ...baseOpportunity,
    ...challengeFields,
    createdBy: "owner",
    businessId: "public-business",
    businessName: "Public Business",
    hostedByType: "business",
    activityAudienceScope: "everyone",
    isPubliclyDiscoverable: true,
  }));
  await deny("ordinary member cannot create challenge for another business", setDoc(doc(db("member"), "opportunities/impersonated-business-challenge"), {
    ...baseOpportunity,
    ...challengeFields,
    createdBy: "member",
    businessId: "public-business",
    businessName: "Public Business",
    hostedByType: "business",
    activityAudienceScope: "everyone",
    isPubliclyDiscoverable: true,
  }));
  await allow("organisation owner can create organisation community challenge", setDoc(doc(db("owner"), "opportunities/org-challenge"), {
    ...baseOpportunity,
    ...challengeFields,
    createdBy: "owner",
    organisationId: "org-rules",
    activityAudienceScope: "everyone",
    isPubliclyDiscoverable: true,
    hostedByType: "organisation",
  }));
  await allow("group leader can create assigned group community challenge", setDoc(doc(db("leader"), "opportunities/group-challenge"), {
    ...baseOpportunity,
    ...challengeFields,
    createdBy: "leader",
    organisationId: "org-rules",
    groupId: "group-rules",
    activityAudienceScope: "group",
    isPubliclyDiscoverable: false,
    hostedByType: "group",
  }));
  await deny("group leader cannot create unassigned group community challenge", setDoc(doc(db("leader"), "opportunities/unassigned-group-challenge"), {
    ...baseOpportunity,
    ...challengeFields,
    createdBy: "leader",
    organisationId: "org-rules",
    groupId: "unassigned-group",
    activityAudienceScope: "group",
    isPubliclyDiscoverable: false,
    hostedByType: "group",
  }));
  await allow("owner can create public organisation activity", setDoc(doc(db("owner"), "opportunities/org-public"), {
    ...baseOpportunity,
    createdBy: "owner",
    organisationId: "org-rules",
    activityAudienceScope: "everyone",
    isPubliclyDiscoverable: true,
  }));
  await allow("organisation admin can create whole organisation activity", setDoc(doc(db("admin"), "opportunities/org-members"), {
    ...baseOpportunity,
    createdBy: "admin",
    organisationId: "org-rules",
    activityAudienceScope: "organisation",
    isPubliclyDiscoverable: false,
  }));
  await allow("secretary can create group activity", setDoc(doc(db("secretary"), "opportunities/secretary-group"), {
    ...baseOpportunity,
    createdBy: "secretary",
    organisationId: "org-rules",
    groupId: "group-rules",
    activityAudienceScope: "group",
    isPubliclyDiscoverable: false,
  }));
  await allow("group leader can create assigned group activity", setDoc(doc(db("leader"), "opportunities/leader-group"), {
    ...baseOpportunity,
    createdBy: "leader",
    organisationId: "org-rules",
    groupId: "group-rules",
    activityAudienceScope: "group",
    isPubliclyDiscoverable: false,
  }));
  await allow("group leader can create second assigned group activity", setDoc(doc(db("leader"), "opportunities/leader-second-group"), {
    ...baseOpportunity,
    createdBy: "leader",
    organisationId: "org-rules",
    groupId: "second-group",
    activityAudienceScope: "group",
    isPubliclyDiscoverable: false,
  }));
  await deny("group leader cannot create unassigned group activity", setDoc(doc(db("leader"), "opportunities/leader-unassigned-group"), {
    ...baseOpportunity,
    createdBy: "leader",
    organisationId: "org-rules",
    groupId: "unassigned-group",
    activityAudienceScope: "group",
    isPubliclyDiscoverable: false,
  }));
  await deny("group leader cannot create public organisation activity", setDoc(doc(db("leader"), "opportunities/leader-public"), {
    ...baseOpportunity,
    createdBy: "leader",
    organisationId: "org-rules",
    activityAudienceScope: "everyone",
    isPubliclyDiscoverable: true,
  }));
  await deny("group leader cannot publish group activity publicly", setDoc(doc(db("leader"), "opportunities/leader-leaky-group"), {
    ...baseOpportunity,
    createdBy: "leader",
    organisationId: "org-rules",
    groupId: "group-rules",
    activityAudienceScope: "group",
    isPubliclyDiscoverable: true,
  }));
  await deny("normal member cannot create organisation activity", setDoc(doc(db("member"), "opportunities/member-org"), {
    ...baseOpportunity,
    createdBy: "member",
    organisationId: "org-rules",
    activityAudienceScope: "organisation",
    isPubliclyDiscoverable: false,
  }));
  await deny("non-member cannot create organisation activity", setDoc(doc(db("outsider"), "opportunities/outsider-org"), {
    ...baseOpportunity,
    createdBy: "outsider",
    organisationId: "org-rules",
    activityAudienceScope: "everyone",
    isPubliclyDiscoverable: true,
  }));

  await allow("standalone public activity remains readable", setDoc(doc(db("member"), "opportunities/standalone-public"), {
    ...baseOpportunity,
    createdBy: "member",
    activityAudienceScope: "everyone",
    isPubliclyDiscoverable: true,
  }));
  await allow("anonymous guest can read standalone public activity", getDoc(doc(guest, "opportunities/standalone-public")));
  await deny("anonymous guest cannot create standalone activity", setDoc(doc(guest, "opportunities/anonymous-activity"), {
    ...baseOpportunity,
    createdBy: "anonymous-guest",
    activityAudienceScope: "everyone",
    isPubliclyDiscoverable: true,
  }));
  await deny("anonymous guest cannot comment on activity", setDoc(doc(guest, "opportunities/standalone-public/comments/anonymous-comment"), {
    userId: "anonymous-guest",
    text: "Hello",
    createdAt: now,
  }));
  await deny("anonymous guest cannot attend activity", setDoc(doc(guest, "opportunities/standalone-public/attendees/anonymous-guest"), {
    userId: "anonymous-guest",
    createdAt: now,
  }));
  await allow("secretary can create unassigned group activity for privacy checks", setDoc(doc(db("secretary"), "opportunities/secretary-unassigned-group"), {
    ...baseOpportunity,
    createdBy: "secretary",
    organisationId: "org-rules",
    groupId: "unassigned-group",
    activityAudienceScope: "group",
    isPubliclyDiscoverable: false,
  }));

  await allow("public organisation activity can be read by non-member", getDoc(doc(db("outsider"), "opportunities/org-public")));
  await allow("standalone activity can be read by non-member", getDoc(doc(db("outsider"), "opportunities/standalone-public")));
  await allow("organisation member can read organisation-only activity", getDoc(doc(db("member"), "opportunities/org-members")));
  await allow("owner can read organisation-only activity", getDoc(doc(db("owner"), "opportunities/org-members")));
  await allow("admin can read organisation-only activity", getDoc(doc(db("admin"), "opportunities/org-members")));
  await allow("secretary can read organisation-only activity", getDoc(doc(db("secretary"), "opportunities/org-members")));
  await deny("non-member cannot read organisation-only activity", getDoc(doc(db("outsider"), "opportunities/org-members")));

  await allow("group member can read their group-only activity", getDoc(doc(db("member"), "opportunities/leader-group")));
  await allow("group leader can read their assigned group-only activity", getDoc(doc(db("leader"), "opportunities/leader-group")));
  await allow("organisation manager can read group-only activity", getDoc(doc(db("secretary"), "opportunities/leader-group")));
  await deny("non-member cannot read group-only activity", getDoc(doc(db("outsider"), "opportunities/leader-group")));
  await deny("member of another group cannot read unrelated group activity", getDoc(doc(db("member"), "opportunities/leader-second-group")));
  await deny("group leader cannot read unassigned group activity", getDoc(doc(db("leader"), "opportunities/secretary-unassigned-group")));

  await testEnv.cleanup();
}

run()
  .then(() => {
    console.log("Organisation Firestore rules emulator tests passed");
  })
  .catch(async (error) => {
    console.error(error);
    if (testEnv) await testEnv.cleanup();
    process.exit(1);
  });
