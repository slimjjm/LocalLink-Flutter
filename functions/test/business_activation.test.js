"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { eligibleBusiness, eligibleOwner, dueDay, reminderPayload,
  buildBusinessActivationExports, APPOINTMENT_CATEGORIES } = require("../business_activation");
const DAY = 86400000;
const START = 1700000000000;
const business = overrides => ({ ownerId: "owner", isClaimed: true,
  isActive: true, category: "Hair Salon", createdAt: START, ...overrides });
const owner = overrides => ({ disabled: false, emailVerified: true,
  providerData: [{ providerId: "password" }], ...overrides });

class Ref {
  constructor(db, path) { this.db = db; this.path = path; this.id = path.split("/").pop(); }
  collection(name) { return new Query(this.db, `${this.path}/${name}`); }
  async get() { const data = this.db.store.get(this.path); return { exists: data !== undefined,
    id: this.id, ref: this, data: () => data }; }
  async delete() { this.db.store.delete(this.path); }
}
class Query {
  constructor(db, path, filters = [], max = Infinity) { Object.assign(this, { db, path, filters, max }); }
  doc(id) { return new Ref(this.db, `${this.path}/${id}`); }
  where(field, op, value) { return new Query(this.db, this.path, [...this.filters, [field, value]], this.max); }
  limit(max) { return new Query(this.db, this.path, this.filters, max); }
  orderBy() { return this; }
  startAfter(last) { this.after = last.id; return this; }
  async get() {
    const docs = [];
    for (const [path, data] of [...this.db.store.entries()].sort()) {
      if (!path.startsWith(`${this.path}/`) || path.slice(this.path.length + 1).includes("/")) continue;
      if (!this.filters.every(([field, value]) => data[field] === value)) continue;
      const ref = new Ref(this.db, path);
      if (this.after && ref.id <= this.after) continue;
      docs.push(await ref.get());
      if (docs.length === this.max) break;
    }
    return { docs, empty: docs.length === 0, size: docs.length };
  }
}
class Db {
  constructor(seed) { this.store = new Map(Object.entries(seed)); this.queue = Promise.resolve(); }
  collection(name) { return new Query(this, name); }
  async runTransaction(fn) {
    const task = this.queue.then(async () => {
      const writes = [];
      const result = await fn({ get: ref => ref.get(),
        set: (ref, data) => writes.push(() => this.store.set(ref.path, data)),
        update: (ref, data) => writes.push(() => this.store.set(ref.path, { ...this.store.get(ref.path), ...data })),
        create: (ref, data) => writes.push(() => {
          assert.equal(this.store.has(ref.path), false); this.store.set(ref.path, data);
        }), delete: ref => writes.push(() => this.store.delete(ref.path)),
      });
      writes.forEach(write => write()); return result;
    });
    this.queue = task.catch(() => {}); return task;
  }
}
function harness({ data = business(), user = owner(), enabled = true, route = true, seed = {} } = {}) {
  const db = new Db({ "businesses/b": data,
    "users/owner/private/notificationCapabilities": { businessServiceSetup: true }, ...seed });
  const pushes = [];
  let time = START;
  const admin = { auth: () => ({ getUser: async () => user }), firestore: {
    Timestamp: { fromMillis: n => n }, FieldValue: { serverTimestamp: () => time },
    FieldPath: { documentId: () => "__name__" },
  } };
  const wrapper = (_, fn) => fn;
  class HttpsError extends Error { constructor(code, message) { super(message); this.code = code; } }
  const notifications = {
    userAllowsPush: async (ref, key) => db.store.get(`${ref.path}/preferences/notifications`)?.[key] !== false,
    sendPushToUser: async (uid, payload) => pushes.push({ uid, payload }),
  };
  const api = buildBusinessActivationExports({ admin, db, HttpsError, notifications,
    onCall: wrapper, onSchedule: wrapper, onDocumentCreated: wrapper, onDocumentWritten: wrapper,
    enabled: () => enabled, routeSupported: () => route, now: () => time });
  return { api, db, pushes, at: days => { time = START + days * DAY; },
    state: () => db.store.get("businessActivationReminders/b"),
    notices: () => [...db.store.keys()].filter(path => path.includes("/notifications/")) };
}
const request = (uid = "owner", provider = "password") => ({ data: { businessId: "b" },
  auth: { uid, token: { firebase: { sign_in_provider: provider } } } });

