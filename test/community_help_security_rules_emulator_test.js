"use strict";

const fs = require("node:fs");
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const {
  collectionGroup,
  deleteDoc,
  deleteField,
  doc,
  getDoc,
  getDocs,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
} = require("firebase/firestore");

const projectId = "locallink-995a5";
const host = "127.0.0.1";
const port = 8080;

let testEnv;

function db(uid, {
  provider = "password",
  email = `${uid}@example.com`,
  emailVerified = true,
} = {}) {
  return testEnv.authenticatedContext(uid, {
    email,
    email_verified: emailVerified,
    firebase: { sign_in_provider: provider },
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

function activePost(overrides = {}) {
  const now = Date.now();
  return {
    createdBy: "owner",
    createdByName: "Owner",
    type: "lost_found",
    mode: "lost",
    title: "Missing dog",
    description: "Brown spaniel",
    location: "Beacon Park, Lichfield",
    publicLocation: "Beacon Park, Lichfield",
    locationPrecision: "approximate",
    locationSource: "place_search",
    placeId: "place-1",
    approxLatitude: 52.683,
    approxLongitude: -1.826,
    discoveryRadiusMiles: 10,
    timing: "Today",
    eventDateText: "Today",
    observedDateOnly: true,
    observedAt: new Date(now - 60 * 60 * 1000),
    lastSeenAt: new Date(now - 60 * 60 * 1000),
    itemCategory: "Pet",
    petType: "Dog",
    keywords: ["brown", "dog", "lichfield"],
    collectionDetails: "",
    photoUrl: "https://example.com/dog.jpg",
    isFree: false,
    allowsPayment: false,
    status: "active",
    lifecycleKind: "lost_pet",
    renewalCount: 0,
    expiryReminderAt: new Date(now + 6 * 24 * 60 * 60 * 1000),
    expiryReminderStatus: "pending",
    isActive: true,
    createdAt: new Date(now - 2 * 60 * 60 * 1000),
    expiresAt: new Date(now + 7 * 24 * 60 * 60 * 1000),
    ...overrides,
  };
}

function createPostPayload(uid = "owner", overrides = {}) {
  const now = Date.now();
  return {
    ...activePost({
      createdBy: uid,
      createdByName: "Member",
      createdAt: serverTimestamp(),
      expiryReminderAt: new Date(now + 6 * 24 * 60 * 60 * 1000),
      expiresAt: new Date(now + 7 * 24 * 60 * 60 * 1000),
    }),
    ...overrides,
  };
}

function subscriptionPayload(uid = "owner", overrides = {}) {
  return {
    userId: uid,
    communityAlertsEnabled: true,
    enabledCategories: ["missingDogs", "missingCats"],
    categoryPreferences: {
      missingDogs: true,
      missingCats: true,
    },
    subscriptionType: "chosenArea",
    approxLatitude: 52.681,
    approxLongitude: -1.831,
    placeLabel: "Burntwood",
    maxRadiusMiles: 3,
    isActive: true,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...overrides,
  };
}

async function setup() {
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: {
      host,
      port,
      rules: fs.readFileSync("firestore.rules", "utf8"),
    },
  });
}

async function reset() {
  await testEnv.clearFirestore();
}

async function testValidPostCreateAndAnonymousCreateDenied() {
  await allow(
    "registered member creates the app's missing-pet payload",
    setDoc(doc(db("owner"), "communityHelpPosts/new-post"), createPostPayload()),
  );
  await deny(
    "anonymous member creates Community Help post",
    setDoc(
      doc(db("guest", { provider: "anonymous" }), "communityHelpPosts/guest-post"),
      createPostPayload("guest"),
    ),
  );
}

async function testOwnerTransitionsAndProtectedFields() {
  await seed("communityHelpPosts/post-1", activePost());

  await allow(
    "owner resolves own report",
    updateDoc(doc(db("owner"), "communityHelpPosts/post-1"), {
      status: "resolved",
      resolvedReason: "reunited",
      isActive: false,
      resolvedAt: serverTimestamp(),
      resolvedBy: "owner",
      expiryReminderStatus: "cancelled",
      closingUpdate: "Home safe.",
    }),
  );

  await seed("communityHelpPosts/post-2", activePost());
  for (const [label, fields] of [
    ["ownerId", { ownerId: "owner" }],
    ["createdBy", { createdBy: "attacker" }],
    ["moderation", { moderationStatus: "approved" }],
    ["alert version", { searchLocationVersion: 99 }],
    ["lookout count", { lookoutCount: 500 }],
    ["forged resolution", {
      status: "resolved",
      isActive: false,
      resolvedAt: serverTimestamp(),
      resolvedBy: "attacker",
      resolvedReason: "reunited",
      expiryReminderStatus: "cancelled",
    }],
  ]) {
    await deny(
      `owner cannot forge ${label}`,
      updateDoc(doc(db("owner"), "communityHelpPosts/post-2"), fields),
    );
  }

  await deny(
    "other member cannot resolve report",
    updateDoc(doc(db("other"), "communityHelpPosts/post-2"), {
      status: "resolved",
      resolvedReason: "reunited",
      isActive: false,
      resolvedAt: serverTimestamp(),
      resolvedBy: "other",
      expiryReminderStatus: "cancelled",
    }),
  );
}

async function testClaimedOwnerAndAdminActions() {
  await seed("communityHelpPosts/community-post", activePost({
    createdBy: "moderator",
    createdByModerator: true,
    communityAdded: true,
    ownerId: "claimed-owner",
    claimStatus: "approved",
    claimedBy: "claimed-owner",
  }));
  await seed("users/moderator", { isAdmin: true });

  await allow(
    "claimed owner resolves community-added report",
    updateDoc(doc(db("claimed-owner"), "communityHelpPosts/community-post"), {
      status: "resolved",
      resolvedReason: "reunited",
      isActive: false,
      resolvedAt: serverTimestamp(),
      resolvedBy: "claimed-owner",
      expiryReminderStatus: "cancelled",
    }),
  );

  await seed("communityHelpPosts/moderation-post", activePost());
  await allow(
    "admin applies moderation state",
    updateDoc(doc(db("moderator"), "communityHelpPosts/moderation-post"), {
      moderationStatus: "removed",
      removedBy: "moderator",
      removedAt: serverTimestamp(),
      isActive: false,
    }),
  );
}

async function testCommunityHelpDeleteSafety() {
  await seed("communityHelpPosts/owner-delete", activePost());
  await seed("communityHelpPosts/other-delete", activePost());
  await deny(
    "other member cannot delete report",
    deleteDoc(doc(db("other"), "communityHelpPosts/other-delete")),
  );
  await allow(
    "owner deletes own report",
    deleteDoc(doc(db("owner"), "communityHelpPosts/owner-delete")),
  );
}

async function testRenewalIsNarrowAndRaceSafeShape() {
  await seed("communityHelpPosts/expired-post", activePost({
    status: "expired",
    isActive: false,
    expiresAt: new Date(Date.now() - 1000),
  }));
  const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);
  await allow(
    "owner renews with exactly one renewal increment",
    updateDoc(doc(db("owner"), "communityHelpPosts/expired-post"), {
      status: "active",
      isActive: true,
      expiresAt,
      expiryReminderAt: new Date(expiresAt.getTime() - 24 * 60 * 60 * 1000),
      expiryReminderStatus: "pending",
      lastRenewedAt: serverTimestamp(),
      renewalCount: 1,
    }),
  );

  await seed("communityHelpPosts/forged-renewal", activePost({
    status: "expired",
    isActive: false,
  }));
  await deny(
    "owner cannot skip renewal count",
    updateDoc(doc(db("owner"), "communityHelpPosts/forged-renewal"), {
      status: "active",
      isActive: true,
      expiresAt,
      expiryReminderAt: new Date(expiresAt.getTime() - 24 * 60 * 60 * 1000),
      expiryReminderStatus: "pending",
      lastRenewedAt: serverTimestamp(),
      renewalCount: 8,
    }),
  );
}

