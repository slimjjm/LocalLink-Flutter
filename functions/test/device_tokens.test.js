"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const { getPushTargets, tokenDocumentId } = require("../device_tokens");

test("token document IDs are deterministic and do not expose the token", () => {
  const token = "fcm-registration-token-that-must-remain-private";
  const first = tokenDocumentId(token);
  assert.equal(first, tokenDocumentId(token));
  assert.equal(first.length, 64);
  assert.equal(first.includes(token), false);
});

test("different tokens produce different device document IDs", () => {
  assert.notEqual(tokenDocumentId("token-a"), tokenDocumentId("token-b"));
});

test("push lookup returns all private devices and deduplicated legacy fallback", async () => {
  const privateRefA = { path: "users/u/devices/a" };
  const privateRefB = { path: "users/u/devices/b" };
  const userRef = {
    collection: () => ({
      get: async () => ({
        docs: [
          { ref: privateRefA, data: () => ({ token: "token-a" }) },
          { ref: privateRefB, data: () => ({ token: "token-b" }) },
        ],
      }),
    }),
    get: async () => ({
      exists: true,
      data: () => ({ fcmTokens: ["token-a", "legacy-only", "legacy-only"] }),
    }),
  };

  const targets = await getPushTargets(userRef, { includeLegacy: true });
  assert.deepEqual(targets.map((target) => target.token), [
    "token-a", "token-b", "legacy-only",
  ]);
  assert.equal(targets[0].legacy, true);
  assert.equal(targets[1].legacy, false);
  assert.equal(targets[2].deviceRef, null);
});
