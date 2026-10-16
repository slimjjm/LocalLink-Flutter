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
  serverTimestamp,
  setDoc,
  updateDoc,
} = require("firebase/firestore");

const projectId = "locallink-private-data-test";
let testEnv;

function registered(uid) {
  return testEnv.authenticatedContext(uid, {
    email: `${uid}@example.com`,
    email_verified: true,
    firebase: { sign_in_provider: "password" },
  }).firestore();
}

function anonymous(uid = "guest") {
  return testEnv.authenticatedContext(uid, {
    firebase: { sign_in_provider: "anonymous" },
  }).firestore();
}

async function seed(path, data) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), path), data);
  });
}

async function main() {
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: {
      host: "127.0.0.1",
      port: 8080,
      rules: fs.readFileSync("firestore.rules", "utf8"),
    },
  });

  await seed("users/alice", {
    name: "Alice", bio: "Public bio", reviewCount: 0,
    ratingTotal: 0, averageRating: 0,
  });
  await seed("users/bob", {
    name: "Bob", bio: "Public bio", reviewCount: 0,
    ratingTotal: 0, averageRating: 0,
  });
  await seed("users/alice/devices/device-a", {
    token: "a-valid-private-registration-token-123456",
    platform: "ios",
    createdAt: new Date(),
    updatedAt: new Date(),
  });
  await seed("users/alice/private/account", { isAdmin: false, email: "alice@example.com" });
  await seed("users/alice/private/access", { isAdmin: false, isBanned: false });
  await seed("businesses/business-1", {
    businessName: "Safe public listing", createdBy: "alice", ownerId: "",
    isClaimed: false, isActive: true,
  });
  await seed("businessClaimSecrets/business-1", {
    claimEmail: "alice@example.com", claimCode: "PRIVATE123",
    claimCodeNormalized: "PRIVATE123", status: "pending",
  });

  await assertSucceeds(getDoc(doc(registered("bob"), "users/alice")));
  await assertFails(getDoc(doc(registered("bob"), "users/alice/devices/device-a")));
  await assertFails(getDoc(doc(registered("alice"), "users/alice/private/account")));
  await assertSucceeds(getDoc(doc(registered("alice"), "users/alice/private/access")));
  await assertFails(getDoc(doc(registered("bob"), "users/alice/private/access")));
  await assertFails(setDoc(doc(registered("bob"), "users/alice/devices/forged"), {
    token: "another-valid-registration-token-123456",
    platform: "android",
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  }));
  await assertFails(getDoc(doc(anonymous(), "users/alice/devices/device-a")));
  await assertFails(setDoc(doc(anonymous(), "users/guest/devices/device-g"), {
    token: "anonymous-registration-token-123456789",
    platform: "ios",
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  }));

  const ownDevice = doc(registered("bob"), "users/bob/devices/device-b");
  await assertSucceeds(setDoc(ownDevice, {
    token: "bob-valid-registration-token-123456789",
    platform: "android",
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  }));
  await assertSucceeds(deleteDoc(ownDevice));

  await assertFails(updateDoc(doc(registered("alice"), "users/alice"), {
    fcmTokens: ["must-not-return-to-public-profile"],
  }));
  await assertFails(getDoc(doc(registered("alice"), "businessClaimSecrets/business-1")));
  await assertFails(getDoc(doc(registered("bob"), "businessClaimSecrets/business-1")));
  await assertFails(getDoc(doc(anonymous(), "businessClaimSecrets/business-1")));
  await assertSucceeds(getDoc(doc(registered("bob"), "businesses/business-1")));

  await testEnv.cleanup();
  console.log("private data security rules emulator tests passed");
}

main().catch(async (error) => {
  if (testEnv) await testEnv.cleanup();
  console.error(error);
  process.exitCode = 1;
});
