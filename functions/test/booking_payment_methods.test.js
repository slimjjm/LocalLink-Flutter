"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const indexSource = fs.readFileSync(
  path.join(__dirname, "..", "index.js"),
  "utf8"
);

test("direct bookings support only explicit direct payment methods", () => {
  assert.match(
    indexSource,
    /DIRECT_BOOKING_PAYMENT_METHODS = new Set\(\["cash", "bank_transfer"\]\)/
  );
  assert.match(indexSource, /paymentMethods\.includes\(paymentMethod\)/);
  assert.doesNotMatch(indexSource, /:\s*\["cash"\]/);
});

test("legacy direct booking callables preserve selected direct method", () => {
  assert.match(
    indexSource,
    /const paymentMethod = directBookingPaymentMethodFromRequest\(request\.data\);/
  );
  assert.match(indexSource, /paymentMethod,\n\s+paymentStatus: directBookingPaymentStatus\(\),/);
});
