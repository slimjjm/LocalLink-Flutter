"use strict";

const fs = require("node:fs");
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const {
  deleteDoc,
  doc,
  getDoc,
  runTransaction,
  setDoc,
  updateDoc,
  writeBatch,
} = require("firebase/firestore");

const projectId = "locallink-995a5";
const host = "127.0.0.1";
const port = 8080;
const challengeId = "challenge-1";
const productionChallengeId = "TcdIvbEw3nYCFgbpoxJ8";
const ownerId = "entrant";
const otherId = "other";
const commentId = "comment-1";
const now = new Date();
const future = new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000);

let testEnv;

function db(uid, provider = "password") {
  return testEnv.authenticatedContext(uid, {
    email: `${uid}@example.com`,
    firebase: { sign_in_provider: provider },
  }).firestore();
}

function adminDb() {
  return testEnv.authenticatedContext("admin", {
    email: "admin@example.com",
    firebase: { sign_in_provider: "password" },
  }).firestore();
}

function unauthDb() {
  return testEnv.unauthenticatedContext().firestore();
}

async function seed(path, data) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), path), data);
  });
}

async function seedAdminUser(uid = "admin") {
  await seed(`users/${uid}`, { isAdmin: true });
}

function challenge(overrides = {}) {
  return {
    activityKind: "community_challenge",
    isActive: true,
    challengeClosesAt: future,
    commentCount: 0,
    title: "Show us your Burntwood",
    createdBy: "creator",
    isPubliclyDiscoverable: true,
    ...overrides,
  };
}

function productionLikeChallenge(overrides = {}) {
  return challenge({
    activityAudienceScope: "everyone",
    activityContext: "standalone",
    allowPhotoEntries: true,
    attendeeCount: 2,
    audience: "All ages",
    cancelledOccurrence: false,
    category: "Social",
    commentCount: 1,
    createdAt: now,
    description: "Upload your best photo of Burntwood.",
    eventDate: new Date("2026-09-25T23:00:00.000Z"),
    eventTime: "19:46",
    followerAccess: "open",
    followerCount: 2,
    hostedByType: "locallink",
    isPubliclyDiscoverable: true,
    isRecurring: false,
    latitude: 52.6746116,
    location: "Ruston Road, Burntwood, UK",
    longitude: -1.9417733,
    nextOccurrenceId: null,
    occurrenceNumber: 1,
    organiserName: "james evans",
    photoUrl: "https://example.com/challenge.jpg",
    previousOccurrenceId: null,
    prizeDescription: "Prize",
    reminder1hSent: false,
    reminder24hSent: false,
    repeatEndDate: null,
    repeatType: "none",
    resumeAfter: null,
    seriesId: productionChallengeId,
    seriesStatus: "active",
    skipNext: false,
    tags: ["Social", "Community challenge", "Challenge", "show", "your", "burntwood"],
    updatedAt: now,
    ...overrides,
  });
}

function commentPayload(uid = ownerId, overrides = {}, id = challengeId) {
  return {
    userId: uid,
    userName: "Entrant",
    text: "My entry",
    createdAt: now,
    imageUrl: "https://example.com/entry.jpg",
    imagePath: `opportunityCommentPhotos/${id}/${uid}/${commentId}.jpg`,
    isChallengeEntry: true,
    ...overrides,
  };
}

function entryPayload(uid = ownerId, overrides = {}, id = challengeId) {
  return {
    userId: uid,
    commentId,
    imageUrl: "https://example.com/entry.jpg",
    imagePath: `opportunityCommentPhotos/${id}/${uid}/${commentId}.jpg`,
    caption: "My entry",
    createdAt: now,
    eligible: true,
    status: "active",
    ...overrides,
  };
}

function entryBatch(uid = ownerId, {
  firestore,
  comment = commentPayload(uid),
  entry = entryPayload(uid),
  count = 1,
} = {}) {
  const instance = firestore || db(uid);
  const batch = writeBatch(instance);
  batch.set(
    doc(instance, `opportunities/${challengeId}/comments/${commentId}`),
    comment,
  );
  batch.set(
    doc(instance, `opportunities/${challengeId}/entries/${uid}`),
    entry,
  );
  batch.update(doc(instance, `opportunities/${challengeId}`), {
    commentCount: count,
  });
  return batch.commit();
}

async function entryTransaction(uid = ownerId, {
  id = challengeId,
  firestore,
  comment = commentPayload(uid, {}, id),
  entry = entryPayload(uid, {}, id),
  nextCommentCount = 1,
} = {}) {
  const instance = firestore || db(uid);
  const opportunityRef = doc(instance, `opportunities/${id}`);
  const commentRef = doc(instance, `opportunities/${id}/comments/${commentId}`);
  const entryRef = doc(instance, `opportunities/${id}/entries/${uid}`);

  return runTransaction(instance, async (transaction) => {
    await transaction.get(opportunityRef);
    await transaction.get(entryRef);
    transaction.set(commentRef, comment);
    transaction.update(opportunityRef, { commentCount: nextCommentCount });
    transaction.set(entryRef, entry);
  });
}

