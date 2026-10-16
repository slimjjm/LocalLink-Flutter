"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const {
  BOOKING_EMAIL_FROM,
  businessEmailFromData,
  confirmationEmails,
  createMemoryEmailDeliveryStore,
  formatPenceAsGbp,
  sendTransactionalBookingEmails,
  paymentMethodLabel,
} = require("../booking_emails");

function confirmedBooking(overrides = {}) {
  return {
    status: "confirmed",
    businessName: "Quietly Local Grooming",
    serviceName: "Groom",
    customerName: "James",
    customerAddress: "12 High Street",
    customerNotes: "Please use the side gate.",
    price: 1250,
    paymentMethod: "stripe",
    paymentStatus: "paid",
    startDate: new Date("2026-09-09T17:51:00.000Z"),
    endDate: new Date("2026-09-09T18:51:00.000Z"),
    serviceDurationMinutes: 60,
    ...overrides,
  };
}

function successFetch(calls) {
  return async (_url, request) => {
    calls.push(JSON.parse(request.body));
    return { ok: true, status: 200 };
  };
}

test("formats booking email money from pence to GBP", () => {
  assert.equal(formatPenceAsGbp(100), "£1.00");
  assert.equal(formatPenceAsGbp(999), "£9.99");
  assert.equal(formatPenceAsGbp(1000), "£10.00");
  assert.equal(formatPenceAsGbp(10000), "£100.00");
});

test("booking price remains an integer minor-unit value for Stripe", () => {
  const booking = confirmedBooking({ price: 100 });
  assert.equal(Number.isInteger(booking.price), true);
  assert.equal(booking.price, 100);
  assert.equal(formatPenceAsGbp(booking.price), "£1.00");
});

test("confirmed paid booking triggers customer and business emails", async () => {
  const calls = [];
  const result = await sendTransactionalBookingEmails({
    bookingId: "booking_12345678",
    booking: confirmedBooking(),
    business: { email: "provider@example.com" },
    customerEmail: "customer@example.com",
    businessEmail: businessEmailFromData({ email: "provider@example.com" }),
    eventType: "confirmation",
    apiKey: "resend_test_key",
    store: createMemoryEmailDeliveryStore(),
    fetchImpl: successFetch(calls),
  });

  assert.deepEqual(result, {
    sent: 2,
    skipped: 0,
    failed: 0,
    missingCustomerEmail: false,
    missingBusinessEmail: false,
  });
  assert.equal(calls.length, 2);
  assert.equal(calls[0].from, BOOKING_EMAIL_FROM);
  assert.match(calls[0].subject, /Booking confirmed/);
  assert.match(calls[1].subject, /New LocalLink booking/);
  assert.match(calls[0].text, /Total: £12.50/);
  assert.match(calls[1].text, /Total: £12.50/);
  assert.match(calls[0].text, /Service address: 12 High Street/);
  assert.doesNotMatch(calls[0].text, /pi_|acct_|secret/i);
});

test("booking email can include a safe HTTPS LocalLink logo", () => {
  const [email] = confirmationEmails({
    bookingId: "booking_logo",
    booking: confirmedBooking(),
    business: { email: "provider@example.com" },
    customerEmail: "customer@example.com",
    businessEmail: "",
    logoUrl: "https://locallinkapp.co.uk/assets/locallink_logo.png",
  });

  assert.match(email.html, /alt="LocalLink"/);
  assert.match(email.html, /width="144"/);
  assert.match(email.html, /https:\/\/locallinkapp\.co\.uk\/assets\/locallink_logo\.png/);
});

test("unconfirmed payment sends no confirmation emails", async () => {
  const calls = [];
  const result = await sendTransactionalBookingEmails({
    bookingId: "booking_pending",
    booking: confirmedBooking({ status: "pending_payment" }),
    business: { email: "provider@example.com" },
    customerEmail: "customer@example.com",
    businessEmail: "provider@example.com",
    eventType: "confirmation",
    apiKey: "resend_test_key",
    store: createMemoryEmailDeliveryStore(),
    fetchImpl: successFetch(calls),
  });

  assert.equal(result.reason, "not_confirmed");
  assert.equal(calls.length, 0);
});

test("duplicate confirmation processing does not duplicate emails", async () => {
  const calls = [];
  const store = createMemoryEmailDeliveryStore();
  const input = {
    bookingId: "booking_duplicate",
    booking: confirmedBooking(),
    business: { email: "provider@example.com" },
    customerEmail: "customer@example.com",
    businessEmail: "provider@example.com",
    eventType: "confirmation",
    apiKey: "resend_test_key",
    store,
    fetchImpl: successFetch(calls),
  };

  const first = await sendTransactionalBookingEmails(input);
  const second = await sendTransactionalBookingEmails(input);

  assert.equal(first.sent, 2);
  assert.equal(second.sent, 0);
  assert.equal(second.skipped, 2);
  assert.equal(calls.length, 2);
});

