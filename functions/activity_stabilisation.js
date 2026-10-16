"use strict";

function validReview({ uid, organiserId, opportunity, attendee, rating, text, now }) {
  const host = opportunity?.organiserId || opportunity?.createdBy;
  const date = opportunity?.eventDate?.toMillis?.() ?? opportunity?.eventDate?.getTime?.();
  return Boolean(uid && organiserId && uid !== organiserId && host === organiserId &&
    attendee?.userId === uid && Number.isInteger(rating) && rating >= 1 && rating <= 5 &&
    typeof text === "string" && text.length <= 2000 && Number.isFinite(date) && date <= now);
}
function aggregateReviews(records) {
  const ratings = records.map(data => data.rating).filter(rating => Number.isInteger(rating) && rating >= 1 && rating <= 5);
  const ratingTotal = ratings.reduce((sum, rating) => sum + rating, 0);
  return { reviewCount: ratings.length, ratingTotal, averageRating: ratings.length ? ratingTotal / ratings.length : 0 };
}
// Read before any transaction writes. Only a tracked public summary is removed;
// unlinked legacy summaries require a separately reviewed cleanup plan.
async function privateSummaryCleanup(tx, db, activityId, data, previousData, admin) {
  const organisations = [...new Set([data?.organisationId, previousData?.organisationId]
    .filter(id => typeof id === "string" && id && !id.includes("/")))];
  const changes = [];
  for (const id of organisations) {
    if (data?.organisationId === id && require('./discovery_privacy').activityDiscoveryVisibility(data) === 'public') continue;
    const ref = db.collection("organisations").doc(id);
    const org = await tx.get(ref);
    if (org.exists && org.data().latestAddedSessionId === activityId) {
      changes.push({ ref, fields: {
        latestAddedSessionId: admin.firestore.FieldValue.delete(),
        latestAddedSessionTitle: admin.firestore.FieldValue.delete(),
        latestAddedSessionAt: admin.firestore.FieldValue.delete(),
      } });
    }
  }
  return changes;
}

