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
const SHORT_NOTICE_APPROVAL_HOURS = 2;
const SHORT_NOTICE_APPROVAL_TIMEOUT_MINUTES = Number(
  process.env.SHORT_NOTICE_APPROVAL_TIMEOUT_MINUTES || 10
);
const PENDING_PAYMENT_TIMEOUT_MINUTES = 15;
const {
  cleanupDecisionForPaymentIntentStatus,
} = require("./stripe_cleanup_policy");

const notifications =
  require("./notifications");
const sendPushToUser =
  notifications.sendPushToUser;

  const reminders =
  require("./reminders");

  const recurring =
  require("./recurring");

let stripeClient = null;

function getStripe() {
  const key = process.env.STRIPE_SECRET_KEY;
  if (!key) throw new HttpsError("failed-precondition", "Stripe secret not configured.");
  if (!stripeClient) stripeClient = require("stripe")(key, { apiVersion: STRIPE_API_VERSION });
  return stripeClient;
}

async function assertAdminRequest(request) {
  assert(request.auth, "unauthenticated", "Login required.");

  const email = String(request.auth.token?.email || "").trim().toLowerCase();
  const approvedEmails = [
    "jae19882011@hotmail.co.uk",
    "founder@locallinkapp.co.uk",
  ];

  assert(approvedEmails.includes(email), "permission-denied", "Admin access required.");

  const adminEmailSnap = await db.collection("adminEmails").doc(email).get();
  assert(
    adminEmailSnap.exists && adminEmailSnap.data()?.enabled !== false,
    "permission-denied",
    "Admin access required."
  );
}

function assert(cond, code, msg) {
  if (!cond) throw new HttpsError(code, msg);
}

function safeTrim(s) {
  return String(s ?? "").trim();
}

function publicText(value, fallback = "") {
  const text = safeTrim(value);
  return text || fallback;
}

function firstPublicText(...values) {
  for (const value of values) {
    const text = safeTrim(value);
    if (text) return text;
  }
  return "";
}

function truncatePublicText(value, maxLength = 220) {
  const text = safeTrim(value).replace(/\s+/g, " ");
  if (text.length <= maxLength) return text;
  return `${text.slice(0, Math.max(0, maxLength - 1)).trim()}…`;
}

function dateToPublicLabel(value) {
  const millis = timestampToMillis(value);
  if (!millis) return "";

  return new Intl.DateTimeFormat("en-GB", {
    weekday: "short",
    day: "numeric",
    month: "short",
    hour: "2-digit",
    minute: "2-digit",
  }).format(new Date(millis));
}

function publicPriceLabel(value) {
  if (typeof value === "number" && Number.isFinite(value)) {
    return value === 0 ? "Free" : `£${value.toFixed(value % 1 === 0 ? 0 : 2)}`;
  }
  return safeTrim(value);
}

function publicImageUrl(data) {
  return firstPublicText(
    data.photoUrl,
    data.photoURL,
    data.imageUrl,
    data.imageURL,
    data.coverImageUrl,
    data.coverPhotoUrl,
    Array.isArray(data.photoURLs) ? data.photoURLs[0] : ""
  );
}

function communityHelpPublicLabel(post) {
  const type = safeTrim(post.type);
  if (type === "free_item") return "Free item";

  const mode = safeTrim(post.mode).toLowerCase();
  const category = safeTrim(post.itemCategory).toLowerCase();
  const title = safeTrim(post.title).toLowerCase();
  const copy = `${category} ${title}`;
  const kind = copy.includes("dog")
    ? "dog"
    : copy.includes("cat")
      ? "cat"
      : category === "pet"
        ? "pet"
        : "item";

  if (mode === "lost") return `Missing ${kind}`;
  if (mode === "found") return `Found ${kind}`;
  return "Community help";
}

function communityHelpPublicStatus(post) {
  const status = safeTrim(post.status).toLowerCase();
  if (["resolved", "reunited", "found"].includes(status)) {
    return status === "reunited" ? "Reunited" : "Found / resolved";
  }
  return communityHelpPublicLabel(post);
}

function isPubliclyPreviewable(data) {
  if (!data) return false;
  if (data.isDeleted === true || data.deleted === true) return false;
  if (data.hidden === true || data.isHidden === true) return false;
  if (data.private === true || data.isPrivate === true) return false;
  return data.isActive !== false;
}

function publicPreviewPayload({ type, id, parentId = "", label, title, subtitle = "", location = "", imageUrl = "" }) {
  return {
    type,
    id,
    parentId,
    label: publicText(label, "LocalLink"),
    title: publicText(title, "LocalLink post"),
    subtitle: truncatePublicText(subtitle),
    location: truncatePublicText(location, 120),
    imageUrl: publicText(imageUrl),
  };
}

exports.getPublicSharePreview = onCall(
  { region: "us-central1" },
  async (request) => {
    const type = safeTrim(request.data?.type);
    const id = safeTrim(request.data?.id);
    const parentId = safeTrim(request.data?.parentId);

    assert(id, "invalid-argument", "Missing shared item id.");

    if (type === "communityHelp") {
      const snap = await db.collection("communityHelpPosts").doc(id).get();
      assert(snap.exists, "not-found", "This Community Help post is no longer available.");

      const post = snap.data() || {};
      assert(isPubliclyPreviewable(post), "not-found", "This Community Help post is no longer available.");

      const lastSeen = firstPublicText(
        post.lastSeenText,
        dateToPublicLabel(post.lastSeenAt),
        dateToPublicLabel(post.createdAt)
      );
      const location = firstPublicText(post.publicLocation, post.approximateLocationLabel, post.areaLabel);
      const subtitleParts = [
        lastSeen ? `Last seen: ${lastSeen}` : "",
        post.description,
        post.markings,
      ].filter((part) => safeTrim(part));

      return publicPreviewPayload({
        type,
        id,
        label: communityHelpPublicStatus(post),
        title: firstPublicText(post.petName, post.itemName, post.title, "Community Help post"),
        subtitle: subtitleParts.join(" · "),
        location,
        imageUrl: publicImageUrl(post),
      });
    }

    if (type === "activity") {
      const snap = await db.collection("opportunities").doc(id).get();
      assert(snap.exists, "not-found", "This activity is no longer available.");

      const post = snap.data() || {};
      assert(isPubliclyPreviewable(post), "not-found", "This activity is no longer available.");

      const when = firstPublicText(post.dateText, post.timeText, dateToPublicLabel(post.date), dateToPublicLabel(post.startTime));
      const location = firstPublicText(post.publicLocation, post.locationLabel, post.location, post.areaLabel);

      return publicPreviewPayload({
        type,
        id,
        label: firstPublicText(post.category, "Activity"),
        title: firstPublicText(post.title, post.name, "Local activity"),
        subtitle: firstPublicText(when, post.description),
        location,
        imageUrl: publicImageUrl(post),
      });
    }

    if (type === "availability") {
      const snap = await db.collection("availabilityPosts").doc(id).get();
      assert(snap.exists, "not-found", "This available time is no longer live.");

      const post = snap.data() || {};
      assert(isPubliclyPreviewable(post), "not-found", "This available time is no longer live.");

      const when = firstPublicText(
        post.availabilityText,
        dateToPublicLabel(post.availabilityAt),
        dateToPublicLabel(post.startDateTime)
      );
      const price = publicPriceLabel(post.price);
      const subtitle = [when, price, post.description].filter((part) => safeTrim(part)).join(" · ");

      return publicPreviewPayload({
        type,
        id,
        label: "Available time",
        title: firstPublicText(post.serviceName, post.title, "Available service"),
        subtitle,
        location: firstPublicText(post.publicLocation, post.locationLabel, post.areaLabel),
        imageUrl: publicImageUrl(post),
      });
    }

    if (type === "business") {
      const snap = await db.collection("businesses").doc(id).get();
      assert(snap.exists, "not-found", "This business is no longer available.");

      const business = snap.data() || {};
      assert(isPubliclyPreviewable(business), "not-found", "This business is no longer available.");

      return publicPreviewPayload({
        type,
        id,
        label: firstPublicText(business.category, "Business"),
        title: firstPublicText(business.businessName, business.name, "Local business"),
        subtitle: firstPublicText(business.shortDescription, business.description),
        location: firstPublicText(business.serviceArea, business.publicLocation, business.areaLabel),
        imageUrl: publicImageUrl(business),
      });
    }

    if (type === "service") {
      assert(parentId, "invalid-argument", "Missing business id.");

      const businessSnap = await db.collection("businesses").doc(parentId).get();
      assert(businessSnap.exists, "not-found", "This service is no longer available.");
      const business = businessSnap.data() || {};
      assert(isPubliclyPreviewable(business), "not-found", "This service is no longer available.");

      const serviceSnap = await db.collection("businesses").doc(parentId).collection("services").doc(id).get();
      assert(serviceSnap.exists, "not-found", "This service is no longer available.");
      const service = serviceSnap.data() || {};
      assert(isPubliclyPreviewable(service), "not-found", "This service is no longer available.");

      const price = publicPriceLabel(service.price);
      const duration = service.durationMinutes ? `${service.durationMinutes} minutes` : "";

      return publicPreviewPayload({
        type,
        id,
        parentId,
        label: "Service",
        title: firstPublicText(service.name, service.serviceName, "Local service"),
        subtitle: [firstPublicText(business.businessName, business.name), price, duration, service.description]
          .filter((part) => safeTrim(part))
          .join(" · "),
        location: firstPublicText(business.serviceArea, business.publicLocation, business.areaLabel),
        imageUrl: firstPublicText(publicImageUrl(service), publicImageUrl(business)),
      });
    }

    throw new HttpsError("invalid-argument", "Unsupported shared item type.");
  }
);

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
exports.notifyBookingCancelled =
  notifications.notifyBookingCancelled;

exports.notifyNewFollower =
  notifications.notifyNewFollower;

  exports.sendOpportunityReminders =
  reminders.sendOpportunityReminders;

  exports.processRecurringOpportunities =
  recurring.processRecurringOpportunities;

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

function bookingConversationRef(bookingId) {
  return db.collection("conversations").doc(bookingId);
}

function businessCustomerConversationId({ businessId, customerId }) {
  return `business_${businessId}_${customerId}`;
}

async function activeBusinessCustomerConversationRef({ businessId, customerId }) {
  const preferredRef = db
    .collection("conversations")
    .doc(businessCustomerConversationId({ businessId, customerId }));
  const preferredSnap = await preferredRef.get();

  if (preferredSnap.exists && preferredSnap.data()?.archived !== true) {
    return preferredRef;
  }

  const snap = await db
    .collection("conversations")
    .where("businessId", "==", businessId)
    .where("customerId", "==", customerId)
    .where("archived", "==", false)
    .limit(1)
    .get();

  if (!snap.empty) {
    return snap.docs[0].ref;
  }

  return preferredRef;
}

function conversationStatusForBookingStatus(status) {
  if (status === "completed") return "completed";
  if (status === "confirmed") return "booking";
  return "enquiry";
}

function isBookingMessageStatus(status) {
  return ["confirmed", "completed"].includes(status);
}