test("confirmed cash booking keeps pay-at-business wording", async () => {
  const calls = [];
  const booking = confirmedBooking({
    paymentMethod: "cash",
    paymentStatus: "pay_on_arrival",
  });

  await sendTransactionalBookingEmails({
    bookingId: "booking_cash",
    booking,
    business: { email: "provider@example.com" },
    customerEmail: "customer@example.com",
    businessEmail: "provider@example.com",
    eventType: "confirmation",
    apiKey: "resend_test_key",
    store: createMemoryEmailDeliveryStore(),
    fetchImpl: successFetch(calls),
  });

  assert.equal(paymentMethodLabel(booking), "Pay at business");
  assert.match(calls[0].text, /Payment: Pay at business/);
});

test("confirmed bank transfer booking keeps direct-transfer wording", async () => {
  const calls = [];
  const booking = confirmedBooking({
    paymentMethod: "bank_transfer",
    paymentStatus: "pay_on_arrival",
  });

  await sendTransactionalBookingEmails({
    bookingId: "booking_bank_transfer",
    booking,
    business: { email: "provider@example.com" },
    customerEmail: "customer@example.com",
    businessEmail: "provider@example.com",
    eventType: "confirmation",
    apiKey: "resend_test_key",
    store: createMemoryEmailDeliveryStore(),
    fetchImpl: successFetch(calls),
  });

  assert.equal(paymentMethodLabel(booking), "Bank transfer");
  assert.match(calls[0].text, /Payment: Bank transfer/);
});

test("pending booking acceptance sends confirmation once status is confirmed", async () => {
  const calls = [];
  await sendTransactionalBookingEmails({
    bookingId: "booking_accepted",
    booking: confirmedBooking({
      status: "confirmed",
      paymentMethod: "stripe",
      paymentStatus: "paid",
    }),
    business: { email: "provider@example.com" },
    customerEmail: "customer@example.com",
    businessEmail: "provider@example.com",
    eventType: "confirmation",
    apiKey: "resend_test_key",
    store: createMemoryEmailDeliveryStore(),
    fetchImpl: successFetch(calls),
  });

  assert.equal(calls.length, 2);
  assert.match(calls[0].text, /Booking confirmed/);
});

test("missing customer or business email fails safely by skipping recipients", async () => {
  const calls = [];
  const result = await sendTransactionalBookingEmails({
    bookingId: "booking_missing_email",
    booking: confirmedBooking(),
    business: {},
    customerEmail: "",
    businessEmail: "",
    eventType: "confirmation",
    apiKey: "resend_test_key",
    store: createMemoryEmailDeliveryStore(),
    fetchImpl: successFetch(calls),
  });

  assert.equal(result.sent, 0);
  assert.equal(result.missingCustomerEmail, true);
  assert.equal(result.missingBusinessEmail, true);
  assert.equal(calls.length, 0);
});

test("Resend failure does not throw and leaves booking workflow valid", async () => {
  const store = createMemoryEmailDeliveryStore();
  const result = await sendTransactionalBookingEmails({
    bookingId: "booking_resend_failure",
    booking: confirmedBooking(),
    business: { email: "provider@example.com" },
    customerEmail: "customer@example.com",
    businessEmail: "provider@example.com",
    eventType: "confirmation",
    apiKey: "resend_test_key",
    store,
    fetchImpl: async () => ({ ok: false, status: 500 }),
    logger: { error() {} },
  });

  assert.equal(result.sent, 0);
  assert.equal(result.failed, 2);
  assert.equal(store.deliveries.get("booking_confirmed_customer").status, "failed");
  assert.equal(store.deliveries.get("booking_confirmed_business").status, "failed");
});

test("cancellation emails include reliable refund wording", async () => {
  const calls = [];
  const result = await sendTransactionalBookingEmails({
    bookingId: "booking_cancelled",
    booking: confirmedBooking({
      status: "cancelled_by_customer",
      cancelledBy: "customer",
      refundStatus: "refunded",
    }),
    business: { email: "provider@example.com" },
    customerEmail: "customer@example.com",
    businessEmail: "provider@example.com",
    eventType: "cancellation",
    apiKey: "resend_test_key",
    store: createMemoryEmailDeliveryStore(),
    fetchImpl: successFetch(calls),
  });

  assert.equal(result.sent, 2);
  assert.match(calls[0].text, /Amount: £12.50/);
  assert.match(calls[0].text, /Refund: Refund issued/);
});
