"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const {
  COOLDOWN_MS,
  buildNearbyNotification,
  cooldownAllows,
  eligibleMissingPets,
} = require("../community_help_nearby_alerts");

const nearby = {
  id: "luna",
  data: {
    type: "lost_found",
    mode: "lost",
    itemCategory: "Pet",
    petType: "Cat",
    title: "Luna",
    location: "Chase Terrace",
    isActive: true,
    status: "active",
    approxLatitude: 52.68,
    approxLongitude: -1.93,
    discoveryRadiusMiles: 4,
  },
};

function eligible(reports, options = {}) {
  return eligibleMissingPets({
    reports,
    latitude: 52.681,
    longitude: -1.927,
    maxRadiusMiles: 5,
    ...options,
  });
}

test("one missing pet creates one report notification with a direct deep link", () => {
  const candidates = eligible([nearby]);
  const notification = buildNearbyNotification(candidates);
  assert.equal(candidates.length, 1);
  assert.equal(notification.type, "community_alert");
  assert.equal(notification.communityHelpPostId, "luna");
});

test("the same report version does not notify repeatedly", () => {
  assert.equal(eligible([nearby], { alertedVersions: { luna: "initial" } }).length, 0);
});

test("multiple missing pets produce one grouped Community Help notification", () => {
  const candidates = eligible([
    nearby,
    { ...nearby, id: "milo", data: { ...nearby.data, title: "Milo" } },
  ]);
  const notification = buildNearbyNotification(candidates);
  assert.equal(notification.type, "community_alert_group");
  assert.equal(notification.communityHelpPostId, "");
  assert.equal(notification.title, "2 missing pets reported nearby");
});

test("resolved pets are excluded", () => {
  assert.equal(eligible([{ ...nearby, data: { ...nearby.data, status: "resolved" } }]).length, 0);
});

test("reports outside the radius are excluded", () => {
  const far = { ...nearby, data: { ...nearby.data, approxLatitude: 53.68 } };
  assert.equal(eligible([far]).length, 0);
});

test("reports without usable coordinates are excluded", () => {
  const noCoordinates = {
    ...nearby,
    data: {
      ...nearby.data,
      approxLatitude: null,
      approxLongitude: null,
    },
  };
  assert.equal(eligible([noCoordinates]).length, 0);
});

test("a report owner does not receive a passive nearby alert", () => {
  const owned = {
    ...nearby,
    data: { ...nearby.data, createdBy: "owner-user" },
  };
  assert.equal(eligible([owned], { recipientId: "owner-user" }).length, 0);
});

test("followed reports are excluded from passive nearby alerts", () => {
  assert.equal(eligible([nearby], { excludedReportIds: ["luna"] }).length, 0);
});

test("disabled pet categories are excluded", () => {
  assert.equal(eligible([nearby], { enabledCategories: ["missingDogs"] }).length, 0);
});

test("a meaningful confirmed-sighting version can notify after the initial version", () => {
  const updated = {
    ...nearby,
    data: { ...nearby.data, confirmedSightingVersion: 2 },
  };
  assert.equal(eligible([updated], { alertedVersions: { luna: "initial" } }).length, 1);
});

test("cooldown prevents repeated area alerts for 24 hours", () => {
  const now = Date.parse("2026-10-04T12:00:00Z");
  assert.equal(cooldownAllows(now - COOLDOWN_MS + 1, now), false);
  assert.equal(cooldownAllows(now - COOLDOWN_MS, now), true);
});
