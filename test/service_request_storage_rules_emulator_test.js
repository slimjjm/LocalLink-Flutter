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
  getBytes,
  ref,
  uploadBytes,
} = require("firebase/storage");

const projectId = "locallink-995a5";
const firestoreHost = "127.0.0.1";
const firestorePort = 8080;
const storageHost = "127.0.0.1";
const storagePort = 9199;
const now = new Date("2026-09-26T10:00:00.000Z");
const future = new Date("2026-09-29T10:00:00.000Z");
const imagePath = "serviceRequests/request-1/images/photo.jpg";

let testEnv;

function auth(uid) {
  return testEnv.authenticatedContext(uid, {
    email: `${uid}@example.com`,
    firebase: { sign_in_provider: "password" },
  });
}

function storage(uid) {
  return auth(uid).storage();
}

function unauthStorage() {
  return testEnv.unauthenticatedContext().storage();
}

async function seedRequest(customerId = "owner") {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "serviceRequests/request-1"), {
      customerId,
      category: "Cleaner",
      title: "Cleaner needed",
      description: "Kitchen and bathroom clean.",
      scheduleText: "Friday morning",
      publicLocation: "Burntwood",
      location: "Burntwood",
      locationPrecision: "approximate",
      approxLatitude: 52.681,
      approxLongitude: -1.831,
      status: "open",
      isActive: true,
      createdAt: now,
      updatedAt: now,
      expiresAt: future,
    });
  });
}

async function ownerUpload(path = imagePath, bytes = new Uint8Array([1, 2, 3])) {
  return uploadBytes(ref(storage("owner"), path), bytes, {
    contentType: "image/jpeg",
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
  await seedRequest();
}

async function testOwnerValidUploadAllowed() {
  await allow("owner valid image upload", ownerUpload());
}

async function testOtherUploadDenied() {
  await deny(
    "other user upload",
    uploadBytes(ref(storage("other"), imagePath), new Uint8Array([1]), {
      contentType: "image/jpeg",
    }),
  );
}

async function testUnauthUploadDenied() {
  await deny(
    "unauthenticated upload",
    uploadBytes(ref(unauthStorage(), imagePath), new Uint8Array([1]), {
      contentType: "image/jpeg",
    }),
  );
}

async function testNonImageUploadDenied() {
  await deny(
    "non-image upload",
    uploadBytes(ref(storage("owner"), imagePath), new Uint8Array([1]), {
      contentType: "text/plain",
    }),
  );
}

async function testOversizedUploadDenied() {
  await deny(
    "oversized image upload",
    ownerUpload(imagePath, new Uint8Array(5 * 1024 * 1024)),
  );
}

async function testOwnerDeleteAllowed() {
  await ownerUpload();
  await allow("owner delete", deleteObject(ref(storage("owner"), imagePath)));
}

async function testOtherDeleteDenied() {
  await ownerUpload();
  await deny("other delete", deleteObject(ref(storage("other"), imagePath)));
}

async function testOwnerReadAllowed() {
  await ownerUpload();
  await allow("owner read", getBytes(ref(storage("owner"), imagePath)));
}

async function testOtherReadDenied() {
  await ownerUpload();
  await deny("other read", getBytes(ref(storage("other"), imagePath)));
}

async function run() {
  await setup();
  try {
    for (const testCase of [
      testOwnerValidUploadAllowed,
      testOtherUploadDenied,
      testUnauthUploadDenied,
      testNonImageUploadDenied,
      testOversizedUploadDenied,
      testOwnerDeleteAllowed,
      testOtherDeleteDenied,
      testOwnerReadAllowed,
      testOtherReadDenied,
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
