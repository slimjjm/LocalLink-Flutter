"use strict";

const APPOINTMENT_CATEGORIES = new Set([
  "aesthetics", "beauty", "brows & lashes", "hair salon", "barber", "nails",
  "massage", "skin clinic", "dog groomer", "dog walker", "mobile valeting",
  "personal trainer",
]);
const DAYS = [3, 7, 14];
const DAY = 86400000;
const TYPE = "business_service_setup";
const text = (value) => typeof value === "string" ? value.trim() : "";
const millis = (value) => value?.toMillis ? value.toMillis() : Number(value);

function eligibleBusiness(business) {
  return Boolean(business && business.isActive === true && business.acceptingLeads !== false &&
    !['removed', 'rejected', 'blocked', 'hidden'].includes(text(business.moderationStatus).toLowerCase()) &&
    business.approvalStatus !== "rejected" &&
    !['isDeleted', 'deleted', 'isArchived', 'archived', 'isHidden', 'hidden', 'isPrivate', 'private'].some(key => business[key] === true) &&
    business.isPubliclyDiscoverable !== false &&
    !['private', 'restricted', 'members', 'members_only'].includes(text(business.visibility).toLowerCase()) &&
    !['inactive', 'archived', 'deleted', 'removed', 'rejected'].includes(text(business.status).toLowerCase()) &&
    text(business.ownerId) &&
    (business.isClaimed === true || business.listingOwnershipStatus === "claimed" ||
      business.claimStatus === "approved") &&
    APPOINTMENT_CATEGORIES.has(text(business.category).toLowerCase()));
}
function eligibleOwner(user, access = {}, account = {}) {
  return Boolean(user && !user.disabled && user.providerData?.length &&
    (user.emailVerified === true || user.providerData.some(p => p.providerId === "phone")) &&
    access.isBanned !== true && account.isBanned !== true);
}
function dueDay(state, now) {
  if (!state || state.status !== "active") return null;
  const start = millis(state.startedAt);
  if (!Number.isFinite(start) || now < start) return null;
  // Never send a catch-up burst or revive a long-abandoned campaign.
  const age = (now - start) / DAY;
  if (age >= 21) return null;
  const due = DAYS.filter(day => age >= day && !(state.handledDays || []).includes(day));
  return due.length ? due[due.length - 1] : null;
}
function reminderPayload(businessId, day) {
  if (!text(businessId) || !DAYS.includes(day)) return null;
  return {
    type: TYPE, businessId, title: "A useful next step for your business",
    body: day === 14
      ? "If appointments are part of what you offer, you can add your first service whenever you are ready. This is our last automatic reminder."
      : day === 7
        ? "A short service description can help local people decide what to ask about. Add one when it suits you; you can set up booking times later."
        : "You can add your first service so local people know what to ask about. Appointment times can come later.",
  };
}