function buildActivityStabilisationExports({ admin, db, onCall, onDocumentCreated, HttpsError, sendPushToUser,
  now = () => Date.now() }) {
  const timestamp = () => admin.firestore.FieldValue.serverTimestamp();
  const userRef = uid => db.collection("users").doc(uid);
  const publicOrMember = async (tx, activity, uid) => {
    if (activity.createdBy === uid || activity.organiserId === uid) return true;
    const policy = require('./discovery_privacy');
    if (policy.activityDiscoveryVisibility(activity) === 'public') return true;
    if (!activity.organisationId) return false;
    const scope = policy.activityScope(activity);
    const orgRef = db.collection("organisations").doc(activity.organisationId);
    const [orgSnap, memberSnap] = await Promise.all([tx.get(orgRef), tx.get(orgRef.collection("members").doc(uid))]);
    const org = orgSnap.data() || {};
    const member = memberSnap.data() || {};
    const manager = org.listingOwnershipStatus === "claimed" &&
      (org.ownerId === uid || (org.adminUserIds || []).includes(uid)) ||
      member.status === "active" && ["owner", "organisation_admin", "secretary"].includes(member.role);
    if (manager) return true;
    if (scope === "organisation") return member.status === "active";
    if (scope !== "group" || !activity.groupId) return false;
    const groupRef = orgRef.collection("groups").doc(activity.groupId);
    const [group, membership] = await Promise.all([tx.get(groupRef), tx.get(groupRef.collection("members").doc(uid))]);
    return (group.data()?.leaderUserIds || []).includes(uid) || membership.data()?.status === "active";
  };
  return {
    submitOrganiserReview: onCall({ region: "us-central1" }, async request => {
      const uid = request.auth?.uid;
      if (!uid || request.auth.token?.firebase?.sign_in_provider === "anonymous") throw new HttpsError("unauthenticated", "Please sign in to review.");
      const { opportunityId, organiserId, rating } = request.data || {};
      const text = typeof request.data?.text === "string" ? request.data.text.trim() : "";
      if (![opportunityId, organiserId].every(id => typeof id === "string" && id && !id.includes("/"))) throw new HttpsError("invalid-argument", "Choose an activity and organiser.");
      const activityRef = db.collection("opportunities").doc(opportunityId);
      const hostRef = userRef(organiserId);
      const reviewRef = hostRef.collection("reviews").doc(uid);
      const notice = hostRef.collection("notifications").doc(`review_${uid}`);
      const result = await db.runTransaction(async tx => {
        const [activity, attendee, existing, reviews, host, user, access, account] = await Promise.all([
          tx.get(activityRef), tx.get(activityRef.collection("attendees").doc(uid)), tx.get(reviewRef),
          tx.get(hostRef.collection("reviews")), tx.get(hostRef), tx.get(userRef(uid)),
          tx.get(userRef(uid).collection("private").doc("access")), tx.get(userRef(uid).collection("private").doc("account")),
        ]);
        if (existing.exists) return { alreadyReviewed: true };
        if (access.data()?.isBanned || account.data()?.isBanned || !host.exists ||
            !validReview({ uid, organiserId, opportunity: activity.data(), attendee: attendee.data(), rating, text, now: now() }) ||
            !(await publicOrMember(tx, activity.data(), uid))) throw new HttpsError("failed-precondition", "You need to have attended this finished activity before reviewing its organiser.");
        const reviewerName = String(user.data()?.name || user.data()?.userName || request.auth.token?.name || "A local member").slice(0, 100);
        const record = { reviewerId: uid, reviewerName, rating, text, opportunityId, createdAt: timestamp() };
        const totals = aggregateReviews([...reviews.docs.map(doc => doc.data()), record]);
        tx.create(reviewRef, record);
        tx.update(hostRef, totals);
        tx.set(notice, { type: "review", title: "New review", body: `${reviewerName} left you a review`, reviewerId: uid,
          isRead: false, createdAt: timestamp() });
        return { alreadyReviewed: false };
      });
      if (!result.alreadyReviewed) {
        try { await sendPushToUser(organiserId, { title: "New review", body: "A participant left you a review.",
          preferenceKey: "activityUpdates", data: { type: "review", reviewerId: uid, notificationId: notice.id } }); }
        catch (error) { console.error("Review push failed after successful commit", error.code || error.message); }
      }
      return result;
    }),
    onActivityAttendanceCreated: onDocumentCreated({ document: "opportunities/{opportunityId}/attendees/{userId}", region: "us-central1" }, async event => {
      const { opportunityId, userId } = event.params;
      const activityRef = db.collection("opportunities").doc(opportunityId);
      const activity = (await activityRef.get()).data();
      const organiserId = activity?.organiserId || activity?.createdBy;
      if (!organiserId || organiserId === userId) return;
      const notice = userRef(organiserId).collection("notifications").doc(`activity_join_${opportunityId}_${userId}`);
      const created = await db.runTransaction(async tx => {
        const [attendee, existing] = await Promise.all([tx.get(activityRef.collection("attendees").doc(userId)), tx.get(notice)]);
        if (!attendee.exists || attendee.data().userId !== userId || existing.exists) return false;
        tx.create(notice, { type: "opportunity_join", title: "New attendee", body: "Someone is going to your activity.",
          opportunityId, userId, isRead: false, createdAt: timestamp() });
        return true;
      });
      if (created) await sendPushToUser(organiserId, { title: "New attendee", body: "Someone is going to your activity.",
        preferenceKey: "activityUpdates", data: { type: "opportunity_join", opportunityId, notificationId: notice.id } });
    }),
    onOrganisationActivityCreated: onDocumentCreated({ document: "opportunities/{opportunityId}", region: "us-central1" }, async event => {
      const opportunityId = event.params.opportunityId;
      const activityRef = db.collection("opportunities").doc(opportunityId);
      const receipt = db.collection("activitySummaryReceipts").doc(opportunityId);
      await db.runTransaction(async tx => {
        const [activity, applied] = await Promise.all([tx.get(activityRef), tx.get(receipt)]);
        const data = activity.data();
        if (!data?.organisationId || applied.exists) return;
        const orgRef = db.collection("organisations").doc(data.organisationId);
        const org = await tx.get(orgRef);
        if (!org.exists) return;
        tx.update(orgRef, { activityCount: admin.firestore.FieldValue.increment(1), updatedAt: timestamp(),
          ...(data.eventDate && require('./discovery_privacy').activityDiscoveryVisibility(data) === 'public'
            ? { latestAddedSessionId: opportunityId, latestAddedSessionAt: data.eventDate,
                latestAddedSessionTitle: String(data.title || "Activity") } : {}) });
        tx.create(receipt, { organisationId: data.organisationId, createdAt: timestamp() });
      });
    }),
  };
}
module.exports = { validReview, aggregateReviews, privateSummaryCleanup, buildActivityStabilisationExports };
