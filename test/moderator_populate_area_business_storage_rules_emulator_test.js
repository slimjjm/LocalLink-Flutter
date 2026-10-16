"use strict";

const fs = require("node:fs");
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const { doc, setDoc, getDoc, writeBatch, serverTimestamp } = require("firebase/firestore");
const { ref, uploadBytes, getDownloadURL } = require("firebase/storage");

const projectId = "locallink-995a5";
const firestoreHost = "127.0.0.1";
const firestorePort = Number((process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080").split(":").pop());
const storageHost = "127.0.0.1";
const storagePort = Number((process.env.FIREBASE_STORAGE_EMULATOR_HOST || "127.0.0.1:9199").split(":").pop());
const adminId = "moderator";
const adminEmail = "jae19882011@gmail.com";
const approvedEmail = "founder@locallinkapp.co.uk";
const {businessPayload, metadataPayload} = require("./populate_area_business_fixture");
const ordinaryId = "ordinary";
const businessId = "seeded-business";
const imagePath = `businessPhotos/${businessId}/listing.jpg`;

let testEnv;

function auth(uid, email, provider = "password") {
  return testEnv.authenticatedContext(uid, {
    email: email || (uid === adminId ? adminEmail : `${uid}@example.com`),
    firebase: { sign_in_provider: provider },
  });
}

function storage(uid, email, provider) {
  return auth(uid, email, provider).storage();
}

function imageMetadata(overrides = {}) {
  return {
    contentType: "image/jpeg",
    customMetadata: {
      ownerId: adminId,
      moderatorSeeded: "true",
      listingId: businessId,
      ...overrides,
    },
  };
}

async function seedAdminUser(uid = adminId) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), `users/${uid}`), {
      isAdmin: true,
    });
  });
}

async function seedAdminEmail(email = approvedEmail) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), `adminEmails/${email}`), {
      enabled: true,
    });
  });
}

function uploadAs(uid, path = imagePath, metadata = imageMetadata(), email, provider) {
  return uploadBytes(ref(storage(uid, email, provider), path), new Uint8Array([1, 2, 3]), metadata);
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
      host: firestoreHost,
      port: firestorePort,
      rules: fs.readFileSync("firestore.rules", "utf8"),
    },
    storage: {
      host: storageHost,
      port: storagePort,
      rules: fs.readFileSync("storage.rules", "utf8"),
    },
  });
}

async function teardown() {
  await testEnv.cleanup();
}

async function beforeEachTest() {
  await testEnv.clearFirestore();
  await testEnv.clearStorage();
  await seedAdminUser();
}

async function testModeratorSeededBusinessPhotoUploadAllowedBeforeBusinessExists() {
  await allow(
    "moderator seeded business photo upload before business exists",
    uploadAs(adminId),
  );
}

async function testAdminEmailModeratorUploadAllowedWithoutProfileFlag() {
  await testEnv.clearFirestore();
  await seedAdminEmail();

  await allow(
    "admin email moderator seeded business photo upload",
    uploadAs(adminId, imagePath, imageMetadata(), approvedEmail),
  );
}

async function testOrdinaryUserCannotUseModeratorSeededBusinessPhotoPath() {
  await deny(
    "ordinary user moderator seeded business photo upload",
    uploadAs(ordinaryId, imagePath, imageMetadata({ ownerId: ordinaryId })),
  );
}

async function testModeratorSeededBusinessPhotoRequiresMatchingListingId() {
  await deny(
    "moderator seeded business photo wrong listing id",
    uploadAs(adminId, imagePath, imageMetadata({ listingId: "other-business" })),
  );
}

async function testModeratorSeededBusinessPhotoRequiresImage() {
  await deny(
    "moderator seeded business non-image upload",
    uploadAs(adminId, imagePath, {
      ...imageMetadata(),
      contentType: "text/plain",
    }),
  );
}