async function buildConversationPayload(bookingId, booking) {
  const businessId = safeTrim(booking.businessId);
  const customerId = safeTrim(booking.customerId);

  assert(businessId && customerId, "failed-precondition", "Booking is missing participant data.");

  const businessSnap = await db.collection("businesses").doc(businessId).get();
  const business = businessSnap.data() || {};
  const businessOwnerId = safeTrim(booking.businessOwnerId) || safeTrim(business.ownerId);

  assert(businessOwnerId, "failed-precondition", "Business owner not found.");

  return {
    bookingId,
    currentBookingId: bookingId,
    customerId,
    businessId,
    businessOwnerId,
    originatingServiceId: safeTrim(booking.originatingServiceId) || safeTrim(booking.serviceId),
    originatingServiceName: safeTrim(booking.originatingServiceName) || safeTrim(booking.serviceName) || "Service",
    currentBookingServiceId: safeTrim(booking.serviceId),
    currentBookingServiceName: safeTrim(booking.serviceName) || "Service",
    currentBookingStatus: booking.status || "unknown",
    serviceId: safeTrim(booking.serviceId),
    businessName: safeTrim(booking.businessName) || safeTrim(business.businessName) || safeTrim(business.name) || "Business",
    customerName: safeTrim(booking.customerName) || "Customer",
    serviceName: safeTrim(booking.serviceName) || "Service",
    serviceImageUrl: safeTrim(booking.serviceImageUrl) || safeTrim(booking.imageUrl) || safeTrim(booking.photoUrl),
    bookingStartAt: booking.startDate || booking.startTime || null,
    lastMessage: safeTrim(booking.lastMessage),
    lastMessageAt: booking.lastMessageAt || null,
    unreadCustomerCount: Number(booking.unreadCustomerCount || 0),
    unreadBusinessCount: Number(booking.unreadBusinessCount || 0),
    archived: booking.archived === true,
    participants: [customerId, businessOwnerId],
    bookingStatus: booking.status || "unknown",
    quotationStatus: booking.quotationStatus || "none",
    acceptedQuotationId: booking.acceptedQuotationId || "",
    quotationIds: Array.isArray(booking.quotationIds) ? booking.quotationIds : [],
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
}

async function ensureBookingConversationDoc(bookingId, booking) {
  if (!isBookingMessageStatus(booking.status)) {
    return null;
  }

  const conversationId = safeTrim(booking.conversationId) || bookingId;
  const ref = bookingConversationRef(conversationId);
  const existingSnap = await ref.get();
  const existing = existingSnap.data() || {};
  const mergedBooking = existingSnap.exists
    ? {
        ...existing,
        ...booking,
        lastMessage: existing.lastMessage,
        lastMessageAt: existing.lastMessageAt,
        lastMessageId: existing.lastMessageId,
        lastSenderId: existing.lastSenderId,
        lastSenderType: existing.lastSenderType,
        unreadCustomerCount: existing.unreadCustomerCount,
        unreadBusinessCount: existing.unreadBusinessCount,
        customerHasMessaged: existing.customerHasMessaged === true,
      }
    : booking;
  const payload = await buildConversationPayload(
    bookingId,
    mergedBooking
  );

  await ref.set(
    {
      ...payload,
      conversationStatus:
        conversationStatusForBookingStatus(booking.status),
      customerHasMessaged:
        existing.customerHasMessaged === true,
      createdAt: existingSnap.exists
        ? existingSnap.data()?.createdAt || admin.firestore.FieldValue.serverTimestamp()
        : admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );

  return ref;
}

async function requireBookingConversationAccess(uid, bookingId) {
  assert(uid, "unauthenticated", "Login required.");
  assert(bookingId, "invalid-argument", "Missing bookingId.");

  const bookingRef = db.collection("bookings").doc(bookingId);
  const bookingSnap = await bookingRef.get();

  assert(bookingSnap.exists, "not-found", "Booking not found.");

  const booking = bookingSnap.data() || {};
  const conversationRef = await ensureBookingConversationDoc(bookingId, booking);

  assert(conversationRef, "failed-precondition", "Conversation is available after booking confirmation.");

  const conversationSnap = await conversationRef.get();
  const conversation = conversationSnap.data() || {};
  const isCustomer = conversation.customerId === uid;
  const isBusiness = conversation.businessOwnerId === uid;
  const communityParticipants = Array.isArray(conversation.communityHelpParticipantIds)
    ? conversation.communityHelpParticipantIds
    : [];
  const isCommunityParticipant = communityParticipants.includes(uid);

  assert(isCustomer || isBusiness || isCommunityParticipant, "permission-denied", "You cannot access this conversation.");

  return {
    conversationRef,
    conversation,
    senderType: isCustomer ? "customer" : "business",
    recipientId: isCustomer ? conversation.businessOwnerId : conversation.customerId,
  };
}

async function requireConversationAccess(uid, conversationId) {
  assert(uid, "unauthenticated", "Login required.");
  assert(conversationId, "invalid-argument", "Missing conversationId.");

  const conversationRef = db.collection("conversations").doc(conversationId);
  const conversationSnap = await conversationRef.get();

  assert(conversationSnap.exists, "not-found", "Conversation not found.");

  const conversation = conversationSnap.data() || {};
  const isCustomer = conversation.customerId === uid;
  const isBusiness = conversation.businessOwnerId === uid;
  const communityParticipants = Array.isArray(conversation.communityHelpParticipantIds)
    ? conversation.communityHelpParticipantIds
    : [];
  const isCommunityParticipant = communityParticipants.includes(uid);

  assert(isCustomer || isBusiness || isCommunityParticipant, "permission-denied", "You cannot access this conversation.");

  return {
    conversationRef,
    conversation,
    senderType: isCustomer ? "customer" : "business",
    recipientId: isCustomer ? conversation.businessOwnerId : conversation.customerId,
  };
}

async function updateRepeatCustomerSnapshot({
  customerId,
  businessId,
  serviceId,
  serviceName,
  customerAddress,
  customerNotes,
}) {
  if (!customerId || !businessId) return;

  await db
    .collection("users")
    .doc(customerId)
    .collection("businessPreferences")
    .doc(businessId)
    .set(
      {
        businessId,
        lastServiceId: serviceId || "",
        lastServiceName: serviceName || "",
        lastAddress: customerAddress || "",
        lastNotes: customerNotes || "",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
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

async function releaseBookingSlots(booking) {
  if (booking.directAvailability === true && booking.bookingId) {
    await restoreDirectAvailabilityBooking(booking.bookingId);
    return;
  }

  const businessId = safeTrim(booking.businessId);
  const staffId = safeTrim(booking.staffId);
  const slotIds = Array.isArray(booking.slotIds)
    ? booking.slotIds
    : [booking.slotId].filter(Boolean);

  for (const slotId of slotIds) {
    await releaseBookedSlot({ businessId, staffId, slotId });
  }
}

function directAvailabilityStartFromRequest(requestData) {
  const millis = Number(requestData?.selectedStartMillis || 0);
  if (!Number.isFinite(millis) || millis <= 0) {
    throw new HttpsError("invalid-argument", "Choose a valid time.");
  }
  return new Date(millis);
}

function postRemainingCapacity(post) {
  return Number(post.remainingCapacity ?? post.capacity ?? 1);
}

function assertDirectAvailabilitySelectable(post, selectedStart, durationMinutes) {
  const type = safeTrim(post.type || post.availabilityType || "exact");
  const remaining = postRemainingCapacity(post);
  assert(post.isActive === true, "failed-precondition", "Availability is no longer live.");
  assert(post.archived !== true, "failed-precondition", "Availability is no longer live.");
  assert((post.status || "live") === "live", "failed-precondition", "Availability is no longer live.");
  assert(remaining > 0, "failed-precondition", "Availability is fully booked.");

  if (type !== "flexible") {
    assert(selectedStart > new Date(), "failed-precondition", "Choose a future time.");
  }

  const postStart = post.startDateTime || post.startTime || post.availabilityAt;
  const postEnd = post.endDateTime || post.endTime || post.availableUntil;

  if (type === "exact" && postStart?.toDate) {
    assert(
      postStart.toDate().getTime() === selectedStart.getTime(),
      "failed-precondition",
      "This appointment time is no longer available."
    );
  }

  if (type === "window" && postStart?.toDate && postEnd?.toDate) {
    const selectedEnd = new Date(selectedStart.getTime() + durationMinutes * 60 * 1000);
    assert(
      selectedStart >= postStart.toDate() && selectedEnd <= postEnd.toDate(),
      "failed-precondition",
      "Choose a time within the advertised window."
    );
  }
}

function directAvailabilityPostUpdate(post, bookingId) {
  const remaining = Math.max(0, postRemainingCapacity(post) - 1);
  return {
    remainingCapacity: remaining,
    status: remaining === 0 ? "booked" : "live",
    isActive: remaining > 0,
    archived: remaining === 0,
    archivedReason: remaining === 0 ? "booked" : null,
    bookingId,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    archivedAt: remaining === 0
      ? admin.firestore.FieldValue.serverTimestamp()
      : admin.firestore.FieldValue.delete(),
  };
}

function directAvailabilityRestoreUpdate(post, bookingId) {
  const capacity = Math.max(1, Number(post.capacity ?? 1));
  const remaining = Math.max(0, postRemainingCapacity(post));
  const restored = Math.min(capacity, remaining + 1);
  const update = {
    remainingCapacity: restored,
    status: "live",
    isActive: true,
    archived: false,
    archivedReason: admin.firestore.FieldValue.delete(),
    archivedAt: admin.firestore.FieldValue.delete(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  if (safeTrim(post.bookingId) === bookingId) {
    update.bookingId = admin.firestore.FieldValue.delete();
  }

  return update;
}

function directAvailabilityNeedsRestore(booking) {
  return booking?.directAvailability === true &&
    Boolean(safeTrim(booking.availabilityPostId)) &&
    !booking.availabilityRestoredAt;
}

async function restoreDirectAvailabilityInTransaction(tx, bookingRef, booking, bookingId) {
  if (!directAvailabilityNeedsRestore(booking)) return false;

  const postRef = db
    .collection("availabilityPosts")
    .doc(safeTrim(booking.availabilityPostId));
  const postSnap = await tx.get(postRef);

  if (postSnap.exists) {
    tx.update(postRef, directAvailabilityRestoreUpdate(postSnap.data() || {}, bookingId));
  }

  tx.update(bookingRef, {
    availabilityRestoredAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return true;
}

async function restoreDirectAvailabilityBooking(bookingId) {
  const bookingRef = db.collection("bookings").doc(bookingId);

  return db.runTransaction(async (tx) => {
    const bookingSnap = await tx.get(bookingRef);
    if (!bookingSnap.exists) return false;

    const booking = bookingSnap.data() || {};
    return restoreDirectAvailabilityInTransaction(
      tx,
      bookingRef,
      booking,
      bookingId
    );
  });
}

function releaseBookingSlotsInTransaction(tx, booking) {
  const businessId = safeTrim(booking.businessId);
  const staffId = safeTrim(booking.staffId);
  const bookingSlotIds = Array.isArray(booking.slotIds)
    ? booking.slotIds
    : [booking.slotId];

  if (!businessId || !staffId) return;

  for (const bookingSlotId of bookingSlotIds.map(safeTrim).filter(Boolean)) {
    const sRef = slotRef(businessId, staffId, bookingSlotId);
    tx.update(sRef, {
      lockedByBookingId: admin.firestore.FieldValue.delete(),
      lockExpiresAt: admin.firestore.FieldValue.delete(),
    });
  }
}

async function finalizePaidBookingInTransaction({
  tx,
  bookingRef,
  bookingId,
  paymentMetadata = {},
}) {
  const bookingSnap = await tx.get(bookingRef);

  if (!bookingSnap.exists) {
    logger.error("Paid booking reconciliation skipped; booking not found", {
      bookingId,
    });
    return { changed: false, reason: "booking_not_found" };
  }

  const data = bookingSnap.data() || {};
  const currentStatus = safeTrim(data.status);
  const currentPaymentStatus = safeTrim(data.paymentStatus);

  if (
    currentPaymentStatus === "paid" &&
    ["confirmed", "pending_business_confirmation"].includes(currentStatus)
  ) {
    return { changed: false, reason: "already_paid" };
  }

  if (currentStatus !== "pending_payment") {
    logger.warn("Paid booking reconciliation skipped; booking is no longer pending", {
      bookingId,
      status: currentStatus,
      paymentStatus: currentPaymentStatus,
    });
    return { changed: false, reason: "not_pending" };
  }

  const businessId = safeTrim(data.businessId || paymentMetadata.businessId);
  const staffId = safeTrim(data.staffId || paymentMetadata.staffId);
  const slotId = safeTrim(data.slotId || paymentMetadata.slotId);
  const directAvailability =
    data.directAvailability === true ||
    paymentMetadata.directAvailability === "true";

  if (!businessId) {
    logger.error("Paid booking reconciliation skipped; missing businessId", {
      bookingId,
    });
    return { changed: false, reason: "missing_business" };
  }

  if (!directAvailability) {
    if (!staffId || !slotId) {
      logger.error("Paid booking reconciliation skipped; missing staff slot metadata", {
        bookingId,
      });
      return { changed: false, reason: "missing_slot_metadata" };
    }

    const bookingSlotIds = Array.isArray(data.slotIds)
      ? data.slotIds
      : [slotId];

    for (const bookingSlotId of bookingSlotIds.map(safeTrim).filter(Boolean)) {
      const bookingSlotRef = db
        .collection("businesses")
        .doc(businessId)
        .collection("staff")
        .doc(staffId)
        .collection("availableSlots")
        .doc(bookingSlotId);

      const slotSnap = await tx.get(bookingSlotRef);
      if (!slotSnap.exists) {
        throw new Error("Slot missing");
      }

      const slotData = slotSnap.data() || {};
      if (slotData.lockedByBookingId !== bookingId) {
        throw new Error("Slot lock mismatch");
      }

      tx.update(bookingSlotRef, {
        isBooked: true,
        lockExpiresAt: admin.firestore.FieldValue.delete(),
        lockedByBookingId: admin.firestore.FieldValue.delete(),
      });
    }
  }

  const nextStatus = data.requiresBusinessApproval === true
    ? "pending_business_confirmation"
    : "confirmed";

  tx.update(bookingRef, {
    status: nextStatus,
    paymentStatus: "paid",
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    confirmedAt: nextStatus === "confirmed"
      ? admin.firestore.FieldValue.serverTimestamp()
      : null,
  });

  return { changed: true, status: nextStatus };
}

async function retrievePendingPaymentIntentForCleanup(stripe, booking) {
  const paymentIntentId = safeTrim(booking.paymentIntentId);

  if (!paymentIntentId) {
    return {
      decision: "abandon",
      paymentIntent: null,
      reason: "missing_payment_intent",
    };
  }

  try {
    const paymentIntent = await stripe.paymentIntents.retrieve(paymentIntentId);
    return {
      decision: cleanupDecisionForPaymentIntentStatus(paymentIntent.status),
      paymentIntent,
      reason: paymentIntent.status,
    };
  } catch (error) {
    if (
      error?.type === "StripeInvalidRequestError" &&
      error?.code === "resource_missing"
    ) {
      return {
        decision: "abandon",
        paymentIntent: null,
        reason: "payment_intent_not_found",
      };
    }

    logger.warn("Pending booking cleanup skipped; Stripe lookup failed", {
      bookingId: booking.bookingId,
      paymentIntentId,
      type: error?.type,
      code: error?.code,
      message: error?.message,
    });

    return {
      decision: "retry_later",
      paymentIntent: null,
      reason: "stripe_lookup_failed",
    };
  }
}

async function cancelAbandonedPaymentIntentIfNeeded(stripe, paymentIntent, bookingId) {
  if (!paymentIntent) return;

  const cancellable = [
    "requires_payment_method",
    "requires_confirmation",
    "requires_action",
    "requires_capture",
  ];

  if (!cancellable.includes(paymentIntent.status)) return;

  try {
    await stripe.paymentIntents.cancel(paymentIntent.id);
  } catch (error) {
    logger.warn("Stripe PaymentIntent cancel failed during scheduled cleanup", {
      bookingId,
      paymentIntentId: paymentIntent.id,
      type: error?.type,
      code: error?.code,
      message: error?.message,
    });
  }
}

async function buildDirectAvailabilityBooking({
  request,
  paymentMethod,
  paymentStatus,
}) {
  const uid = request.auth?.uid;
  assert(uid, "unauthenticated", "Login required.");

  const businessId = safeTrim(request.data?.businessId);
  const serviceId = safeTrim(request.data?.serviceId);
  const availabilityPostId = safeTrim(request.data?.availabilityPostId);
  const customerName = safeTrim(request.data?.customerName);
  const customerAddress = safeTrim(request.data?.customerAddress);
  const customerNotes = safeTrim(request.data?.customerNotes);
  const selectedStart = directAvailabilityStartFromRequest(request.data);

  assert(businessId && serviceId && availabilityPostId, "invalid-argument", "Missing booking data.");

  const businessRef = db.collection("businesses").doc(businessId);
  const businessSnap = await businessRef.get();
  assert(businessSnap.exists, "not-found", "Business not found.");

  const business = businessSnap.data() || {};
  const paymentMethods = Array.isArray(business.paymentMethods)
    ? business.paymentMethods
    : ["cash"];
  assert(paymentMethods.includes(paymentMethod), "failed-precondition", "This payment method is not available.");

  const serviceSnap = await businessRef.collection("services").doc(serviceId).get();
  assert(serviceSnap.exists, "not-found", "Service not found.");

  const service = serviceSnap.data() || {};
  const availabilityRef = db.collection("availabilityPosts").doc(availabilityPostId);
  const serviceName = safeTrim(service.name) || "Service";
  const serviceDurationMinutes = Number(service.durationMinutes || 30);
  const serviceImageUrl = safeTrim(service.imageUrl || service.photoUrl || "");
  const activeConversationRef = await activeBusinessCustomerConversationRef({
    businessId,
    customerId: uid,
  });
  const activeConversationSnap = await activeConversationRef.get();
  const bookingRef = db.collection("bookings").doc();
  const bookingId = bookingRef.id;
  const conversationId = activeConversationSnap.exists ? activeConversationRef.id : bookingId;
  const bookingDay = new Date(selectedStart);
  bookingDay.setHours(0, 0, 0, 0);
  const hoursBefore = (selectedStart - new Date()) / (1000 * 60 * 60);
  const requiresBusinessApproval = hoursBefore < SHORT_NOTICE_APPROVAL_HOURS;
  const approvalExpiresAt = requiresBusinessApproval
    ? admin.firestore.Timestamp.fromMillis(Date.now() + SHORT_NOTICE_APPROVAL_TIMEOUT_MINUTES * 60 * 1000)
    : null;
  const lockExpiresAt = paymentMethod === "stripe"
    ? admin.firestore.Timestamp.fromMillis(
      Date.now() + PENDING_PAYMENT_TIMEOUT_MINUTES * 60 * 1000
    )
    : null;

  let booking = null;

  await db.runTransaction(async (tx) => {
    const postSnap = await tx.get(availabilityRef);
    assert(postSnap.exists, "failed-precondition", "Availability no longer exists.");

    const post = postSnap.data() || {};
    assert(safeTrim(post.businessId) === businessId, "permission-denied", "Availability does not belong to this business.");
    assert(safeTrim(post.serviceId) === serviceId, "failed-precondition", "Availability no longer matches this service.");
    assertDirectAvailabilitySelectable(post, selectedStart, serviceDurationMinutes);

    const price = Number(post.priceOverride ?? post.price ?? service.price ?? 0);
    assert(price > 0, "failed-precondition", "Invalid service price.");
    const selectedEnd = new Date(selectedStart.getTime() + serviceDurationMinutes * 60 * 1000);
    const status = paymentMethod === "cash"
      ? (requiresBusinessApproval ? "pending_business_confirmation" : "confirmed")
      : "pending_payment";

    booking = {
      bookingId,
      conversationId,
      businessId,
      customerId: uid,
      serviceId,
      serviceName,
      serviceDurationMinutes,
      serviceImageUrl,
      staffId: null,
      staffName: "",
      customerName,
      customerAddress,
      customerNotes,
      addOns: [],
      addOnsTotal: 0,
      price,
      status,
      requiresBusinessApproval,
      approvalExpiresAt,
      paymentMethod,
      paymentStatus,
      paymentIntentId: "",
      directAvailability: true,
      availabilityPostId,
      lockExpiresAt,
      slotId: "",
      slotIds: [],
      slotPath: "",
      bookingDay: admin.firestore.Timestamp.fromDate(bookingDay),
      startDate: admin.firestore.Timestamp.fromDate(selectedStart),
      endDate: admin.firestore.Timestamp.fromDate(selectedEnd),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      confirmedAt: paymentMethod === "cash" && !requiresBusinessApproval
        ? admin.firestore.FieldValue.serverTimestamp()
        : null,
      unreadForCustomer: 0,
      unreadForBusiness: 0,
    };

    tx.set(bookingRef, booking);
    tx.update(availabilityRef, directAvailabilityPostUpdate(post, bookingId));
  });

  return {
    bookingId,
    booking,
    business,
    bookingRef,
    requiresBusinessApproval,
  };
}

exports.createDirectAvailabilityCashBooking = onCall(
  { region: "us-central1" },
  async (request) => {
    const result = await buildDirectAvailabilityBooking({
      request,
      paymentMethod: "cash",
      paymentStatus: "pay_on_arrival",
    });

    const booking = result.booking || {};
    const ownerId = result.business.ownerId || result.business.businessOwnerId;

    if (ownerId) {
      await sendPushToUser(ownerId, {
        title: result.requiresBusinessApproval ? "New Last-Minute Request" : "New Booking",
        body: `${booking.customerName || "A customer"} booked ${booking.serviceName || "a service"}.`,
        data: {
          bookingId: result.bookingId,
          businessId: booking.businessId,
          type: result.requiresBusinessApproval ? "last_minute_request" : "new_booking",
        },
        preferenceKey: "serviceBookingUpdates",
      });
    }

    await sendPushToUser(booking.customerId, {
      title: result.requiresBusinessApproval ? "Booking request sent" : "Booking confirmed",
      body: result.requiresBusinessApproval
        ? `This appointment starts soon, so the business needs to confirm it. Most businesses respond within ${SHORT_NOTICE_APPROVAL_TIMEOUT_MINUTES} minutes.`
        : `Your booking for ${booking.serviceName || "your service"} is confirmed.`,
      data: {
        bookingId: result.bookingId,
        businessId: booking.businessId,
        type: result.requiresBusinessApproval ? "last_minute_request" : "booking_confirmed",
      },
      preferenceKey: "serviceBookingUpdates",
    });

    await ensureBookingConversationDoc(result.bookingId, booking);

    return {
      ok: true,
      bookingId: result.bookingId,
      status: booking.status,
      requiresBusinessApproval: result.requiresBusinessApproval,
    };
  }
);

exports.createDirectAvailabilityPaymentIntent = onCall(
  {
    region: "us-central1",
    secrets: ["STRIPE_SECRET_KEY"],
  },
  async (request) => {
    const stripe = getStripe();
    const businessId = safeTrim(request.data?.businessId);
    assert(businessId, "invalid-argument", "Missing booking data.");

    const preflightBusinessSnap = await db.collection("businesses").doc(businessId).get();
    assert(preflightBusinessSnap.exists, "not-found", "Business not found.");

    const preflightBusiness = preflightBusinessSnap.data() || {};
    const stripeAccountId = preflightBusiness.stripeAccountId;
    assert(stripeAccountId, "failed-precondition", "Stripe not connected.");

    const account = await stripe.accounts.retrieve(stripeAccountId);
    assert(account.charges_enabled, "failed-precondition", "Business cannot accept payments yet.");

    let result = null;

    try {
      result = await buildDirectAvailabilityBooking({
        request,
        paymentMethod: "stripe",
        paymentStatus: "pending",
      });
      const booking = result.booking || {};

      const paymentIntent = await stripe.paymentIntents.create(
        {
          amount: booking.price,
          currency: "gbp",
          automatic_payment_methods: { enabled: true },
          metadata: {
            bookingId: result.bookingId,
            businessId: booking.businessId,
            customerId: booking.customerId,
            directAvailability: "true",
            availabilityPostId: booking.availabilityPostId,
          },
          transfer_data: {
            destination: stripeAccountId,
          },
        },
        {
          idempotencyKey: `direct_availability_booking_${result.bookingId}`,
        }
      );

      await result.bookingRef.update({
        paymentIntentId: paymentIntent.id,
        paymentStatus: "payment_intent_created",
      });

      return {
        ok: true,
        bookingId: result.bookingId,
        clientSecret: paymentIntent.client_secret,
        requiresBusinessApproval: result.requiresBusinessApproval,
      };
    } catch (error) {
      if (result?.bookingId) {
        logger.warn("Restoring direct availability after payment setup failure", {
          bookingId: result.bookingId,
          error: error.message,
        });
        await restoreDirectAvailabilityBooking(result.bookingId);
      }

      throw error;
    }
  }
);

exports.cancelPendingCardBooking = onCall(
  {
    region: "us-central1",
    secrets: ["STRIPE_SECRET_KEY"],
  },
  async (request) => {
    const uid = request.auth?.uid;
    assert(uid, "unauthenticated", "Login required.");

    const bookingId = safeTrim(request.data?.bookingId);
    assert(bookingId, "invalid-argument", "Missing bookingId.");

    const bookingRef = db.collection("bookings").doc(bookingId);
    const bookingSnap = await bookingRef.get();
    assert(bookingSnap.exists, "not-found", "Booking not found.");

    const booking = bookingSnap.data() || {};
    assert(booking.customerId === uid, "permission-denied", "Not allowed.");
    assert(booking.paymentMethod === "stripe", "failed-precondition", "This is not a card booking.");

    const status = safeTrim(booking.status);
    const paymentStatus = safeTrim(booking.paymentStatus);
    const pendingStatuses = ["pending_payment"];
    const pendingPaymentStatuses = ["", "pending", "payment_intent_created"];

    if (!pendingStatuses.includes(status) ||
      !pendingPaymentStatuses.includes(paymentStatus)) {
      return { ok: true, status, paymentStatus, alreadyFinal: true };
    }

    const stripe = getStripe();
    const paymentIntentId = safeTrim(booking.paymentIntentId);

    if (paymentIntentId) {
      const paymentIntent = await stripe.paymentIntents.retrieve(paymentIntentId);

      if (paymentIntent.status === "succeeded") {
        return { ok: false, status: "payment_succeeded" };
      }

      if (paymentIntent.status === "processing") {
        return { ok: false, status: "payment_processing" };
      }

      const cancellable = [
        "requires_payment_method",
        "requires_confirmation",
        "requires_action",
        "requires_capture",
      ];

      if (cancellable.includes(paymentIntent.status)) {
        try {
          await stripe.paymentIntents.cancel(paymentIntentId);
        } catch (error) {
          logger.warn("Stripe PaymentIntent cancel failed during booking release", {
            bookingId,
            paymentIntentId,
            message: error.message,
          });
        }
      }
    }

    await db.runTransaction(async (tx) => {
      const freshSnap = await tx.get(bookingRef);
      if (!freshSnap.exists) return;

      const fresh = freshSnap.data() || {};
      const freshStatus = safeTrim(fresh.status);
      const freshPaymentStatus = safeTrim(fresh.paymentStatus);

      if (!pendingStatuses.includes(freshStatus) ||
        !pendingPaymentStatuses.includes(freshPaymentStatus)) {
        return;
      }

      if (fresh.directAvailability === true) {
        await restoreDirectAvailabilityInTransaction(tx, bookingRef, fresh, bookingId);
      } else {
        releaseBookingSlotsInTransaction(tx, fresh);
      }

      tx.update(bookingRef, {
        status: "payment_cancelled",
        paymentStatus: "cancelled",
        cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });

    return { ok: true, status: "payment_cancelled" };
  }
);

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

    if (booking.directAvailability === true) {
      await restoreDirectAvailabilityBooking(bookingId);
    }

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
    data: { bookingId, type: "booking_cancelled" },
    preferenceKey: "serviceBookingUpdates",
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
      data: { bookingId, type: "booking_cancelled" },
      preferenceKey: "serviceBookingUpdates",
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

exports.acceptShortNoticeBooking = onCall(
  { region: "us-central1" },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "You must be signed in.");

    const bookingId = safeTrim(request.data?.bookingId);
    assert(bookingId, "invalid-argument", "Missing bookingId.");

    const bookingRef = db.collection("bookings").doc(bookingId);
    const bookingSnap = await bookingRef.get();
    assert(bookingSnap.exists, "not-found", "Booking not found.");

    const booking = bookingSnap.data() || {};
    const businessId = safeTrim(booking.businessId);
    assert(await isBusinessOwner(uid, businessId), "permission-denied", "Not allowed.");
    assert(
      booking.status === "pending_business_confirmation",
      "failed-precondition",
      "This booking is not awaiting confirmation."
    );

    await bookingRef.update({
      status: "confirmed",
      confirmedAt: admin.firestore.FieldValue.serverTimestamp(),
      acceptedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await addSystemBookingMessage(bookingId, "Short-notice booking accepted by business");
    await incrementAnalytics({
      "bookings.businessAccepted": 1,
      "bookings.pendingApprovalResolved": 1,
    });

    if (booking.customerId) {
      await sendPushToUser(booking.customerId, {
        title: "Booking Confirmed",
        body: `${booking.businessName || "The business"} confirmed ${booking.serviceName || "your service"}.`,
        data: { bookingId, businessId, type: "booking_confirmed" },
        preferenceKey: "serviceBookingUpdates",
      });
    }

    return { ok: true, bookingId, status: "confirmed" };
  }
);

exports.declineShortNoticeBooking = onCall(
  {
    region: "us-central1",
    secrets: ["STRIPE_SECRET_KEY"],
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "You must be signed in.");

    const bookingId = safeTrim(request.data?.bookingId);
    assert(bookingId, "invalid-argument", "Missing bookingId.");

    const bookingRef = db.collection("bookings").doc(bookingId);
    const bookingSnap = await bookingRef.get();
    assert(bookingSnap.exists, "not-found", "Booking not found.");

    const booking = bookingSnap.data() || {};
    const businessId = safeTrim(booking.businessId);
    const staffId = safeTrim(booking.staffId);
    assert(await isBusinessOwner(uid, businessId), "permission-denied", "Not allowed.");
    assert(
      booking.status === "pending_business_confirmation",
      "failed-precondition",
      "This booking is not awaiting confirmation."
    );

    let refundId = null;
    if (booking.paymentIntentId) {
      const stripe = getStripe();
      const existing = await stripe.refunds.list({
        payment_intent: booking.paymentIntentId,
        limit: 1,
      });

      if (existing.data.length > 0) {
        refundId = existing.data[0].id;
      } else {
        const refund = await stripe.refunds.create({
          payment_intent: booking.paymentIntentId,
        });
        refundId = refund.id;
      }
    }

    const batch = db.batch();
    batch.update(bookingRef, {
      status: "declined",
      declinedAt: admin.firestore.FieldValue.serverTimestamp(),
      refundStatus: booking.paymentIntentId ? "refunded" : "not_required",
      refundId: refundId || null,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    const slotIds = Array.isArray(booking.slotIds)
      ? booking.slotIds
      : [booking.slotId].filter(Boolean);

    for (const slotId of slotIds) {
      if (!staffId || !slotId) continue;

      const ref = db
        .collection("businesses")
        .doc(businessId)
        .collection("staff")
        .doc(staffId)
        .collection("availableSlots")
        .doc(slotId);

      batch.update(ref, {
        isBooked: false,
        lockedByBookingId: admin.firestore.FieldValue.delete(),
        lockExpiresAt: admin.firestore.FieldValue.delete(),
      });
    }

    await batch.commit();
    await releaseBookingSlots(booking);
    await addSystemBookingMessage(bookingId, "Short-notice booking declined by business");
    await incrementAnalytics({
      "bookings.businessDeclined": 1,
      "bookings.pendingApprovalResolved": 1,
      ...(refundId ? { "payments.refundsIssued": 1 } : {}),
    });

    if (booking.customerId) {
      await sendPushToUser(booking.customerId, {
        title: "Booking Declined",
        body:
          "Unfortunately this appointment could not be accepted because it was requested at very short notice.",
        data: { bookingId, businessId, type: "booking_declined" },
        preferenceKey: "serviceBookingUpdates",
      });
    }

    return { ok: true, bookingId, status: "declined", refundIssued: !!refundId };
  }
);

exports.cleanupExpiredAvailabilityPosts = onSchedule(
  {
    schedule: "every 15 minutes",
    region: "us-central1",
  },
  async () => {
    const now = admin.firestore.Timestamp.now();
    const snap = await db
      .collection("availabilityPosts")
      .where("isActive", "==", true)
      .where("availabilityAt", "<", now)
      .limit(200)
      .get();

    if (snap.empty) {
      return null;
    }

    const batch = db.batch();
    snap.docs.forEach((doc) => {
      batch.update(doc.ref, {
        isActive: false,
        archived: true,
        archivedReason: "expired",
        archivedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });

    await batch.commit();
    logger.info("Expired availability posts archived", { count: snap.size });
    return null;
  }
);

exports.expireServiceRequests = onSchedule(
  {
    schedule: "every 30 minutes",
    region: "us-central1",
  },
  async () => {
    const now = admin.firestore.Timestamp.now();
    const snap = await db
      .collection("serviceRequests")
      .where("isActive", "==", true)
      .where("status", "==", "open")
      .where("expiresAt", "<=", now)
      .limit(300)
      .get();

    if (snap.empty) {
      return null;
    }

    const batch = db.batch();
    snap.docs.forEach((doc) => {
      batch.set(
        doc.ref,
        {
          status: "expired",
          isActive: false,
          closedAt: admin.firestore.FieldValue.serverTimestamp(),
          expiredAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    });

    await batch.commit();
    logger.info("Expired service requests", { count: snap.size });
    return null;
  }
);

exports.cleanupExpiredShortNoticeBookings = onSchedule(
  {
    schedule: "every 5 minutes",
    region: "us-central1",
    secrets: ["STRIPE_SECRET_KEY"],
  },
  async () => {
    const now = admin.firestore.Timestamp.now();
    const snap = await db
      .collection("bookings")
      .where("status", "==", "pending_business_confirmation")
      .where("approvalExpiresAt", "<=", now)
      .limit(100)
      .get();

    if (snap.empty) {
      return null;
    }

    for (const doc of snap.docs) {
      const booking = doc.data() || {};

      let refundId = null;
      if (booking.paymentIntentId) {
        const stripe = getStripe();
        const existing = await stripe.refunds.list({
          payment_intent: booking.paymentIntentId,
          limit: 1,
        });

        if (existing.data.length > 0) {
          refundId = existing.data[0].id;
        } else {
          const refund = await stripe.refunds.create({
            payment_intent: booking.paymentIntentId,
          });
          refundId = refund.id;
        }
      }

      await doc.ref.update({
        status: "declined",
        declinedReason: "approval_timeout",
        declinedAt: admin.firestore.FieldValue.serverTimestamp(),
        refundStatus: booking.paymentIntentId ? "refunded" : "not_required",
        refundId: refundId || null,
        paymentStatus: booking.paymentIntentId ? "refunded" : booking.paymentStatus,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      await releaseBookingSlots(booking);
      await addSystemBookingMessage(
        doc.id,
        "Short-notice booking expired before it was accepted"
      );

      if (booking.customerId) {
        await sendPushToUser(booking.customerId, {
          title: "Booking Request Expired",
          body: "Unfortunately we didn't receive confirmation in time.",
          data: {
            bookingId: doc.id,
            businessId: booking.businessId || "",
            type: "booking_expired",
          },
          preferenceKey: "serviceBookingUpdates",
        });
      }

      const businessSnap = booking.businessId
        ? await db.collection("businesses").doc(booking.businessId).get()
        : null;
      const ownerId = businessSnap?.data()?.ownerId;
      if (ownerId) {
        await sendPushToUser(ownerId, {
          title: "Booking Request Expired",
          body: "This booking request expired before it was accepted.",
          data: {
            bookingId: doc.id,
            businessId: booking.businessId || "",
            type: "booking_expired",
          },
          preferenceKey: "serviceBookingUpdates",
        });
      }

      await incrementAnalytics({
        "bookings.pendingApprovalExpired": 1,
        "bookings.pendingApprovalResolved": 1,
        ...(refundId ? { "payments.refundsIssued": 1 } : {}),
      });
    }

    logger.info("Expired short-notice bookings processed", {
      count: snap.size,
    });
    return null;
  }
);

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
const availabilityPostId = safeTrim(request.data?.availabilityPostId);
const customerName = safeTrim(request.data?.customerName);
      const customerAddress = safeTrim(request.data?.customerAddress);
      const customerNotes = safeTrim(request.data?.customerNotes);

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

      const minimumNoticeHours = SHORT_NOTICE_APPROVAL_HOURS;
      const hoursBefore = (slotStart - new Date()) / (1000 * 60 * 60);
      const requiresBusinessApproval = hoursBefore < minimumNoticeHours;
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
      const serviceImageUrl = safeTrim(service.imageUrl || service.photoUrl || "");

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
      const bookingStatus = requiresBusinessApproval
        ? "pending_business_confirmation"
        : "confirmed";
      const approvalExpiresAt = requiresBusinessApproval
        ? admin.firestore.Timestamp.fromMillis(
            Date.now() + SHORT_NOTICE_APPROVAL_TIMEOUT_MINUTES * 60 * 1000
          )
        : null;
      const activeConversationRef =
        await activeBusinessCustomerConversationRef({ businessId, customerId });
      const activeConversationSnap = await activeConversationRef.get();
      const conversationId = activeConversationSnap.exists
        ? activeConversationRef.id
        : bookingId;

      await db.runTransaction(async (tx) => {
        const availabilityPostRef = availabilityPostId
          ? db.collection("availabilityPosts").doc(availabilityPostId)
          : null;

        if (availabilityPostRef) {
          const postSnap = await tx.get(availabilityPostRef);
          assert(postSnap.exists, "failed-precondition", "Availability no longer exists.");
          const post = postSnap.data() || {};
          assert(post.isActive === true && post.archived !== true, "failed-precondition", "Availability no longer exists.");
          assert(safeTrim(post.slotId) === slotId, "failed-precondition", "Availability no longer matches this slot.");
        }

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
    conversationId,
    businessId,
    customerId,
    serviceId,
    serviceName,
    serviceDurationMinutes,
    serviceImageUrl,

    staffId,
    staffName,

    customerName,
    customerAddress,
    customerNotes,

    addOns: cleanedAddOns,
    addOnsTotal,

    price: totalPrice,

    status: bookingStatus,
    requiresBusinessApproval,
    approvalExpiresAt,

    paymentMethod: "cash",

    paymentStatus: "pay_on_arrival",

    paymentIntentId: "",

    slotId,
    availabilityPostId,

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

    confirmedAt: requiresBusinessApproval
      ? null
      : admin.firestore.FieldValue.serverTimestamp(),

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

  if (availabilityPostRef) {
    tx.update(availabilityPostRef, {
      isActive: false,
      archived: true,
      archivedReason: "booked",
      bookingId,
      archivedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
});

const ownerId = business.ownerId;

if (ownerId) {

  await sendPushToUser(ownerId, {

    title: requiresBusinessApproval
      ? "New Last-Minute Request"
      : "New Booking",

    body: requiresBusinessApproval
      ? `${customerName || "A customer"} requested ${serviceName} soon. Please accept or decline within ${SHORT_NOTICE_APPROVAL_TIMEOUT_MINUTES} minutes.`
      : `${customerName || "A customer"} booked ${serviceName}.`,

    data: {
      bookingId,
      businessId,
      type: requiresBusinessApproval ? "last_minute_request" : "new_booking",
    },
    preferenceKey: "serviceBookingUpdates",
  });
}

await sendPushToUser(customerId, {

  title: requiresBusinessApproval
    ? "Booking request sent"
    : "Booking confirmed",

  body:
    requiresBusinessApproval
      ? `This appointment starts soon, so the business needs to confirm it. Most businesses respond within ${SHORT_NOTICE_APPROVAL_TIMEOUT_MINUTES} minutes.`
      : `Your booking for ${serviceName} is confirmed.`,

	  data: {
	    bookingId,
	    businessId,
	    type: requiresBusinessApproval ? "last_minute_request" : "booking_confirmed",
	  },
	  preferenceKey: "serviceBookingUpdates",
	});

await ensureBookingConversationDoc(bookingId, {
  conversationId,
  businessId,
  customerId,
  serviceId,
  serviceName,
  customerName,
  customerAddress,
  customerNotes,
  businessName: business.businessName || business.name || "Business",
  status: bookingStatus,
});

await updateRepeatCustomerSnapshot({
  customerId,
  businessId,
  serviceId,
  serviceName,
  customerAddress,
  customerNotes,
});

return {
  ok: true,
  bookingId,
  status: bookingStatus,
  requiresBusinessApproval,
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
      assert(request.auth, "unauthenticated", "Login required.");

      const provider = request.auth.token?.firebase?.sign_in_provider;
      if (provider === "anonymous") {
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
const availabilityPostId = safeTrim(request.data?.availabilityPostId);
const customerName = safeTrim(request.data?.customerName);
      const customerAddress = safeTrim(request.data?.customerAddress);
      const customerNotes = safeTrim(request.data?.customerNotes);

      const addOnIds = Array.isArray(request.data?.addOnIds)
  ? request.data.addOnIds.map(id => safeTrim(id)).filter(Boolean)
  : [];

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
        logger.warn("Booking slot does not exist");
        throw new HttpsError("failed-precondition", "Slot does not exist");
      }

      const slot = slotSnap.data();

      const isBooked =
        typeof slot.isBooked === "boolean"
          ? slot.isBooked
          : slot.isBooked === 1;

      if (isBooked) {
        logger.warn("Booking slot already booked");
        throw new HttpsError("failed-precondition", "Slot already booked");
      }

      if (!slot.startTime || !slot.startTime.toDate) {
        logger.warn("Invalid slot startTime");
        throw new HttpsError("internal", "Invalid slot data");
      }

      const slotStart = slot.startTime.toDate();


      if (slotStart < new Date()) {
        logger.warn("Booking slot is in the past");
        throw new HttpsError("failed-precondition", "Slot is in the past");
      }

	      const minimumNoticeHours = SHORT_NOTICE_APPROVAL_HOURS;
	      const hoursBefore = (slotStart - new Date()) / (1000 * 60 * 60);
	      const requiresBusinessApproval = hoursBefore < minimumNoticeHours;
	      const approvalExpiresAt = requiresBusinessApproval
	        ? admin.firestore.Timestamp.fromMillis(
	          Date.now() + SHORT_NOTICE_APPROVAL_TIMEOUT_MINUTES * 60 * 1000
	        )
	        : null;

	      // =================================================
      // VALIDATE BUSINESS / STRIPE
      // =================================================

      const businessSnap = await businessRef.get();
      assert(businessSnap.exists, "not-found", "Business not found.");

      const business = businessSnap.data() || {};
      const stripeAccountId = business.stripeAccountId;

      assert(stripeAccountId, "failed-precondition", "Stripe not connected.");

      const account = await stripe.accounts.retrieve(stripeAccountId);

      if (!account.charges_enabled) {
        throw new HttpsError(
          "failed-precondition",
          "Business cannot accept payments yet."
        );
      }

      // =================================================
      // VALIDATE STAFF
      // =================================================

      const active = await staffIsActiveServer(businessId, staffId);
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
      const serviceImageUrl = safeTrim(service.imageUrl || service.photoUrl || "");

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

      // =================================================
      // CREATE BOOKING ID
      // =================================================

      const bookingRef = db.collection("bookings").doc();
      const bookingId = bookingRef.id;
      const activeConversationRef =
        await activeBusinessCustomerConversationRef({ businessId, customerId });
      const activeConversationSnap = await activeConversationRef.get();
      const conversationId = activeConversationSnap.exists
        ? activeConversationRef.id
        : bookingId;

      // =================================================
      // TRANSACTION: LOCK SLOT + CREATE BOOKING
      // =================================================

      await db.runTransaction(async (tx) => {
        const availabilityPostRef = availabilityPostId
          ? db.collection("availabilityPosts").doc(availabilityPostId)
          : null;

        if (availabilityPostRef) {
          const postSnap = await tx.get(availabilityPostRef);
          assert(postSnap.exists, "failed-precondition", "Availability no longer exists.");
          const post = postSnap.data() || {};
          assert(post.isActive === true && post.archived !== true, "failed-precondition", "Availability no longer exists.");
          assert(safeTrim(post.slotId) === slotId, "failed-precondition", "Availability no longer matches this slot.");
        }

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
          conversationId,
          businessId,
          customerId,
          serviceId,
          serviceName,
          serviceDurationMinutes,
          serviceImageUrl,
          staffId,
          staffName,
          customerName,
          customerAddress,
          customerNotes,
          addOns: cleanedAddOns,
          addOnsTotal,
         price: totalPrice,
status: "pending_payment",
requiresBusinessApproval,
approvalExpiresAt,
paymentMethod: "stripe",
paymentStatus: "pending",
lockExpiresAt: expires,
slotId,
availabilityPostId,
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

        if (availabilityPostRef) {
          tx.update(availabilityPostRef, {
            isActive: false,
            archived: true,
            archivedReason: "booked",
            bookingId,
            archivedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }
      });

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

     await bookingRef.update({
  paymentIntentId: paymentIntent.id,
  paymentStatus: "payment_intent_created",
});

      await updateRepeatCustomerSnapshot({
        customerId,
        businessId,
        serviceId,
        serviceName,
        customerAddress,
        customerNotes,
      });

      return {
        clientSecret: paymentIntent.client_secret,
        bookingId,
      };

    } catch (error) {
      logger.error("createBookingPaymentIntent failed", error);

      if (error instanceof HttpsError) throw error;

      throw new HttpsError(
        "internal",
        error?.message || "Failed to create booking."
      );
    }
  }
);


exports.onBookingConversationSync = onDocumentUpdated(
  {
    document: "bookings/{bookingId}",
    region: "us-central1",
  },
  async (event) => {
    const after = event.data?.after.data();
    if (!after || !isBookingMessageStatus(after.status)) return;

    await ensureBookingConversationDoc(event.params.bookingId, after);
  }
);

exports.ensureBookingConversation = onCall(
  { region: "us-central1" },
  async (request) => {
    const bookingId = safeTrim(request.data?.bookingId);
    const result = await requireBookingConversationAccess(
      request.auth?.uid,
      bookingId
    );

    return {
      conversationId: result.conversationRef.id,
    };
  }
);

exports.ensureConversationAccess = onCall(
  { region: "us-central1" },
  async (request) => {
    const conversationId = safeTrim(request.data?.conversationId);
    const result = await requireConversationAccess(
      request.auth?.uid,
      conversationId
    );

    return {
      conversationId: result.conversationRef.id,
    };
  }
);

exports.createServiceEnquiry = onCall(
  { region: "us-central1" },
  async (request) => {
    const uid = request.auth?.uid;
    const businessId = safeTrim(request.data?.businessId);
    const serviceId = safeTrim(request.data?.serviceId);
    const text = safeTrim(request.data?.text);

    logger.info("Service enquiry started", {
      uid,
      businessId,
      serviceId,
      hasText: Boolean(text),
    });

    assert(uid, "unauthenticated", "Login required.");
    assert(businessId && serviceId, "invalid-argument", "Missing service data.");
    assert(text, "invalid-argument", "Please enter a message.");
    assert(text.length <= 2000, "invalid-argument", "Message is too long.");

    const businessRef = db.collection("businesses").doc(businessId);
    const businessSnap = await businessRef.get();
    assert(businessSnap.exists, "not-found", "Business not found.");

    const business = businessSnap.data() || {};
    const businessOwnerId =
      safeTrim(business.ownerId) ||
      safeTrim(business.businessOwnerId);
    logger.info("Service enquiry business resolved", {
      businessId,
      businessOwnerId,
      hasOwnerId: Boolean(safeTrim(business.ownerId)),
      hasBusinessOwnerId: Boolean(safeTrim(business.businessOwnerId)),
    });
    assert(businessOwnerId, "failed-precondition", "Business owner not found.");
    assert(businessOwnerId !== uid, "failed-precondition", "Businesses cannot start customer conversations.");

    const serviceSnap = await businessRef.collection("services").doc(serviceId).get();
    assert(serviceSnap.exists, "not-found", "Service not found.");

    const service = serviceSnap.data() || {};
    logger.info("Service enquiry service resolved", {
      businessId,
      serviceId,
      serviceName: safeTrim(service.name) || "Service",
    });
    const userSnap = await db.collection("users").doc(uid).get();
    const user = userSnap.data() || {};
    const customerName =
      safeTrim(user.name) ||
      safeTrim(user.displayName) ||
      safeTrim(request.auth?.token?.name) ||
      "Customer";
    const conversationRef = await activeBusinessCustomerConversationRef({
      businessId,
      customerId: uid,
    });
    const conversationId = conversationRef.id;
    const messageRef = conversationRef.collection("messages").doc();
    const now = admin.firestore.FieldValue.serverTimestamp();

    logger.info("Service enquiry conversation resolved", {
      businessId,
      serviceId,
      conversationId,
      messageId: messageRef.id,
    });

    await db.runTransaction(async (tx) => {
      const conversationSnap = await tx.get(conversationRef);
      const conversation = conversationSnap.data() || {};

      assert(conversation.archived !== true, "failed-precondition", "This conversation is archived.");
      assert(
        !conversationSnap.exists || conversation.customerId === uid,
        "permission-denied",
        "You cannot access this conversation."
      );

      tx.set(
        conversationRef,
        {
          bookingId: conversation.bookingId || "",
          currentBookingId: conversation.currentBookingId || conversation.bookingId || "",
          conversationType: conversation.conversationType || "service_enquiry",
          conversationStatus: conversation.conversationStatus || "enquiry",
          customerId: uid,
          businessId,
          businessOwnerId,
          businessName: safeTrim(business.businessName) || safeTrim(business.name) || "Business",
          customerName,
          originatingServiceId: conversation.originatingServiceId || serviceId,
          originatingServiceName: conversation.originatingServiceName || safeTrim(service.name) || "Service",
          serviceId: conversation.serviceId || serviceId,
          serviceName: conversation.serviceName || safeTrim(service.name) || "Service",
          serviceImageUrl: conversation.serviceImageUrl || safeTrim(service.imageUrl) || safeTrim(service.photoUrl),
          lastMessage: text,
          lastMessageAt: now,
          lastMessageId: messageRef.id,
          lastSenderId: uid,
          lastSenderType: "customer",
          unreadCustomerCount: conversation.unreadCustomerCount || 0,
          unreadBusinessCount: admin.firestore.FieldValue.increment(1),
          archived: false,
          customerHasMessaged: true,
          quotationStatus: conversation.quotationStatus || "none",
          acceptedQuotationId: conversation.acceptedQuotationId || "",
          quotationIds: Array.isArray(conversation.quotationIds) ? conversation.quotationIds : [],
          participants: [uid, businessOwnerId],
          createdAt: conversation.createdAt || now,
          updatedAt: now,
        },
        { merge: true }
      );

      tx.set(messageRef, {
        senderId: uid,
        senderType: "customer",
        text,
        timestamp: now,
        read: false,
        edited: false,
        deleted: false,
        attachments: [],
      });
    });

    logger.info("Service enquiry conversation written", {
      businessId,
      serviceId,
      conversationId,
      messageId: messageRef.id,
    });

    try {
      await sendPushToUser(businessOwnerId, {
        title: "New customer enquiry",
        body: text,
        data: {
          type: "service_enquiry",
          conversationId,
          businessId,
          serviceId,
        },
        preferenceKey: "serviceBookingUpdates",
      });
      logger.info("Service enquiry notification attempted", {
        businessOwnerId,
        conversationId,
      });
    } catch (error) {
      logger.error("Service enquiry notification failed after write", {
        businessOwnerId,
        conversationId,
        error: error?.message || String(error),
        code: error?.code || "unknown",
        stack: error?.stack || "",
      });
    }

    return {
      conversationId,
    };
  }
);

function communityHelpConversationId({ postId, ownerId, responderId }) {
  return `community_${postId}_${ownerId}_${responderId}`;
}

function isCommunityHelpActive(post) {
  const status = safeTrim(post.status) || "active";
  const activeStatuses = ["active", "open", "missing", "looking_for_owner"];
  if (post.isActive === false || !activeStatuses.includes(status)) return false;
  if (post.resolvedAt || status === "resolved" || status === "expired") return false;

  const expiresMillis = timestampToMillis(post.expiresAt);
  return expiresMillis === null || expiresMillis > Date.now();
}

function communityHelpContextLabel(post) {
  const mode = safeTrim(post.mode).toUpperCase();
  const title = safeTrim(post.title) || "Community Help post";
  if (mode === "FOUND") return `FOUND · ${title}`;
  if (mode === "LOST") return `LOST · ${title}`;
  if (safeTrim(post.type) === "free_item") return `FREE · ${title}`;
  return title;
}

function communityHelpSystemText({ responderName, post }) {
  const mode = safeTrim(post.mode);
  const category = safeTrim(post.itemCategory);
  if (mode === "lost" && category === "Pet") {
    return `${responderName} responded to your missing pet post.`;
  }
  if (mode === "lost") {
    return `${responderName} may have seen your lost item.`;
  }
  if (mode === "found" && category === "Pet") {
    return `${responderName} may know this pet or the owner.`;
  }
  if (mode === "found") {
    return `${responderName} thinks this may be their item.`;
  }
  if (mode === "wanted") {
    return `${responderName} may have something that helps.`;
  }
  return `${responderName} is interested in your free item.`;
}

function communityHelpNotification({ post }) {
  const mode = safeTrim(post.mode);
  const category = safeTrim(post.itemCategory);
  const location = safeTrim(post.publicLocation || post.location);
  const near = location ? ` near ${location}` : "";
  if (mode === "lost" && category === "Pet") {
    return {
      title: "Possible sighting",
      body: `Someone may have seen your missing pet${near}.`,
    };
  }
  if (mode === "lost") {
    return {
      title: "New response",
      body: "Open the conversation to see their message.",
    };
  }
  if (mode === "found") {
    return {
      title: "New response",
      body: "Open the conversation to check the details privately.",
    };
  }
  return {
    title: "New response",
    body: "Open the conversation to reply privately.",
  };
}

function numberFrom(value) {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function degreesToRadians(value) {
  return (value * Math.PI) / 180;
}

function distanceMilesBetweenPosts(a, b) {
  const aLat = numberFrom(a.approxLatitude);
  const aLng = numberFrom(a.approxLongitude);
  const bLat = numberFrom(b.approxLatitude);
  const bLng = numberFrom(b.approxLongitude);
  if (aLat === null || aLng === null || bLat === null || bLng === null) {
    return null;
  }

  const earthRadiusMiles = 3958.8;
  const dLat = degreesToRadians(bLat - aLat);
  const dLng = degreesToRadians(bLng - aLng);
  const lat1 = degreesToRadians(aLat);
  const lat2 = degreesToRadians(bLat);
  const h =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(lat1) * Math.cos(lat2) *
      Math.sin(dLng / 2) * Math.sin(dLng / 2);

  return earthRadiusMiles * 2 * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
}

function keywordOverlapCount(a, b) {
  const aWords = new Set(Array.isArray(a.keywords) ? a.keywords.map(safeTrim).filter(Boolean) : []);
  const bWords = new Set(Array.isArray(b.keywords) ? b.keywords.map(safeTrim).filter(Boolean) : []);
  let count = 0;
  for (const word of aWords) {
    if (bWords.has(word)) count += 1;
  }
  return count;
}

function communityHelpPostsMayMatch(a, b) {
  if (safeTrim(a.type) !== "lost_found" || safeTrim(b.type) !== "lost_found") return false;
  if (safeTrim(a.mode) === safeTrim(b.mode)) return false;
  if (safeTrim(a.itemCategory) !== safeTrim(b.itemCategory)) return false;
  if (!isCommunityHelpActive(a) || !isCommunityHelpActive(b)) return false;

  const distance = distanceMilesBetweenPosts(a, b);
  if (distance !== null) {
    const aRadius = numberFrom(a.discoveryRadiusMiles) ?? 5;
    const bRadius = numberFrom(b.discoveryRadiusMiles) ?? 5;
    return distance <= aRadius || distance <= bRadius;
  }

  const aLocation = safeTrim(a.publicLocation || a.location).toLowerCase();
  const bLocation = safeTrim(b.publicLocation || b.location).toLowerCase();
  const locationsOverlap =
    aLocation &&
    bLocation &&
    (aLocation.includes(bLocation) || bLocation.includes(aLocation));

  return locationsOverlap || keywordOverlapCount(a, b) > 0;
}

function communityHelpMatchNotification({ newPost, matchingPost }) {
  const newMode = safeTrim(newPost.mode);
  const newTitle = safeTrim(newPost.title) || "a nearby post";
  const matchingTitle = safeTrim(matchingPost.title) || "your post";

  if (newMode === "found") {
    return {
      title: `Possible match for ${matchingTitle}`,
      body: `Someone found ${newTitle} nearby. Open Community Help to check it.`,
    };
  }

  return {
    title: `Someone is missing ${newTitle}`,
    body: `It may match ${matchingTitle}. Open Community Help to check it.`,
  };
}

function communityAlertCategoryForPost(post) {
  if (safeTrim(post.type) !== "lost_found" || safeTrim(post.mode) !== "lost") {
    return null;
  }

  const category = safeTrim(post.itemCategory).toLowerCase();
  const title = safeTrim(post.title).toLowerCase();
  const description = safeTrim(post.description).toLowerCase();
  const combined = `${title} ${description}`;

  if (category === "pet") {
    if (combined.includes("dog") || combined.includes("puppy")) {
      return "missingDogs";
    }
    if (combined.includes("cat") || combined.includes("kitten")) {
      return "missingCats";
    }
    return "otherMissingPets";
  }

  if (["keys", "wallet", "phone", "bag", "bike / scooter"].includes(category)) {
    return "importantLostItems";
  }

  return "otherLostItems";
}

function communityAlertRadiusMilesForCategory(category) {
  if (category === "missingDogs") return 8;
  if (category === "missingCats") return 4;
  if (category === "otherMissingPets") return 5;
  if (category === "importantLostItems") return 2;
  return 1;
}

function communityAlertCopy(post) {
  const category = communityAlertCategoryForPost(post);
  const title = safeTrim(post.title) || "An item";
  const location = safeTrim(post.publicLocation || post.location);
  const near = location ? ` near ${location}` : " nearby";

  if (category === "missingDogs") {
    return {
      title: "Missing dog near you",
      body: `${title} was last seen${near}.`,
    };
  }
  if (category === "missingCats") {
    return {
      title: "Missing cat near you",
      body: `${title} was last seen${near}.`,
    };
  }
  if (category === "otherMissingPets") {
    return {
      title: "Missing pet near you",
      body: `${title} was last seen${near}.`,
    };
  }
  return {
    title: "Lost item near you",
    body: `${title} was reported missing${near}.`,
  };
}

const TEMPORARY_LOCALITY_MINIMUM_MS = 10 * 60 * 1000;
const TEMPORARY_LOCALITY_GRACE_MS = 2 * 60 * 60 * 1000;
const NEARBY_COMMUNITY_ALERT_DAILY_LIMIT = 3;

function communityAlertSubscriptionIsEligible(subscription, nowMs) {
  if (timestampToMillis(subscription.expiresAt) !== null &&
      timestampToMillis(subscription.expiresAt) <= nowMs) {
    return false;
  }

  const type = safeTrim(subscription.subscriptionType) || "chosenArea";
  if (type !== "temporaryArea") {
    return subscription.isActive === true;
  }

  const establishedAt =
    timestampToMillis(subscription.establishedAt) ??
    timestampToMillis(subscription.firstSeenAt);
  if (establishedAt === null ||
      nowMs - establishedAt < TEMPORARY_LOCALITY_MINIMUM_MS) {
    return false;
  }

  const leftAt = timestampToMillis(subscription.leftAt);
  if (leftAt !== null) {
    return nowMs - leftAt <= TEMPORARY_LOCALITY_GRACE_MS;
  }

  const lastSeenAt = timestampToMillis(subscription.lastSeenAt);
  if (lastSeenAt !== null) {
    return nowMs - lastSeenAt <= TEMPORARY_LOCALITY_GRACE_MS;
  }

  return subscription.isActive === true;
}

async function reserveNearbyCommunityAlertQuota(recipientId, nowMs) {
  const dayKey = new Date(nowMs).toISOString().slice(0, 10);
  const quotaRef = db
    .collection("users")
    .doc(recipientId)
    .collection("notificationDailyCaps")
    .doc(`nearbyCommunityAlerts_${dayKey}`);
  let allowed = false;

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(quotaRef);
    const count = numberFrom(snap.data()?.count) ?? 0;
    if (count >= NEARBY_COMMUNITY_ALERT_DAILY_LIMIT) return;

    tx.set(
      quotaRef,
      {
        count: count + 1,
        limit: NEARBY_COMMUNITY_ALERT_DAILY_LIMIT,
        preferenceKey: "nearbyCommunityAlerts",
        dayKey,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    allowed = true;
  });

  return allowed;
}

async function createAndSendCommunityAlertCampaign({ postId, post }) {
  const alertCategory = communityAlertCategoryForPost(post);
  if (!alertCategory || !isCommunityHelpActive(post)) {
    return;
  }

  const ownerId = safeTrim(post.createdBy);
  const campaignId = `${postId}_initial`;
  const campaignRef = db.collection("communityAlertCampaigns").doc(campaignId);
  const campaignSnap = await campaignRef.get();
  if (campaignSnap.exists && campaignSnap.data()?.status === "completed") {
    return;
  }

  const radiusMiles = communityAlertRadiusMilesForCategory(alertCategory);
  const now = admin.firestore.FieldValue.serverTimestamp();
  const nowMs = Date.now();

  await campaignRef.set(
    {
      postId,
      ownerId,
      alertCategory,
      radiusMiles,
      status: "running",
      source: "community_help_post_created",
      distributionTier: "freePreview",
      entitlementType: "freePreview",
      paymentRequired: false,
      paymentStatus: "not_required",
      imageUrl: safeTrim(post.photoUrl),
      createdAt: campaignSnap.exists ? campaignSnap.data()?.createdAt || now : now,
      startedAt: now,
      updatedAt: now,
    },
    { merge: true }
  );

  const subscriptionSnapshot = await db
    .collection("communityAlertSubscriptions")
    .where("communityAlertsEnabled", "==", true)
    .where("enabledCategories", "array-contains", alertCategory)
    .limit(500)
    .get();

  const copy = communityAlertCopy(post);
  let eligibleRecipientCount = 0;
  let sentCount = 0;
  let failedCount = 0;
  let cappedCount = 0;

  for (const subDoc of subscriptionSnapshot.docs) {
    const subscription = subDoc.data() || {};
    const recipientId = safeTrim(subscription.userId) || subDoc.id;
    if (!recipientId || recipientId === ownerId) continue;
    if (!communityAlertSubscriptionIsEligible(subscription, nowMs)) continue;

    const distance = distanceMilesBetweenPosts(
      {
        approxLatitude: post.approxLatitude,
        approxLongitude: post.approxLongitude,
      },
      {
        approxLatitude: subscription.approxLatitude,
        approxLongitude: subscription.approxLongitude,
      }
    );
    const recipientRadius = numberFrom(subscription.maxRadiusMiles) ?? 10;
    if (distance === null || distance > radiusMiles || distance > recipientRadius) {
      continue;
    }

    eligibleRecipientCount += 1;
    const recipientRef = campaignRef.collection("recipients").doc(recipientId);
    let shouldSend = false;
    await db.runTransaction(async (tx) => {
      const recipientSnap = await tx.get(recipientRef);
      if (recipientSnap.exists) return;

      tx.set(recipientRef, {
        userId: recipientId,
        status: "pending",
        distanceMiles: distance,
        createdAt: now,
      });
      shouldSend = true;
    });

    if (!shouldSend) continue;
    const quotaAllowed = await reserveNearbyCommunityAlertQuota(
      recipientId,
      nowMs
    );
    if (!quotaAllowed) {
      cappedCount += 1;
      await recipientRef.set({ status: "capped", cappedAt: now }, { merge: true });
      continue;
    }

    const notificationId = `community_alert_${campaignId}`;
    await db
      .collection("users")
      .doc(recipientId)
      .collection("notifications")
      .doc(notificationId)
      .set({
        type: "community_alert",
        title: copy.title,
        body: copy.body,
        communityHelpPostId: postId,
        campaignId,
        imageUrl: safeTrim(post.photoUrl),
        isRead: false,
        createdAt: now,
      });

    try {
      await sendPushToUser(recipientId, {
        title: copy.title,
        body: copy.body,
        imageUrl: safeTrim(post.photoUrl),
        preferenceKey: "nearbyCommunityAlerts",
        data: {
          type: "community_alert",
          communityHelpPostId: postId,
          campaignId,
          notificationId,
          imageUrl: safeTrim(post.photoUrl),
        },
      });
      sentCount += 1;
      await recipientRef.set({ status: "sent", sentAt: now }, { merge: true });
    } catch (error) {
      failedCount += 1;
      await recipientRef.set(
        {
          status: "failed",
          failedAt: now,
          error: safeTrim(error?.message).slice(0, 240),
        },
        { merge: true }
      );
    }
  }

  await campaignRef.set(
    {
      status: "completed",
      eligibleRecipientCount,
      sentCount,
      failedCount,
      cappedCount,
      completedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
}

exports.notifyCommunityHelpMatches = onDocumentCreated(
  {
    document: "communityHelpPosts/{postId}",
    region: "us-central1",
  },
  async (event) => {
    const newPost = event.data?.data() || {};
    if (safeTrim(newPost.type) !== "lost_found" || !isCommunityHelpActive(newPost)) {
      return;
    }

    const ownerId = safeTrim(newPost.createdBy);
    const oppositeMode = safeTrim(newPost.mode) === "lost" ? "found" : "lost";
    const snapshot = await db
      .collection("communityHelpPosts")
      .where("type", "==", "lost_found")
      .where("mode", "==", oppositeMode)
      .where("isActive", "==", true)
      .limit(400)
      .get();

    let notifiedCount = 0;
    for (const doc of snapshot.docs) {
      if (doc.id === event.params.postId) continue;
      const matchingPost = doc.data() || {};
      const matchingOwnerId = safeTrim(matchingPost.createdBy);
      if (!matchingOwnerId || matchingOwnerId === ownerId) continue;
      if (!communityHelpPostsMayMatch(newPost, matchingPost)) continue;

      const notification = communityHelpMatchNotification({
        newPost,
        matchingPost,
      });
      const notificationId = `community_help_match_${event.params.postId}_${doc.id}`;
      const notificationRef = db
        .collection("users")
        .doc(matchingOwnerId)
        .collection("notifications")
        .doc(notificationId);

      await notificationRef.set({
        type: "community_help_match",
        title: notification.title,
        body: notification.body,
        communityHelpPostId: doc.id,
        matchingCommunityHelpPostId: event.params.postId,
        imageUrl: safeTrim(matchingPost.photoUrl || newPost.photoUrl),
        isRead: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      await sendPushToUser(matchingOwnerId, {
        title: notification.title,
        body: notification.body,
        imageUrl: safeTrim(matchingPost.photoUrl || newPost.photoUrl),
        preferenceKey: "communityResponses",
        data: {
          type: "community_help_match",
          communityHelpPostId: doc.id,
          matchingCommunityHelpPostId: event.params.postId,
          notificationId,
          imageUrl: safeTrim(matchingPost.photoUrl || newPost.photoUrl),
        },
      });
      notifiedCount += 1;
      if (notifiedCount >= 20) break;
    }

    logger.info("Community Help match notifications processed", {
      postId: event.params.postId,
      notifiedCount,
    });

    await createAndSendCommunityAlertCampaign({
      postId: event.params.postId,
      post: newPost,
    });
  }
);

exports.createCommunityHelpConversation = onCall(
  { region: "us-central1" },
  async (request) => {
    const uid = request.auth?.uid;
    const postId = safeTrim(request.data?.postId);
    const text = safeTrim(request.data?.text);
    const sightingPhotoUrl = safeTrim(request.data?.sightingPhotoUrl);

    assert(uid, "unauthenticated", "Login required.");
    assert(postId, "invalid-argument", "Missing Community Help post.");
    assert(text, "invalid-argument", "Please enter a message.");
    assert(text.length <= 2000, "invalid-argument", "Message is too long.");

    const postRef = db.collection("communityHelpPosts").doc(postId);
    const postSnap = await postRef.get();
    assert(postSnap.exists, "not-found", "Community Help post not found.");

    const post = postSnap.data() || {};
    const ownerId = safeTrim(post.createdBy);
    assert(ownerId, "failed-precondition", "This post is missing an owner.");
    assert(ownerId !== uid, "failed-precondition", "You cannot respond to your own post.");
    assert(isCommunityHelpActive(post), "failed-precondition", "This post is no longer active.");

    const [ownerSnap, responderSnap] = await Promise.all([
      db.collection("users").doc(ownerId).get(),
      db.collection("users").doc(uid).get(),
    ]);
    const owner = ownerSnap.data() || {};
    const responder = responderSnap.data() || {};
    const ownerName =
      safeTrim(owner.name) ||
      safeTrim(owner.displayName) ||
      "LocalLink member";
    const responderName =
      safeTrim(responder.name) ||
      safeTrim(responder.displayName) ||
      safeTrim(request.auth?.token?.name) ||
      "LocalLink member";

    const conversationId = communityHelpConversationId({
      postId,
      ownerId,
      responderId: uid,
    });
    const conversationRef = db.collection("conversations").doc(conversationId);
    const systemMessageRef = conversationRef.collection("messages").doc("context");
    const userMessageRef = conversationRef.collection("messages").doc();
    const responseRef = postRef.collection("responses").doc(uid);
    const now = admin.firestore.FieldValue.serverTimestamp();
    let createdConversation = false;

    await db.runTransaction(async (tx) => {
      const freshPostSnap = await tx.get(postRef);
      assert(freshPostSnap.exists, "not-found", "Community Help post not found.");
      const freshPost = freshPostSnap.data() || {};
      assert(isCommunityHelpActive(freshPost), "failed-precondition", "This post is no longer active.");
      assert(safeTrim(freshPost.createdBy) === ownerId, "failed-precondition", "Post owner changed.");

      const conversationSnap = await tx.get(conversationRef);
      const conversation = conversationSnap.data() || {};
      createdConversation = !conversationSnap.exists;

      tx.set(
        conversationRef,
        {
          conversationStatus: "community_help",
          conversationType: "community_help",
          customerId: uid,
          businessOwnerId: ownerId,
          businessId: "",
          bookingId: "",
          currentBookingId: "",
          customerName: responderName,
          businessName: ownerName,
          originatingServiceId: "",
          originatingServiceName: "Community Help",
          currentBookingServiceName: communityHelpContextLabel(freshPost),
          serviceId: "",
          serviceName: "Community Help",
          serviceImageUrl: safeTrim(freshPost.photoUrl),
          lastMessage: text,
          lastMessageAt: now,
          lastMessageId: userMessageRef.id,
          lastSenderId: uid,
          lastSenderType: "customer",
          unreadCustomerCount: conversation.unreadCustomerCount || 0,
          unreadBusinessCount: admin.firestore.FieldValue.increment(1),
          archived: false,
          customerHasMessaged: true,
          quotationStatus: "none",
          acceptedQuotationId: "",
          quotationIds: [],
          participants: [uid, ownerId],
          communityHelpParticipantIds: [uid, ownerId],
          communityHelpPostId: postId,
          communityHelpType: safeTrim(freshPost.type),
          communityHelpMode: safeTrim(freshPost.mode),
          communityHelpTitle: safeTrim(freshPost.title),
          communityHelpLocation: safeTrim(freshPost.publicLocation) || safeTrim(freshPost.location),
          communityHelpLifecycleKind: safeTrim(freshPost.lifecycleKind),
          communityHelpOwnerId: ownerId,
          communityHelpResponderId: uid,
          createdAt: conversation.createdAt || now,
          updatedAt: now,
        },
        { merge: true }
      );

      if (!conversationSnap.exists) {
        tx.set(systemMessageRef, {
          senderId: "system",
          senderType: "system",
          text: communityHelpSystemText({
            responderName,
            post: freshPost,
          }),
          timestamp: now,
          read: false,
          edited: false,
          deleted: false,
          attachments: [],
          systemEvent: "community_help_response_started",
        });
      }

      tx.set(userMessageRef, {
        senderId: uid,
        senderType: "customer",
        text,
        timestamp: now,
        read: false,
        edited: false,
        deleted: false,
        attachments: sightingPhotoUrl
          ? [
              {
                type: "image",
                url: sightingPhotoUrl,
                visibility: "private",
                purpose: "community_help_sighting",
              },
            ]
          : [],
      });

      tx.set(
        responseRef,
        {
          postId,
          postOwnerId: ownerId,
          responderId: uid,
          responderName,
          conversationId,
          message: text,
          status: "conversation_open",
          createdAt: conversation.createdAt || now,
          updatedAt: now,
        },
        { merge: true }
      );
    });

    if (createdConversation) {
      const notification = communityHelpNotification({ post });
      const notificationType = sightingPhotoUrl
        ? "community_help_sighting"
        : "community_help_response";
      const notificationRef = db
        .collection("users")
        .doc(ownerId)
        .collection("notifications")
        .doc(`community_help_${conversationId}`);

      await notificationRef.set({
        type: notificationType,
        title: notification.title,
        body: notification.body,
        communityHelpPostId: postId,
        conversationId,
        viewerType: "business",
        imageUrl: safeTrim(post.photoUrl),
        isRead: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      await sendPushToUser(ownerId, {
        title: notification.title,
        body: notification.body,
        imageUrl: safeTrim(post.photoUrl),
        preferenceKey: "communityResponses",
        data: {
          type: notificationType,
          conversationId,
          bookingId: "",
          viewerType: "business",
          communityHelpPostId: postId,
          notificationId: `community_help_${conversationId}`,
          imageUrl: safeTrim(post.photoUrl),
        },
      });
    }

    return {
      conversationId,
      created: createdConversation,
    };
  }
);

exports.followCommunityHelpPost = onCall(
  { region: "us-central1" },
  async (request) => {
    const uid = request.auth?.uid;
    const postId = safeTrim(request.data?.postId);
    assert(uid, "unauthenticated", "Login required.");
    assert(postId, "invalid-argument", "Missing Community Help post.");

    const postRef = db.collection("communityHelpPosts").doc(postId);
    const followerRef = postRef.collection("followers").doc(uid);
    let post = null;
    let createdFollow = false;
    await db.runTransaction(async (tx) => {
      const postSnap = await tx.get(postRef);
      assert(postSnap.exists, "not-found", "Community Help post not found.");
      post = postSnap.data() || {};
      assert(safeTrim(post.createdBy) !== uid, "failed-precondition", "You already own this post.");
      assert(isCommunityHelpActive(post), "failed-precondition", "This post is no longer active.");

      const followerSnap = await tx.get(followerRef);
      if (!followerSnap.exists) {
        createdFollow = true;
        tx.set(followerRef, {
          userId: uid,
          postId,
          notificationState: "active",
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        tx.set(
          postRef,
          {
            lookoutCount: admin.firestore.FieldValue.increment(1),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
      }
    });

    const ownerId = safeTrim(post?.createdBy);
    if (createdFollow && ownerId && ownerId !== uid) {
      const notificationId = `community_help_lookout_${postId}_${uid}`;
      const title = "Someone is keeping a lookout";
      const body = "A LocalLink member is now following updates on your Community Help post.";
      await db
        .collection("users")
        .doc(ownerId)
        .collection("notifications")
        .doc(notificationId)
        .set({
          type: "community_help_lookout",
          title,
          body,
          communityHelpPostId: postId,
          followerId: uid,
          imageUrl: safeTrim(post.photoUrl),
          isRead: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

      await sendPushToUser(ownerId, {
        title,
        body,
        imageUrl: safeTrim(post.photoUrl),
        preferenceKey: "communityResponses",
        data: {
          type: "community_help_lookout",
          communityHelpPostId: postId,
          followerId: uid,
          notificationId,
          imageUrl: safeTrim(post.photoUrl),
        },
      });
    }

    return { following: true };
  }
);

exports.unfollowCommunityHelpPost = onCall(
  { region: "us-central1" },
  async (request) => {
    const uid = request.auth?.uid;
    const postId = safeTrim(request.data?.postId);
    assert(uid, "unauthenticated", "Login required.");
    assert(postId, "invalid-argument", "Missing Community Help post.");

    const postRef = db.collection("communityHelpPosts").doc(postId);
    const followerRef = postRef.collection("followers").doc(uid);
    await db.runTransaction(async (tx) => {
      const followerSnap = await tx.get(followerRef);
      if (!followerSnap.exists) return;

      tx.delete(followerRef);
      tx.set(
        postRef,
        {
          lookoutCount: admin.firestore.FieldValue.increment(-1),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    });

    return { following: false };
  }
);

async function notifyCommunityHelpFollowers({ postId, post, title, body, updateId }) {
  const followers = await db
    .collection("communityHelpPosts")
    .doc(postId)
    .collection("followers")
    .where("notificationState", "==", "active")
    .limit(500)
    .get();

  for (const followerDoc of followers.docs) {
    const followerId = safeTrim(followerDoc.data()?.userId) || followerDoc.id;
    if (!followerId || followerId === safeTrim(post.createdBy)) continue;

    const notificationId = updateId
      ? `community_help_update_${postId}_${updateId}`
      : `community_help_resolved_${postId}`;
    await db
      .collection("users")
      .doc(followerId)
      .collection("notifications")
      .doc(notificationId)
      .set({
        type: updateId ? "community_help_update" : "community_help_resolved",
        title,
        body,
        communityHelpPostId: postId,
        updateId: updateId || "",
        imageUrl: safeTrim(post.photoUrl),
        isRead: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

    await sendPushToUser(followerId, {
      title,
      body,
      imageUrl: safeTrim(post.photoUrl),
      preferenceKey: "communityFollowing",
      data: {
        type: updateId ? "community_help_update" : "community_help_resolved",
        communityHelpPostId: postId,
        updateId: updateId || "",
        notificationId,
        imageUrl: safeTrim(post.photoUrl),
      },
    });
  }
}

exports.publishCommunityHelpUpdate = onCall(
  { region: "us-central1" },
  async (request) => {
    const uid = request.auth?.uid;
    const postId = safeTrim(request.data?.postId);
    const text = safeTrim(request.data?.text);
    assert(uid, "unauthenticated", "Login required.");
    assert(postId, "invalid-argument", "Missing Community Help post.");
    assert(text, "invalid-argument", "Write a short update.");
    assert(text.length <= 240, "invalid-argument", "Keep updates under 240 characters.");

    const postRef = db.collection("communityHelpPosts").doc(postId);
    const updateRef = postRef.collection("updates").doc();
    const now = admin.firestore.FieldValue.serverTimestamp();
    let post = null;

    await db.runTransaction(async (tx) => {
      const postSnap = await tx.get(postRef);
      assert(postSnap.exists, "not-found", "Community Help post not found.");
      post = postSnap.data() || {};
      assert(safeTrim(post.createdBy) === uid, "permission-denied", "Only the post owner can publish updates.");
      assert(isCommunityHelpActive(post), "failed-precondition", "This post is not active.");

      const lastUpdateMillis = timestampToMillis(post.lastPublicUpdateAt);
      assert(
        lastUpdateMillis === null || Date.now() - lastUpdateMillis > 30 * 60 * 1000,
        "resource-exhausted",
        "Please wait before posting another update."
      );

      tx.set(updateRef, {
        postId,
        ownerId: uid,
        text,
        type: "owner_update",
        createdAt: now,
        imageUrl: safeTrim(post.photoUrl),
      });
      tx.set(
        postRef,
        {
          lastPublicUpdateAt: now,
          lastPublicUpdateText: text,
          updatedAt: now,
        },
        { merge: true }
      );
    });

    await notifyCommunityHelpFollowers({
      postId,
      post,
      title: `Update on ${safeTrim(post.title) || "Community Help"}`,
      body: text,
      updateId: updateRef.id,
    });

    return { ok: true, updateId: updateRef.id };
  }
);

exports.notifyCommunityHelpResolved = onDocumentUpdated(
  {
    document: "communityHelpPosts/{postId}",
    region: "us-central1",
  },
  async (event) => {
    const before = event.data?.before.data() || {};
    const after = event.data?.after.data() || {};
    const wasResolved = before.status === "resolved" || before.resolvedAt;
    const isResolved = after.status === "resolved" || after.resolvedAt;
    if (wasResolved || !isResolved || after.followerResolutionNotifiedAt) return;

    const title = safeTrim(after.title) || "This alert";
    const isPet = safeTrim(after.itemCategory) === "Pet";
    const notificationTitle = isPet
      ? `${title} has been found`
      : `Good news — ${title} was found`;
    const body =
      safeTrim(after.closingUpdate) ||
      (isPet
        ? `${title} has been reunited.`
        : "This Community Help alert has been resolved.");

    await notifyCommunityHelpFollowers({
      postId: event.params.postId,
      post: after,
      title: notificationTitle,
      body,
    });

    await event.data.after.ref.set(
      {
        followerResolutionNotifiedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  }
);

function communityHelpExpiryReminderCopy(post) {
  const mode = safeTrim(post.mode);
  const type = safeTrim(post.type);
  const category = safeTrim(post.itemCategory);
  const title = safeTrim(post.title) || "your post";

  if (mode === "lost" && category === "Pet") {
    return {
      title: "Still missing?",
      body: `Your missing pet post expires tomorrow. Keep it active if you're still looking.`,
    };
  }
  if (mode === "lost") {
    return {
      title: "Still looking?",
      body: `Your lost item post expires tomorrow.`,
    };
  }
  if (mode === "found") {
    return {
      title: "Still looking for the owner?",
      body: `Your found item post expires tomorrow.`,
    };
  }
  if (type === "free_item") {
    return {
      title: "Still available?",
      body: `Your free item post expires tomorrow.`,
    };
  }
  return {
    title: "Community Help post expiring",
    body: `${title} expires tomorrow.`,
  };
}

exports.processCommunityHelpLifecycle = onSchedule(
  {
    schedule: "every 60 minutes",
    region: "us-central1",
  },
  async () => {
    const now = admin.firestore.Timestamp.now();
    const activeStatuses = ["active", "open", "missing", "looking_for_owner"];

    const expiredSnapshot = await db
      .collection("communityHelpPosts")
      .where("isActive", "==", true)
      .where("status", "in", activeStatuses)
      .where("expiresAt", "<=", now)
      .limit(300)
      .get();

    let expiredCount = 0;
    for (const doc of expiredSnapshot.docs) {
      const data = doc.data() || {};
      if (data.resolvedAt || data.status === "resolved" || data.status === "expired") {
        continue;
      }

      await doc.ref.set(
        {
          status: "expired",
          isActive: false,
          expiredAt: admin.firestore.FieldValue.serverTimestamp(),
          expiryReminderStatus:
            data.expiryReminderStatus === "sent" ? "sent" : "cancelled",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      expiredCount += 1;
    }

    const reminderSnapshot = await db
      .collection("communityHelpPosts")
      .where("isActive", "==", true)
      .where("status", "in", activeStatuses)
      .where("expiryReminderStatus", "==", "pending")
      .where("expiryReminderAt", "<=", now)
      .limit(300)
      .get();

    let reminderCount = 0;
    for (const doc of reminderSnapshot.docs) {
      const data = doc.data() || {};
      const ownerId = safeTrim(data.createdBy);
      const expiresAtMillis = timestampToMillis(data.expiresAt);
      if (!ownerId || data.resolvedAt || data.status === "resolved") continue;
      if (expiresAtMillis !== null && expiresAtMillis <= Date.now()) continue;

      const copy = communityHelpExpiryReminderCopy(data);
      const notificationId = `community_help_expiry_${doc.id}_${expiresAtMillis || "legacy"}`;
      const notificationRef = db
        .collection("users")
        .doc(ownerId)
        .collection("notifications")
        .doc(notificationId);
      let reminderCreated = false;

      await db.runTransaction(async (tx) => {
        const freshPostSnap = await tx.get(doc.ref);
        const freshPost = freshPostSnap.data() || {};
        if (
          !freshPostSnap.exists ||
          freshPost.expiryReminderStatus !== "pending" ||
          freshPost.isActive === false ||
          freshPost.resolvedAt ||
          freshPost.status === "resolved" ||
          freshPost.status === "expired"
        ) {
          return;
        }

        const freshExpiresAtMillis = timestampToMillis(freshPost.expiresAt);
        if (freshExpiresAtMillis !== null && freshExpiresAtMillis <= Date.now()) {
          return;
        }

        tx.set(notificationRef, {
          type: "community_help_expiry",
          title: copy.title,
          body: copy.body,
          communityHelpPostId: doc.id,
          imageUrl: safeTrim(freshPost.photoUrl),
          isRead: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        tx.set(
          doc.ref,
          {
            expiryReminderStatus: "sent",
            expiryReminderSentAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
        reminderCreated = true;
      });

      if (reminderCreated) {
        reminderCount += 1;
        await sendPushToUser(ownerId, {
          title: copy.title,
          body: copy.body,
          imageUrl: safeTrim(data.photoUrl),
          preferenceKey: "reminders",
          data: {
            type: "community_help_expiry",
            communityHelpPostId: doc.id,
            notificationId,
            imageUrl: safeTrim(data.photoUrl),
          },
        });
      }
    }

    logger.info("Community Help lifecycle processed", {
      expiredCount,
      reminderCount,
    });
  }
);

exports.sendBookingMessage = onCall(
  { region: "us-central1" },
  async (request) => {
    const uid = request.auth?.uid;
    const conversationId = safeTrim(request.data?.conversationId) || safeTrim(request.data?.bookingId);
    const text = safeTrim(request.data?.text);

    assert(text, "invalid-argument", "Message cannot be empty.");
    assert(text.length <= 2000, "invalid-argument", "Message is too long.");

    const {
      conversationRef,
      conversation,
      senderType,
      recipientId,
    } = await requireConversationAccess(uid, conversationId);

    assert(conversation.archived !== true, "failed-precondition", "This conversation is archived.");
    assert(
      senderType === "customer" || conversation.customerHasMessaged === true,
      "failed-precondition",
      "Customers must start the conversation."
    );

    const messageRef = conversationRef.collection("messages").doc();
    const now = admin.firestore.FieldValue.serverTimestamp();

    await db.runTransaction(async (tx) => {
      const freshConversationSnap = await tx.get(conversationRef);
      const freshConversation = freshConversationSnap.data() || {};

      if (freshConversation.archived === true) {
        throw new HttpsError("failed-precondition", "This conversation is archived.");
      }

      tx.set(messageRef, {
        senderId: uid,
        senderType,
        text,
        timestamp: now,
        read: false,
        edited: false,
        deleted: false,
        attachments: [],
      });

      tx.set(
        conversationRef,
        {
          lastMessage: text,
          lastMessageAt: now,
          updatedAt: now,
          lastMessageId: messageRef.id,
          lastSenderId: uid,
          lastSenderType: senderType,
          customerHasMessaged: senderType === "customer"
            ? true
            : freshConversation.customerHasMessaged === true,
          unreadCustomerCount: senderType === "business"
            ? admin.firestore.FieldValue.increment(1)
            : freshConversation.unreadCustomerCount || 0,
          unreadBusinessCount: senderType === "customer"
            ? admin.firestore.FieldValue.increment(1)
            : freshConversation.unreadBusinessCount || 0,
        },
        { merge: true }
      );
    });

    const isCommunityHelpConversation =
      conversation.conversationType === "community_help" ||
      conversation.conversationStatus === "community_help";
    const notificationType = isCommunityHelpConversation
      ? "community_help_message"
      : "booking_message";
    const notificationTitle = isCommunityHelpConversation
      ? "New Community Help message"
      : senderType === "customer"
        ? "New customer enquiry"
        : conversation.conversationStatus === "enquiry"
          ? "Business replied to your enquiry"
          : "New business message";
    const notificationBody = isCommunityHelpConversation
      ? "Open LocalLink to read and reply privately."
      : text;
    const notificationId = `${notificationType}_${conversationRef.id}_${messageRef.id}`;

    await db
      .collection("users")
      .doc(recipientId)
      .collection("notifications")
      .doc(notificationId)
      .set({
        type: notificationType,
        title: notificationTitle,
        body: notificationBody,
        bookingId: conversation.bookingId || "",
        conversationId: conversationRef.id,
        messageId: messageRef.id,
        viewerType: senderType === "customer" ? "business" : "customer",
        communityHelpPostId: conversation.communityHelpPostId || "",
        imageUrl: isCommunityHelpConversation
          ? safeTrim(conversation.serviceImageUrl)
          : "",
        isRead: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

    await sendPushToUser(recipientId, {
      title: notificationTitle,
      body: notificationBody,
      imageUrl: isCommunityHelpConversation
        ? safeTrim(conversation.serviceImageUrl)
        : "",
      preferenceKey: isCommunityHelpConversation
        ? "communityMessages"
        : "serviceBookingUpdates",
      data: {
        type: notificationType,
        bookingId: conversation.bookingId || "",
        conversationId: conversationRef.id,
        messageId: messageRef.id,
        viewerType: senderType === "customer" ? "business" : "customer",
        communityHelpPostId: conversation.communityHelpPostId || "",
        notificationId,
      },
    });

    return {
      ok: true,
      messageId: messageRef.id,
    };
  }
);

exports.markBookingConversationRead = onCall(
  { region: "us-central1" },
  async (request) => {
    const conversationId = safeTrim(request.data?.conversationId) || safeTrim(request.data?.bookingId);
    const {
      conversationRef,
      senderType,
    } = await requireConversationAccess(request.auth?.uid, conversationId);

    const unreadField = senderType === "customer"
      ? "unreadCustomerCount"
      : "unreadBusinessCount";
    const oppositeSenderType = senderType === "customer"
      ? "business"
      : "customer";

    const unreadMessages = await conversationRef
      .collection("messages")
      .where("read", "==", false)
      .limit(100)
      .get();

    const batch = db.batch();

    batch.set(
      conversationRef,
      {
        [unreadField]: 0,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    unreadMessages.docs
      .filter((doc) => doc.data()?.senderType === oppositeSenderType)
      .forEach((doc) => {
      batch.update(doc.ref, {
        read: true,
      });
    });

    await batch.commit();

    return { ok: true };
  }
);

exports.editBookingMessage = onCall(
  { region: "us-central1" },
  async (request) => {
    const uid = request.auth?.uid;
    const conversationId = safeTrim(request.data?.conversationId) || safeTrim(request.data?.bookingId);
    const messageId = safeTrim(request.data?.messageId);
    const text = safeTrim(request.data?.text);

    assert(messageId, "invalid-argument", "Missing messageId.");
    assert(text, "invalid-argument", "Message cannot be empty.");
    assert(text.length <= 2000, "invalid-argument", "Message is too long.");

    const { conversationRef, conversation } =
      await requireConversationAccess(uid, conversationId);

    assert(conversation.archived !== true, "failed-precondition", "This conversation is archived.");

    const messageRef = conversationRef.collection("messages").doc(messageId);

    await db.runTransaction(async (tx) => {
      const messageSnap = await tx.get(messageRef);

      assert(messageSnap.exists, "not-found", "Message not found.");

      const message = messageSnap.data() || {};
      const sentAt = timestampToMillis(message.timestamp);
      const withinEditWindow =
        sentAt !== null && Date.now() - sentAt <= 5 * 60 * 1000;

      assert(message.senderId === uid, "permission-denied", "You can only edit your own messages.");
      assert(message.deleted !== true, "failed-precondition", "Deleted messages cannot be edited.");
      assert(withinEditWindow, "failed-precondition", "Messages can only be edited for 5 minutes.");

      tx.update(messageRef, {
        text,
        edited: true,
        editedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      const conversationSnap = await tx.get(conversationRef);
      const currentConversation = conversationSnap.data() || {};

      if (currentConversation.archived === true) {
        throw new HttpsError("failed-precondition", "This conversation is archived.");
      }

      if (currentConversation.lastMessageId === messageId) {
        tx.set(
          conversationRef,
          {
            lastMessage: text,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
      }
    });

    return { ok: true };
  }
);

exports.deleteBookingMessage = onCall(
  { region: "us-central1" },
  async (request) => {
    const uid = request.auth?.uid;
    const conversationId = safeTrim(request.data?.conversationId) || safeTrim(request.data?.bookingId);
    const messageId = safeTrim(request.data?.messageId);

    assert(messageId, "invalid-argument", "Missing messageId.");

    const { conversationRef, conversation } =
      await requireConversationAccess(uid, conversationId);

    assert(conversation.archived !== true, "failed-precondition", "This conversation is archived.");

    const messageRef = conversationRef.collection("messages").doc(messageId);

    await db.runTransaction(async (tx) => {
      const messageSnap = await tx.get(messageRef);

      assert(messageSnap.exists, "not-found", "Message not found.");

      const message = messageSnap.data() || {};

      assert(message.senderId === uid, "permission-denied", "You can only delete your own messages.");

      tx.update(messageRef, {
        text: "",
        deleted: true,
        deletedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      const conversationSnap = await tx.get(conversationRef);
      const currentConversation = conversationSnap.data() || {};

      if (currentConversation.archived === true) {
        throw new HttpsError("failed-precondition", "This conversation is archived.");
      }

      if (currentConversation.lastMessageId === messageId) {
        tx.set(
          conversationRef,
          {
            lastMessage: "Message deleted",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
      }
    });

    return { ok: true };
  }
);

exports.archiveCompletedBookingConversations = onSchedule(
  {
    schedule: "every 24 hours",
    region: "us-central1",
  },
  async () => {
    const cutoff = admin.firestore.Timestamp.fromMillis(
      Date.now() - 90 * 24 * 60 * 60 * 1000
    );

    const snap = await db.collection("bookings")
      .where("status", "==", "completed")
      .where("completedAt", "<=", cutoff)
      .limit(300)
      .get();

    if (snap.empty) return;

    const batch = db.batch();

    for (const doc of snap.docs) {
      await ensureBookingConversationDoc(doc.id, doc.data() || {});

      batch.set(
        bookingConversationRef(doc.id),
        {
          archived: true,
          archivedAt: admin.firestore.FieldValue.serverTimestamp(),
          bookingStatus: "completed",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    }

    await batch.commit();
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
        const directAvailability = pi.metadata?.directAvailability === "true";

        console.log("💰 PAYMENT SUCCEEDED:", bookingId);

        if (!bookingId || !businessId || (!directAvailability && (!staffId || !slotId))) {
          console.error("❌ Missing metadata on payment_intent:", pi.id, pi.metadata);
          return res.json({ received: true });
        }

        const bookingRef = db.collection("bookings").doc(bookingId);

        await db.runTransaction(async (tx) => {
          await finalizePaidBookingInTransaction({
            tx,
            bookingRef,
            bookingId,
            paymentMetadata: {
              businessId,
              staffId,
              slotId,
              directAvailability: String(directAvailability),
            },
          });
        });

        const updatedSnap = await bookingRef.get();
        const booking = updatedSnap.data();

        if (booking) {
          await ensureBookingConversationDoc(bookingId, booking);
        }

        if (booking && booking.customerId && businessId) {
          const businessSnap = await db.collection("businesses").doc(businessId).get();
          const ownerId = businessSnap.data()?.ownerId;
          const awaitingApproval = booking.status === "pending_business_confirmation";

          await sendPushToUser(booking.customerId, {
            title: awaitingApproval
              ? "Booking request sent"
              : "Booking confirmed",
            body: awaitingApproval
              ? `This appointment starts soon, so the business needs to confirm it. Most businesses respond within ${SHORT_NOTICE_APPROVAL_TIMEOUT_MINUTES} minutes.`
              : `Your booking for ${booking.serviceName} is confirmed`,
            data: {
              bookingId,
              businessId,
              type: awaitingApproval ? "last_minute_request" : "booking_confirmed"
            },
            preferenceKey: "serviceBookingUpdates",
          });

          if (ownerId) {
            await sendPushToUser(ownerId, {
              title: awaitingApproval
                ? "New Last-Minute Request"
                : "Booking Confirmed",
              body: awaitingApproval
                ? `${booking.customerName || "A customer"} booked ${booking.serviceName || "a service"} soon. Please accept or decline within ${SHORT_NOTICE_APPROVAL_TIMEOUT_MINUTES} minutes.`
                : `${booking.customerName || "A customer"} has a confirmed booking for ${booking.serviceName || "a service"}.`,
	              data: {
	                bookingId,
	                businessId,
	                type: awaitingApproval ? "last_minute_request" : "booking_confirmed"
	              },
	              preferenceKey: "serviceBookingUpdates",
	            });
          }
        }

        console.log("✅ PAYMENT BOOKING UPDATED:", bookingId);
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

  const directAvailability =
    pi.metadata?.directAvailability === "true";

  if (
    !bookingId ||
    !businessId ||
    (!directAvailability && (!slotId || !staffId))
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

    if (booking.directAvailability === true) {
      await restoreDirectAvailabilityInTransaction(tx, bookingRef, booking, bookingId);
      tx.update(bookingRef, {
        status: "payment_failed",
        paymentStatus: "failed",
        cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      return;
    }

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

    tx.update(bookingRef, {

      status: "payment_failed",

      paymentStatus: "failed",

      cancelledAt:
        admin.firestore.FieldValue
          .serverTimestamp(),
    });
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
	    preferenceKey: "serviceBookingUpdates",
	    data: {
	      type: "payment_failed",
	      bookingId,
	    },
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
  {
    schedule: "every 5 minutes",
    region: "us-central1",
    secrets: ["STRIPE_SECRET_KEY"],
  },
  async () => {
    const stripe = getStripe();
    const snap = await db
      .collection("bookings")
      .where("status", "==", "pending_payment")
      .where("lockExpiresAt", "<", new Date())
      .get();

    if (snap.empty) return;

    let cancelled = 0;
    let reconciled = 0;
    let deferred = 0;

    for (const doc of snap.docs) {
      const booking = doc.data() || {};

      if (booking.paymentMethod !== "stripe") {
        continue;
      }

      const paymentIntentState = await retrievePendingPaymentIntentForCleanup(
        stripe,
        { ...booking, bookingId: doc.id }
      );

      if (paymentIntentState.decision === "retry_later") {
        deferred += 1;
        continue;
      }

      if (paymentIntentState.decision === "keep_pending") {
        deferred += 1;
        logger.info("Pending booking cleanup deferred by Stripe state", {
          bookingId: doc.id,
          paymentIntentStatus: paymentIntentState.reason,
        });
        continue;
      }

      if (paymentIntentState.decision === "reconcile_paid") {
        const outcome = await db.runTransaction(async (tx) => {
          return finalizePaidBookingInTransaction({
            tx,
            bookingRef: doc.ref,
            bookingId: doc.id,
            paymentMetadata: {
              businessId: booking.businessId,
              staffId: booking.staffId,
              slotId: booking.slotId,
              directAvailability: String(booking.directAvailability === true),
            },
          });
        });

        if (outcome.changed) {
          reconciled += 1;
          logger.info("Pending booking reconciled from Stripe success", {
            bookingId: doc.id,
            status: outcome.status,
          });
        }

        continue;
      }

      await cancelAbandonedPaymentIntentIfNeeded(
        stripe,
        paymentIntentState.paymentIntent,
        doc.id
      );

      await db.runTransaction(async (tx) => {
        const bookingSnap = await tx.get(doc.ref);
        if (!bookingSnap.exists) return;

        const fresh = bookingSnap.data() || {};
        if (fresh.status !== "pending_payment") return;
        if (fresh.paymentStatus === "paid") return;

        if (fresh.directAvailability === true) {
          await restoreDirectAvailabilityInTransaction(
            tx,
            doc.ref,
            fresh,
            doc.id
          );
        } else {
          releaseBookingSlotsInTransaction(tx, fresh);
        }

        tx.update(doc.ref, {
          status: "cancelled_by_system",
          paymentStatus: "failed",
          cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        cancelled += 1;
      });
    }

    logger.info("Pending booking cleanup complete", {
      count: snap.size,
      cancelled,
      reconciled,
      deferred,
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
    const requestedBusinessId = safeTrim(request.data?.businessId);

    let businessDoc = null;

    if (requestedBusinessId) {
      const businessSnap = await db.collection("businesses").doc(requestedBusinessId).get();
      assert(businessSnap.exists, "not-found", "Business not found.");
      assert(businessSnap.data().ownerId === uid, "permission-denied", "Not your business.");
      businessDoc = businessSnap;
    } else {
      const snap = await db
        .collection("businesses")
        .where("ownerId", "==", uid)
        .limit(1)
        .get();

      assert(!snap.empty, "not-found", "Business not found.");
      businessDoc = snap.docs[0];
    }

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
   
const ANALYTICS_SUMMARY_REF = db.collection("analytics").doc("summary");

function startOfDay(date = new Date()) {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate());
}

function periodIds(date = new Date()) {
  const day = startOfDay(date);
  const year = day.getFullYear();
  const month = String(day.getMonth() + 1).padStart(2, "0");
  const dateOfMonth = String(day.getDate()).padStart(2, "0");
  const firstDay = new Date(year, 0, 1);
  const pastDays = Math.floor((day - firstDay) / 86400000);
  const week = String(Math.ceil((pastDays + firstDay.getDay() + 1) / 7)).padStart(2, "0");

  return {
    day: `${year}-${month}-${dateOfMonth}`,
    week: `${year}-W${week}`,
    month: `${year}-${month}`,
  };
}

function incrementMap(fields) {
  return Object.fromEntries(
    Object.entries(fields).map(([key, value]) => [
      key,
      admin.firestore.FieldValue.increment(value),
    ])
  );
}

async function incrementAnalytics(fields, date = new Date()) {
  const ids = periodIds(date);
  const increments = incrementMap(fields);
  const batch = db.batch();

  batch.set(
    ANALYTICS_SUMMARY_REF,
    {
      ...increments,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );

  for (const [period, id] of Object.entries(ids)) {
    batch.set(
      db.collection("analytics").doc("summary").collection(period).doc(id),
      {
        ...increments,
        period,
        periodId: id,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  }

  await batch.commit();
}

async function deleteCollection(collectionRef, batchSize = 400) {
  while (true) {
    const snapshot = await collectionRef.limit(batchSize).get();

    if (snapshot.empty) {
      return;
    }

    const batch = db.batch();
    snapshot.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
  }
}

async function updateQueryInBatches(query, updateFactory) {
  const snapshot = await query.get();

  for (let index = 0; index < snapshot.docs.length; index += 400) {
    const batch = db.batch();
    const docs = snapshot.docs.slice(index, index + 400);

    docs.forEach((doc) => batch.set(doc.ref, updateFactory(doc), { merge: true }));
    await batch.commit();
  }
}

exports.onUserDocumentCreated = onDocumentCreated("users/{uid}", async (event) => {
  await incrementAnalytics({
    "users.totalUsersCreated": 1,
    "users.activeUsers": 1,
    "users.newUsers": 1,
  });
});

exports.onOpportunityCreatedAnalytics = onDocumentCreated(
  "opportunities/{opportunityId}",
  async (event) => {
    const data = event.data?.data() || {};
    const category = String(data.category || "Uncategorised");
    const location = String(data.location || "Unknown");

    await incrementAnalytics({
      "engagement.opportunitiesCreated": 1,
      [`community.topCategories.${category}`]: 1,
      [`community.activeLocations.${location}`]: 1,
    });
  }
);

exports.onCommentCreatedAnalytics = onDocumentCreated(
  "opportunities/{opportunityId}/comments/{commentId}",
  async () => {
    await incrementAnalytics({
      "engagement.comments": 1,
    });
  }
);

exports.onReviewCreatedAnalytics = onDocumentCreated(
  "users/{userId}/reviews/{reviewId}",
  async () => {
    await incrementAnalytics({
      "engagement.reviews": 1,
    });
  }
);

exports.onBookingCreatedAnalytics = onDocumentCreated(
  "bookings/{bookingId}",
  async (event) => {
    const data = event.data?.data() || {};
    const fields = {
      "bookings.started": 1,
    };

    if (data.status === "pending_business_confirmation") {
      fields["bookings.pendingBusinessApproval"] = 1;
    }

    if (data.status === "confirmed") {
      fields["bookings.completedBookingFlow"] = 1;
    }

    await incrementAnalytics(fields);
  }
);

exports.onBookingUpdatedAnalytics = onDocumentUpdated(
  "bookings/{bookingId}",
  async (event) => {
    const before = event.data?.before?.data() || {};
    const after = event.data?.after?.data() || {};

    if (before.status === after.status && before.refundStatus === after.refundStatus) {
      return;
    }

    const fields = {};

    if (before.status !== after.status) {
      if (after.status === "confirmed") fields["bookings.confirmed"] = 1;
      if (after.status === "completed") fields["bookings.completed"] = 1;
      if (String(after.status || "").startsWith("cancelled")) {
        fields["bookings.cancelled"] = 1;
      }
      if (after.status === "declined") fields["bookings.declined"] = 1;
      if (after.status === "pending_business_confirmation") {
        fields["bookings.pendingBusinessApproval"] = 1;
      }
    }

    if (before.refundStatus !== after.refundStatus && after.refundStatus === "refunded") {
      fields["payments.refundsIssued"] = 1;
    }

    if (Object.keys(fields).length > 0) {
      await incrementAnalytics(fields);
    }
  }
);

exports.onNotificationOpenedAnalytics = onDocumentUpdated(
  "users/{userId}/notifications/{notificationId}",
  async (event) => {
    const before = event.data?.before?.data() || {};
    const after = event.data?.after?.data() || {};

    if (before.isRead === true || after.isRead !== true) {
      return;
    }

    await incrementAnalytics({
      "notifications.opened": 1,
    });
  }
);

exports.onSavedOpportunityAnalytics = onDocumentCreated(
  "users/{userId}/savedOpportunities/{savedId}",
  async () => {
    await incrementAnalytics({
      "engagement.saves": 1,
    });
  }
);

exports.onShareCreatedAnalytics = onDocumentCreated("shares/{shareId}", async () => {
  await incrementAnalytics({
    "engagement.shares": 1,
  });
});

exports.onReportCreatedAnalytics = onDocumentCreated("reports/{reportId}", async (event) => {
  const data = event.data?.data() || {};
  const reportType = String(data.reportType || "unknown");

  await incrementAnalytics({
    "moderation.reportsSubmitted": 1,
    "moderation.pendingReports": 1,
    [`moderation.reportTypes.${reportType}`]: 1,
  });
});

exports.onReportUpdatedAnalytics = onDocumentUpdated("reports/{reportId}", async (event) => {
  const before = event.data?.before?.data() || {};
  const after = event.data?.after?.data() || {};

  if (before.status === "open" && after.status && after.status !== "open") {
    await incrementAnalytics({
      "moderation.pendingReports": -1,
      "moderation.reportsResolved": 1,
    });
  }
});

exports.banUserForReport = onCall(
  {
    region: "us-central1",
  },
  async (request) => {
    try {
      await assertAdminRequest(request);

      const reportId = safeTrim(request.data?.reportId);
      const userId = safeTrim(request.data?.userId);

      assert(reportId, "invalid-argument", "Missing report ID.");
      assert(userId, "invalid-argument", "Missing user ID.");

      await db.collection("users").doc(userId).set({
        isBanned: true,
        bannedAt: admin.firestore.FieldValue.serverTimestamp(),
        bannedBy: request.auth.uid,
        moderationStatus: "banned",
      }, { merge: true });

      await db.collection("reports").doc(reportId).set({
        status: "resolved",
        actionTaken: "user_banned",
        resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
        resolvedBy: request.auth.uid,
      }, { merge: true });

      return { ok: true };
    } catch (error) {
      logger.error("banUserForReport failed", error);
      if (error instanceof HttpsError) throw error;
      throw new HttpsError("internal", "Could not ban this user.");
    }
  }
);

exports.onDailyActiveUser = onDocumentCreated(
  "activityDaily/{day}/users/{uid}",
  async () => {
    await incrementAnalytics({
      "activity.dailyActiveUsers": 1,
    });
  }
);

exports.onWeeklyActiveUser = onDocumentCreated(
  "activityWeekly/{week}/users/{uid}",
  async () => {
    await incrementAnalytics({
      "activity.weeklyActiveUsers": 1,
    });
  }
);

exports.onMonthlyActiveUser = onDocumentCreated(
  "activityMonthly/{month}/users/{uid}",
  async () => {
    await incrementAnalytics({
      "activity.monthlyActiveUsers": 1,
    });
  }
);

exports.generateWeeklyFounderReport = onSchedule(
  {
    schedule: "0 18 * * 0",
    timeZone: "Europe/London",
    region: "us-central1",
  },
  async () => {
    const ids = periodIds();
    const summarySnap = await ANALYTICS_SUMMARY_REF.get();
    const weekSnap = await ANALYTICS_SUMMARY_REF.collection("week").doc(ids.week).get();

    await db.collection("founderReports").doc(ids.week).set(
      {
        periodId: ids.week,
        generatedAt: admin.firestore.FieldValue.serverTimestamp(),
        summary: summarySnap.data() || {},
        week: weekSnap.data() || {},
      },
      { merge: true }
    );
  }
);

exports.deleteUserAccount = onCall({ region: "us-central1", timeoutSeconds: 120, memory: "1GiB" }, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Login required.");
  }

  const uid = request.auth.uid;
  const userRef = db.collection("users").doc(uid);
  const deletionRef = db.collection("accountDeletionRequests").doc(uid);
  const now = admin.firestore.FieldValue.serverTimestamp();

  await db.runTransaction(async (transaction) => {
    const deletionSnap = await transaction.get(deletionRef);

    if (deletionSnap.exists && deletionSnap.data()?.status === "completed") {
      throw new HttpsError("failed-precondition", "Account deletion has already completed.");
    }

    transaction.set(
      deletionRef,
      {
        uid,
        status: "processing",
        startedAt: deletionSnap.exists ? deletionSnap.data()?.startedAt || now : now,
        updatedAt: now,
      },
      { merge: true }
    );
  });

  try {
    await userRef.set(
      {
        name: "Deleted User",
        userName: "Deleted User",
        displayName: "Deleted User",
        photoUrl: null,
        profilePhoto: null,
        profilePhotoUrl: null,
        bio: "",
        email: admin.firestore.FieldValue.delete(),
        phone: admin.firestore.FieldValue.delete(),
        phoneNumber: admin.firestore.FieldValue.delete(),
        fcmTokens: admin.firestore.FieldValue.delete(),
        preferences: admin.firestore.FieldValue.delete(),
        isDeleted: true,
        deletedAt: now,
        deletionStatus: "completed",
        updatedAt: now,
      },
      { merge: true }
    );

    const subcollections = [
      "savedOpportunities",
      "following",
      "followers",
      "notifications",
      "blockedUsers",
      "preferences",
      "deviceTokens",
    ];

    for (const name of subcollections) {
      await deleteCollection(userRef.collection(name));
    }

    await updateQueryInBatches(
      db.collectionGroup("following").where("userId", "==", uid),
      () => ({
        userName: "Deleted User",
        photoUrl: null,
        isDeleted: true,
      })
    );

    await updateQueryInBatches(
      db.collectionGroup("followers").where("userId", "==", uid),
      () => ({
        userName: "Deleted User",
        photoUrl: null,
        isDeleted: true,
      })
    );

    await updateQueryInBatches(
      db.collection("opportunities").where("createdBy", "==", uid),
      () => ({
        organiserName: "Deleted User",
        organiserPhotoUrl: null,
        creatorName: "Deleted User",
        creatorPhotoUrl: null,
        updatedAt: now,
      })
    );

    await updateQueryInBatches(
      db.collectionGroup("comments").where("userId", "==", uid),
      () => ({
        userName: "Deleted User",
        photoUrl: null,
        isDeletedUser: true,
      })
    );

    await updateQueryInBatches(
      db.collectionGroup("reviews").where("reviewerId", "==", uid),
      () => ({
        reviewerName: "Deleted User",
        reviewerPhotoUrl: null,
        isDeletedUser: true,
      })
    );

    await updateQueryInBatches(
      db.collection("bookings").where("customerId", "==", uid),
      () => ({
        customerName: "Deleted User",
        customerEmail: admin.firestore.FieldValue.delete(),
        customerPhone: admin.firestore.FieldValue.delete(),
      })
    );

    await updateQueryInBatches(
      db.collection("reports").where("reporterUserId", "==", uid),
      () => ({
        reporterUserDeleted: true,
      })
    );

    await updateQueryInBatches(
      db.collection("reports").where("reportedUserId", "==", uid),
      () => ({
        reportedUserDeleted: true,
      })
    );

    await incrementAnalytics({
      "users.activeUsers": -1,
      "users.deletedUsers": 1,
    });

    await admin.auth().deleteUser(uid).catch((error) => {
      if (error.code !== "auth/user-not-found") {
        throw error;
      }
    });

    await deletionRef.set(
      {
        status: "completed",
        completedAt: now,
        updatedAt: now,
      },
      { merge: true }
    );

    return { success: true };
  } catch (error) {
    console.error("deleteUserAccount failed", error);

    await deletionRef.set(
      {
        status: "failed",
        error: error.message || String(error),
        updatedAt: now,
      },
      { merge: true }
    );

    throw new HttpsError("internal", error.message || "Account deletion failed.");
  }
});

exports.expireOldOpportunities =
  require("./opportunities")
    .expireOldOpportunities;
