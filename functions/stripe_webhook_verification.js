"use strict";

function configuredSecrets(platformSecret, connectSecret) {
  return [
    { source: "platform", secret: String(platformSecret || "").trim() },
    { source: "connect", secret: String(connectSecret || "").trim() },
  ].filter((entry, index, entries) =>
    entry.secret &&
    entries.findIndex((candidate) => candidate.secret === entry.secret) === index
  );
}

function verifyStripeWebhookEvent({
  stripe,
  rawBody,
  signature,
  platformSecret,
  connectSecret,
}) {
  if (!signature) {
    const error = new Error("Missing stripe-signature.");
    error.code = "missing_signature";
    throw error;
  }

  const secrets = configuredSecrets(platformSecret, connectSecret);
  if (secrets.length === 0) {
    const error = new Error("Missing webhook secret.");
    error.code = "missing_secret";
    throw error;
  }

  let lastError = null;

  for (const entry of secrets) {
    try {
      // entry.secret is deliberately trimmed by configuredSecrets().
      return {
        event: stripe.webhooks.constructEvent(rawBody, signature, entry.secret),
      };
    } catch (error) {
      lastError = error;
    }
  }

  throw lastError;
}

module.exports = {
  verifyStripeWebhookEvent,
};
