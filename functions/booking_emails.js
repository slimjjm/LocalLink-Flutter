"use strict";

const RESEND_ENDPOINT = "https://api.resend.com/emails";
const BOOKING_EMAIL_FROM =
  "LocalLink <bookings@mail.locallinkapp.co.uk>";

function safeTrim(value) {
  return String(value ?? "").trim();
}

function htmlEscape(value) {
  return safeTrim(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function timestampToDate(value) {
  if (!value) return null;
  if (typeof value.toDate === "function") return value.toDate();
  if (value instanceof Date) return value;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

function timestampToMillis(value) {
  const date = timestampToDate(value);
  return date ? date.getTime() : null;
}

function formatDate(value) {
  const date = timestampToDate(value);
  if (!date) return "";
  return new Intl.DateTimeFormat("en-GB", {
    weekday: "long",
    day: "numeric",
    month: "long",
    year: "numeric",
    timeZone: "Europe/London",
  }).format(date);
}

function formatTime(value) {
  const date = timestampToDate(value);
  if (!date) return "";
  return new Intl.DateTimeFormat("en-GB", {
    hour: "2-digit",
    minute: "2-digit",
    timeZone: "Europe/London",
  }).format(date);
}

function formatPenceAsGbp(value) {
  const amountPence = Number(value);
  if (!Number.isInteger(amountPence)) return "";
  return new Intl.NumberFormat("en-GB", {
    style: "currency",
    currency: "GBP",
  }).format(amountPence / 100);
}

function paymentMethodLabel(booking) {
  const method = safeTrim(booking.paymentMethod).toLowerCase();
  const status = safeTrim(booking.paymentStatus).toLowerCase();
  if (method === "cash") return "Pay at business";
  if (method === "bank_transfer") return "Bank transfer";
  if (method === "stripe" && status === "paid") return "Card / Apple Pay";
  if (method === "stripe") return "Card";
  return "";
}

function businessEmailFromData(business) {
  return safeTrim(
    business.email ||
    business.businessEmail ||
    business.contactEmail ||
    business.ownerEmail
  );
}

function businessNameFromData(booking, business) {
  return safeTrim(
    booking.businessName ||
    business.businessName ||
    business.name ||
    "the business"
  );
}

function bookingReference(bookingId) {
  const id = safeTrim(bookingId);
  return id ? id.slice(-8).toUpperCase() : "";
}

function safeHttpsUrl(value) {
  const url = safeTrim(value);
  return url.startsWith("https://") ? url : "";
}

function bookingSummaryRows({ bookingId, booking, business, includeCustomer, includeNotes, cancellation }) {
  const rows = [];
  const businessName = businessNameFromData(booking, business);
  const serviceName = safeTrim(booking.serviceName || booking.activityName || "Booking");
  const date = formatDate(booking.startDate);
  const start = formatTime(booking.startDate);
  const end = formatTime(booking.endDate);
  const duration = Number(booking.serviceDurationMinutes);
  const price = formatPenceAsGbp(booking.price);
  const method = paymentMethodLabel(booking);
  const reference = bookingReference(bookingId);
  const location = safeTrim(booking.customerAddress);
  const notes = safeTrim(booking.customerNotes);

  if (includeCustomer) rows.push(["Customer", safeTrim(booking.customerName) || "A customer"]);
  rows.push(["Business", businessName]);
  rows.push(["Service", serviceName]);
  if (date) rows.push(["Date", date]);
  if (start) rows.push(["Time", end ? `${start} - ${end}` : start]);
  if (Number.isFinite(duration) && duration > 0) rows.push(["Duration", `${duration} minutes`]);
  if (price) rows.push([cancellation ? "Amount" : "Total", price]);
  if (method) rows.push(["Payment", method]);
  if (location) rows.push(["Service address", location]);
  if (includeNotes && notes) rows.push(["Notes", notes]);
  if (reference) rows.push(["Reference", reference]);
  if (cancellation?.refundLabel) rows.push(["Refund", cancellation.refundLabel]);
  return rows;
}

function refundLabel(booking) {
  const status = safeTrim(booking.refundStatus).toLowerCase();
  if (["refunded", "processed"].includes(status)) return "Refund issued";
  if (status === "not_refunded") return "No refund due";
  if (status === "not_required" || status === "not_applicable") return "No refund required";
  return "";
}

function buildEmail({ heading, intro, rows, footer, logoUrl = "" }) {
  const textRows = rows.map(([label, value]) => `${label}: ${value}`).join("\n");
  const text = `${heading}\n\n${intro}\n\n${textRows}\n\n${footer}`.trim();
  const safeLogoUrl = safeHttpsUrl(logoUrl);
  const brandHeader = safeLogoUrl
    ? `<img src="${htmlEscape(safeLogoUrl)}" width="144" alt="LocalLink" style="display:block;width:144px;max-width:60%;height:auto;border:0;">`
    : '<div style="font-size:14px;font-weight:700;color:#7b5f42;">LocalLink</div>';
  const htmlRows = rows.map(([label, value]) => `
    <tr>
      <td style="padding:8px 0;color:#6b625b;font-size:14px;">${htmlEscape(label)}</td>
      <td style="padding:8px 0;color:#26221f;font-size:14px;font-weight:600;text-align:right;">${htmlEscape(value)}</td>
    </tr>`).join("");

  const html = `<!doctype html>
<html>
  <body style="margin:0;background:#f7f3ee;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;color:#26221f;">
    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f7f3ee;padding:24px 12px;">
      <tr><td align="center">
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:560px;background:#fffaf4;border:1px solid #eadfd3;border-radius:14px;overflow:hidden;">
          <tr><td style="padding:24px 24px 8px;">
            ${brandHeader}
            <h1 style="margin:12px 0 8px;font-size:26px;line-height:1.2;color:#26221f;">${htmlEscape(heading)}</h1>
            <p style="margin:0;color:#5d554e;font-size:15px;line-height:1.5;">${htmlEscape(intro)}</p>
          </td></tr>
          <tr><td style="padding:12px 24px 20px;">
            <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="border-top:1px solid #eadfd3;border-bottom:1px solid #eadfd3;">
              ${htmlRows}
            </table>
            <p style="margin:18px 0 0;color:#5d554e;font-size:14px;line-height:1.5;">${htmlEscape(footer)}</p>
          </td></tr>
        </table>
      </td></tr>
    </table>
  </body>
</html>`;

  return { html, text };
}

function confirmationEmails({ bookingId, booking, business, customerEmail, businessEmail, logoUrl = "" }) {
  const businessName = businessNameFromData(booking, business);
  const serviceName = safeTrim(booking.serviceName || booking.activityName || "your booking");
  const footer = "You can also view these booking details in LocalLink.";
  const emails = [];

  if (safeTrim(customerEmail)) {
    const content = buildEmail({
      heading: "Booking confirmed",
      intro: `Your booking with ${businessName} is confirmed.`,
      rows: bookingSummaryRows({ bookingId, booking, business, includeCustomer: false, includeNotes: false }),
      footer,
      logoUrl,
    });
    emails.push({
      deliveryId: "booking_confirmed_customer",
      to: safeTrim(customerEmail),
      subject: `Booking confirmed: ${serviceName}`,
      ...content,
    });
  }

  if (safeTrim(businessEmail)) {
    const content = buildEmail({
      heading: "New LocalLink booking",
      intro: `${safeTrim(booking.customerName) || "A customer"} has a confirmed booking.`,
      rows: bookingSummaryRows({ bookingId, booking, business, includeCustomer: true, includeNotes: true }),
      footer: "Open LocalLink to manage or view this booking.",
      logoUrl,
    });
    emails.push({
      deliveryId: "booking_confirmed_business",
      to: safeTrim(businessEmail),
      subject: `New LocalLink booking: ${serviceName}`,
      ...content,
    });
  }

  return emails;
}

function cancellationEmails({ bookingId, booking, business, customerEmail, businessEmail, logoUrl = "" }) {
  const serviceName = safeTrim(booking.serviceName || booking.activityName || "your booking");
  const cancelledBy = safeTrim(booking.cancelledBy).toLowerCase();
  const byBusiness = cancelledBy === "business";
  const cancellation = { refundLabel: refundLabel(booking) };
  const emails = [];

  if (safeTrim(customerEmail)) {
    const content = buildEmail({
      heading: "Booking cancelled",
      intro: byBusiness
        ? "The business has cancelled this booking."
        : "Your booking has been cancelled.",
      rows: bookingSummaryRows({ bookingId, booking, business, includeCustomer: false, includeNotes: false, cancellation }),
      footer: "You can view the latest booking details in LocalLink.",
      logoUrl,
    });
    emails.push({
      deliveryId: "booking_cancelled_customer",
      to: safeTrim(customerEmail),
      subject: `Booking cancelled: ${serviceName}`,
      ...content,
    });
  }

  if (safeTrim(businessEmail)) {
    const content = buildEmail({
      heading: "Booking cancelled",
      intro: byBusiness
        ? "This booking has been cancelled by the business."
        : `${safeTrim(booking.customerName) || "A customer"} has cancelled their booking.`,
      rows: bookingSummaryRows({ bookingId, booking, business, includeCustomer: true, includeNotes: false, cancellation }),
      footer: "Open LocalLink to manage or view this booking.",
      logoUrl,
    });
    emails.push({
      deliveryId: "booking_cancelled_business",
      to: safeTrim(businessEmail),
      subject: `Booking cancelled: ${serviceName}`,
      ...content,
    });
  }

  return emails;
}

function createFirestoreEmailDeliveryStore({ db, admin }) {
  return {
    async claim({ bookingId, deliveryId, to }) {
      const ref = db
        .collection("bookings")
        .doc(bookingId)
        .collection("emailDeliveries")
        .doc(deliveryId);
      const attemptId = `${Date.now()}_${Math.random().toString(16).slice(2)}`;
      let claimed = false;

      await db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        const data = snap.exists ? snap.data() || {} : {};
        const status = safeTrim(data.status);
        const leaseExpiresAt = timestampToMillis(data.leaseExpiresAt) || 0;
        if (status === "sent") return;
        if (status === "sending" && leaseExpiresAt > Date.now()) return;

        const leaseExpiresAtValue = admin.firestore.Timestamp?.fromMillis
          ? admin.firestore.Timestamp.fromMillis(Date.now() + 10 * 60 * 1000)
          : new Date(Date.now() + 10 * 60 * 1000);

        const payload = {
          status: "sending",
          to,
          attemptId,
          leaseExpiresAt: leaseExpiresAtValue,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        };
        if (snap.exists) {
          tx.set(ref, {
            ...payload,
            attempts: admin.firestore.FieldValue.increment(1),
          }, { merge: true });
        }
        else tx.create(ref, {
          ...payload,
          attempts: 1,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        claimed = true;
      });

      return { claimed, attemptId, ref };
    },

    async markSent(claim) {
      await claim.ref.set({
        status: "sent",
        leaseExpiresAt: admin.firestore.FieldValue.delete(),
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    },

    async markFailed(claim, error) {
      await claim.ref.set({
        status: "failed",
        leaseExpiresAt: admin.firestore.FieldValue.delete(),
        errorMessage: safeTrim(error?.message).slice(0, 300),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    },
  };
}

function createMemoryEmailDeliveryStore() {
  const deliveries = new Map();
  return {
    deliveries,
    async claim({ deliveryId }) {
      const existing = deliveries.get(deliveryId);
      if (existing && ["sent", "sending"].includes(existing.status)) {
        return { claimed: false, deliveryId };
      }
      deliveries.set(deliveryId, { status: "sending", attempts: (existing?.attempts || 0) + 1 });
      return { claimed: true, deliveryId };
    },
    async markSent(claim) {
      deliveries.set(claim.deliveryId, {
        ...(deliveries.get(claim.deliveryId) || {}),
        status: "sent",
      });
    },
    async markFailed(claim, error) {
      deliveries.set(claim.deliveryId, {
        ...(deliveries.get(claim.deliveryId) || {}),
        status: "failed",
        errorMessage: safeTrim(error?.message),
      });
    },
  };
}

async function sendResendEmail({ apiKey, email, fetchImpl = fetch }) {
  const key = safeTrim(apiKey);
  if (!key) throw new Error("RESEND_API_KEY is not configured.");

  const response = await fetchImpl(RESEND_ENDPOINT, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${key}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: BOOKING_EMAIL_FROM,
      to: [email.to],
      subject: email.subject,
      html: email.html,
      text: email.text,
    }),
  });

  if (!response.ok) {
    throw new Error(`Resend returned ${response.status}`);
  }
}

async function sendTransactionalBookingEmails({
  bookingId,
  booking,
  business = {},
  customerEmail = "",
  businessEmail = "",
  eventType,
  apiKey,
  store,
  fetchImpl = fetch,
  logger = console,
}) {
  if (safeTrim(booking?.status) !== "confirmed" && eventType === "confirmation") {
    return { sent: 0, skipped: 0, failed: 0, reason: "not_confirmed" };
  }

  const emails = eventType === "cancellation"
    ? cancellationEmails({ bookingId, booking, business, customerEmail, businessEmail, logoUrl: process.env.BOOKING_EMAIL_LOGO_URL })
    : confirmationEmails({ bookingId, booking, business, customerEmail, businessEmail, logoUrl: process.env.BOOKING_EMAIL_LOGO_URL });

  let sent = 0;
  let skipped = 0;
  let failed = 0;

  for (const email of emails) {
    const claim = await store.claim({
      bookingId,
      deliveryId: email.deliveryId,
      to: email.to,
    });

    if (!claim.claimed) {
      skipped += 1;
      continue;
    }

    try {
      await sendResendEmail({ apiKey, email, fetchImpl });
      await store.markSent(claim);
      sent += 1;
    } catch (error) {
      await store.markFailed(claim, error);
      failed += 1;
      logger.error?.("Booking email delivery failed", {
        bookingId,
        deliveryId: email.deliveryId,
        message: safeTrim(error?.message),
      });
    }
  }

  return {
    sent,
    skipped,
    failed,
    missingCustomerEmail: !safeTrim(customerEmail),
    missingBusinessEmail: !safeTrim(businessEmail),
  };
}

async function accountEmailForUid(admin, uid) {
  const userId = safeTrim(uid);
  if (!userId) return "";
  try {
    const user = await admin.auth().getUser(userId);
    return safeTrim(user.email);
  } catch {
    return "";
  }
}

async function sendBookingConfirmationEmailsSafe({
  db,
  admin,
  logger = console,
  bookingId,
  booking,
  business,
}) {
  try {
    const customerEmail = await accountEmailForUid(admin, booking.customerId);
    const businessEmail = businessEmailFromData(business);
    const result = await sendTransactionalBookingEmails({
      bookingId,
      booking,
      business,
      customerEmail,
      businessEmail,
      eventType: "confirmation",
      apiKey: process.env.RESEND_API_KEY,
      store: createFirestoreEmailDeliveryStore({ db, admin }),
      logger,
    });
    logger.info?.("Booking confirmation email workflow completed", {
      bookingId,
      ...result,
    });
    return result;
  } catch (error) {
    logger.error?.("Booking confirmation email workflow failed safely", {
      bookingId,
      message: safeTrim(error?.message),
    });
    return { sent: 0, skipped: 0, failed: 1 };
  }
}

async function sendBookingCancellationEmailsSafe({
  db,
  admin,
  logger = console,
  bookingId,
  booking,
  business,
}) {
  try {
    const customerEmail = await accountEmailForUid(admin, booking.customerId);
    const businessEmail = businessEmailFromData(business);
    const result = await sendTransactionalBookingEmails({
      bookingId,
      booking,
      business,
      customerEmail,
      businessEmail,
      eventType: "cancellation",
      apiKey: process.env.RESEND_API_KEY,
      store: createFirestoreEmailDeliveryStore({ db, admin }),
      logger,
    });
    logger.info?.("Booking cancellation email workflow completed", {
      bookingId,
      ...result,
    });
    return result;
  } catch (error) {
    logger.error?.("Booking cancellation email workflow failed safely", {
      bookingId,
      message: safeTrim(error?.message),
    });
    return { sent: 0, skipped: 0, failed: 1 };
  }
}

module.exports = {
  BOOKING_EMAIL_FROM,
  businessEmailFromData,
  confirmationEmails,
  cancellationEmails,
  createFirestoreEmailDeliveryStore,
  createMemoryEmailDeliveryStore,
  sendTransactionalBookingEmails,
  sendBookingConfirmationEmailsSafe,
  sendBookingCancellationEmailsSafe,
  formatPenceAsGbp,
  paymentMethodLabel,
};
