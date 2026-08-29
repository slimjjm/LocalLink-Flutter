"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const {
  cleanupDecisionForPaymentIntentStatus,
} = require("../stripe_cleanup_policy");

test("succeeded payment is reconciled instead of cancelled", () => {
  assert.equal(
    cleanupDecisionForPaymentIntentStatus("succeeded"),
    "reconcile_paid"
  );
});

test("processing and requires_capture payments remain pending", () => {
  assert.equal(
    cleanupDecisionForPaymentIntentStatus("processing"),
    "keep_pending"
  );
  assert.equal(
    cleanupDecisionForPaymentIntentStatus("requires_capture"),
    "keep_pending"
  );
});

test("definitively unpaid payment states can be abandoned", () => {
  for (const status of [
    "canceled",
    "requires_payment_method",
    "requires_confirmation",
    "requires_action",
  ]) {
    assert.equal(cleanupDecisionForPaymentIntentStatus(status), "abandon");
  }
});

test("unknown payment states fail safe", () => {
  assert.equal(
    cleanupDecisionForPaymentIntentStatus("future_stripe_state"),
    "keep_pending"
  );
});
