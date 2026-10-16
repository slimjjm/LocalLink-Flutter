"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {
  PRIVATE_ACCOUNT_FIELDS,
  parseArgs,
  selectedFields,
} = require("../scripts/migrate_private_data");

test("migration defaults to a non-writing verification pass", () => {
  assert.deepEqual(parseArgs(["node", "script", "--project=test-project"]), {
    phase: "verify",
    projectId: "test-project",
    apply: false,
    confirmProject: "",
  });
});

test("private account selection excludes public profile fields", () => {
  const selected = selectedFields({
    name: "Public name",
    bio: "Public bio",
    email: "private@example.com",
    isAdmin: true,
    stripeCustomerId: "cus_private",
  }, PRIVATE_ACCOUNT_FIELDS);
  assert.deepEqual(selected, {
    email: "private@example.com",
    isAdmin: true,
    stripeCustomerId: "cus_private",
  });
});
