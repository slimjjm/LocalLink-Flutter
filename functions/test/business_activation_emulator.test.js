"use strict";
const { test, before, after } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const emulator = process.env.FIRESTORE_EMULATOR_HOST;
let env, app, db, api;
let now = 1700000000000;
const pushes = [];
const options = { skip: !emulator };
before(async () => {
  if (!emulator) return;
  assert.match(emulator, /^127\.0\.0\.1:\d+$/, "Synthetic checks must use a local emulator");
  const { initializeTestEnvironment } = require("@firebase/rules-unit-testing");
  const [host, port] = emulator.split(":");
  const projectId = "demo-locallink-activation";
  env = await initializeTestEnvironment({ projectId, firestore: { host, port: Number(port),
    rules: fs.readFileSync(path.join(__dirname, "../../firestore.rules"), "utf8") } });
  await env.clearFirestore();
  const admin = require("firebase-admin");
  app = admin.initializeApp({ projectId }, "activation-tests");
  db = admin.firestore(app);
  const depsAdmin = { firestore: admin.firestore,
    auth: () => ({ getUser: async () => ({ disabled: false, emailVerified: true,
      providerData: [{ providerId: "password" }] }) }) };
  const wrapper = (_, fn) => fn;
  api = require("../business_activation").buildBusinessActivationExports({ admin: depsAdmin, db,
    onCall: wrapper, onSchedule: wrapper, onDocumentCreated: wrapper, onDocumentWritten: wrapper,
    HttpsError: class extends Error {}, enabled: () => true, now: () => now,
    notifications: { userAllowsPush: async () => true,
      sendPushToUser: async (uid, payload) => pushes.push({ uid, payload }) },
  });
  await db.doc("users/owner/private/notificationCapabilities").set({ businessServiceSetup: true });
  await db.doc("businesses/b").set({ ownerId: "owner", createdBy: "owner", isClaimed: true,
    isActive: true, category: "Hair Salon", createdAt: admin.firestore.Timestamp.fromMillis(now) });
});
after(async () => { if (env) await env.cleanup(); if (app) await app.delete(); });

test("real transactions schedule idempotently under concurrent workers", options, async () => {
  await api._start("b", "owner"); now += 3 * 86400000;
  await Promise.all([api._process("b"), api._process("b"), api._process("b")]);
  const notices = await db.collection("users/owner/notifications").get();
  assert.equal(notices.size, 1); assert.equal(pushes.length, 1);
  assert.equal(notices.docs[0].data().businessId, "b");
});
test("scheduler query and first-service cancellation work with real Firestore", options, async () => {
  await api.sendBusinessServiceSetupReminders();
  assert.equal(pushes.length, 1);
  await db.doc("businesses/b/services/first").set({ isActive: true });
  await api._cancelOnService("b");
  assert.equal((await db.doc("businessActivationReminders/b").get()).data().status, "completed");
  assert.equal((await db.collection("users/owner/notifications").get()).size, 0);
  await db.doc("businesses/b/services/first").update({ isActive: false });
  now += 4 * 86400000; await api._process("b"); assert.equal(pushes.length, 1);
});
test("preference is owner-only and boolean; reminder state and notification writes stay server-only", options, async () => {
  const { assertFails, assertSucceeds } = require("@firebase/rules-unit-testing");
  const { doc, setDoc, getDoc } = require("firebase/firestore");
  const client = uid => env.authenticatedContext(uid, {
    firebase: { sign_in_provider: "password" }, email_verified: true }).firestore();
  const owner = client("owner"); const outsider = client("outsider");
  const anon = env.authenticatedContext("anon", { firebase: { sign_in_provider: "anonymous" } }).firestore();
  await assertSucceeds(setDoc(doc(owner, "users/owner/preferences/notifications"), { businessSetupReminders: false }));
  await assertFails(setDoc(doc(outsider, "users/owner/preferences/notifications"), { businessSetupReminders: true }));
  await assertFails(setDoc(doc(anon, "users/anon/preferences/notifications"), { businessSetupReminders: true }));
  await assertFails(setDoc(doc(owner, "users/owner/preferences/notifications"), { businessSetupReminders: "yes" }));
  await assertFails(setDoc(doc(owner, "businessActivationReminders/b"), { status: "active" }));
  await assertFails(getDoc(doc(owner, "businessActivationReminders/b")));
  await assertFails(setDoc(doc(owner, "users/owner/notifications/forged"), { type: "business_service_setup" }));
});

test("legitimate owner can create first service; outsider and anonymous users cannot", options, async () => {
  const { assertFails, assertSucceeds } = require("@firebase/rules-unit-testing");
  const { doc, setDoc } = require("firebase/firestore");
  const client = (uid, provider) => env.authenticatedContext(uid, {
    firebase: { sign_in_provider: provider }, email_verified: true }).firestore();
  await assertSucceeds(setDoc(doc(client("owner", "password"), "businesses/b/services/owner-service"),
    { name: "Haircut", isActive: true, durationMinutes: 30, price: 2000 }));
  await assertFails(setDoc(doc(client("outsider", "password"), "businesses/b/services/forged"), { isActive: true }));
  await assertFails(setDoc(doc(client("anon", "anonymous"), "businesses/b/services/anonymous"), { isActive: true }));
  await api._cancelOnService("b");
  assert.equal((await db.doc("businessActivationReminders/b").get()).data().status, "completed");
});
