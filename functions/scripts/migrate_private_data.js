#!/usr/bin/env node
"use strict";

const admin = require("firebase-admin");
const { tokenDocumentId } = require("../device_tokens");

const PRIVATE_ACCOUNT_FIELDS = [
  "email", "phone", "phoneNumber",
  "isAdmin", "isBanned", "bannedAt", "bannedBy",
  "moderationStatus", "moderationReasonCode", "adminNotes", "internalNotes",
  "roles", "permissions", "claims",
  "isVerified", "verified", "verification", "verificationStatus",
  "subscription", "subscriptionStatus", "paymentStatus",
  "customerId", "stripeStatus", "stripeCustomerId", "stripeSubscriptionId",
];
const LEGACY_BUSINESS_CLAIM_FIELDS = [
  "claimEmail", "claimCode", "claimToken", "claimSecret",
];

function parseArgs(argv) {
  const values = Object.fromEntries(argv.slice(2).filter((arg) => arg.startsWith("--"))
    .map((arg) => {
      const [key, ...rest] = arg.slice(2).split("=");
      return [key, rest.length ? rest.join("=") : true];
    }));
  return {
    phase: String(values.phase || "verify"),
    projectId: String(values.project || ""),
    apply: values.apply === true,
    confirmProject: String(values["confirm-project"] || ""),
  };
}

function selectedFields(data, names) {
  return Object.fromEntries(names.filter((name) => data[name] !== undefined)
    .map((name) => [name, data[name]]));
}