async function testFollowersAreServerWrittenAndPrivate() {
  await seed("communityHelpPosts/post-a", activePost());
  await seed("communityHelpPosts/post-b", activePost());
  await seed("communityHelpPosts/post-a/followers/member", {
    userId: "member",
    postId: "post-a",
    notificationState: "active",
  });
  await seed("communityHelpPosts/post-b/followers/member", {
    userId: "member",
    postId: "post-b",
    notificationState: "active",
  });
  await seed("communityHelpPosts/post-a/followers/other", {
    userId: "other",
    postId: "post-a",
    notificationState: "active",
  });

  await deny(
    "member cannot follow as another uid",
    setDoc(doc(db("member"), "communityHelpPosts/post-a/followers/other-user"), {
      userId: "other-user",
      postId: "post-a",
      notificationState: "active",
    }),
  );
  await deny(
    "member cannot directly create own server follower record",
    setDoc(doc(db("member"), "communityHelpPosts/post-b/followers/member-2"), {
      userId: "member",
      postId: "post-b",
      notificationState: "active",
    }),
  );
  await allow(
    "member reads own follower relation",
    getDoc(doc(db("member"), "communityHelpPosts/post-a/followers/member")),
  );
  await deny(
    "member cannot read another follower relation",
    getDoc(doc(db("member"), "communityHelpPosts/post-a/followers/other")),
  );
  await deny(
    "anonymous user cannot read follower relation",
    getDoc(doc(db("member", { provider: "anonymous" }), "communityHelpPosts/post-a/followers/member")),
  );

  const memberDb = db("member");
  const ownFollowing = query(
    collectionGroup(memberDb, "followers"),
    where("userId", "==", "member"),
    where("notificationState", "==", "active"),
    where("postId", ">", ""),
  );
  const snapshot = await assertSucceeds(getDocs(ownFollowing));
  if (snapshot.size !== 2) {
    throw new Error(`own Following query should return 2 records, got ${snapshot.size}`);
  }
  await deny(
    "collection-group query cannot expose another user's follows",
    getDocs(query(
      collectionGroup(memberDb, "followers"),
      where("userId", "==", "other"),
      where("notificationState", "==", "active"),
      where("postId", ">", ""),
    )),
  );
}

