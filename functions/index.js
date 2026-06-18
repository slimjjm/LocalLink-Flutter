/**
 * LocalLink Cloud Functions (Firebase Functions v2)
 * PRODUCTION BILLING ENGINE – Subscriptions + Booking Fulfilment (Stripe PI Webhook)
 */

const admin = require("firebase-admin");
admin.initializeApp();
const db = admin.firestore();

const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");

const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const logger = require("firebase-functions/logger");

const STRIPE_API_VERSION = "2023-10-16";

const notifications =
  require("./notifications");

let stripeClient = null;

function getStripe() {
  const key = process.env.STRIPE_SECRET_KEY;
    console.log("🔥 STRIPE KEY:", key.substring(0, 8));
  if (!key) throw new HttpsError("failed-precondition", "Stripe secret not configured.");
  if (!stripeClient) stripeClient = require("stripe")(key, { apiVersion: STRIPE_API_VERSION });
  return stripeClient;
}

function assert(cond, code, msg) {
  if (!cond) throw new HttpsError(code, msg);
}

function safeTrim(s) {
  return String(s ?? "").trim();
}

//
// =================================================
// ENTITLEMENTS HELPERS
// =================================================
//
function timestampToMillis(value) {
  if (!value) return null;

  if (typeof value.toMillis === "function") {
    return value.toMillis();
  }

  if (value instanceof Date) {
    return value.getTime();
  }

  if (typeof value === "number") {
    return value;
  }

  return null;
}
exports.notifyNewMessage =
  notifications.notifyNewMessage;

exports.notifyBookingCancelled =
  notifications.notifyBookingCancelled;

exports.notifyNewFollower =
  notifications.notifyNewFollower;

function hoursUntil(timestampValue) {
  const millis = timestampToMillis(timestampValue);
  if (!millis) return null;
  return (millis - Date.now()) / (1000 * 60 * 60);
}

function bookingMessageRef(bookingId) {
  return db.collection("bookings").doc(bookingId).collection("messages");
}

async function isBusinessOwner(uid, businessId) {
  const snap = await db.collection("businesses").doc(businessId).get();
  return snap.exists && snap.data()?.ownerId === uid;
}

