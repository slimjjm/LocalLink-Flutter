"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const {
  _test: {
    opportunityExpiresMillis,
    shouldExpireOpportunity,
  },
} = require("../opportunities");

const now = new Date("2026-09-28T12:00:00Z");

function fakeTimestamp(iso) {
  return {
    toDate() {
      return new Date(iso);
    },
    toMillis() {
      return new Date(iso).getTime();
    },
  };
}

test("normal activity with past eventDate expires", () => {
  assert.equal(
    shouldExpireOpportunity({
      isActive: true,
      activityKind: "activity",
      eventDate: fakeTimestamp("2026-09-27T10:00:00Z"),
    }, now),
    true
  );
});

test("normal activity with future eventDate remains active", () => {
  assert.equal(
    shouldExpireOpportunity({
      isActive: true,
      activityKind: "activity",
      eventDate: fakeTimestamp("2026-09-29T10:00:00Z"),
    }, now),
    false
  );
});

test("date-only normal activity expires after the activity day", () => {
  assert.equal(
    shouldExpireOpportunity({
      isActive: true,
      activityKind: "activity",
      eventDate: fakeTimestamp("2026-09-27T23:00:00Z"),
    }, new Date("2026-09-28T10:00:00Z")),
    false
  );

  assert.equal(
    shouldExpireOpportunity({
      isActive: true,
      activityKind: "activity",
      eventDate: fakeTimestamp("2026-09-27T23:00:00Z"),
    }, new Date("2026-09-29T00:05:00Z")),
    true
  );
});

test("community challenge with past eventDate and future challengeClosesAt remains active", () => {
  assert.equal(
    shouldExpireOpportunity({
      isActive: true,
      activityKind: "community_challenge",
      eventDate: fakeTimestamp("2026-09-27T00:00:00Z"),
      challengeClosesAt: fakeTimestamp("2026-10-04T18:00:00Z"),
    }, now),
    false
  );
});

test("community challenge with past eventDate and past challengeClosesAt expires", () => {
  assert.equal(
    shouldExpireOpportunity({
      isActive: true,
      activityKind: "community_challenge",
      eventDate: fakeTimestamp("2026-09-27T00:00:00Z"),
      challengeClosesAt: fakeTimestamp("2026-09-28T09:00:00Z"),
    }, now),
    true
  );
});

test("community challenge with future eventDate and past challengeClosesAt expires", () => {
  assert.equal(
    shouldExpireOpportunity({
      isActive: true,
      activityKind: "community_challenge",
      eventDate: fakeTimestamp("2026-10-04T00:00:00Z"),
      challengeClosesAt: fakeTimestamp("2026-09-28T09:00:00Z"),
    }, now),
    true
  );
});

test("community challenge missing or malformed challengeClosesAt falls back to eventDate expiry", () => {
  assert.equal(
    shouldExpireOpportunity({
      isActive: true,
      activityKind: "community_challenge",
      eventDate: fakeTimestamp("2026-09-27T09:00:00Z"),
    }, now),
    true
  );

  assert.equal(
    shouldExpireOpportunity({
      isActive: true,
      activityKind: "community_challenge",
      eventDate: fakeTimestamp("2026-09-29T09:00:00Z"),
      challengeClosesAt: "not-a-timestamp",
    }, now),
    false
  );
});

test("community challenge missing both challengeClosesAt and eventDate is left untouched", () => {
  assert.equal(
    opportunityExpiresMillis({
      isActive: true,
      activityKind: "community_challenge",
    }),
    null
  );
  assert.equal(
    shouldExpireOpportunity({
      isActive: true,
      activityKind: "community_challenge",
    }, now),
    false
  );
});

test("already inactive opportunity remains untouched", () => {
  assert.equal(
    shouldExpireOpportunity({
      isActive: false,
      activityKind: "community_challenge",
      eventDate: fakeTimestamp("2026-09-27T00:00:00Z"),
      challengeClosesAt: fakeTimestamp("2026-09-27T18:00:00Z"),
    }, now),
    false
  );
});

test("moderated or deleted inactive challenge is not reactivated or touched", () => {
  for (const data of [
    {
      isActive: false,
      deleted: true,
      activityKind: "community_challenge",
      challengeClosesAt: fakeTimestamp("2026-10-04T18:00:00Z"),
    },
    {
      isActive: false,
      moderationStatus: "removed",
      activityKind: "community_challenge",
      challengeClosesAt: fakeTimestamp("2026-10-04T18:00:00Z"),
    },
  ]) {
    assert.equal(shouldExpireOpportunity(data, now), false);
  }
});
