"use strict";

function cleanupDecisionForPaymentIntentStatus(status) {
  if (status === "succeeded") {
    return "reconcile_paid";
  }

  if (status === "processing" || status === "requires_capture") {
    return "keep_pending";
  }

  if ([
    "canceled",
    "requires_payment_method",
    "requires_confirmation",
    "requires_action",
  ].includes(status)) {
    return "abandon";
  }

  return "keep_pending";
}

module.exports = {
  cleanupDecisionForPaymentIntentStatus,
};
