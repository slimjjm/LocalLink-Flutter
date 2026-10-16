"use strict";

const crypto = require("crypto");

function tokenDocumentId(token) {
  return crypto.createHash("sha256").update(String(token)).digest("hex");
}

async function getPushTargets(userRef, { includeLegacy = true } = {}) {
  const [deviceSnap, userSnap] = await Promise.all([
    userRef.collection("devices").get(),
    includeLegacy ? userRef.get() : Promise.resolve(null),
  ]);

  const targetsByToken = new Map();
  for (const deviceDoc of deviceSnap.docs) {
    const token = String(deviceDoc.data()?.token || "").trim();
    if (token) targetsByToken.set(token, {
      token,
      deviceRef: deviceDoc.ref,
      legacy: false,
    });
  }

  if (includeLegacy && userSnap?.exists) {
    const legacyTokens = Array.isArray(userSnap.data()?.fcmTokens)
      ? userSnap.data().fcmTokens
      : [];
    for (const value of legacyTokens) {
      const token = String(value || "").trim();
      if (token && targetsByToken.has(token)) {
        targetsByToken.get(token).legacy = true;
      } else if (token) {
        targetsByToken.set(token, { token, deviceRef: null, legacy: true });
      }
    }
  }

  return [...targetsByToken.values()];
}

async function removeInvalidPushTargets({ admin, userRef, targets }) {
  if (!targets.length) return;

  const batch = userRef.firestore.batch();
  const legacyTokens = [];
  for (const target of targets) {
    if (target.deviceRef) batch.delete(target.deviceRef);
    if (target.legacy) legacyTokens.push(target.token);
  }
  if (legacyTokens.length) {
    batch.set(userRef, {
      fcmTokens: admin.firestore.FieldValue.arrayRemove(...legacyTokens),
    }, { merge: true });
  }
  await batch.commit();
}

module.exports = {
  getPushTargets,
  removeInvalidPushTargets,
  tokenDocumentId,
};
