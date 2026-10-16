const admin = require("firebase-admin");

const {
  onSchedule,
} = require("firebase-functions/v2/scheduler");

function timestampMillis(value) {
  if (!value) return null;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (typeof value.toDate === "function") {
    const date = value.toDate();
    return date instanceof Date ? date.getTime() : null;
  }
  if (value instanceof Date) return value.getTime();
  return null;
}

function isCommunityChallenge(data) {
  return data?.activityKind === "community_challenge";
}

function isLondonMidnight(value) {
  const millis = timestampMillis(value);
  if (!millis) return false;
  const parts = new Intl.DateTimeFormat("en-GB", {
    timeZone: "Europe/London",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
  }).formatToParts(new Date(millis));
  const values = Object.fromEntries(
    parts.map((part) => [part.type, part.value])
  );
  return values.hour === "00" &&
    values.minute === "00" &&
    values.second === "00";
}

function opportunityExpiresMillis(data) {
  if (isCommunityChallenge(data)) {
    const closesAt = timestampMillis(data.challengeClosesAt);
    if (closesAt) return closesAt;
  }

  const eventMillis = timestampMillis(data?.eventDate);
  if (!eventMillis) return null;

  if (isLondonMidnight(data.eventDate)) {
    const nextDay = new Date(eventMillis);
    nextDay.setUTCDate(nextDay.getUTCDate() + 1);
    return nextDay.getTime();
  }

  return eventMillis;
}

function shouldExpireOpportunity(data, now = new Date()) {
  if (!data || data.isActive !== true) return false;

  const expiresAt = opportunityExpiresMillis(data);
  if (!expiresAt) return false;

  return expiresAt <= now.getTime();
}

exports.expireOldOpportunities =
  onSchedule(
    {
      schedule: "every day 02:00",
      region: "us-central1",
    },
    async () => {
      const db = admin.firestore();

      const snapshot =
        await db
          .collection("opportunities")
          .where(
            "isActive",
            "==",
            true
          )
          .get();

      const now = new Date();

      let expiredCount = 0;

      const batch =
        db.batch();

      snapshot.docs.forEach(
        (doc) => {

          const data =
            doc.data();

          if (shouldExpireOpportunity(data, now)) {

            batch.update(
              doc.ref,
              {
                isActive: false,
              }
            );

            expiredCount++;
          }
        }
      );

      if (expiredCount > 0) {
        await batch.commit();
      }

      console.log(
        `Expired ${expiredCount} opportunities`
      );
    }
  );

exports._test = {
  opportunityExpiresMillis,
  shouldExpireOpportunity,
  timestampMillis,
};
