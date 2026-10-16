"use strict";

const fs = require("node:fs");
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const { doc, getDoc, setDoc, writeBatch } = require("firebase/firestore");

const projectId = "locallink-995a5";
const host = "127.0.0.1";
const port = Number((process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080").split(":").pop());
const adminId = "moderator";
const ordinaryId = "ordinary";
const businessId = "seeded-business";

let testEnv;

function db(uid, provider = "password") {
  return testEnv.authenticatedContext(uid, {
    email: `${uid}@example.com`,
    firebase: { sign_in_provider: provider },
  }).firestore();
}

async function seed(path, data) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), path), data);
  });
}

const {businessPayload, metadataPayload} = require("./populate_area_business_fixture");

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
  await seed(`users/${adminId}`, { isAdmin: true });
}

async function testModeratorCanCreateBusinessWithBlankSourceMetadata() {
  const instance = db(adminId);
  const batch = writeBatch(instance);
  batch.set(doc(instance, `businesses/${businessId}`), businessPayload());
  batch.set(
    doc(instance, `moderatorListingMetadata/${businessId}`),
    metadataPayload(),
  );

  await allow(
    "moderator create business and blank source metadata",
    batch.commit(),
  );
}

async function testModeratorCanCreateBusinessWithoutOptionalSourceMetadata() {
  await allow(
    "moderator create business with image URL and no metadata document",
    setDoc(doc(db(adminId), `businesses/${businessId}`), businessPayload()),
  );
}

async function testOrdinaryUserCannotUseModeratorBusinessCreatePath() {
  await deny(
    "ordinary user create moderator-seeded business",
    setDoc(
      doc(db(ordinaryId), `businesses/${businessId}`),
      businessPayload({ createdBy: ordinaryId }),
    ),
  );

  await deny(
    "ordinary user write moderator listing metadata",
    setDoc(
      doc(db(ordinaryId), `moderatorListingMetadata/${businessId}`),
      metadataPayload({ seededByModeratorUserId: ordinaryId }),
    ),
  );
}

async function testMalformedModeratorBusinessDenied() {
  await deny(
    "moderator business missing unclaimed ownership status",
    setDoc(
      doc(db(adminId), `businesses/${businessId}`),
      businessPayload({ listingOwnershipStatus: "claimed" }),
    ),
  );
}

async function testMigratedAdminBusinessAndMetadata() {
  await testEnv.clearFirestore();
  await seed(`users/${adminId}`, { name: "Moderator" });
  await seed(`users/${adminId}/private/account`, { isAdmin: true });
  await testModeratorCanCreateBusinessWithBlankSourceMetadata();
}

async function testRevokedAdminAtomicSaveLeavesNoBusiness() {
  await seed(`users/${adminId}/private/account`, { isAdmin: false });
  const instance = db(adminId);
  const batch = writeBatch(instance);
  batch.set(doc(instance, `businesses/${businessId}`), businessPayload());
  batch.set(doc(instance, `moderatorListingMetadata/${businessId}`), metadataPayload());
  await deny("revoked administrator batch", batch.commit());
  const snapshot = await getDoc(doc(instance, `businesses/${businessId}`));
  if (snapshot.exists()) throw new Error("Failed atomic save left a business behind");
}

async function testMetadataFailureRollsBackOtherwiseAllowedBusiness() {
  const instance = db(ordinaryId);
  const payload = businessPayload({ createdBy: ordinaryId, ownerId: ordinaryId });
  for (const key of ["createdByModerator", "listingOwnershipStatus", "claimedByUserId", "claimedAt", "claimStatus"]) delete payload[key];
  await allow("self-service business control write", setDoc(doc(instance, "businesses/control"), payload));
  const batch = writeBatch(instance);
  batch.set(doc(instance, `businesses/${businessId}`), payload);
  batch.set(doc(instance, `moderatorListingMetadata/${businessId}`), metadataPayload());
  await deny("denied metadata rolls back otherwise allowed business", batch.commit());
  if ((await getDoc(doc(instance, `businesses/${businessId}`))).exists()) throw new Error("Partial business save");
}

async function run() {
  await setup();
  try {
    for (const testCase of [
      testMetadataFailureRollsBackOtherwiseAllowedBusiness,
      testMigratedAdminBusinessAndMetadata,
      testRevokedAdminAtomicSaveLeavesNoBusiness,
      testModeratorCanCreateBusinessWithBlankSourceMetadata,
      testModeratorCanCreateBusinessWithoutOptionalSourceMetadata,
      testOrdinaryUserCannotUseModeratorBusinessCreatePath,
      testMalformedModeratorBusinessDenied,
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
