"use strict";

const assert = require("node:assert/strict");
const {
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const { doc, getDoc, setDoc } = require("firebase/firestore");

const projectId = process.env.GCLOUD_PROJECT || "locallink-995a5";
let testEnv;

async function seed(path, data) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), path), data);
  });
}

function request(uid, email, claimCode) {
  return {
    data: { claimCode },
    auth: {
      uid,
      token: {
        email,
        email_verified: true,
        firebase: { sign_in_provider: "password" },
      },
    },
  };
}

async function expectCode(promise, code) {
  await assert.rejects(promise, (error) => error?.code === code);
}

async function main() {
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: { host: "127.0.0.1", port: 8080 },
  });
  const functions = require("../functions/index");

  await seed("businesses/private-success", {
    businessName: "Private success", createdBy: "seed", ownerId: "",
    isClaimed: false,
  });
  await seed("businessClaimSecrets/private-success", {
    businessId: "private-success", claimCode: "PRIVATE123",
    claimCodeNormalized: "PRIVATE123", claimEmail: "owner@example.com",
    status: "pending",
  });
  const result = await functions.claimBusinessByCode.run(
    request("owner", "owner@example.com", "private123"),
  );
  assert.equal(result.businessId, "private-success");
  const claimed = await getDoc(doc(testEnv.authenticatedContext("reader", {
    firebase: { sign_in_provider: "password" },
  }).firestore(), "businesses/private-success"));
  assert.equal(claimed.data().ownerId, "owner");

  await seed("businesses/wrong-email", {
    businessName: "Wrong email", createdBy: "seed", ownerId: "",
    isClaimed: false,
  });
  await seed("businessClaimSecrets/wrong-email", {
    businessId: "wrong-email", claimCode: "EMAIL123",
    claimCodeNormalized: "EMAIL123", claimEmail: "assigned@example.com",
    status: "pending",
  });
  await expectCode(
    functions.claimBusinessByCode.run(request("other", "other@example.com", "EMAIL123")),
    "permission-denied",
  );
  await expectCode(
    functions.claimBusinessByCode.run(request("owner", "owner@example.com", "NO-SUCH-CODE")),
    "not-found",
  );

  await seed("businesses/legacy-success", {
    businessName: "Legacy success", createdBy: "seed", ownerId: "",
    isClaimed: false, claimCode: "LEGACY123", claimEmail: "legacy@example.com",
  });
  const legacyResult = await functions.claimBusinessByCode.run(
    request("legacy-owner", "legacy@example.com", "LEGACY123"),
  );
  assert.equal(legacyResult.businessId, "legacy-success");

  await testEnv.cleanup();
  console.log("business claim function emulator tests passed");
}

main().catch(async (error) => {
  if (testEnv) await testEnv.cleanup();
  console.error(error);
  process.exitCode = 1;
});