test("appointment categories qualify, cafés, shops, trades and unknown categories do not", () => {
  for (const category of APPOINTMENT_CATEGORIES) assert.equal(eligibleBusiness(business({ category })), true);
  for (const category of ["Café", "Shop", "Gardener", "Handyman", "Unknown"]) {
    assert.equal(eligibleBusiness(business({ category })), false);
  }
});
test("unclaimed, unowned, inactive, removed and rejected listings are excluded", () => {
  for (const patch of [{ isClaimed: false }, { ownerId: "" }, { isActive: false },
    { moderationStatus: "removed" }, { approvalStatus: "rejected" },
    { createdByModerator: true, isClaimed: false, createdBy: "moderator" }]) {
    assert.equal(eligibleBusiness(business(patch)), false);
  }
});
test("a properly claimed moderator-seeded listing can qualify", () => {
  assert.equal(eligibleBusiness(business({ createdByModerator: true, claimStatus: "approved" })), true);
});
test("anonymous, unverified, disabled and banned owners are excluded", () => {
  assert.equal(eligibleOwner(owner({ providerData: [] })), false);
  assert.equal(eligibleOwner(owner({ emailVerified: false })), false);
  assert.equal(eligibleOwner(owner({ disabled: true })), false);
  assert.equal(eligibleOwner(owner(), { isBanned: true }), false);
  assert.equal(eligibleOwner(owner(), {}, { isBanned: true }), false);
});
test("day boundaries are 3, 7, 14 and late runs send only the latest milestone", () => {
  const state = { status: "active", startedAt: START, handledDays: [] };
  for (const [age, expected] of [[0, null], [2.99, null], [3, 3], [6.99, 3], [7, 7], [14, 14], [21, null]]) {
    assert.equal(dueDay(state, START + age * DAY), expected);
  }
  assert.equal(dueDay({ ...state, handledDays: [3] }, START + 4 * DAY), null);
  assert.equal(dueDay({ ...state, status: "completed" }, START + 7 * DAY), null);
  assert.equal(reminderPayload("", 3), null);
  assert.equal(reminderPayload("b", 99), null);
});
test("new business gets guidance cycle without immediate notification", async () => {
  const h = harness();
  await h.api.onBusinessCreatedServiceSetup({ params: { businessId: "b" }, data: { data: () => business() } });
  await h.api._process("b");
  assert.equal(h.state().status, "active"); assert.equal(h.notices().length, 0);
});
test("three milestones create exactly three notifications, never more", async () => {
  const h = harness(); await h.api._start("b", "owner");
  for (const day of [3, 7, 14, 15, 30]) { h.at(day); await h.api._process("b"); }
  assert.equal(h.notices().length, 3); assert.equal(h.pushes.length, 3);
  assert.equal(h.state().status, "finished");
});
test("concurrent/repeated runs cannot duplicate a milestone", async () => {
  const h = harness(); await h.api._start("b", "owner"); h.at(3);
  await Promise.all([h.api._process("b"), h.api._process("b"), h.api._process("b")]);
  assert.equal(h.notices().length, 1); assert.equal(h.pushes.length, 1);
});
test("late worker avoids a burst and does not send skipped milestones later", async () => {
  const h = harness(); await h.api._start("b", "owner"); h.at(8); await h.api._process("b");
  assert.equal(h.notices().length, 1); assert.deepEqual(h.state().handledDays, [3, 7]);
  h.at(9); await h.api._process("b"); assert.equal(h.notices().length, 1);
});
test("active first service cancels cycle and removes unread reminders; archive does not restart", async () => {
  const h = harness(); await h.api._start("b", "owner"); h.at(3); await h.api._process("b");
  h.db.store.set("businesses/b/services/s", { isActive: true });
  await h.api.onBusinessServiceSetupChanged({ params: { businessId: "b" } });
  assert.equal(h.state().status, "completed"); assert.equal(h.notices().length, 0);
  h.db.store.set("businesses/b/services/s", { isActive: false }); h.at(7);
  await h.api._process("b"); assert.equal(h.pushes.length, 1);
});
test("service created before delayed creation event leaves a completed tombstone", async () => {
  const h = harness(); h.db.store.set("businesses/b/services/s", { isActive: true });
  await h.api._cancelOnService("b");
  h.db.store.delete("businesses/b/services/s");
  await h.api._start("b", "owner"); assert.equal(h.state().status, "completed");
});
test("existing active service prevents enrolment; inactive service does not", async () => {
  const h = harness({ seed: { "businesses/b/services/s": { isActive: true } } });
  assert.equal((await h.api._start("b", "owner", true)).status, "not_needed");
  h.db.store.set("businesses/b/services/s", { isActive: false });
  assert.equal((await h.api._start("b", "owner", true)).status, "active");
});
test("service added after scheduler claim is rechecked before push", async () => {
  const h = harness(); await h.api._start("b", "owner"); h.at(3);
  const real = h.db.runTransaction.bind(h.db);
  h.db.runTransaction = async fn => { const value = await real(fn);
    h.db.store.set("businesses/b/services/s", { isActive: true }); return value; };
  await h.api._process("b"); assert.equal(h.pushes.length, 0); assert.equal(h.notices().length, 0);
});
test("legacy listing is not backfilled automatically; explicit owner action starts a new cycle", async () => {
  const h = harness({ data: business({ createdAt: START - 90 * DAY }) });
  assert.equal((await h.api._start("b", "owner")).status, "legacy");
  assert.equal(h.state(), undefined);
  assert.equal((await h.api.beginBusinessServiceSetup(request())).status, "active");
});
test("finished cycle stays finished unless owner explicitly re-enters", async () => {
  const h = harness(); await h.api._start("b", "owner"); h.at(14); await h.api._process("b");
  await h.api._start("b", "owner"); assert.equal(h.state().cycle, 1);
  await h.api.beginBusinessServiceSetup(request()); assert.equal(h.state().cycle, 2);
  await h.api.beginBusinessServiceSetup(request()); assert.equal(h.state().cycle, 2);
});
test("non-owner and anonymous callable requests are denied", async () => {
  const h = harness();
  await assert.rejects(h.api.beginBusinessServiceSetup(request("outsider")), { code: "permission-denied" });
  await assert.rejects(h.api.beginBusinessServiceSetup(request("owner", "anonymous")), { code: "unauthenticated" });
  await assert.rejects(h.api.beginBusinessServiceSetup({ data: { businessId: "b" } }), { code: "unauthenticated" });
  assert.equal(h.state(), undefined);
});
for (const key of ["reminders", "businessSetupReminders"]) {
  test(`${key} opt-out prevents in-app and push reminders`, async () => {
    const h = harness(); await h.api._start("b", "owner");
    h.db.store.set("users/owner/preferences/notifications", { [key]: false });
    h.at(3); await h.api._process("b");
    assert.equal(h.state().status, "cancelled"); assert.equal(h.notices().length, 0);
    assert.equal(h.pushes.length, 0);
  });
}
test("owner reassignment and deletion cancel instead of notifying former owner", async () => {
  for (const deleted of [false, true]) {
    const h = harness(); await h.api._start("b", "owner");
    if (deleted) h.db.store.delete("businesses/b");
    else h.db.store.set("businesses/b", business({ ownerId: "new-owner" }));
    h.at(3); await h.api._process("b");
    assert.equal(h.state().status, "cancelled"); assert.equal(h.pushes.length, 0);
  }
});
test("ban after enrolment cancels reminders", async () => {
  const h = harness(); await h.api._start("b", "owner");
  h.db.store.set("users/owner/private/access", { isBanned: true });
  h.at(3); await h.api._process("b"); assert.equal(h.state().status, "cancelled");
});
test("unsupported route or release flag prevents enrolment", async () => {
  for (const options of [{ enabled: false }, { route: false }]) {
    const h = harness(options);
    assert.equal((await h.api.beginBusinessServiceSetup(request())).status, "disabled");
    assert.equal(h.state(), undefined); await h.api.sendBusinessServiceSetupReminders();
    assert.equal(h.pushes.length, 0);
  }
});
test("ambiguous push failure is not retried and cannot duplicate the reminder", async () => {
  const h = harness(); await h.api._start("b", "owner"); h.at(3);
  // The deterministic in-app notification and handled milestone survive a push
  // transport failure; at-most-once means a failed push is deliberately not retried.
  const realPush = h.pushes.push.bind(h.pushes);
  h.pushes.push = value => { realPush(value); throw new Error("FCM timeout"); };
  await assert.rejects(h.api._process("b"), /FCM timeout/);
  await h.api._process("b"); assert.equal(h.notices().length, 1); assert.equal(h.pushes.length, 1);
});

