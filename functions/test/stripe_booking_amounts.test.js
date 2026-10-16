"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const indexSource = fs.readFileSync(
  path.join(__dirname, "..", "index.js"),
  "utf8"
);

test("direct availability PaymentIntent still receives booking price in minor units", () => {
  assert.match(
    indexSource,
    /paymentIntents\.create\(\s*\{\s*amount:\s*booking\.price,\s*currency:\s*"gbp"/s
  );
});

test("standard booking PaymentIntent still receives total price in minor units", () => {
  assert.match(
    indexSource,
    /paymentIntents\.create\(\s*\{\s*amount:\s*totalPrice,\s*currency:\s*"gbp"/s
  );
});

test("new card bookings use connected-account direct charges", () => {
  assert.match(indexSource, /stripeAccount:\s*stripeAccountId/);
  assert.match(
    indexSource,
    /stripeAccountContext:\s*STRIPE_PAYMENT_ACCOUNT_CONTEXT_CONNECTED/
  );
  assert.match(indexSource, /paymentStripeAccountId:\s*stripeAccountId/);
});

test("new card bookings do not use destination transfers or application fees", () => {
  assert.doesNotMatch(indexSource, /transfer_data\s*:/);
  assert.doesNotMatch(indexSource, /application_fee_amount\s*:/);
  assert.doesNotMatch(indexSource, /application_fee\s*:/);
});

test("direct-charge refunds and cleanup use the booking Stripe account context", () => {
  assert.match(
    indexSource,
    /function stripeOptionsForBookingPayment\(booking\)/
  );
  assert.match(
    indexSource,
    /stripe\.refunds\.create\(\s*\{\s*payment_intent:\s*safeTrim\(booking\.paymentIntentId\),\s*\},\s*stripeOptionsForBookingPayment\(booking\)/s
  );
  assert.match(
    indexSource,
    /stripe\.paymentIntents\.retrieve\(\s*paymentIntentId,\s*stripeOptionsForBookingPayment\(booking\)/s
  );
});

test("legacy destination-charge bookings remain on platform context by default", () => {
  assert.match(indexSource, /STRIPE_CHARGE_TYPE_DESTINATION = "destination"/);
  assert.match(indexSource, /return undefined;\n\}/);
});

test("connected-account webhook events are reconciled by booking metadata", () => {
  assert.match(indexSource, /const eventStripeAccountId = safeTrim\(event\.account\);/);
  assert.match(indexSource, /stripe_account_mismatch/);
});