async function copyUser(db, userDoc, apply) {
  const data = userDoc.data();
  const tokens = [...new Set((Array.isArray(data.fcmTokens) ? data.fcmTokens : [])
    .map((token) => String(token || "").trim()).filter(Boolean))];
  const account = selectedFields(data, PRIVATE_ACCOUNT_FIELDS);
  if (apply) {
    const batch = db.batch();
    for (const token of tokens) {
      batch.set(userDoc.ref.collection("devices").doc(tokenDocumentId(token)), {
        token,
        platform: "legacy",
        source: "legacy_profile_migration",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        migratedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    }
    if (Object.keys(account).length) {
      batch.set(userDoc.ref.collection("private").doc("account"), {
        ...account,
        migratedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    }
    const access = selectedFields(data, ["isAdmin", "isBanned"]);
    if (Object.keys(access).length) {
      batch.set(userDoc.ref.collection("private").doc("access"), {
        ...access,
        migratedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    }
    await batch.commit();
  }
  return { tokenCount: tokens.length, hasAccount: Object.keys(account).length > 0 };
}

async function verifyUser(userDoc) {
  const data = userDoc.data();
  const tokens = [...new Set((Array.isArray(data.fcmTokens) ? data.fcmTokens : [])
    .map((token) => String(token || "").trim()).filter(Boolean))];
  const deviceDocs = await Promise.all(tokens.map((token) =>
    userDoc.ref.collection("devices").doc(tokenDocumentId(token)).get()));
  const accountFields = selectedFields(data, PRIVATE_ACCOUNT_FIELDS);
  const accountSnap = Object.keys(accountFields).length
    ? await userDoc.ref.collection("private").doc("account").get()
    : null;
  const accessFields = selectedFields(data, ["isAdmin", "isBanned"]);
  const accessSnap = Object.keys(accessFields).length
    ? await userDoc.ref.collection("private").doc("access").get()
    : null;
  return deviceDocs.every((doc, index) =>
    doc.exists && doc.data()?.token === tokens[index])
    && (!accountSnap || accountSnap.exists
      && Object.entries(accountFields).every(([key, value]) =>
        JSON.stringify(accountSnap.data()?.[key]) === JSON.stringify(value)))
    && (!accessSnap || accessSnap.exists
      && Object.entries(accessFields).every(([key, value]) =>
        JSON.stringify(accessSnap.data()?.[key]) === JSON.stringify(value)));
}

async function copyBusiness(db, businessDoc, apply) {
  const legacy = selectedFields(businessDoc.data(), LEGACY_BUSINESS_CLAIM_FIELDS);
  if (!Object.keys(legacy).length) return false;
  if (apply) {
    const code = String(legacy.claimCode || "").trim().toUpperCase();
    await db.collection("businessClaimSecrets").doc(businessDoc.id).set({
      businessId: businessDoc.id,
      ...legacy,
      ...(code ? { claimCodeNormalized: code } : {}),
      status: businessDoc.data().isClaimed === true ? "claimed" : "pending",
      migratedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  }
  return true;
}

async function verifyBusiness(db, businessDoc) {
  const legacy = selectedFields(businessDoc.data(), LEGACY_BUSINESS_CLAIM_FIELDS);
  if (!Object.keys(legacy).length) return true;
  const secretSnap = await db.collection("businessClaimSecrets").doc(businessDoc.id).get();
  return secretSnap.exists && Object.entries(legacy).every(([key, value]) =>
    JSON.stringify(secretSnap.data()?.[key]) === JSON.stringify(value));
}

async function run() {
  const options = parseArgs(process.argv);
  if (!options.projectId) throw new Error("Pass --project=<firebase-project-id>.");
  if (!["copy", "verify", "cleanup"].includes(options.phase)) {
    throw new Error("--phase must be copy, verify, or cleanup.");
  }
  if (options.apply && options.confirmProject !== options.projectId) {
    throw new Error("Writes require --confirm-project to exactly match --project.");
  }
  if (options.phase === "cleanup" && !options.apply) {
    throw new Error("Cleanup is write-only and requires --apply plus --confirm-project.");
  }

  admin.initializeApp({ projectId: options.projectId });
  const db = admin.firestore();
  const [usersSnap, businessesSnap] = await Promise.all([
    db.collection("users").get(),
    db.collection("businesses").get(),
  ]);
  const counts = {
    usersScanned: 0, tokensFound: 0, privateAccountsFound: 0,
    businessesScanned: 0, businessSecretsFound: 0,
    verifiedUsers: 0, verifiedBusinesses: 0, cleanupBlocked: 0,
  };

  for (const userDoc of usersSnap.docs) {
    counts.usersScanned += 1;
    const result = await copyUser(db, userDoc, options.phase === "copy" && options.apply);
    counts.tokensFound += result.tokenCount;
    if (result.hasAccount) counts.privateAccountsFound += 1;
    const verified = await verifyUser(userDoc);
    if (verified) counts.verifiedUsers += 1;
    if (options.phase === "cleanup") {
      if (!verified) {
        counts.cleanupBlocked += 1;
      } else {
        const deletion = Object.fromEntries(
          ["fcmTokens", ...PRIVATE_ACCOUNT_FIELDS]
            .filter((field) => userDoc.data()[field] !== undefined)
            .map((field) => [field, admin.firestore.FieldValue.delete()]),
        );
        if (Object.keys(deletion).length) await userDoc.ref.update(deletion);
      }
    }
  }

  for (const businessDoc of businessesSnap.docs) {
    counts.businessesScanned += 1;
    const found = await copyBusiness(db, businessDoc, options.phase === "copy" && options.apply);
    if (found) counts.businessSecretsFound += 1;
    const verified = await verifyBusiness(db, businessDoc);
    if (verified) counts.verifiedBusinesses += 1;
    if (options.phase === "cleanup" && found) {
      if (!verified) {
        counts.cleanupBlocked += 1;
      } else {
        await businessDoc.ref.update(Object.fromEntries(
          LEGACY_BUSINESS_CLAIM_FIELDS
            .filter((field) => businessDoc.data()[field] !== undefined)
            .map((field) => [field, admin.firestore.FieldValue.delete()]),
        ));
      }
    }
  }

  console.log(JSON.stringify({
    phase: options.phase,
    mode: options.apply ? "apply" : "dry-run",
    projectId: options.projectId,
    counts,
  }, null, 2));
  if (counts.cleanupBlocked) process.exitCode = 2;
}

if (require.main === module) {
  run().catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
}

module.exports = {
  LEGACY_BUSINESS_CLAIM_FIELDS,
  PRIVATE_ACCOUNT_FIELDS,
  parseArgs,
  selectedFields,
};