test("owners who turn off LocalLink booking requests do not qualify", async () => {
  const h = harness({ data: business({ acceptingLeads: false }) });
  assert.equal((await h.api._start("b", "owner", true)).status, "not_needed");
});
test("preference disabled during scheduler claim suppresses external push", async () => {
  const h = harness(); await h.api._start("b", "owner"); h.at(3);
  const real = h.db.runTransaction.bind(h.db);
  h.db.runTransaction = async fn => { const result = await real(fn);
    h.db.store.set("users/owner/preferences/notifications", { reminders: false }); return result; };
  await h.api._process("b"); assert.equal(h.pushes.length, 0); assert.equal(h.notices().length, 0);
});

test("new owner can explicitly start their own cycle without inheriting old reminders", async () => {
  const h = harness(); await h.api._start("b", "owner"); h.at(3); await h.api._process("b");
  h.db.store.set("businesses/b", business({ ownerId: "new-owner" }));
  await h.api.beginBusinessServiceSetup(request("new-owner"));
  assert.equal(h.state().ownerId, "new-owner"); assert.equal(h.state().cycle, 2);
  assert.equal(h.notices().length, 0);
});
test("deleting an in-app reminder cannot cause another notification for the same milestone", async () => {
  const h = harness(); await h.api._start("b", "owner"); h.at(3); await h.api._process("b");
  h.notices().forEach(path => h.db.store.delete(path));
  await h.api._process("b"); assert.equal(h.pushes.length, 1); assert.equal(h.notices().length, 0);
});

