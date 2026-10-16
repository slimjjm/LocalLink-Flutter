"use strict";

function safeTrim(value) {
  return String(value ?? "").trim();
}

function firstPublicText(...values) {
  for (const value of values) {
    const text = safeTrim(value);
    if (text) return text;
  }
  return "";
}

function notificationSafeId(value) {
  return safeTrim(value).replace(/[^a-zA-Z0-9_-]/g, "_").slice(0, 180);
}

function uniqueNonEmpty(values) {
  return [...new Set(values.map(safeTrim).filter(Boolean))];
}

function opportunityNotificationRecipientIds(opportunity) {
  return uniqueNonEmpty([
    opportunity?.organiserId,
    opportunity?.createdBy,
    opportunity?.ownerId,
    ...(Array.isArray(opportunity?.ownerIds) ? opportunity.ownerIds : []),
    ...(Array.isArray(opportunity?.adminUserIds) ? opportunity.adminUserIds : []),
  ]);
}

function isTopLevelComment(comment) {
  return !firstPublicText(
    comment?.parentId,
    comment?.parentCommentId,
    comment?.replyToCommentId,
    comment?.replyTo,
  );
}

function isRemovedContent(data) {
  return data?.deleted === true ||
    data?.isDeleted === true ||
    data?.hidden === true ||
    data?.isHidden === true ||
    safeTrim(data?.moderationStatus).toLowerCase() === "removed" ||
    safeTrim(data?.status).toLowerCase() === "removed";
}

function actorIdForParticipation(data, entryId = "") {
  return firstPublicText(
    data?.userId,
    data?.authorId,
    data?.createdBy,
    entryId,
  );
}

function displayNameForParticipation(data) {
  return firstPublicText(
    data?.userName,
    data?.displayName,
    data?.authorName,
    data?.createdByName,
    "Someone",
  );
}

function participationIsChallengeEntry({ source, data, opportunity }) {
  return source === "entry" ||
    data?.isChallengeEntry === true ||
    safeTrim(opportunity?.activityKind) === "community_challenge";
}

function participationHasPhoto(data) {
  return Boolean(firstPublicText(data?.imageUrl, data?.imagePath, data?.photoUrl, data?.photoPath));
}

function participationNotificationId({
  opportunityId,
  commentId = "",
  entryId = "",
  actorUserId = "",
  source = "comment",
  data = {},
  opportunity = {},
}) {
  const challengeEntry = participationIsChallengeEntry({ source, data, opportunity });
  const base = `opportunity_participation_${notificationSafeId(opportunityId)}`;

  if (challengeEntry) {
    const entrantId = firstPublicText(actorUserId, data.userId, entryId);
    return `${base}_challenge_entry_${notificationSafeId(entrantId)}`;
  }

  return `${base}_comment_${notificationSafeId(commentId || data.commentId)}`;
}

function buildOpportunityParticipationCopy({ data, opportunity, source }) {
  const displayName = displayNameForParticipation(data);
  const challengeEntry = participationIsChallengeEntry({ source, data, opportunity });
  const hasPhoto = participationHasPhoto(data);
  const opportunityTitle = firstPublicText(
    opportunity?.title,
    opportunity?.name,
    challengeEntry ? "your competition" : "your activity",
  );

  if (challengeEntry) {
    return {
      title: "New entry in your competition",
      body: hasPhoto
        ? `${displayName} added a photo to ${opportunityTitle}`
        : `${displayName} added an entry to ${opportunityTitle}`,
    };
  }

  return {
    title: "New comment on your activity",
    body: `${displayName} commented on ${opportunityTitle}`,
  };
}

function isAlreadyExistsError(error) {
  return error?.code === 6 ||
    error?.code === "already-exists" ||
    error?.code === "ALREADY_EXISTS";
}

async function createNotificationIfAbsent(ref, payload) {
  try {
    await ref.create(payload);
    return true;
  } catch (error) {
    if (isAlreadyExistsError(error)) return false;
    throw error;
  }
}

async function notifyOpportunityParticipationCreated({
  db,
  admin,
  sendPushToUser,
  logger = console,
  opportunityId,
  commentId = "",
  entryId = "",
  source = "comment",
  data,
}) {
  if (!data || !opportunityId) return { created: 0, skipped: "missing_data" };
  if (source === "comment" && !isTopLevelComment(data)) {
    return { created: 0, skipped: "reply" };
  }
  if (isRemovedContent(data)) return { created: 0, skipped: "removed" };

  const actorUserId = actorIdForParticipation(data, entryId);
  if (!actorUserId) return { created: 0, skipped: "missing_actor" };

  const opportunityRef = db.collection("opportunities").doc(opportunityId);
  const opportunitySnap = await opportunityRef.get();
  if (!opportunitySnap.exists) return { created: 0, skipped: "missing_opportunity" };

  const opportunity = opportunitySnap.data() || {};
  if (isRemovedContent(opportunity)) return { created: 0, skipped: "removed_opportunity" };

  const recipientIds = opportunityNotificationRecipientIds(opportunity)
    .filter((recipientId) => recipientId !== actorUserId);
  if (!recipientIds.length) return { created: 0, skipped: "no_recipients" };

  const challengeEntry = participationIsChallengeEntry({ source, data, opportunity });
  const { title, body } = buildOpportunityParticipationCopy({
    data,
    opportunity,
    source,
  });
  const notificationId = participationNotificationId({
    opportunityId,
    commentId: firstPublicText(commentId, data.commentId),
    entryId,
    actorUserId,
    source,
    data,
    opportunity,
  });
  const resolvedCommentId = firstPublicText(commentId, data.commentId);
  const resolvedEntryId = challengeEntry
    ? firstPublicText(entryId, data.entryId, actorUserId)
    : firstPublicText(entryId, data.entryId);
  const serverTimestamp = admin.firestore.FieldValue.serverTimestamp();
  let created = 0;

  await Promise.all(recipientIds.map(async (recipientId) => {
    const notificationRef = db
      .collection("users")
      .doc(recipientId)
      .collection("notifications")
      .doc(notificationId);

    const notification = {
      type: "opportunity_comment",
      title,
      body,
      opportunityId,
      commentId: resolvedCommentId,
      entryId: resolvedEntryId,
      userId: actorUserId,
      actorUserId,
      isChallengeEntry: challengeEntry,
      participationSource: source,
      isRead: false,
      createdAt: serverTimestamp,
    };

    const didCreate = await createNotificationIfAbsent(notificationRef, notification);
    if (!didCreate) return;
    created += 1;

    await sendPushToUser(recipientId, {
      title,
      body,
      preferenceKey: "activityUpdates",
      data: {
        type: "opportunity_comment",
        opportunityId,
        commentId: resolvedCommentId,
        entryId: resolvedEntryId,
        userId: actorUserId,
        isChallengeEntry: String(challengeEntry),
      },
    });
  }));

  logger.info?.("Opportunity participation notifications processed", {
    opportunityId,
    commentId,
    entryId,
    source,
    actorUserId,
    recipientCount: recipientIds.length,
    created,
  });

  return { created, recipientCount: recipientIds.length, notificationId };
}

module.exports = {
  buildOpportunityParticipationCopy,
  notifyOpportunityParticipationCreated,
  opportunityNotificationRecipientIds,
  participationNotificationId,
};