function buildBusinessActivationExports({ admin, db, onCall, onSchedule,
  onDocumentCreated, onDocumentWritten, HttpsError, notifications,
  enabled = () => process.env.BUSINESS_SERVICE_REMINDERS_ENABLED === "true",
  now = () => Date.now(), routeSupported = () => true }) {
  const stateRef = id => db.collection("businessActivationReminders").doc(id);
  const businessRef = id => db.collection("businesses").doc(id);
  const services = ref => ref.collection("services").where("isActive", "==", true).limit(1);
  const userRef = uid => db.collection("users").doc(uid);
  const capabilityRef = uid => userRef(uid).collection("private").doc("notificationCapabilities");
  const notificationRef = (uid, id, cycle, day) => userRef(uid).collection("notifications")
    .doc(`business_setup_${id}_${cycle}_${day}`);
  const getOwner = async uid => {
    try { return await admin.auth().getUser(uid); }
    catch (e) { if (e.code === "auth/user-not-found") return null; throw e; }
  };

  async function removeUnread(tx, uid, id, cycle) {
    const refs = DAYS.map(day => notificationRef(uid, id, cycle, day));
    const snapshots = await Promise.all(refs.map(ref => tx.get(ref)));
    snapshots.forEach((snap, i) => {
      if (snap.exists && snap.data().isRead !== true) tx.delete(refs[i]);
    });
  }

  async function start(id, uid, explicit = false) {
    if (!enabled() || !routeSupported(TYPE)) return { status: "disabled" };
    const ref = businessRef(id);
    const first = await ref.get();
    const business = first.data();
    if (!business || business.ownerId !== uid) throw new HttpsError("permission-denied", "Only the business owner can start setup reminders.");
    const owner = await getOwner(uid);
    return db.runTransaction(async tx => {
      const [fresh, state, active, access, account, prefs] = await Promise.all([
        tx.get(ref), tx.get(stateRef(id)), tx.get(services(ref)),
        tx.get(userRef(uid).collection("private").doc("access")),
        tx.get(userRef(uid).collection("private").doc("account")),
        tx.get(userRef(uid).collection("preferences").doc("notifications")),
      ]);
      const data = fresh.data();
      if (data?.ownerId !== uid) throw new HttpsError("permission-denied", "Your business access has changed.");
      if (!eligibleBusiness(data) || !eligibleOwner(owner, access.data(), account.data()) ||
          !active.empty || prefs.data()?.reminders === false ||
          prefs.data()?.businessSetupReminders === false) return { status: "not_needed" };
      if (state.exists && (!explicit ||
          (state.data().status === "active" && state.data().ownerId === uid))) {
        return { status: state.data().status };
      }
      // Creation events use authoritative createdAt. Legacy listings only enrol
      // through an explicit setup action; no automatic backfill or claim trigger.
      const started = explicit ? now() : millis(data.createdAt);
      if (!Number.isFinite(started) || now() - started >= 21 * DAY) return { status: "legacy" };
      const cycle = (state.data()?.cycle || 0) + 1;
      if (state.exists) await removeUnread(tx, state.data().ownerId, id, state.data().cycle);
      tx.set(stateRef(id), { ownerId: uid, startedAt: admin.firestore.Timestamp.fromMillis(started),
        cycle, status: "active", handledDays: [] });
      return { status: "active" };
    });
  }

  async function process(id) {
    const ref = businessRef(id);
    const initial = await stateRef(id).get();
    if (!initial.exists || initial.data().status !== "active") return;
    const uid = initial.data().ownerId;
    const owner = await getOwner(uid);
    const result = await db.runTransaction(async tx => {
      const [state, fresh, active, access, account, prefs, capability] = await Promise.all([
        tx.get(stateRef(id)), tx.get(ref), tx.get(services(ref)),
        tx.get(userRef(uid).collection("private").doc("access")),
        tx.get(userRef(uid).collection("private").doc("account")),
        tx.get(userRef(uid).collection("preferences").doc("notifications")),
        tx.get(capabilityRef(uid)),
      ]);
      const current = state.data();
      if (!current || current.status !== "active" || current.ownerId !== uid) return null;
      const business = fresh.data();
      const stop = !active.empty ? "completed" :
        (!eligibleBusiness(business) || business?.ownerId !== uid ||
          !eligibleOwner(owner, access.data(), account.data()) ||
          prefs.data()?.reminders === false || prefs.data()?.businessSetupReminders === false ||
          !routeSupported(TYPE)) ? "cancelled" :
        now() - millis(current.startedAt) >= 21 * DAY ? "finished" : null;
      if (stop) {
        await removeUnread(tx, uid, id, current.cycle);
        tx.update(stateRef(id), { status: stop });
        return null;
      }
      if (capability.data()?.businessServiceSetup !== true) return null;
      const day = dueDay(current, now());
      if (!day) return null;
      const payload = reminderPayload(id, day);
      const notice = notificationRef(uid, id, current.cycle, day);
      const existing = await tx.get(notice);
      tx.update(stateRef(id), { handledDays: DAYS.filter(d => d <= day),
        status: day === 14 ? "finished" : "active" });
      if (existing.exists) return null;
      tx.create(notice, { ...payload, isRead: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp() });
      return { payload, notice };
    });
    if (!result) return;
    // Recheck just before the external push. Never retry a claimed reminder:
    // at-most-once push attempts avoid duplicates after an ambiguous FCM result.
    const [active, fresh] = await Promise.all([services(ref).get(), ref.get()]);
    if (!active.empty || fresh.data()?.ownerId !== uid || !eligibleBusiness(fresh.data())) {
      await result.notice.delete();
      return;
    }
    if ((await capabilityRef(uid).get()).data()?.businessServiceSetup !== true ||
        !(await notifications.userAllowsPush(userRef(uid), "reminders")) ||
        !(await notifications.userAllowsPush(userRef(uid), "businessSetupReminders"))) {
      await result.notice.delete();
      return;
    }
    await notifications.sendPushToUser(uid, { ...result.payload,
      preferenceKey: "businessSetupReminders", data: { type: TYPE, businessId: id,
        notificationId: result.notice.id } });
  }

  async function cancelOnService(id) {
    const ref = businessRef(id);
    await db.runTransaction(async tx => {
      const [state, active] = await Promise.all([tx.get(stateRef(id)), tx.get(services(ref))]);
      if (active.empty) return;
      if (!state.exists) {
        const business = (await tx.get(ref)).data();
        if (eligibleBusiness(business)) tx.set(stateRef(id), {
          ownerId: business.ownerId, cycle: 0, status: "completed", handledDays: [],
        });
        return;
      }
      const current = state.data();
      const notices = DAYS.map(day => notificationRef(current.ownerId, id, current.cycle, day));
      const snapshots = await Promise.all(notices.map(notice => tx.get(notice)));
      tx.update(stateRef(id), { status: "completed" });
      snapshots.forEach((snap, i) => { if (snap.exists && snap.data().isRead !== true) tx.delete(notices[i]); });
    });
  }

  return {
    beginBusinessServiceSetup: onCall({ region: "us-central1" }, async request => {
      if (!request.auth || request.auth.token?.firebase?.sign_in_provider === "anonymous") {
        throw new HttpsError("unauthenticated", "Please sign in to manage your business.");
      }
      const id = text(request.data?.businessId);
      if (!id || id.includes("/")) throw new HttpsError("invalid-argument", "Choose a business.");
      const uid = request.auth.uid;
      const owner = await getOwner(uid);
      const registered = await db.runTransaction(async tx => {
        const [business, access, account] = await Promise.all([
          tx.get(businessRef(id)), tx.get(userRef(uid).collection("private").doc("access")),
          tx.get(userRef(uid).collection("private").doc("account")),
        ]);
        const data = business.data();
        if (data?.ownerId !== uid) throw new HttpsError("permission-denied", "Only the business owner can manage setup reminders.");
        const claimed = data.isClaimed === true || data.listingOwnershipStatus === "claimed" || data.claimStatus === "approved";
        if (!claimed || !eligibleOwner(owner, access.data(), account.data())) return false;
        tx.set(capabilityRef(uid), { businessServiceSetup: true }, { merge: true });
        return true;
      });
      if (!registered) return { status: "not_needed" };
      // Dashboard registration announces route support only; it never enrols,
      // resets or backfills a campaign. Add-service entry is explicit enrolment.
      if (request.data?.registerRouteOnly === true) return { status: "route_ready" };
      return start(id, uid, true);
    }),
    onBusinessCreatedServiceSetup: onDocumentCreated({ document: "businesses/{businessId}", region: "us-central1" },
      async event => {
        if (!enabled()) return;
        const data = event.data?.data();
        if (eligibleBusiness(data)) await start(event.params.businessId, data.ownerId);
      }),
    onBusinessServiceSetupChanged: onDocumentWritten({ document: "businesses/{businessId}/services/{serviceId}", region: "us-central1" },
      event => cancelOnService(event.params.businessId)),
    sendBusinessServiceSetupReminders: onSchedule({ schedule: "every 60 minutes", region: "us-central1" }, async () => {
      if (!enabled()) return;
      let last;
      do {
        let query = db.collection("businessActivationReminders").where("status", "==", "active")
          .orderBy(admin.firestore.FieldPath.documentId()).limit(100);
        if (last) query = query.startAfter(last);
        const page = await query.get();
        for (const doc of page.docs) {
          try { await process(doc.id); }
          catch (error) { console.error("Business setup reminder failed", doc.id, error.code || error.message); }
        }
        last = page.size === 100 ? page.docs[page.docs.length - 1] : null;
      } while (last);
    }),
    // Dependency-injected entry points allow behavioural tests without Firebase.
    _start: start, _process: process, _cancelOnService: cancelOnService,
  };
}
module.exports = { APPOINTMENT_CATEGORIES, DAYS, TYPE, eligibleBusiness,
  eligibleOwner, dueDay, reminderPayload, buildBusinessActivationExports };