test("unsupported owner app receives no reminders until dashboard registers route, without resetting cycle", async () => {
  const h = harness(); h.db.store.delete("users/owner/private/notificationCapabilities");
  await h.api._start("b", "owner"); h.at(3); await h.api._process("b");
  assert.equal(h.notices().length, 0); assert.equal(h.pushes.length, 0);
  await h.api.beginBusinessServiceSetup({ ...request(), data: { businessId: "b", registerRouteOnly: true } });
  assert.equal(h.state().cycle, 1); await h.api._process("b"); assert.equal(h.pushes.length, 1);
});
test("registering route does not enrol a legacy listing or restart a finished campaign", async () => {
  const h = harness({ data: business({ createdAt: START - 90 * DAY }) });
  await h.api.beginBusinessServiceSetup({ ...request(), data: { businessId: "b", registerRouteOnly: true } });
  assert.equal(h.state(), undefined);
  await h.api.beginBusinessServiceSetup(request()); h.at(14); await h.api._process("b");
  await h.api.beginBusinessServiceSetup({ ...request(), data: { businessId: "b", registerRouteOnly: true } });
  assert.equal(h.state().status, "finished"); assert.equal(h.state().cycle, 1);
});

test("explicit discovery visibility blocks exclude reminder enrolment", () => {
  for (const patch of [{ isHidden: true }, { isPrivate: true }, { isDeleted: true },
    { isPubliclyDiscoverable: false }, { status: "archived" }, { visibility: "members_only" },
    { moderationStatus: "blocked" }]) assert.equal(eligibleBusiness(business(patch)), false);
});