async function testNearbySubscriptionOwnershipAndServerFields() {
  await allow(
    "member creates own chosen-area subscription",
    setDoc(
      doc(db("member"), "communityAlertSubscriptions/member"),
      subscriptionPayload("member"),
    ),
  );
  await deny(
    "member creates another user's subscription",
    setDoc(
      doc(db("member"), "communityAlertSubscriptions/other"),
      subscriptionPayload("other"),
    ),
  );
  await deny(
    "anonymous member creates subscription",
    setDoc(
      doc(db("guest", { provider: "anonymous" }), "communityAlertSubscriptions/guest"),
      subscriptionPayload("guest"),
    ),
  );
  await deny(
    "member forges server locality timestamps",
    setDoc(
      doc(db("other"), "communityAlertSubscriptions/other"),
      subscriptionPayload("other", {
        subscriptionType: "temporaryArea",
        establishedAt: new Date(0),
        lastSeenAt: serverTimestamp(),
      }),
    ),
  );

  await allow(
    "member disables own passive alerts",
    updateDoc(doc(db("member"), "communityAlertSubscriptions/member"), {
      communityAlertsEnabled: false,
      enabledCategories: [],
      isActive: false,
      updatedAt: serverTimestamp(),
    }),
  );
  await deny(
    "other member cannot read subscription coordinates",
    getDoc(doc(db("other"), "communityAlertSubscriptions/member")),
  );
  await seed("users/moderator", { isAdmin: true });
  await deny(
    "client-side admin cannot read private subscription coordinates",
    getDoc(doc(db("moderator"), "communityAlertSubscriptions/member")),
  );
  await allow(
    "member deletes own subscription",
    deleteDoc(doc(db("member"), "communityAlertSubscriptions/member")),
  );
}

async function testAlertHistoryIsReadOnlyAndPrivate() {
  for (const path of [
    "users/member/nearbyCommunityAlertReports/post-a",
    "users/member/nearbyCommunityAlertAreas/area-a",
    "users/member/notificationDailyCaps/nearbyCommunityAlerts_2026-10-04",
  ]) {
    await seed(path, { owner: "member", version: "initial" });
    await allow(`member reads ${path}`, getDoc(doc(db("member"), path)));
    await deny(`other member cannot read ${path}`, getDoc(doc(db("other"), path)));
    await deny(`member cannot write ${path}`, setDoc(doc(db("member"), path), {
      owner: "member",
      version: "forged",
    }));
    await deny(`member cannot delete ${path}`, deleteDoc(doc(db("member"), path)));
  }

  await seed("moderatorListingMetadata/post-a", {
    listingType: "community_help_missing_pet",
    moderatorNotes: "Private evidence",
  });
  await deny(
    "ordinary member cannot read moderation history",
    getDoc(doc(db("member"), "moderatorListingMetadata/post-a")),
  );
  await deny(
    "ordinary member cannot delete moderation history",
    deleteDoc(doc(db("member"), "moderatorListingMetadata/post-a")),
  );
}

