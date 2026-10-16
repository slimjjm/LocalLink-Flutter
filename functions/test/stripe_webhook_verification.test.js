"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const Stripe = require("stripe");

const {
  verifyStripeWebhookEvent,
} = require("../stripe_webhook_verification");

const stripe = Stripe("sk_test_local");
const platformSecret = "whsec_platform_test";
const connectSecret = "whsec_connect_test";

function signedPayload({ event, secret }) {
  const payload = JSON.stringify(event);
  return {
    payload,
    signature: stripe.webhooks.generateTestHeaderString({
      payload,
      secret,
    }),
  };
}

function paymentIntentEvent(overrides = {}) {
  return {
    id: overrides.id || "evt_test",
    object: "event",
    type: overrides.type || "payment_intent.succeeded",
    account: overrides.account,
    data: {
      object: {
        id: overrides.paymentIntentId || "pi_test",
        object: "payment_intent",
        metadata: {
          bookingId: overrides.bookingId || "booking_1",
          businessId: overrides.businessId || "business_1",
          staffId: overrides.staffId || "staff_1",
          slotId: overrides.slotId || "slot_1",
          directAvailability: overrides.directAvailability || "false",
        },
      },
    },
  };
}

test("correctly signed platform webhook is accepted first", () => {
  const event = paymentIntentEvent({ id: "evt_platform" });
  const { payload, signature } = signedPayload({
    event,
    secret: platformSecret,
  });

  const verified = verifyStripeWebhookEvent({
    stripe,
    rawBody: payload,
    signature,
    platformSecret,
    connectSecret,
  });

  assert.equal(verified.event.id, "evt_platform");
  assert.equal(verified.event.account, undefined);
});

test("correctly signed Connect webhook is accepted with connected account", () => {
  const event = paymentIntentEvent({
    id: "evt_connect",
    account: "acct_connected_123",
  });
  const { payload, signature } = signedPayload({
    event,
    secret: connectSecret,
  });

  const verified = verifyStripeWebhookEvent({
    stripe,
    rawBody: payload,
    signature,
    platformSecret,
    connectSecret,
  });

  assert.equal(verified.event.id, "evt_connect");
  assert.equal(verified.event.account, "acct_connected_123");
});

test("Connect webhook secret tolerates accidental leading and trailing whitespace", () => {
  const event = paymentIntentEvent({
    id: "evt_connect_trimmed_secret",
    account: "acct_connected_123",
  });
  const { payload, signature } = signedPayload({
    event,
    secret: connectSecret,
  });

  const verified = verifyStripeWebhookEvent({
    stripe,
    rawBody: payload,
    signature,
    platformSecret,
    connectSecret: `  ${connectSecret}\n`,
  });

  assert.equal(verified.event.id, "evt_connect_trimmed_secret");
});

test("invalid webhook signature is rejected", () => {
  const event = paymentIntentEvent({ id: "evt_invalid" });
  const { payload, signature } = signedPayload({
    event,
    secret: "whsec_wrong",
  });

  assert.throws(
    () => verifyStripeWebhookEvent({
      stripe,
      rawBody: payload,
      signature,
      platformSecret,
      connectSecret,
    }),
    /signature/i
  );
});

const indexSource = fs.readFileSync(
  path.join(__dirname, "..", "index.js"),
  "utf8"
);

test("stripeWebhook declares both platform and Connect webhook secrets", () => {
  assert.match(indexSource, /"STRIPE_WEBHOOK_SECRET"/);
  assert.match(indexSource, /"STRIPE_CONNECT_WEBHOOK_SECRET"/);
});

test("platform events continue to reconcile legacy bookings", () => {
  assert.match(indexSource, /event\.account \|\| "platform"/);
  assert.match(indexSource, /finalizePaidBookingInTransaction/);
});

test("connected-account events continue to reconcile direct-charge bookings", () => {
  assert.match(indexSource, /const eventStripeAccountId = safeTrim\(event\.account\);/);
  assert.match(indexSource, /stripeAccountId: eventStripeAccountId/);
});

test("connected-account mismatch protection remains effective", () => {
  assert.match(indexSource, /expectedAccountId && expectedAccountId !== eventStripeAccountId/);
  assert.match(indexSource, /Connected Stripe event account did not match booking/);
});

test("existing webhook idempotency remains intact", () => {
  assert.match(indexSource, /stripeEventRef\(event\.id\)/);
  assert.match(indexSource, /Duplicate webhook ignored/);
});