async function addSystemBookingMessage(bookingId, text) {
  await bookingMessageRef(bookingId).add({
    senderId: "system",
    senderRole: "system",
    text,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

async function releaseBookedSlot({ businessId, staffId, slotId }) {
  if (!businessId || !staffId || !slotId) return;

  const slotRef = db
    .collection("businesses")
    .doc(businessId)
    .collection("staff")
    .doc(staffId)
    .collection("availableSlots")
    .doc(slotId);

  const snap = await slotRef.get();
  if (!snap.exists) return;

  await slotRef.update({
    isBooked: false,
    lockedByBookingId: admin.firestore.FieldValue.delete(),
    lockExpiresAt: admin.firestore.FieldValue.delete(),
  });
}

function buildCancellationOutcome({ cancelledBy, shouldRefund, hoursBeforeStart }) {
  if (cancelledBy === "business") {
    return {
      bookingStatus: "cancelled_by_business",
      refundStatus: shouldRefund ? "processed" : "not_applicable",
      systemMessage: shouldRefund
        ? "This booking was cancelled by the business. A refund has been issued."
        : "This booking was cancelled by the business.",
    };
  }

  if (shouldRefund) {
    return {
      bookingStatus: "cancelled_by_customer",
      refundStatus: "processed",
      systemMessage:
        "This booking was cancelled by the customer more than 24 hours before the appointment. A refund has been issued.",
    };
  }

  return {
    bookingStatus: "cancelled_by_customer",
    refundStatus: "not_applicable",
    systemMessage:
      hoursBeforeStart !== null && hoursBeforeStart < 24
        ? "This booking was cancelled by the customer less than 24 hours before the appointment. No refund is due under the cancellation policy."
        : "This booking was cancelled by the customer.",
  };
}
function entitlementsRef(businessId) {
  return db.collection("businesses").doc(businessId).collection("entitlements").doc("default");
}

async function ensureEntitlementsDoc(businessId) {
  const ref = entitlementsRef(businessId);
  const snap = await ref.get();

  if (!snap.exists) {
    await ref.set(
      {
        freeStaffSlots: 999,
        extraStaffSlots: 0,
        stripeStatus: "free",
        restrictionMode: false,
        pastDueSince: null,
        currentPeriodEnd: null,
        stripeCustomerId: null,
        stripeSubscriptionId: null,
      },
      { merge: true }
    );
  }
}
function stripeEventRef(eventId) {
  return db.collection("stripeWebhookEvents").doc(eventId);
}

async function getAllowedSeats(businessId) {
  const snap = await entitlementsRef(businessId).get();
  const data = snap.exists ? snap.data() : {};
  const free = typeof data.freeStaffSlots === "number" ? data.freeStaffSlots : 999;
  const extra = typeof data.extraStaffSlots === "number" ? data.extraStaffSlots : 0;
  return free + extra;
}

async function syncExtraStaffSlots(businessId, quantity) {
  await entitlementsRef(businessId).set(
    { extraStaffSlots: Math.max(0, Number(quantity || 0)) },
    { merge: true }
  );
}

async function syncSubscriptionStatus(businessId, status) {
  await entitlementsRef(businessId).set({ stripeStatus: status }, { merge: true });
}

async function syncCurrentPeriodEnd(businessId, unixSeconds) {
  const ts = unixSeconds
    ? admin.firestore.Timestamp.fromMillis(Number(unixSeconds) * 1000)
    : null;
  await entitlementsRef(businessId).set({ currentPeriodEnd: ts }, { merge: true });
}

async function setPastDueTimestamp(businessId) {
  await entitlementsRef(businessId).set(
    { pastDueSince: admin.firestore.FieldValue.serverTimestamp() },
    { merge: true }
  );
}

async function clearPastDueTimestamp(businessId) {
  await entitlementsRef(businessId).set({ pastDueSince: null }, { merge: true });
}

async function enableRestrictionMode(businessId) {
  await entitlementsRef(businessId).set({ restrictionMode: true }, { merge: true });
}

async function disableRestrictionMode(businessId) {
  await entitlementsRef(businessId).set({ restrictionMode: false }, { merge: true });
}




//
// =================================================
// 7-DAY GRACE → RESTRICTION MODE EVALUATION
// =================================================
//

async function evaluateRestrictionState(businessId) {

  const entSnap = await entitlementsRef(businessId).get();
  if (!entSnap.exists) return;

  const ent = entSnap.data();

  // 🔥 HANDLE APPLE FIRST (EXIT EARLY)
  const billingSource = ent.billingSource;

  if (billingSource === "apple") {
    await disableRestrictionMode(businessId);
    return;
  }

  // 🔽 STRIPE LOGIC BELOW ONLY

  const status = ent.stripeStatus;
  const pastDueSince = ent.pastDueSince;

  if (status === "active" || status === "free") {
    await disableRestrictionMode(businessId);
    return;
  }

  if (status === "past_due") {
    if (!pastDueSince) {
      await disableRestrictionMode(businessId);
      return;
    }

    const graceMs = 7 * 24 * 60 * 60 * 1000;
    const now = Date.now();
    const pastDueMs = pastDueSince.toMillis();

    if (now - pastDueMs > graceMs) {
      await enableRestrictionMode(businessId);
    } else {
      await disableRestrictionMode(businessId);
    }

    return;
  }

  if (status && status !== "past_due" && status !== "active" && status !== "free") {
    await enableRestrictionMode(businessId);
  }
}

//
// =================================================
// SEAT ENFORCEMENT
// =================================================
//

async function applySeatEnforcement(businessId) {
  const businessRef = db.collection("businesses").doc(businessId);
  const allowed = await getAllowedSeats(businessId);

  const staffSnap = await businessRef.collection("staff").orderBy("seatRank").get();
  if (staffSnap.empty) return;

  const batch = db.batch();

  staffSnap.docs.forEach((doc, idx) => {
    const shouldBeActive = idx < allowed;
    const currentActive = doc.data().isActive !== false;
    if (currentActive !== shouldBeActive) batch.update(doc.ref, { isActive: shouldBeActive });
  });

  await batch.commit();

  logger.info("Seat enforcement applied", { businessId, allowed, staffCount: staffSnap.size });
}
exports.previewSeatReductionImpact = onCall(
  { region: "us-central1" },
  async (request) => {
    assert(request.auth, "unauthenticated", "Login required.");

    const uid = request.auth.uid;
    const businessId = request.data?.businessId;

    assert(businessId, "invalid-argument", "Missing businessId.");

    const businessRef = db.collection("businesses").doc(businessId);
    const businessSnap = await businessRef.get();

    assert(businessSnap.exists, "not-found", "Business not found.");
    assert(businessSnap.data().ownerId === uid, "permission-denied", "Not owner.");

    const allowed = await getAllowedSeats(businessId);
    const newAllowed = Math.max(0, allowed - 1);

    const staffSnap = await businessRef
      .collection("staff")
      .orderBy("seatRank")
      .get();

    const impacted = staffSnap.docs
      .map((doc, idx) => ({
        id: doc.id,
        name: doc.data().name || "Unnamed staff",
        seatRank: doc.data().seatRank ?? 9999,
        wouldBeActive: idx < newAllowed
      }))
      .filter((staff) => !staff.wouldBeActive);

    return {
      currentAllowed: allowed,
      newAllowed,
      impacted
    };
  }
);


exports.cancelBooking = onCall(
  {
    region: "us-central1",
    secrets: ["STRIPE_SECRET_KEY"], // 🔥 THIS IS THE FIX
  },
  async (request) => {
  console.log("🚀 CANCEL FUNCTION HIT");

  try {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "You must be signed in.");
    }

    const bookingId = request.data?.bookingId;
    if (!bookingId) {
      throw new HttpsError("invalid-argument", "Missing bookingId.");
    }

    const bookingRef = db.collection("bookings").doc(bookingId);
    const bookingSnap = await bookingRef.get();

    if (!bookingSnap.exists) {
      throw new HttpsError("not-found", "Booking not found.");
    }

    const booking = bookingSnap.data() || {};

    // ✅ SAFE FIELD ACCESS (NO safeTrim)
    const status = booking.status || "";
    const businessId = booking.businessId;
    const customerId = booking.customerId;
    const staffId = booking.staffId;
    const slotId = booking.slotId;
    const paymentIntentId = booking.paymentIntentId;

    if (!businessId) {
      throw new HttpsError("failed-precondition", "Missing businessId.");
    }

    if (!booking.startDate) {
      throw new HttpsError("failed-precondition", "Missing booking date.");
    }

    const startDate = booking.startDate.toDate
      ? booking.startDate.toDate()
      : new Date(booking.startDate);

    const now = new Date();

    console.log("📦 CANCEL REQUEST:", {
      bookingId,
      status,
      businessId,
      customerId,
      staffId,
      slotId
    });

    // 🚫 Prevent past cancellation
    if (startDate < now) {
      throw new HttpsError("failed-precondition", "Cannot cancel past bookings.");
    }

    // 🚫 Prevent double cancel
    if (status.startsWith("cancelled")) {
      return { ok: true, alreadyCancelled: true };
    }

    // 🔐 Permissions
    const isCustomer = uid === customerId;
    const isBusiness = await isBusinessOwner(uid, businessId);

    if (!isCustomer && !isBusiness) {
      throw new HttpsError("permission-denied", "Not allowed.");
    }

    const cancelledBy = isBusiness ? "business" : "customer";

    // ⏱ Time logic
    const hoursBefore = (startDate - now) / (1000 * 60 * 60);

    let shouldRefund = false;

    if (cancelledBy === "business") {
      shouldRefund = true;
    } else if (cancelledBy === "customer") {
      shouldRefund = hoursBefore >= 24;
    }

    // 💸 REFUND (SAFE — NO DOUBLE REFUNDS)
    let refundId = null;

    if (shouldRefund && paymentIntentId) {
      const stripe = getStripe();

      const existing = await stripe.refunds.list({
        payment_intent: paymentIntentId,
        limit: 1
      });

      if (existing.data.length > 0) {
        refundId = existing.data[0].id;
        console.log("⚠️ Refund already exists:", refundId);
      } else {
        const refund = await stripe.refunds.create({
          payment_intent: paymentIntentId
        });
        refundId = refund.id;
        console.log("💸 Refund created:", refundId);
      }
    }

    const bookingStatus =
      cancelledBy === "business"
        ? "cancelled_by_business"
        : "cancelled_by_customer";

    const refundStatus = shouldRefund ? "refunded" : "not_refunded";

    // 🔄 ATOMIC UPDATE
    const batch = db.batch();

    batch.update(bookingRef, {
      status: bookingStatus,
      cancelledBy,
      cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
      refundStatus,
      refundId: refundId || null,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    });

    // 🔓 Release slot
    if (slotId && staffId) {
      const slotRef = db
        .collection("businesses")
        .doc(businessId)
        .collection("staff")
        .doc(staffId)
        .collection("availableSlots")
        .doc(slotId);

      batch.update(slotRef, {
        isBooked: false,
        lockedByBookingId: admin.firestore.FieldValue.delete(),
        lockExpiresAt: admin.firestore.FieldValue.delete()
      });
    }

    await batch.commit();

    console.log("✅ BOOKING CANCELLED:", bookingId);

    // 🔥 SYSTEM MESSAGE
    await addSystemBookingMessage(
      bookingId,
      cancelledBy === "business"
        ? "Booking cancelled by business"
        : "Booking cancelled by customer"
    );

    // 🔔 PUSH + UNREAD
  if (isBusiness) {

  await sendPushToUser(customerId, {
    title: "Booking cancelled",
    body: shouldRefund
      ? "Your booking was cancelled by the business. A refund has been issued."
      : "Your booking was cancelled by the business.",
    data: { bookingId, type: "booking_cancelled" }
  });

  await bookingRef.update({
    unreadForCustomer: admin.firestore.FieldValue.increment(1),
  });

} else {

  const businessSnap = await db.collection("businesses").doc(businessId).get();
  const ownerId = businessSnap.data()?.ownerId;

  if (ownerId) {
    await sendPushToUser(ownerId, {
      title: "Booking cancelled",
      body: shouldRefund
        ? "A customer cancelled their booking (refund issued)."
        : "A customer cancelled their booking (no refund).",
      data: { bookingId, type: "booking_cancelled" }
    });
  }

  await bookingRef.update({
    unreadForBusiness: admin.firestore.FieldValue.increment(1),
  });
}

    return {
      ok: true,
      bookingId,
      bookingStatus,
      cancelledBy,
      refundIssued: !!refundId,
      refundStatus,
      hoursBefore,
    };

  } catch (error) {
    console.error("❌ CANCEL ERROR:", error);
    throw new HttpsError("internal", error.message);
  }
});
// =================================================
// STRIPE HELPERS
// =================================================
//

async function resolveBusinessIdFromCustomer(stripe, customerId) {
  console.log("🔍 Resolving business for customer:", customerId);

  const businessesSnap = await db.collection("businesses").get();

  for (const doc of businessesSnap.docs) {
    const entSnap = await doc.ref
      .collection("entitlements")
      .doc("default")
      .get();

    const stripeCustomerId = entSnap.data()?.stripeCustomerId;

    if (stripeCustomerId === customerId) {
      console.log("✅ Resolved businessId:", doc.id);
      return doc.id;
    }
  }

  console.log("❌ No business found for customer:", customerId);
  return null;
}

async function getClientSecretFromSubscription(stripe, subscription) {
  const latestInvoice = subscription.latest_invoice;
  if (!latestInvoice) return null;

  if (typeof latestInvoice === "object") {
    return latestInvoice.payment_intent?.client_secret ?? null;
  }

  if (typeof latestInvoice === "string") {
    const invoice = await stripe.invoices.retrieve(latestInvoice, { expand: ["payment_intent"] });
    return invoice.payment_intent?.client_secret ?? null;
  }

  return null;
}

//
// =================================================
// BOOKING HELPERS
// =================================================

function slotRef(businessId, staffId, slotId) {
  return db
    .collection("businesses")
    .doc(businessId)
    .collection("staff")
    .doc(staffId)
    .collection("availableSlots")
    .doc(slotId);
}

async function staffIsActiveServer(businessId, staffId) {

  const s = await db
    .collection("businesses")
    .doc(businessId)
    .collection("staff")
    .doc(staffId)
    .get()

  if (!s.exists) return false
  return s.data().isActive !== false
}

async function sendSystemMessage(bookingId, text) {

  const messageRef = db
    .collection("bookings")
    .doc(bookingId)
    .collection("messages")
    .doc()

  await messageRef.set({
    senderId: "system",
    senderRole: "system",
    text: text,
    createdAt: admin.firestore.FieldValue.serverTimestamp()
  })
}
exports.regenerateAvailability = onCall(
  { region: "us-central1" },
  async (request) => {

    try {

      assert(request.auth,
        "unauthenticated",
        "Login required.");

      const businessId =
        safeTrim(request.data?.businessId);

      const staffId =
        safeTrim(request.data?.staffId);

      assert(
        businessId,
        "invalid-argument",
        "Missing businessId."
      );

      assert(
        staffId,
        "invalid-argument",
        "Missing staffId."
      );

      const businessRef = db
        .collection("businesses")
        .doc(businessId);

      const staffRef = businessRef
        .collection("staff")
        .doc(staffId);
const staffSnap = await staffRef.get();

assert(
  staffSnap.exists,
  "not-found",
  "Staff not found."
);

const staffData = staffSnap.data() || {};
      // =====================================
      // LOAD WEEKLY AVAILABILITY
      // =====================================

      const weeklySnap =
        await staffRef
          .collection("weeklyAvailability")
          .get();

      // =====================================
      // DELETE OLD SLOTS
      // =====================================

      const oldSlots =
        await staffRef
          .collection("availableSlots")
          .get();

      const deleteBatch = db.batch();

      oldSlots.docs.forEach((doc) => {
        deleteBatch.delete(doc.ref);
      });

      await deleteBatch.commit();

      // =====================================
      // GENERATE NEXT 30 DAYS
      // =====================================

      const now = new Date();

      for (let i = 0; i < 30; i++) {

        const date =
          new Date(now);

        date.setDate(
          now.getDate() + i
        );

        const weekday =
          date.toLocaleDateString(
            "en-GB",
            { weekday: "long" }
          ).toLowerCase();

        const dayDoc =
          weeklySnap.docs.find(
            d => d.id === weekday
          );

        if (!dayDoc) continue;

        const data = dayDoc.data();

        if (data.closed === true) {
          continue;
        }

        const open =
          data.open || "09:00";

        const close =
          data.close || "17:00";

        const [openHour, openMinute] =
          open.split(":").map(Number);

        const [closeHour, closeMinute] =
          close.split(":").map(Number);

        let current =
          new Date(date);

        current.setHours(
          openHour,
          openMinute,
          0,
          0
        );

      const end =
  new Date(date);

end.setHours(
  closeHour,
  closeMinute,
  0,
  0
);

// =====================================
// LOAD DAY BLOCKS
// =====================================

const dayStart =
  new Date(date);

dayStart.setHours(
  0,
  0,
  0,
  0
);

const dayEnd =
  new Date(date);

dayEnd.setHours(
  23,
  59,
  59,
  999
);

const blocksSnap =
  await staffRef
    .collection("dayBlocks")
    .where(
      "startDate",
      "<=",
      admin.firestore.Timestamp.fromDate(dayEnd)
    )
    .where(
      "endDate",
      ">=",
      admin.firestore.Timestamp.fromDate(dayStart)
    )
    .get();

// =====================================
// LOAD EXISTING BOOKINGS
// =====================================

const bookingsSnap =
  await db
    .collection("bookings")
    .where(
      "businessId",
      "==",
      businessId
    )
    .where(
      "staffId",
      "==",
      staffId
    )
    .where(
      "status",
      "in",
      [
        "confirmed",
        "pending_payment",
      ]
    )
    .where(
      "startDate",
      "<=",
      admin.firestore.Timestamp.fromDate(dayEnd)
    )
    .where(
      "endDate",
      ">=",
      admin.firestore.Timestamp.fromDate(dayStart)
    )
    .get();

// =====================================
// SLOT LOOP
// =====================================

while (current < end) {

  const slotStart =
    new Date(current);

  const slotEnd =
    new Date(current);

  slotEnd.setMinutes(
    slotEnd.getMinutes() + 30
  );

  // =====================================
  // SKIP BLOCKED TIME
  // =====================================

  const overlapsBlock =
    blocksSnap.docs.some((doc) => {

      const block =
        doc.data();

      const blockStart =
        block.startDate.toDate();

      const blockEnd =
        block.endDate.toDate();

      return (
        slotStart < blockEnd &&
        slotEnd > blockStart
      );
    });

  if (overlapsBlock) {

    current.setMinutes(
      current.getMinutes() + 30
    );

    continue;
  }

      // =====================================
// SKIP BOOKED TIME
// =====================================

const overlapsBooking =
  bookingsSnap.docs.some((doc) => {

    const booking =
      doc.data();

    const bookingStart =
      booking.startDate.toDate();

    const bookingEnd =
      booking.endDate.toDate();

    return (
      slotStart < bookingEnd &&
      slotEnd > bookingStart
    );
  });

if (overlapsBooking) {

  current.setMinutes(
    current.getMinutes() + 30
  );

  continue;
}

const slotId =
  slotStart.toISOString();

          await staffRef
            .collection("availableSlots")
            .doc(slotId)
            .set({

  businessId,

  staffId,

  staffName:
    staffData.name || "Staff",

  startTime:
                admin.firestore.Timestamp
                  .fromDate(slotStart),

              endTime:
                admin.firestore.Timestamp
                  .fromDate(slotEnd),

              isBooked: false,
            });

          current.setMinutes(
            current.getMinutes() + 30
          );
        }
      }

      return {
        success: true
      };

    } catch (error) {

      console.error(
        "❌ regenerateAvailability failed:",
        error
      );

      throw new HttpsError(
        "internal",
        error.message ||
          "Failed to regenerate availability."
      );
    }
  }
);


async function getRequiredSlots({
  businessId,
  staffId,
  slotStart,
  slotsRequired,
}) {

  const slots = [];

  for (let i = 0; i < slotsRequired; i++) {

    const expectedStart =
      new Date(
        slotStart.getTime() + i * 30 * 60000
      );

    const slotId =
      expectedStart.toISOString();

    const slotRef = db
      .collection("businesses")
      .doc(businessId)
      .collection("staff")
      .doc(staffId)
      .collection("availableSlots")
      .doc(slotId);

    const snap = await slotRef.get();

    if (!snap.exists) {
      return null;
    }

    const data = snap.data();

    if (data.isBooked === true) {
      return null;
    }

    slots.push({
      ref: slotRef,
      data,
      slotId,
    });
  }

  return slots;
}
exports.createCashBooking = onCall(
  { region: "us-central1" },
  async (request) => {
    try {
      assert(request.auth, "unauthenticated", "Login required.");

      const provider = request.auth.token?.firebase?.sign_in_provider;
      if (provider === "anonymous") {
        throw new HttpsError(
          "failed-precondition",
          "Please log in to make a booking"
        );
      }

      const customerId = request.auth.uid;

      const businessId = safeTrim(request.data?.businessId);
      const staffId = safeTrim(request.data?.staffId);
      const serviceId = safeTrim(request.data?.serviceId);
      const slotId = safeTrim(request.data?.slotId);
const slotPath = safeTrim(request.data?.slotPath);
const customerName = safeTrim(request.data?.customerName);
      const customerAddress = safeTrim(request.data?.customerAddress);

      const addOnIds = Array.isArray(request.data?.addOnIds)
        ? request.data.addOnIds.map(id => safeTrim(id)).filter(Boolean)
        : [];

      assert(
        businessId && staffId && serviceId && slotId,
        "invalid-argument",
        "Missing booking data."
      );

      const businessRef = db.collection("businesses").doc(businessId);
      const businessSnap = await businessRef.get();

      assert(businessSnap.exists, "not-found", "Business not found.");

      const business = businessSnap.data() || {};
      const paymentMethods = Array.isArray(business.paymentMethods)
        ? business.paymentMethods
        : ["cash"];

      assert(
        paymentMethods.includes("cash"),
        "failed-precondition",
        "This business does not accept cash bookings."
      );

      const slotDocRef = businessRef
        .collection("staff")
        .doc(staffId)
        .collection("availableSlots")
        .doc(slotId);

      const slotSnap = await slotDocRef.get();

      assert(slotSnap.exists, "failed-precondition", "Slot does not exist.");

      const slot = slotSnap.data();

      const isBooked =
        typeof slot.isBooked === "boolean"
          ? slot.isBooked
          : slot.isBooked === 1;

      assert(!isBooked, "failed-precondition", "Slot already booked.");

      assert(
        slot.startTime && slot.startTime.toDate,
        "internal",
        "Invalid slot data."
      );

      const slotStart = slot.startTime.toDate();

      assert(slotStart > new Date(), "failed-precondition", "Slot is in the past.");

      const minimumNoticeHours = 2;
      const hoursBefore = (slotStart - new Date()) / (1000 * 60 * 60);

      assert(
        hoursBefore >= minimumNoticeHours,
        "failed-precondition",
        "This slot is too soon to book."
      );

      const active = await staffIsActiveServer(businessId, staffId);
      assert(active, "failed-precondition", "Staff inactive.");


      const staffSnap = await businessRef.collection("staff").doc(staffId).get();
      assert(staffSnap.exists, "not-found", "Staff not found.");

      const staff = staffSnap.data() || {};
      const staffName = safeTrim(staff.name) || "Staff";

      const serviceSnap = await businessRef.collection("services").doc(serviceId).get();
      assert(serviceSnap.exists, "not-found", "Service not found.");

      const service = serviceSnap.data() || {};
      const price = Number(service.price || 0);
      const serviceName = safeTrim(service.name) || "Service";
      const serviceDurationMinutes = Number(service.durationMinutes || 0);

      assert(price > 0, "failed-precondition", "Invalid service price.");

      let addOnsTotal = 0;
      const cleanedAddOns = [];

      if (addOnIds.length > 0) {
        const validAddOns = Array.isArray(service.addOns) ? service.addOns : [];

        for (const addOnId of addOnIds) {
          const match = validAddOns.find(a => safeTrim(a.id) === addOnId);
          if (!match) continue;

          const safeAddOn = {
            id: safeTrim(match.id),
            name: safeTrim(match.name),
            price: Number(match.price || 0),
            details: safeTrim(match.details || ""),
          };

          if (safeAddOn.id && safeAddOn.name && safeAddOn.price > 0) {
            addOnsTotal += safeAddOn.price;
            cleanedAddOns.push(safeAddOn);
          }
        }
      }

      const totalPrice = price + addOnsTotal;

      const bookingRef = db.collection("bookings").doc();
      const bookingId = bookingRef.id;

      await db.runTransaction(async (tx) => {
        const slotsRequired =
  Math.ceil(serviceDurationMinutes / 30);

const requiredSlots =
  await getRequiredSlots({
    businessId,
    staffId,
    slotStart,
    slotsRequired,
  });

if (!requiredSlots) {
  throw new HttpsError(
    "failed-precondition",
    "Required consecutive slots unavailable."
  );
}

  for (const requiredSlot of requiredSlots) {

    const slotSnapTx =
      await tx.get(requiredSlot.ref);

    if (!slotSnapTx.exists) {
      throw new HttpsError(
        "failed-precondition",
        "Slot missing"
      );
    }

    const slotData =
      slotSnapTx.data();

    const isBookedTx =
      typeof slotData.isBooked === "boolean"
        ? slotData.isBooked
        : slotData.isBooked === 1;

    if (isBookedTx) {
      throw new HttpsError(
        "failed-precondition",
        "Slot already booked"
      );
    }
  }

  const bookingDay =
    new Date(slotStart);

  bookingDay.setHours(
    0,
    0,
    0,
    0
  );

  tx.set(bookingRef, {

    bookingId,
    businessId,
    customerId,
    serviceId,
    serviceName,
    serviceDurationMinutes,

    staffId,
    staffName,

    customerName,
    customerAddress,

    addOns: cleanedAddOns,
    addOnsTotal,

    price: totalPrice,

    status: "confirmed",

    paymentMethod: "cash",

    paymentStatus: "pay_on_arrival",

    paymentIntentId: "",

    slotId,

    slotIds:
      requiredSlots.map(
        s => s.slotId
      ),

    slotPath,

    bookingDay:
      admin.firestore.Timestamp.fromDate(
        bookingDay
      ),

    startDate:
      admin.firestore.Timestamp.fromDate(
        slotStart
      ),

    endDate:
      admin.firestore.Timestamp.fromDate(

        new Date(
          slotStart.getTime() +
          slotsRequired * 30 * 60000
        )
      ),

    createdAt:
      admin.firestore.FieldValue.serverTimestamp(),

    confirmedAt:
      admin.firestore.FieldValue.serverTimestamp(),

    unreadForCustomer: 0,

    unreadForBusiness: 0,
  });

  for (const requiredSlot of requiredSlots) {

    tx.update(requiredSlot.ref, {

      isBooked: true,

      lockedByBookingId:
        admin.firestore.FieldValue.delete(),

      lockExpiresAt:
        admin.firestore.FieldValue.delete(),
    });
  }
});

const ownerId = business.ownerId;

if (ownerId) {

  await sendPushToUser(ownerId, {

    title: "New booking",

    body: "You have a new cash booking.",

    data: {
      bookingId,
      type: "new_booking",
    },
  });
}

await sendPushToUser(customerId, {

  title: "Booking confirmed",

  body:
    `Your booking for ${serviceName} is confirmed.`,

  data: {
    bookingId,
    type: "booking_confirmed",
  },
});

return {
  ok: true,
  bookingId,
};

     } catch (error) {

      console.error(
        "❌ createCashBooking failed:",
        error
      );

      if (error instanceof HttpsError) {
        throw error;
      }

      throw new HttpsError(
        "internal",
        error.message || "Failed to create cash booking."
      );
    }
  }
);

// =================================================
// CREATE BOOKING + PAYMENT INTENT (CONNECT VERSION)
// =================================================

exports.createBookingPaymentIntent = onCall(
  {
    region: "us-central1",
    secrets: ["STRIPE_SECRET_KEY"],
  },
  async (request) => {
    try {
      console.log("🔥 FUNCTION HIT", {
        uid: request.auth?.uid,
        provider: request.auth?.token?.firebase?.sign_in_provider,
        data: request.data,
      });

      assert(request.auth, "unauthenticated", "Login required.");

      const provider = request.auth.token?.firebase?.sign_in_provider;
      if (provider === "anonymous") {
        console.log("❌ BLOCKED: Anonymous user");
        throw new HttpsError(
          "failed-precondition",
          "Please log in to make a booking"
        );
      }

      const stripe = getStripe();
      const customerId = request.auth.uid;


      // =================================================
      // EXTRACT DATA
      // =================================================

      const businessId = safeTrim(request.data?.businessId);
      const staffId = safeTrim(request.data?.staffId);
      const serviceId = safeTrim(request.data?.serviceId);
      const slotId = safeTrim(request.data?.slotId);
const slotPath = safeTrim(request.data?.slotPath);
const customerName = safeTrim(request.data?.customerName);
      const customerAddress = safeTrim(request.data?.customerAddress);

      const addOnIds = Array.isArray(request.data?.addOnIds)
  ? request.data.addOnIds.map(id => safeTrim(id)).filter(Boolean)
  : [];

      console.log("📦 Booking Params:", {
        businessId,
        staffId,
        serviceId,
        slotId,
        customerName,
        customerAddress,
        addOnsCount: addOnIds.length,
      });

      assert(
        businessId && staffId && serviceId && slotId,
        "invalid-argument",
        "Missing booking data."
      );

      // =================================================
      // REFERENCES
      // =================================================

      const businessRef = db.collection("businesses").doc(businessId);

      const slotDocRef = businessRef
        .collection("staff")
        .doc(staffId)
        .collection("availableSlots")
        .doc(slotId);

      // =================================================
      // VALIDATE SLOT
      // =================================================

      const slotSnap = await slotDocRef.get();

      if (!slotSnap.exists) {
        console.log("❌ Slot does not exist:", slotId);
        throw new HttpsError("failed-precondition", "Slot does not exist");
      }

      const slot = slotSnap.data();

      console.log("🕒 Slot data:", slot);

      const isBooked =
        typeof slot.isBooked === "boolean"
          ? slot.isBooked
          : slot.isBooked === 1;

      if (isBooked) {
        console.log("❌ Slot already booked");
        throw new HttpsError("failed-precondition", "Slot already booked");
      }

      if (!slot.startTime || !slot.startTime.toDate) {
        console.log("❌ Invalid slot startTime:", slot.startTime);
        throw new HttpsError("internal", "Invalid slot data");
      }

      const slotStart = slot.startTime.toDate();


      if (slotStart < new Date()) {
        console.log("❌ Slot in the past:", slotStart);
        throw new HttpsError("failed-precondition", "Slot is in the past");
      }

      const minimumNoticeHours = 2;
      const hoursBefore = (slotStart - new Date()) / (1000 * 60 * 60);

      if (hoursBefore < minimumNoticeHours) {
        console.log("❌ Slot too soon to book:", {
          slotStart,
          hoursBefore,
        });

        throw new HttpsError(
          "failed-precondition",
          "This slot is too soon to book."
        );
      }

      // =================================================
      // VALIDATE BUSINESS / STRIPE
      // =================================================

      const businessSnap = await businessRef.get();
      assert(businessSnap.exists, "not-found", "Business not found.");

      const business = businessSnap.data() || {};
      const stripeAccountId = business.stripeAccountId;

      console.log("🏢 Business:", {
        businessId,
        stripeAccountId,
        stripeConnected: business.stripeConnected,
      });

      assert(stripeAccountId, "failed-precondition", "Stripe not connected.");

      const account = await stripe.accounts.retrieve(stripeAccountId);

      console.log("💳 Stripe account status:", {
        charges_enabled: account.charges_enabled,
        payouts_enabled: account.payouts_enabled,
      });

      if (!account.charges_enabled) {
        console.log("❌ Stripe charges not enabled");
        throw new HttpsError(
          "failed-precondition",
          "Business cannot accept payments yet."
        );
      }

      // =================================================
      // VALIDATE STAFF
      // =================================================

      const active = await staffIsActiveServer(businessId, staffId);
      console.log("👤 Staff active:", active);

      assert(active, "failed-precondition", "Staff inactive.");

      const staffSnap = await businessRef.collection("staff").doc(staffId).get();
      assert(staffSnap.exists, "not-found", "Staff not found.");

      const staff = staffSnap.data() || {};
      const staffName = safeTrim(staff.name) || "Staff";

      // =================================================
      // VALIDATE SERVICE
      // =================================================

      const serviceSnap = await businessRef.collection("services").doc(serviceId).get();
      assert(serviceSnap.exists, "not-found", "Service not found.");

      const service = serviceSnap.data() || {};
      const price = Number(service.price || 0);
      const serviceName = safeTrim(service.name) || "Service";
      const serviceDurationMinutes = Number(service.durationMinutes || 0);

const slotsRequired =
  Math.ceil(serviceDurationMinutes / 30);
 
const requiredSlots =
  await getRequiredSlots({
    businessId,
    staffId,
    slotStart,
    slotsRequired,
  });

if (!requiredSlots) {

  throw new HttpsError(
    "failed-precondition",
    "Required consecutive slots unavailable."
  );
}
      assert(price > 0, "failed-precondition", "Invalid service price.");

      console.log("💷 Base price (pence):", price);

      // =================================================
      // SECURE ADD-ONS (SERVER VALIDATED)
      // =================================================

   let addOnsTotal = 0;
const cleanedAddOns = [];

if (addOnIds.length > 0) {
  const validAddOns = Array.isArray(service.addOns) ? service.addOns : [];

  for (const addOnId of addOnIds) {
    const match = validAddOns.find(a => safeTrim(a.id) === addOnId);

    if (!match) continue;

    const safeAddOn = {
      id: safeTrim(match.id),
      name: safeTrim(match.name),
      price: Number(match.price || 0),
      details: safeTrim(match.details || ""),
    };

    if (safeAddOn.id && safeAddOn.name && safeAddOn.price > 0) {
      addOnsTotal += safeAddOn.price;
      cleanedAddOns.push(safeAddOn);
    }
  }
}

      const totalPrice = price + addOnsTotal;
      assert(totalPrice > 0, "failed-precondition", "Invalid total price");

      console.log("💷 TOTAL PRICE:", totalPrice);

      // =================================================
      // CREATE BOOKING ID
      // =================================================

      const bookingRef = db.collection("bookings").doc();
      const bookingId = bookingRef.id;

      console.log("🧾 Creating booking:", bookingId);

      // =================================================
      // TRANSACTION: LOCK SLOT + CREATE BOOKING
      // =================================================

      await db.runTransaction(async (tx) => {
        const slotSnapTx = await tx.get(slotDocRef);
        assert(slotSnapTx.exists, "not-found", "Slot not found.");

        const slotTx = slotSnapTx.data();

        const isBookedTx =
          typeof slotTx.isBooked === "boolean"
            ? slotTx.isBooked
            : slotTx.isBooked === 1;

        if (isBookedTx) {
          throw new HttpsError("failed-precondition", "Slot already booked");
        }

        const now = Date.now();
        const lockExpiresAt = slotTx.lockExpiresAt?.toMillis?.() || 0;
        const lockedBy = slotTx.lockedByBookingId;

        if (lockedBy && lockExpiresAt > now) {
          throw new HttpsError(
            "aborted",
            "This slot is currently being reserved. Please try another."
          );
        }

        const expires = admin.firestore.Timestamp.fromMillis(now + 15 * 60 * 1000);

       for (const requiredSlot of requiredSlots) {

  tx.update(requiredSlot.ref, {

    lockedByBookingId: bookingId,

    lockExpiresAt: expires,

    isBooked: false,
  });
}

        const bookingDay = new Date(slotTx.startTime.toDate());
        bookingDay.setHours(0, 0, 0, 0);

        tx.set(bookingRef, {
          bookingId,
          businessId,
          customerId,
          serviceId,
          serviceName,
          serviceDurationMinutes,
          staffId,
          staffName,
          customerName,
          customerAddress,
          addOns: cleanedAddOns,
          addOnsTotal,
         price: totalPrice,
status: "pending_payment",
paymentMethod: "stripe",
paymentStatus: "pending",
lockExpiresAt: expires,
slotId,
slotIds:
  requiredSlots.map(
    s => s.slotId
  ),
slotPath,
bookingDay: admin.firestore.Timestamp.fromDate(bookingDay),
          startDate: slotTx.startTime,
         endDate:
  admin.firestore.Timestamp.fromDate(

    new Date(
      slotStart.getTime() +
      slotsRequired * 30 * 60000
    )
  ),
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          unreadForCustomer: 0,
          unreadForBusiness: 0,
        });
      });

      console.log("✅ Booking created, creating PaymentIntent...");

      // =================================================
      // CREATE PAYMENT INTENT
      // =================================================

      const paymentIntent = await stripe.paymentIntents.create(
        {
          amount: totalPrice,
          currency: "gbp",
          automatic_payment_methods: { enabled: true },
          metadata: {
            bookingId,
            businessId,
            staffId,
            slotId,
            customerId,
          },
          transfer_data: {
            destination: stripeAccountId,
          },
        },
        {
          idempotencyKey: `booking_${bookingId}`,
        }
      );

      console.log("💰 PaymentIntent created:", paymentIntent.id);

     await bookingRef.update({
  paymentIntentId: paymentIntent.id,
  paymentStatus: "payment_intent_created",
});

      console.log("🎉 SUCCESS");

      return {
        clientSecret: paymentIntent.client_secret,
        bookingId,
      };

    } catch (error) {
      console.error("❌ createBookingPaymentIntent failed:", error);

      if (error instanceof HttpsError) throw error;

      throw new HttpsError(
        "internal",
        error?.message || "Failed to create booking."
      );
    }
  }
);



exports.autoCompleteBookings = onSchedule(
  { schedule: "every 15 minutes", region: "us-central1" },
  async () => {

    const now = new Date();

    const snap = await db.collection("bookings")
      .where("status", "==", "confirmed")
      .where("endDate", "<=", now)
      .get();

    if (snap.empty) return;

    const batch = db.batch();

    snap.docs.forEach(doc => {
      batch.update(doc.ref, {
        status: "completed",
        completedAt: admin.firestore.FieldValue.serverTimestamp()
      });
    });

    await batch.commit();

    console.log("✅ Auto-completed bookings:", snap.size);
  }
);
// =================================================
// DECREMENT SUBSCRIPTION
// =================================================

exports.decrementStaffSubscriptionQuantity = onCall(
  { region: "us-central1", secrets: ["STRIPE_SECRET_KEY"] },
  async (request) => {
      // 🔒 AUTH CHECK
      assert(request.auth, "unauthenticated", "Login required.");

      const provider = request.auth.token.firebase?.sign_in_provider;

      // 🔒 BLOCK ANONYMOUS USERS
      if (provider === "anonymous") {
        throw new HttpsError(
          "failed-precondition",
          "Please log in to make a booking"
        );
      }

    const stripe = getStripe();
    const uid = request.auth.uid;
    const businessId = request.data?.businessId;

    assert(businessId, "invalid-argument", "Missing businessId.");

    const businessRef = db.collection("businesses").doc(businessId);
    const businessSnap = await businessRef.get();

    assert(businessSnap.exists, "not-found", "Business not found.");
    assert(
      businessSnap.data().ownerId === uid,
      "permission-denied",
      "Not owner."
    );

    await ensureEntitlementsDoc(businessId);

    const entRef = entitlementsRef(businessId);
    const entSnap = await entRef.get();
    const subscriptionId = entSnap.data()?.stripeSubscriptionId || null;

    if (!subscriptionId) {
      await syncExtraStaffSlots(businessId, 0);
      await syncSubscriptionStatus(businessId, "free");
      await clearPastDueTimestamp(businessId);
      await disableRestrictionMode(businessId);
      await applySeatEnforcement(businessId);
      return { success: true };
    }

    let sub;

    try {
      sub = await stripe.subscriptions.retrieve(subscriptionId);
    } catch (err) {
      console.error("Subscription retrieve failed", err);

      await syncExtraStaffSlots(businessId, 0);
      await syncSubscriptionStatus(businessId, "free");
      await clearPastDueTimestamp(businessId);
      await disableRestrictionMode(businessId);
      await entRef.set({ stripeSubscriptionId: null }, { merge: true });
      await applySeatEnforcement(businessId);

      return { success: true };
    }

    const item = sub.items?.data?.[0];
    assert(item, "failed-precondition", "Subscription item not found.");

    const newQty = Math.max(0, Number(item.quantity || 0) - 1);

    if (newQty === 0) {
      await stripe.subscriptions.cancel(subscriptionId);
      return { success: true };
    }

    await stripe.subscriptions.update(subscriptionId, {
      items: [{ id: item.id, quantity: newQty }],
      proration_behavior: "always_invoice",
    });

    return { success: true };
  }
);

// =================================================
// STRIPE WEBHOOK (CLEAN + PRODUCTION SAFE)
// =================================================

exports.stripeWebhook = onRequest(
  {
    region: "us-central1",
    secrets: ["STRIPE_SECRET_KEY", "STRIPE_WEBHOOK_SECRET"],
  },
  async (req, res) => {
    console.log("🔥 STRIPE WEBHOOK HIT");

    const stripe = getStripe();
    const sig = req.headers["stripe-signature"];
    const endpointSecret = process.env.STRIPE_WEBHOOK_SECRET;

    if (!sig) return res.status(400).send("Missing stripe-signature.");
    if (!endpointSecret) return res.status(500).send("Missing webhook secret.");

    let event;

    try {
      event = stripe.webhooks.constructEvent(req.rawBody, sig, endpointSecret);
      console.log("✅ Event:", event.type);
    } catch (err) {
      console.error("❌ Signature failed:", err.message);
      return res.status(400).send(`Webhook Error: ${err.message}`);
    }

    const processedRef = stripeEventRef(event.id);

    try {
      await processedRef.create({
        createdAt: admin.firestore.FieldValue.serverTimestamp()
      });
    } catch (e) {
      console.log("↩️ Duplicate webhook ignored:", event.id);
      return res.status(200).json({ received: true, duplicate: true });
    }

    try {
      // ===============================
      // ✅ PAYMENT SUCCESS
      // ===============================
      if (event.type === "payment_intent.succeeded") {
        const pi = event.data.object;

        const bookingId = pi.metadata?.bookingId;
        const slotId = pi.metadata?.slotId;
        const businessId = pi.metadata?.businessId;
        const staffId = pi.metadata?.staffId;

        console.log("💰 PAYMENT SUCCEEDED:", bookingId);

        if (!bookingId || !businessId || !staffId || !slotId) {
          console.error("❌ Missing metadata on payment_intent:", pi.id, pi.metadata);
          return res.json({ received: true });
        }

        const bookingRef = db.collection("bookings").doc(bookingId);

        await db.runTransaction(async (tx) => {
          const bookingSnap = await tx.get(bookingRef);

          if (!bookingSnap.exists) {
            console.error("❌ Booking not found:", bookingId);
            return;
          }

          const data = bookingSnap.data();

          if (data.status === "confirmed") {
            console.log("✅ Already confirmed — skipping");
            return;
          }

        tx.update(bookingRef, {
  status: "confirmed",
  paymentStatus: "paid",
  confirmedAt: admin.firestore.FieldValue.serverTimestamp()
});

       const bookingSlotIds =
  Array.isArray(data.slotIds)
    ? data.slotIds
    : [slotId];

for (const bookingSlotId of bookingSlotIds) {

  const slotRef = db
    .collection("businesses")
    .doc(businessId)
    .collection("staff")
    .doc(staffId)
    .collection("availableSlots")
    .doc(bookingSlotId);

  const slotSnap =
    await tx.get(slotRef);

  if (!slotSnap.exists) {
    throw new Error("Slot missing");
  }

  const slotData =
    slotSnap.data();

  if (
    slotData.lockedByBookingId !== bookingId
  ) {
    throw new Error(
      "Slot lock mismatch"
    );
  }

  tx.update(slotRef, {

    isBooked: true,

    lockExpiresAt:
      admin.firestore.FieldValue.delete(),

    lockedByBookingId:
      admin.firestore.FieldValue.delete(),
  });
}
        });

        const updatedSnap = await bookingRef.get();
        const booking = updatedSnap.data();

        if (booking && booking.customerId && businessId) {
          const businessSnap = await db.collection("businesses").doc(businessId).get();
          const ownerId = businessSnap.data()?.ownerId;

          await sendPushToUser(booking.customerId, {
            title: "Booking confirmed",
            body: `Your booking for ${booking.serviceName} is confirmed`,
            data: { bookingId }
          });

          if (ownerId) {
            await sendPushToUser(ownerId, {
              title: "Booking confirmed",
              body: "You have a confirmed booking",
              data: { bookingId }
            });
          }
        }

        console.log("✅ BOOKING CONFIRMED:", bookingId);
      }

      // ===============================
      // ❌ PAYMENT FAILED / CANCELED
      // ===============================
     if (
  event.type === "payment_intent.payment_failed" ||
  event.type === "payment_intent.canceled"
) {

  const pi = event.data.object;

  const bookingId =
    pi.metadata?.bookingId;

  const slotId =
    pi.metadata?.slotId;

  const businessId =
    pi.metadata?.businessId;

  const staffId =
    pi.metadata?.staffId;

  if (
    !bookingId ||
    !slotId ||
    !businessId ||
    !staffId
  ) {

    console.error(
      "❌ Missing metadata on failed payment",
      pi.id,
      pi.metadata
    );

    return res.json({
      received: true
    });
  }

  const bookingRef =
    db.collection("bookings")
      .doc(bookingId);

  await db.runTransaction(async (tx) => {

    const bookingSnap =
      await tx.get(bookingRef);

    if (!bookingSnap.exists) return;

    const booking =
      bookingSnap.data();

    if (
      booking.status !== "pending_payment"
    ) {
      return;
    }

    tx.update(bookingRef, {

      status: "payment_failed",

      paymentStatus: "failed",

      cancelledAt:
        admin.firestore.FieldValue
          .serverTimestamp(),
    });

    const bookingSlotIds =
      Array.isArray(booking.slotIds)
        ? booking.slotIds
        : [slotId];

    for (const bookingSlotId of bookingSlotIds) {

      const slotRef = db
        .collection("businesses")
        .doc(businessId)
        .collection("staff")
        .doc(staffId)
        .collection("availableSlots")
        .doc(bookingSlotId);

      tx.update(slotRef, {

        isBooked: false,

        lockExpiresAt:
          admin.firestore.FieldValue
            .delete(),

        lockedByBookingId:
          admin.firestore.FieldValue
            .delete(),
      });
    }
  });

  const bookingSnap =
    await bookingRef.get();

  const booking =
    bookingSnap.data();

  const customerId =
    booking?.customerId;

  await sendPushToUser(customerId, {

    title: "Payment failed",

    body:
      "Your booking payment failed. Please try again.",
  });

  console.log(
    "❌ Payment failed — booking released"
  );
}

      // ===============================
      // 💳 SUBSCRIPTIONS
      // ===============================
      if (event.type === "invoice.paid") {
        const invoice = event.data.object;

        const businessId = await resolveBusinessIdFromCustomer(
          stripe,
          invoice.customer
        );

        if (businessId && invoice.subscription) {
          const sub = await stripe.subscriptions.retrieve(invoice.subscription);

          await entitlementsRef(businessId).set(
            { stripeSubscriptionId: sub.id },
            { merge: true }
          );

          const qty = sub.items?.data?.[0]?.quantity ?? 0;

          await syncExtraStaffSlots(businessId, qty);
          await syncSubscriptionStatus(businessId, sub.status);
          await syncCurrentPeriodEnd(businessId, sub.current_period_end);

          await clearPastDueTimestamp(businessId);
          await evaluateRestrictionState(businessId);
          await applySeatEnforcement(businessId);
        }
      }

      if (event.type === "customer.subscription.deleted") {
        const sub = event.data.object;

        const businessId = await resolveBusinessIdFromCustomer(
          stripe,
          sub.customer
        );

        if (businessId) {
          await entitlementsRef(businessId).set(
            { stripeSubscriptionId: null },
            { merge: true }
          );

          await syncExtraStaffSlots(businessId, 0);
          await syncSubscriptionStatus(businessId, "free");
          await clearPastDueTimestamp(businessId);

          await evaluateRestrictionState(businessId);
          await applySeatEnforcement(businessId);
        }
      }

      console.log("ℹ️ Event handled:", event.type);
      return res.status(200).json({ received: true });

} catch (err) {

  console.error(
    "❌ Webhook error:",
    err
  );

  return res
    .status(500)
    .send("Webhook failed");
}
  }
);

// =================================================
// CLEAN UP STALE PENDING BOOKINGS
// =================================================

exports.cleanupPendingBookings = onSchedule(
  { schedule: "every 5 minutes", region: "us-central1" },
  async () => {
    const cutoff = new Date(Date.now() - 15 * 60 * 1000);

    const snap = await db
      .collection("bookings")
      .where("status", "==", "pending_payment")
      .where("lockExpiresAt", "<", new Date())
      .get();

    if (snap.empty) return;

    const batch = db.batch();

    for (const doc of snap.docs) {
      const booking = doc.data();

      batch.update(doc.ref, {
        status: "cancelled_by_system",
        cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      const bookingSlotIds =
  Array.isArray(booking.slotIds)
    ? booking.slotIds
    : [booking.slotId];

for (const bookingSlotId of bookingSlotIds) {

  const sRef = slotRef(
    booking.businessId,
    booking.staffId,
    bookingSlotId
  );

  batch.update(sRef, {

    lockedByBookingId:
      admin.firestore.FieldValue.delete(),

    lockExpiresAt:
      admin.firestore.FieldValue.delete(),
  });
}
    }

    await batch.commit();

    logger.info("Cancelled stale pending bookings + unlocked slots", {
      count: snap.size,
    });
  }
);
// =================================================
// DAILY SAFETY SWEEP (CRON) – catches missed webhooks
// =================================================

exports.dailyRestrictionSweep = onSchedule(
  { schedule: "every 24 hours", region: "us-central1" },
  async () => {
    const snap = await db
      .collectionGroup("entitlements")
      .where("stripeStatus", "in", [
        "past_due",
        "canceled",
        "unpaid",
        "incomplete",
        "incomplete_expired",
      ])
      .get();

    let count = 0;

    for (const doc of snap.docs) {
      const businessId = doc.ref.parent.parent.id;
      await evaluateRestrictionState(businessId);
      await applySeatEnforcement(businessId);
      count += 1;
    }

    logger.info("Daily restriction sweep completed", { businessesChecked: count });
  }
);

// =================================================
// STRIPE CONNECT / PORTAL
// =================================================

exports.createConnectedAccount = onCall(
  { region: "us-central1", secrets: ["STRIPE_SECRET_KEY"] },
  async (request) => {

    assert(request.auth, "unauthenticated", "Login required.");

    const stripe = getStripe();
    const uid = request.auth.uid;

    const snap = await db
      .collection("businesses")
      .where("ownerId", "==", uid)
      .limit(1)
      .get();

    assert(!snap.empty, "not-found", "Business not found.");

    const businessDoc = snap.docs[0];
    let stripeAccountId = businessDoc.data().stripeAccountId || null;

    // ✅ CREATE ACCOUNT IF NOT EXISTS
    if (!stripeAccountId) {

      const account = await stripe.accounts.create({
        type: "express",
        country: "GB",
        email: request.auth.token.email || undefined,
        capabilities: {
          card_payments: { requested: true },
          transfers: { requested: true },
        },
        metadata: {
          businessId: businessDoc.id,
          uid,
        },
      });

      stripeAccountId = account.id;

      // ✅ SAVE ACCOUNT ID ONLY (NOT CONNECTED YET)
      await businessDoc.ref.set({
        stripeAccountId,
        stripeConnected: false
      }, { merge: true });
    }

    // ✅ ALWAYS RETURN ACCOUNT ID
    return { accountId: stripeAccountId };
  }
);
exports.refreshStripeConnectionStatus = onCall(
  { region: "us-central1", secrets: ["STRIPE_SECRET_KEY"] },
  async (request) => {

    assert(request.auth, "unauthenticated", "Login required.");

    const stripe = getStripe();
    const uid = request.auth.uid;

    const snap = await db
      .collection("businesses")
      .where("ownerId", "==", uid)
      .limit(1)
      .get();

    assert(!snap.empty, "not-found", "Business not found.");

    const businessDoc = snap.docs[0];
    const stripeAccountId = businessDoc.data().stripeAccountId;

    assert(stripeAccountId, "failed-precondition", "Stripe not set up.");

    const account = await stripe.accounts.retrieve(stripeAccountId);

    // 🔥 KEY CHANGE
    const onboardingComplete = account.details_submitted === true;
    const fullyEnabled = account.charges_enabled && account.payouts_enabled;

    await businessDoc.ref.set({
      stripeConnected: onboardingComplete,   // ✅ THIS drives your UI
      stripeFullyEnabled: fullyEnabled,      // (optional, for later)
      stripeDetailsSubmitted: account.details_submitted,
      stripeChargesEnabled: account.charges_enabled,
      stripePayoutsEnabled: account.payouts_enabled,
      stripeRequirements: account.requirements?.currently_due ?? []
    }, { merge: true });

    return {
      connected: onboardingComplete,
      fullyEnabled
    };
  }
);
exports.createAccountLink = onCall(
  { region: "us-central1", secrets: ["STRIPE_SECRET_KEY"] },
  async (request) => {
    assert(request.auth, "unauthenticated", "Login required.");

    const stripe = getStripe();
    const uid = request.auth.uid;
    const businessId = safeTrim(request.data?.businessId);

    assert(businessId, "invalid-argument", "businessId is required.");

    const businessRef = db.collection("businesses").doc(businessId);
    const businessSnap = await businessRef.get();

    assert(businessSnap.exists, "not-found", "Business not found.");

    const business = businessSnap.data();
    assert(business.ownerId === uid, "permission-denied", "Not your business.");

    const stripeAccountId = business.stripeAccountId;
    assert(stripeAccountId, "failed-precondition", "Stripe account not created.");

    const link = await stripe.accountLinks.create({
      account: stripeAccountId,
      refresh_url: "https://locallinkapp.co.uk/stripe-refresh?businessId=" + businessId,
      return_url: "https://locallinkapp.co.uk/stripe-return?businessId=" + businessId,
      type: "account_onboarding",
    });

    return { url: link.url };
  }
);
exports.createStripePortalLink = onCall(
  { region: "us-central1", secrets: ["STRIPE_SECRET_KEY"] },
  async (request) => {
    assert(request.auth, "unauthenticated", "Login required.");

    const stripe = getStripe();
    const uid = request.auth.uid;

    const snap = await db
      .collection("businesses")
      .where("ownerId", "==", uid)
      .limit(1)
      .get();

    assert(!snap.empty, "not-found", "Business not found.");

    const businessRef = snap.docs[0].ref;

    await ensureEntitlementsDoc(businessRef.id);

    const entSnap = await businessRef
      .collection("entitlements")
      .doc("default")
      .get();

    let stripeCustomerId = entSnap.data()?.stripeCustomerId || null;

    if (!stripeCustomerId) {
      const customer = await stripe.customers.create({
        metadata: {
          businessId: businessRef.id,
          uid,
        },
      });

      stripeCustomerId = customer.id;

      await businessRef
        .collection("entitlements")
        .doc("default")
        .set({ stripeCustomerId }, { merge: true });
    }

    console.log("Stripe customer ID:", stripeCustomerId);

    const session = await stripe.billingPortal.sessions.create({
      customer: stripeCustomerId,
      return_url: "https://locallinkapp.co.uk/billing-return",
    });

    return { url: session.url };
  }
);

exports.extractServicesFromPriceList = onCall(
  {
    region: "us-central1",
    secrets: ["OPENAI_API_KEY"],
    timeoutSeconds: 60,
    memory: "512MiB",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Login required.");
    }

    const { base64Image } = request.data || {};

    if (!base64Image) {
      throw new HttpsError("invalid-argument", "Missing image.");
    }

    const prompt = `
You are extracting a business price list from an image.

Return ONLY structured JSON.

Rules:
- Extract services and prices.
- Prices must be numbers only, in GBP.
- If duration is unknown, estimate sensibly.
- Classify items as either "service" or "addon".
- Add-ons are extras like wash, mask, waxing, treatments.
- Do not invent items.
- If unsure, include confidence below 0.7.
`;

    const schema = {
      type: "object",
      additionalProperties: false,
      properties: {
        services: {
          type: "array",
          items: {
            type: "object",
            additionalProperties: false,
            properties: {
              name: { type: "string" },
              price: { type: "number" },
              durationMinutes: { type: "number" },
              category: { type: "string" },
              type: {
                type: "string",
                enum: ["service", "addon"],
              },
              confidence: { type: "number" },
            },
            required: [
              "name",
              "price",
              "durationMinutes",
              "category",
              "type",
              "confidence",
            ],
          },
        },
      },
      required: ["services"],
    };

    const response = await fetch("https://api.openai.com/v1/responses", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "gpt-4.1-mini",
        input: [
          {
            role: "user",
            content: [
              { type: "input_text", text: prompt },
              {
                type: "input_image",
                image_url: `data:image/jpeg;base64,${base64Image}`,
                detail: "high",
              },
            ],
          },
        ],
        text: {
          format: {
            type: "json_schema",
            name: "price_list_extraction",
            strict: true,
            schema,
          },
        },
      }),
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.error("OpenAI error:", errorText);
      throw new HttpsError("internal", "Could not extract services.");
    }

    const result = await response.json();

    const outputText = result.output?.[0]?.content?.[0]?.text;

    if (!outputText) {
      console.error("No output_text:", JSON.stringify(result));
      throw new HttpsError("internal", "No extraction result.");
    }

    return JSON.parse(outputText);
  }
);
// =================================================
// APPLE STAFF SEAT PURCHASE
// =================================================