async function testNotificationsAreServerWrittenAndReadUpdateIsNarrow() {
  await seed("users/member/notifications/notice-1", {
    type: "community_alert",
    title: "Missing dog nearby",
    body: "Open LocalLink",
    communityHelpPostId: "post-a",
    isRead: false,
    createdAt: new Date(),
  });

  await allow(
    "member reads own notification",
    getDoc(doc(db("member"), "users/member/notifications/notice-1")),
  );
  await deny(
    "member cannot read another user's notification",
    getDoc(doc(db("other"), "users/member/notifications/notice-1")),
  );
  await deny(
    "member cannot create arbitrary notification",
    setDoc(doc(db("member"), "users/member/notifications/forged"), {
      type: "admin_message",
      isRead: false,
    }),
  );
  await allow(
    "member marks own notification read",
    updateDoc(doc(db("member"), "users/member/notifications/notice-1"), {
      isRead: true,
    }),
  );
  await deny(
    "member cannot smuggle payload change with read update",
    updateDoc(doc(db("member"), "users/member/notifications/notice-1"), {
      isRead: false,
      communityHelpPostId: "different-post",
    }),
  );
  await deny(
    "anonymous user cannot read notification",
    getDoc(
      doc(db("member", { provider: "anonymous" }), "users/member/notifications/notice-1"),
    ),
  );
  await deny(
    "other member cannot delete notification",
    deleteDoc(doc(db("other"), "users/member/notifications/notice-1")),
  );
  await allow(
    "member deletes own notification",
    deleteDoc(doc(db("member"), "users/member/notifications/notice-1")),
  );
}

async function testPrivilegeEscalationAndClaimReviewDenied() {
  await seed("users/member", { displayName: "Member" });
  await deny(
    "member cannot make themselves admin",
    updateDoc(doc(db("member"), "users/member"), { isAdmin: true }),
  );
  await deny(
    "member cannot create admin profile",
    setDoc(doc(db("new-member"), "users/new-member"), {
      displayName: "New member",
      isAdmin: true,
    }),
  );

  await seed("listingClaims/claim-1", {
    listingType: "community_help_missing_pet",
    listingId: "post-a",
    claimantUserId: "member",
    claimantName: "Member",
    relationship: "Owner",
    status: "pending",
  });
  await deny(
    "claimant cannot approve own listing claim",
    updateDoc(doc(db("member"), "listingClaims/claim-1"), {
      status: "approved",
      reviewedBy: "member",
      reviewedAt: serverTimestamp(),
    }),
  );
  await deny(
    "member cannot create claim for another uid",
    setDoc(doc(db("member"), "listingClaims/forged-claim"), {
      listingType: "community_help_missing_pet",
      listingId: "post-a",
      claimantUserId: "other",
      claimantName: "Other",
      relationship: "Owner",
      evidence: "",
      status: "pending",
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }),
  );
}

async function testLegacyBusinessClaimRequiresServerFunction() {
  await seed("businesses/legacy-business", {
    businessName: "Legacy Business",
    ownerId: "",
    isClaimed: false,
    createdBy: "creator",
    createdByModerator: false,
    claimEmail: "assigned@example.com",
  });
  const claim = {
    ownerId: "claimant",
    isClaimed: true,
    claimedAt: serverTimestamp(),
    claimEmail: deleteField(),
  };
  await deny(
    "unassigned member cannot take legacy business",
    updateDoc(doc(db("claimant"), "businesses/legacy-business"), claim),
  );
  await deny(
    "unverified assigned email cannot claim legacy business",
    updateDoc(doc(db("claimant", {
      email: "assigned@example.com",
      emailVerified: false,
    }), "businesses/legacy-business"), claim),
  );
  await deny(
    "verified assigned email must use the server claim function",
    updateDoc(doc(db("claimant", {
      email: "assigned@example.com",
    }), "businesses/legacy-business"), claim),
  );
}

async function run() {
  await setup();
  try {
    for (const testCase of [
      testValidPostCreateAndAnonymousCreateDenied,
      testOwnerTransitionsAndProtectedFields,
      testClaimedOwnerAndAdminActions,
      testCommunityHelpDeleteSafety,
      testRenewalIsNarrowAndRaceSafeShape,
      testFollowersAreServerWrittenAndPrivate,
      testNearbySubscriptionOwnershipAndServerFields,
      testAlertHistoryIsReadOnlyAndPrivate,
      testNotificationsAreServerWrittenAndReadUpdateIsNarrow,
      testPrivilegeEscalationAndClaimReviewDenied,
      testLegacyBusinessClaimRequiresServerFunction,
    ]) {
      await reset();
      await testCase();
    }
  } finally {
    await testEnv.cleanup();
  }
}

run().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
