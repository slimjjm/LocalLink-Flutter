"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const {
  notifyOpportunityParticipationCreated,
  participationNotificationId,
} = require("../opportunity_participation_notifications");

const serverTimestamp = { __type: "serverTimestamp" };
const admin = {
  firestore: {
    FieldValue: {
      serverTimestamp: () => serverTimestamp,
    },
  },
};

class FakeDocRef {
  constructor(store, path) {
    this.store = store;
    this.path = path;
  }

  collection(name) {
    return new FakeCollectionRef(this.store, `${this.path}/${name}`);
  }

  async get() {
    const data = this.store.get(this.path);
    return {
      exists: data !== undefined,
      data: () => data,
    };
  }

  async create(data) {
    if (this.store.has(this.path)) {
      const error = new Error("already exists");
      error.code = 6;
      throw error;
    }
    this.store.set(this.path, data);
  }
}

class FakeCollectionRef {
  constructor(store, path) {
    this.store = store;
    this.path = path;
  }

  doc(id) {
    return new FakeDocRef(this.store, `${this.path}/${id}`);
  }
}

class FakeDb {
  constructor(seed = {}) {
    this.store = new Map(Object.entries(seed));
  }

  collection(name) {
    return new FakeCollectionRef(this.store, name);
  }

  dataAt(path) {
    return this.store.get(path);
  }
}

function baseOpportunity(overrides = {}) {
  return {
    title: "Burntwood Photo Competition",
    activityKind: "community_challenge",
    createdBy: "organiser-1",
    isActive: true,
    ...overrides,
  };
}

function baseComment(overrides = {}) {
  return {
    userId: "entrant-1",
    userName: "Alex",
    text: "Sunset from the park",
    imageUrl: "https://example.com/photo.jpg",
    imagePath: "opportunityCommentPhotos/challenge-1/entrant-1/comment-1.jpg",
    isChallengeEntry: true,
    ...overrides,
  };
}

function logger() {
  return { info() {} };
}

test("organiser receives notification for another user's photo entry", async () => {
  const db = new FakeDb({
    "opportunities/challenge-1": baseOpportunity(),
  });
  const pushes = [];

  const result = await notifyOpportunityParticipationCreated({
    db,
    admin,
    sendPushToUser: async (uid, payload) => pushes.push({ uid, payload }),
    logger: logger(),
    opportunityId: "challenge-1",
    commentId: "comment-1",
    source: "comment",
    data: baseComment(),
  });

  const notificationId = participationNotificationId({
    opportunityId: "challenge-1",
    commentId: "comment-1",
    actorUserId: "entrant-1",
    source: "comment",
    data: baseComment(),
    opportunity: baseOpportunity(),
  });
  const notification = db.dataAt(
    `users/organiser-1/notifications/${notificationId}`,
  );

  assert.equal(result.created, 1);
  assert.equal(notification.type, "opportunity_comment");
  assert.equal(notification.title, "New entry in your competition");
  assert.equal(
    notification.body,
    "Alex added a photo to Burntwood Photo Competition",
  );
  assert.equal(notification.opportunityId, "challenge-1");
  assert.equal(notification.commentId, "comment-1");
  assert.equal(notification.entryId, "entrant-1");
  assert.equal(notification.userId, "entrant-1");
  assert.equal(pushes.length, 1);
  assert.equal(pushes[0].uid, "organiser-1");
  assert.equal(pushes[0].payload.preferenceKey, "activityUpdates");
});

test("organiser receives notification for a text comment", async () => {
  const db = new FakeDb({
    "opportunities/activity-1": baseOpportunity({
      title: "Coffee morning",
      activityKind: "activity",
    }),
  });
  const pushes = [];

  await notifyOpportunityParticipationCreated({
    db,
    admin,
    sendPushToUser: async (uid, payload) => pushes.push({ uid, payload }),
    logger: logger(),
    opportunityId: "activity-1",
    commentId: "comment-2",
    source: "comment",
    data: baseComment({
      imageUrl: undefined,
      imagePath: undefined,
      isChallengeEntry: false,
      text: "Is this still going ahead?",
    }),
  });

  const notification = [...db.store.entries()]
    .find(([path]) => path.startsWith("users/organiser-1/notifications/"))?.[1];

  assert.equal(notification.title, "New comment on your activity");
  assert.equal(notification.body, "Alex commented on Coffee morning");
  assert.equal(notification.commentId, "comment-2");
  assert.equal(pushes.length, 1);
});

test("organiser does not receive notification for their own entry", async () => {
  const db = new FakeDb({
    "opportunities/challenge-1": baseOpportunity(),
  });
  const pushes = [];

  const result = await notifyOpportunityParticipationCreated({
    db,
    admin,
    sendPushToUser: async (uid, payload) => pushes.push({ uid, payload }),
    logger: logger(),
    opportunityId: "challenge-1",
    commentId: "comment-1",
    source: "comment",
    data: baseComment({ userId: "organiser-1" }),
  });

  assert.equal(result.created, 0);
  assert.equal(result.skipped, "no_recipients");
  assert.equal(pushes.length, 0);
});

test("duplicate comment and entry writes create only one notification", async () => {
  const db = new FakeDb({
    "opportunities/challenge-1": baseOpportunity(),
  });
  const pushes = [];
  const sendPushToUser = async (uid, payload) => pushes.push({ uid, payload });

  await notifyOpportunityParticipationCreated({
    db,
    admin,
    sendPushToUser,
    logger: logger(),
    opportunityId: "challenge-1",
    commentId: "comment-1",
    source: "comment",
    data: baseComment(),
  });

  const result = await notifyOpportunityParticipationCreated({
    db,
    admin,
    sendPushToUser,
    logger: logger(),
    opportunityId: "challenge-1",
    entryId: "entrant-1",
    source: "entry",
    data: {
      userId: "entrant-1",
      commentId: "comment-1",
      imageUrl: "https://example.com/photo.jpg",
      caption: "Sunset from the park",
      status: "active",
    },
  });

  const notifications = [...db.store.keys()]
    .filter((path) => path.startsWith("users/organiser-1/notifications/"));

  assert.equal(result.created, 0);
  assert.equal(notifications.length, 1);
  assert.equal(pushes.length, 1);
});

test("removed entries do not notify organisers", async () => {
  const db = new FakeDb({
    "opportunities/challenge-1": baseOpportunity(),
  });

  const result = await notifyOpportunityParticipationCreated({
    db,
    admin,
    sendPushToUser: async () => {
      throw new Error("should not push");
    },
    logger: logger(),
    opportunityId: "challenge-1",
    entryId: "entrant-1",
    source: "entry",
    data: {
      userId: "entrant-1",
      status: "removed",
    },
  });

  assert.equal(result.created, 0);
  assert.equal(result.skipped, "removed");
});