async function testMigratedAdminCanUpload() {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async context => {
    await setDoc(doc(context.firestore(), `users/${adminId}`), { name: "Moderator" });
    await setDoc(doc(context.firestore(), `users/${adminId}/private/account`), { isAdmin: true });
  });
  await allow("migrated private-account admin upload", uploadAs(adminId));
}

async function testRevokedPrivateAdminCannotUseStalePublicFlag() {
  await testEnv.withSecurityRulesDisabled(async context => {
    await setDoc(doc(context.firestore(), `users/${adminId}/private/account`), { isAdmin: false });
  });
  await deny("revoked private admin with stale public flag", uploadAs(adminId));
}

async function testUnapprovedEmailRecordCannotSeedBusiness() {
  await testEnv.clearFirestore();
  await seedAdminEmail(adminEmail);
  await deny("unapproved email allowlist cannot seed", uploadAs(adminId));
}

async function testAnonymousAndBadMetadataDenied() {
  await deny("anonymous admin cannot seed", uploadAs(adminId, imagePath, imageMetadata(), adminEmail, "anonymous"));
  await deny("missing seeded marker", uploadAs(adminId, imagePath, imageMetadata({ moderatorSeeded: "false" })));
  await deny("wrong image owner", uploadAs(adminId, imagePath, imageMetadata({ ownerId: ordinaryId })));
}

async function testImageSizeLimitPreserved() {
  await deny("8 MB image rejected", uploadBytes(ref(storage(adminId), imagePath), new Uint8Array(8 * 1024 * 1024), imageMetadata()));
}

async function testFullMigratedAdminSaveWithImageAndMetadata() {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async context => {
    await setDoc(doc(context.firestore(), `users/${adminId}`), { name: "Moderator" });
    await setDoc(doc(context.firestore(), `users/${adminId}/private/account`), { isAdmin: true });
    await setDoc(doc(context.firestore(), `users/${adminId}/private/access`), { isAdmin: true });
  });
  const uploaded = await uploadAs(adminId);
  const imageUrl = await getDownloadURL(uploaded.ref);
  const instance = auth(adminId).firestore();
  const batch = writeBatch(instance);
  batch.set(doc(instance, `businesses/${businessId}`), businessPayload({ photoURLs: [imageUrl], createdAt: serverTimestamp(), updatedAt: serverTimestamp() }));
  batch.set(doc(instance, `moderatorListingMetadata/${businessId}`), metadataPayload({ sourceName: "Business website", sourceUrl: "https://example.com", moderatorNotes: "Verified local business", createdAt: serverTimestamp(), updatedAt: serverTimestamp() }));
  await allow("full image, business and metadata save for reported account schema", batch.commit());
  const business = await getDoc(doc(instance, `businesses/${businessId}`));
  const metadata = await getDoc(doc(instance, `moderatorListingMetadata/${businessId}`));
  if (!business.exists() || !metadata.exists() || business.data().photoURLs[0] !== imageUrl) throw new Error("Incomplete save");
}

async function run() {
  await setup();
  try {
    for (const testCase of [
      testFullMigratedAdminSaveWithImageAndMetadata,
      testUnapprovedEmailRecordCannotSeedBusiness,
      testAnonymousAndBadMetadataDenied,
      testImageSizeLimitPreserved,
      testMigratedAdminCanUpload,
      testRevokedPrivateAdminCannotUseStalePublicFlag,
      testModeratorSeededBusinessPhotoUploadAllowedBeforeBusinessExists,
      testAdminEmailModeratorUploadAllowedWithoutProfileFlag,
      testOrdinaryUserCannotUseModeratorSeededBusinessPhotoPath,
      testModeratorSeededBusinessPhotoRequiresMatchingListingId,
      testModeratorSeededBusinessPhotoRequiresImage,
    ]) {
      await beforeEachTest();
      await testCase();
      console.log(`PASS ${testCase.name}`);
    }
  } finally {
    await teardown();
  }
}

run().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
