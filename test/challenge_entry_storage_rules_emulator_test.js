"use strict";

const fs = require("node:fs");
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const { doc, setDoc } = require("firebase/firestore");
const {
  deleteObject,
  ref,
  uploadBytes,
} = require("firebase/storage");

const projectId = "locallink-995a5";
const firestoreHost = "127.0.0.1";
const firestorePort = 8080;
const storageHost = "127.0.0.1";
const storagePort = 9199;
const challengeId = "challenge-1";
const commentId = "comment-1";
const ownerId = "owner";
const imagePath =
  `opportunityCommentPhotos/${challengeId}/${ownerId}/${commentId}.jpg`;

let testEnv;

function auth(uid, extraClaims = {}) {
  return testEnv.authenticatedContext(uid, {
    email: `${uid}@example.com`,
    firebase: { sign_in_provider: "password" },
    ...extraClaims,
  });
}

function storage(uid, extraClaims = {}) {
  return auth(uid, extraClaims).storage();
}

function unauthStorage() {
  return testEnv.unauthenticatedContext().storage();
}

function imageMetadata(overrides = {}) {
  return {
    contentType: "image/jpeg",
    customMetadata: {
      ownerId,
      opportunityId: challengeId,
      commentId,
      ...overrides,
    },
  };
}

async function seedAdminUser(uid = "admin") {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), `users/${uid}`), {
      isAdmin: true,
    });
  });
}

function ownerUpload(
  path = imagePath,
  bytes = new Uint8Array([1, 2, 3]),
  metadata = imageMetadata(),
) {
  return uploadBytes(ref(storage(ownerId), path), bytes, metadata);
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
}

async function seedStorageObject(path = imagePath, metadata = imageMetadata()) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await uploadBytes(ref(context.storage(), path), new Uint8Array([1, 2, 3]), metadata);
  });
}

async function testOwnerValidUploadAllowed() {
  await allow("owner challenge entry photo upload", ownerUpload());
}

async function testGuestUploadDenied() {
  await deny(
    "guest challenge entry photo upload",
    uploadBytes(ref(unauthStorage(), imagePath), new Uint8Array([1]), imageMetadata()),
  );
}

async function testOtherUserUploadDenied() {
  await deny(
    "other user challenge entry photo upload",
    uploadBytes(ref(storage("other"), imagePath), new Uint8Array([1]), imageMetadata()),
  );
}

async function testSpoofedOwnerMetadataDenied() {
  await deny(
    "spoofed owner metadata upload",
    uploadBytes(
      ref(storage(ownerId), imagePath),
      new Uint8Array([1]),
      imageMetadata({ ownerId: "other" }),
    ),
  );
}

async function testCommentIdFilenameMismatchDenied() {
  await deny(
    "comment id filename mismatch upload",
    uploadBytes(
      ref(storage(ownerId), imagePath),
      new Uint8Array([1]),
      imageMetadata({ commentId: "other-comment" }),
    ),
  );
}

async function testOwnerReplacementAllowed() {
  await ownerUpload();
  await allow(
    "owner challenge entry photo replacement",
    uploadBytes(ref(storage(ownerId), imagePath), new Uint8Array([4, 5, 6]), imageMetadata()),
  );
}

async function testOwnerInvalidReplacementDenied() {
  await ownerUpload();
  await deny(
    "owner invalid replacement",
    uploadBytes(ref(storage(ownerId), imagePath), new Uint8Array([1]), {
      ...imageMetadata(),
      contentType: "text/plain",
    }),
  );
}

async function testOwnerRemovalAllowed() {
  await ownerUpload();
  await allow(
    "owner challenge entry photo removal",
    deleteObject(ref(storage(ownerId), imagePath)),
  );
}

async function testOwnerRemovalUsesPathUid() {
  await seedStorageObject(imagePath, {
    contentType: "image/jpeg",
    customMetadata: {
      opportunityId: challengeId,
      commentId,
    },
  });
  await allow(
    "owner challenge entry photo removal by path uid",
    deleteObject(ref(storage(ownerId), imagePath)),
  );
}

async function testOtherUserRemovalDenied() {
  await ownerUpload();
  await deny(
    "other user challenge entry photo removal",
    deleteObject(ref(storage("other"), imagePath)),
  );
}

async function testAdminModerationRemovalAllowed() {
  await seedAdminUser();
  await ownerUpload();
  await allow(
    "admin challenge entry photo moderation removal",
    deleteObject(ref(storage("admin"), imagePath)),
  );
}

async function testOrdinaryUserModerationRemovalDenied() {
  await ownerUpload();
  await deny(
    "ordinary user moderation removal",
    deleteObject(ref(storage("ordinary"), imagePath)),
  );
}

async function testInvalidFileTypeDenied() {
  await deny(
    "invalid file type upload",
    uploadBytes(ref(storage(ownerId), imagePath), new Uint8Array([1]), {
      ...imageMetadata(),
      contentType: "text/plain",
    }),
  );
}

async function testOversizedImageDenied() {
  await deny(
    "oversized challenge entry photo upload",
    ownerUpload(imagePath, new Uint8Array(8 * 1024 * 1024), imageMetadata()),
  );
}

async function run() {
  await setup();
  try {
    for (const testCase of [
      testOwnerValidUploadAllowed,
      testGuestUploadDenied,
      testOtherUserUploadDenied,
      testSpoofedOwnerMetadataDenied,
      testCommentIdFilenameMismatchDenied,
      testOwnerReplacementAllowed,
      testOwnerInvalidReplacementDenied,
      testOwnerRemovalAllowed,
      testOwnerRemovalUsesPathUid,
      testOtherUserRemovalDenied,
      testAdminModerationRemovalAllowed,
      testOrdinaryUserModerationRemovalDenied,
      testInvalidFileTypeDenied,
      testOversizedImageDenied,
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