exports.verifyAppleSeatPurchase = onCall(
  { region: "us-central1" },
  async (request) => {

    const uid = request.auth?.uid;
    const businessId = request.data?.businessId;
    const productId = request.data?.productId;

    assert(uid, "unauthenticated", "Login required.");
    assert(businessId, "invalid-argument", "Missing businessId.");
    assert(productId, "invalid-argument", "Missing productId.");

    const businessRef = db.collection("businesses").doc(businessId);
    const businessSnap = await businessRef.get();

    assert(businessSnap.exists, "not-found", "Business not found.");
    assert(
      businessSnap.data().ownerId === uid,
      "permission-denied",
      "Not owner."
    );

    await ensureEntitlementsDoc(businessId);

    const entRef = entitlementsRef(businessId);

    // 🧠 PLAN SIZE
    let planSeats = 0;

    if (productId === "locallink.staff.1") planSeats = 1;
    if (productId === "locallink.staff.3") planSeats = 3;
    if (productId === "locallink.staff.5") planSeats = 5;

    assert(planSeats > 0, "invalid-argument", "Invalid productId.");

    // 💰 APPLY
   await entRef.set(
  {
    extraStaffSlots: planSeats,
    restrictionMode: false,
    billingSource: "apple",

    // 🔥 CLEAR STRIPE STATE
    stripeStatus: "apple",
    stripeCustomerId: null,
    stripeSubscriptionId: null,
    currentPeriodEnd: null,
    pastDueSince: null
  },
  { merge: true }
);

    await applySeatEnforcement(businessId);

    return { success: true };
  }
);
   
exports.deleteUserAccount = onCall(async (request) => {

  if (!request.auth) {
    throw new HttpsError(
      "unauthenticated",
      "Login required"
    );
  }

  const uid = request.auth.uid;
  const db = admin.firestore();

  console.log(
    "🔥 Deleting account for:",
    uid
  );

  try {

    // =========================
    // DELETE USER DOC
    // =========================

    await db
      .collection("users")
      .doc(uid)
      .delete()
      .catch(() => {});

    // =========================
    // ANONYMISE BOOKINGS
    // =========================

    const bookingsSnap = await db
      .collection("bookings")
      .where("customerId", "==", uid)
      .get();

    const batch = db.batch();

    bookingsSnap.forEach((doc) => {

      batch.update(doc.ref, {
        customerName: "Deleted user"
      });
    });

    await batch.commit();

    // =========================
    // DELETE AUTH USER
    // =========================

    await admin.auth().deleteUser(uid);

    console.log(
      "✅ Account deleted:",
      uid
    );

    return {
      success: true
    };

  } catch (error) {

    console.error(
      "❌ deleteUserAccount failed:",
      error
    );

    throw new HttpsError(
      "internal",
      error.message
    );
  }
});