function deleteEntryBatch({
  firestore,
  id = challengeId,
  entryUserId = ownerId,
  linkedCommentId = commentId,
  nextCommentCount = 0,
} = {}) {
  const instance = firestore || db(entryUserId);
  const batch = writeBatch(instance);
  batch.delete(
    doc(instance, `opportunities/${id}/comments/${linkedCommentId}`),
  );
  batch.delete(
    doc(instance, `opportunities/${id}/entries/${entryUserId}`),
  );
  batch.update(doc(instance, `opportunities/${id}`), {
    commentCount: nextCommentCount,
  });
  return batch.commit();
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

async function teardown() {
  await testEnv.cleanup();
}

async function beforeEachTest() {
  await testEnv.clearFirestore();
  await seed(`opportunities/${challengeId}`, challenge());
}

async function testOrdinaryUserCanCreateOwnValidEntry() {
  await allow("ordinary user create own challenge entry", entryBatch(ownerId));
}

async function testOrdinaryUserCanCreateEntryOnProductionLikeChallenge() {
  await seed(`opportunities/${challengeId}`, productionLikeChallenge());
  await allow(
    "ordinary user create challenge entry against production-like challenge",
    entryBatch(ownerId, { count: 2 }),
  );
}

async function testOrdinaryUserCanCreateEntryWithExactProductionTransactionShape() {
  await seed(
    `opportunities/${productionChallengeId}`,
    productionLikeChallenge({ seriesId: productionChallengeId }),
  );

  await allow(
    "ordinary user transaction creates entry against exact production challenge",
    entryTransaction(ownerId, {
      id: productionChallengeId,
      nextCommentCount: 2,
    }),
  );
}

async function testUnauthenticatedAndAnonymousDenied() {
  await deny(
    "unauthenticated challenge entry",
    entryBatch(ownerId, { firestore: unauthDb() }),
  );
  await deny(
    "anonymous challenge entry",
    entryBatch(ownerId, { firestore: db(ownerId, "anonymous") }),
  );
}

async function testBannedUserDenied() {
  await seed(`users/${ownerId}`, { isBanned: true });
  await deny("banned user challenge entry", entryBatch(ownerId));
}

async function testCannotCreateEntryForAnotherUid() {
  await deny(
    "entry for another uid",
    entryBatch(otherId, {
      firestore: db(ownerId),
      comment: commentPayload(ownerId),
      entry: entryPayload(otherId),
    }),
  );
}

async function testProtectedModerationFieldsDenied() {
  await deny(
    "entry moderation field",
    entryBatch(ownerId, {
      entry: entryPayload(ownerId, {
        moderationStatus: "approved",
      }),
    }),
  );
  await deny(
    "comment moderation field",
    entryBatch(ownerId, {
      comment: commentPayload(ownerId, {
        moderationStatus: "approved",
      }),
    }),
  );
}

async function testAnotherUserCannotEditOrDeleteEntry() {
  await seed(`opportunities/${challengeId}/entries/${ownerId}`, entryPayload(ownerId));
  await deny(
    "other user edit entry",
    updateDoc(doc(db(otherId), `opportunities/${challengeId}/entries/${ownerId}`), {
      caption: "Changed",
    }),
  );
  await deny(
    "other user delete entry",
    deleteDoc(doc(db(otherId), `opportunities/${challengeId}/entries/${ownerId}`)),
  );
}

async function seedExistingChallengeEntry() {
  await seed(`opportunities/${challengeId}`, challenge({ commentCount: 1 }));
  await seed(
    `opportunities/${challengeId}/comments/${commentId}`,
    commentPayload(ownerId),
  );
  await seed(
    `opportunities/${challengeId}/entries/${ownerId}`,
    entryPayload(ownerId),
  );
}

async function testOrdinaryUserCanDeleteOwnChallengeEntry() {
  await seedExistingChallengeEntry();
  await allow(
    "ordinary user delete own challenge entry and comment",
    deleteEntryBatch(),
  );
}

async function testOtherUserCannotDeleteChallengeEntry() {
  await seedExistingChallengeEntry();
  await deny(
    "other user delete challenge entry",
    deleteEntryBatch({ firestore: db(otherId) }),
  );
}

async function testGuestCannotDeleteChallengeEntry() {
  await seedExistingChallengeEntry();
  await deny(
    "unauthenticated delete challenge entry",
    deleteEntryBatch({ firestore: unauthDb() }),
  );
  await deny(
    "anonymous delete challenge entry",
    deleteEntryBatch({ firestore: db(ownerId, "anonymous") }),
  );
}

async function testAdminCanDeleteChallengeEntryForModeration() {
  await seedAdminUser();
  await seedExistingChallengeEntry();
  await allow(
    "admin delete challenge entry and comment",
    deleteEntryBatch({ firestore: adminDb() }),
  );
}

async function testCommentCountDecrementRequiresLinkedEntryCleanup() {
  await seedExistingChallengeEntry();
  await deny(
    "comment count decrement without entry cleanup",
    updateDoc(doc(db(ownerId), `opportunities/${challengeId}`), {
      commentCount: 0,
    }),
  );
}

async function testCommentCountIncrementCannotModifyOtherOpportunityFields() {
  const instance = db(ownerId);
  const batch = writeBatch(instance);
  batch.set(
    doc(instance, `opportunities/${challengeId}/comments/${commentId}`),
    commentPayload(ownerId),
  );
  batch.set(
    doc(instance, `opportunities/${challengeId}/entries/${ownerId}`),
    entryPayload(ownerId),
  );
  batch.update(doc(instance, `opportunities/${challengeId}`), {
    commentCount: 1,
    title: "Changed by entrant",
  });

  await deny("comment count update with unrelated opportunity field", batch.commit());
}

async function testClientCannotCreateOrganiserNotification() {
  await deny(
    "client-side organiser notification create",
    setDoc(
      doc(db(ownerId), "users/creator/notifications/client-notification"),
      {
        type: "opportunity_comment",
        title: "New comment",
        body: "Entrant commented",
        createdAt: now,
        isRead: false,
        opportunityId: challengeId,
        userId: ownerId,
      },
    ),
  );
}

async function testEntryTransactionDoesNotCreateAttendanceOrNotificationSideEffects() {
  await seed(
    `opportunities/${productionChallengeId}`,
    productionLikeChallenge({ seriesId: productionChallengeId }),
  );

  await allow(
    "entry transaction without attendance or notification writes",
    entryTransaction(ownerId, {
      id: productionChallengeId,
      nextCommentCount: 2,
    }),
  );

  await testEnv.withSecurityRulesDisabled(async (context) => {
    const instance = context.firestore();
    const attendee = await getDoc(
      doc(instance, `opportunities/${productionChallengeId}/attendees/${ownerId}`),
    );
    const notification = await getDoc(
      doc(instance, "users/creator/notifications/client-notification"),
    );

    if (attendee.exists()) {
      throw new Error("competition entry transaction unexpectedly created attendance");
    }
    if (notification.exists()) {
      throw new Error("competition entry transaction unexpectedly created notification");
    }
  });
}

async function testAdminCanModerateChallengeEntry() {
  await seedAdminUser();
  await seed(`opportunities/${challengeId}/entries/${ownerId}`, entryPayload(ownerId));
  await allow(
    "admin delete challenge entry",
    deleteDoc(doc(adminDb(), `opportunities/${challengeId}/entries/${ownerId}`)),
  );
}

async function testMalformedEntryDenied() {
  await deny(
    "missing eligible",
    entryBatch(ownerId, {
      entry: entryPayload(ownerId, {
        eligible: false,
      }),
    }),
  );
  await deny(
    "missing linked comment",
    entryBatch(ownerId, {
      comment: commentPayload(ownerId, {
        isChallengeEntry: false,
      }),
    }),
  );
  await deny(
    "bad comment count",
    entryBatch(ownerId, { count: 2 }),
  );
}

async function run() {
  await setup();
  try {
    for (const testCase of [
      testOrdinaryUserCanCreateOwnValidEntry,
      testOrdinaryUserCanCreateEntryOnProductionLikeChallenge,
      testOrdinaryUserCanCreateEntryWithExactProductionTransactionShape,
      testUnauthenticatedAndAnonymousDenied,
      testBannedUserDenied,
      testCannotCreateEntryForAnotherUid,
      testProtectedModerationFieldsDenied,
      testAnotherUserCannotEditOrDeleteEntry,
      testOrdinaryUserCanDeleteOwnChallengeEntry,
      testOtherUserCannotDeleteChallengeEntry,
      testGuestCannotDeleteChallengeEntry,
      testAdminCanDeleteChallengeEntryForModeration,
      testCommentCountDecrementRequiresLinkedEntryCleanup,
      testCommentCountIncrementCannotModifyOtherOpportunityFields,
      testClientCannotCreateOrganiserNotification,
      testEntryTransactionDoesNotCreateAttendanceOrNotificationSideEffects,
      testAdminCanModerateChallengeEntry,
      testMalformedEntryDenied,
    ]) {
      await beforeEachTest();
      await testCase();
    }
  } finally {
    await teardown();
  }
}

run().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
