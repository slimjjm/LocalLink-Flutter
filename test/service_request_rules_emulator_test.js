"use strict";

const fs = require("node:fs");
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const {
  doc,
  setDoc,
  updateDoc,
  deleteField,
} = require("firebase/firestore");

const projectId = "locallink-995a5";
const host = "127.0.0.1";
const port = 8080;
const now = new Date();
const future = new Date(now.getTime() + 3 * 24 * 60 * 60 * 1000);

let testEnv;

function db(uid, email = `${uid}@example.com`) {
  return testEnv.authenticatedContext(uid, {
    email,
    firebase: { sign_in_provider: "password" },
  }).firestore();
}

async function seed(path, data) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), path), data);
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

function serviceRequest(overrides = {}) {
  return {
    customerId: "owner",
    category: "Cleaner",
    title: "Cleaner needed",
    description: "Kitchen and bathroom clean.",
    scheduleText: "Friday morning",
    budgetText: "£20/hour",
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
    ...overrides,
  };
}

async function createAsOwner(id, data) {
  return setDoc(doc(db("owner"), `serviceRequests/${id}`), data);
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
}

async function testOwnerCreateImageUrls() {
  await allow(
    "owner create without imageUrls",
    createAsOwner("no-images", serviceRequest()),
  );
  await allow(
    "owner create with empty imageUrls",
    createAsOwner("empty-images", serviceRequest({ imageUrls: [] })),
  );
  await allow(
    "owner create with one image",
    createAsOwner("one-image", serviceRequest({
      imageUrls: ["https://example.com/one.jpg"],
    })),
  );
  await allow(
    "owner create with three images",
    createAsOwner("three-images", serviceRequest({
      imageUrls: [
        "https://example.com/one.jpg",
        "https://example.com/two.jpg",
        "https://example.com/three.jpg",
      ],
    })),
  );
}

async function testInvalidImageUrlsDenied() {
  await deny(
    "four image urls",
    createAsOwner("four-images", serviceRequest({
      imageUrls: [
        "https://example.com/one.jpg",
        "https://example.com/two.jpg",
        "https://example.com/three.jpg",
        "https://example.com/four.jpg",
      ],
    })),
  );
  await deny(
    "invalid imageUrls type",
    createAsOwner("invalid-images", serviceRequest({ imageUrls: "not-a-list" })),
  );
  await deny(
    "invalid imageUrls entry",
    createAsOwner("invalid-entry", serviceRequest({ imageUrls: [123] })),
  );
}

async function testOwnerUpdateImageUrls() {
  await seed("serviceRequests/update-images", serviceRequest());
  await allow(
    "owner add image urls",
    updateDoc(doc(db("owner"), "serviceRequests/update-images"), {
      imageUrls: ["https://example.com/one.jpg"],
      updatedAt: now,
    }),
  );
  await allow(
    "owner remove image urls",
    updateDoc(doc(db("owner"), "serviceRequests/update-images"), {
      imageUrls: deleteField(),
      updatedAt: now,
    }),
  );
}

async function testOwnerCanEditCustomerFields() {
  await seed("serviceRequests/edit-request", serviceRequest());
  await seed("serviceRequests/edit-request/offers/offer-1", {
    businessId: "business-1",
    businessOwnerId: "provider",
    status: "pending",
    createdAt: now,
  });

  await allow(
    "owner edit customer request fields",
    updateDoc(doc(db("owner"), "serviceRequests/edit-request"), {
      category: "Handyman",
      title: "Door repair needed",
      description: "The back door lock is sticking.",
      details: "The back door lock is sticking.",
      scheduleText: "Saturday morning",
      budgetText: "£60",
      publicLocation: "Burntwood",
      location: "Burntwood",
      locationPrecision: "approximate",
      approxLatitude: 52.681,
      approxLongitude: -1.831,
      imageUrls: ["https://example.com/door.jpg"],
      updatedAt: now,
    }),
  );
}

async function testOwnerCannotEditProtectedRequestFields() {
  await seed("serviceRequests/protected-request", serviceRequest());

  await deny(
    "owner cannot change request owner while editing",
    updateDoc(doc(db("owner"), "serviceRequests/protected-request"), {
      customerId: "other",
      updatedAt: now,
    }),
  );
  await deny(
    "owner cannot change request creation time while editing",
    updateDoc(doc(db("owner"), "serviceRequests/protected-request"), {
      createdAt: future,
      updatedAt: now,
    }),
  );
}

async function testOtherUsersCannotUpdateImageUrls() {
  await seed("serviceRequests/other-user-images", serviceRequest());
  await deny(
    "other user modify image urls",
    updateDoc(doc(db("other"), "serviceRequests/other-user-images"), {
      imageUrls: ["https://example.com/other.jpg"],
      updatedAt: now,
    }),
  );
}

async function testBusinessCannotUpdateImageUrls() {
  await seed("serviceRequests/provider-images", serviceRequest());
  await seed("businesses/business-1", {
    businessName: "Provider",
    ownerId: "provider",
    isClaimed: true,
    isActive: true,
    acceptingLeads: true,
  });
  await deny(
    "provider modify customer image urls",
    updateDoc(doc(db("provider"), "serviceRequests/provider-images"), {
      imageUrls: ["https://example.com/provider.jpg"],
      updatedAt: now,
    }),
  );
}

async function testProviderInterestUpdateIsAppendOnly() {
  await seed("businesses/business-1", {
    businessName: "Provider",
    ownerId: "provider",
    isClaimed: true,
    isActive: true,
    acceptingLeads: true,
  });
  await seed("serviceRequests/provider-interest", serviceRequest());

  await allow(
    "provider appends own business interest",
    updateDoc(doc(db("provider"), "serviceRequests/provider-interest"), {
      interestedBusinessIds: ["business-1"],
      lastInterestedBusinessId: "business-1",
      updatedAt: now,
    }),
  );

  await seed("serviceRequests/existing-interest", serviceRequest({
    interestedBusinessIds: ["business-2"],
    lastInterestedBusinessId: "business-2",
  }));
  await deny(
    "provider cannot erase another provider's interest",
    updateDoc(doc(db("provider"), "serviceRequests/existing-interest"), {
      interestedBusinessIds: ["business-1"],
      lastInterestedBusinessId: "business-1",
      updatedAt: now,
    }),
  );
  await deny(
    "provider cannot close customer's request while adding interest",
    updateDoc(doc(db("provider"), "serviceRequests/existing-interest"), {
      status: "closed",
      interestedBusinessIds: ["business-2", "business-1"],
      lastInterestedBusinessId: "business-1",
      updatedAt: now,
    }),
  );
}

async function run() {
  await setup();
  try {
    for (const testCase of [
      testOwnerCreateImageUrls,
      testInvalidImageUrlsDenied,
      testOwnerUpdateImageUrls,
      testOwnerCanEditCustomerFields,
      testOwnerCannotEditProtectedRequestFields,
      testOtherUsersCannotUpdateImageUrls,
      testBusinessCannotUpdateImageUrls,
      testProviderInterestUpdateIsAppendOnly,
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
