const admin = require("firebase-admin");

const {
  onSchedule,
} = require("firebase-functions/v2/scheduler");

const db = admin.firestore();
const notifications =
  require("./notifications");
// =================================================
// OPPORTUNITY REMINDERS
// =================================================

exports.sendOpportunityReminders =
  onSchedule(
    {
      schedule: "every 15 minutes",
      region: "us-central1",
    },
    async () => {

      console.log(
        "Checking opportunity reminders..."
      );

      const snapshot =
        await db
          .collection("opportunities")
          .where(
            "isActive",
            "==",
            true
          )
          .get();

      console.log(
        `Found ${snapshot.size} active opportunities`
      );

      for (const doc of snapshot.docs) {

        const data =
          doc.data();

        if (!data.eventDate) {
          continue;
        }

        const eventDate =
          data.eventDate.toDate();

        const now =
          new Date();

        if (eventDate <= now) {
          continue;
        }

        const hoursUntilEvent =
          (eventDate - now) /
          (1000 * 60 * 60);

        await createReminderNotifications({
          opportunityRef: doc.ref,
          opportunityId: doc.id,
          opportunity: data,
          hoursUntilEvent,
          reminderType: "opportunity_reminder_24h",
          lowerHour: 23,
          upperHour: 24,
          title: "Opportunity tomorrow",
          body: `"${data.title || "Your opportunity"}" starts tomorrow.`,
        });

        await createReminderNotifications({
          opportunityRef: doc.ref,
          opportunityId: doc.id,
          opportunity: data,
          hoursUntilEvent,
          reminderType: "opportunity_reminder_1h",
          lowerHour: 0,
          upperHour: 1,
          title: "Opportunity soon",
          body: `"${data.title || "Your opportunity"}" starts in 1 hour.`,
        });
      }

      console.log(
        "Opportunity reminder check complete"
      );
    }
  );

// =================================================
// CREATE REMINDER NOTIFICATIONS
// =================================================

async function createReminderNotifications({
  opportunityRef,
  opportunityId,
  opportunity,
  hoursUntilEvent,
  reminderType,
  lowerHour,
  upperHour,
  title,
  body,
}) {

  if (
    hoursUntilEvent > upperHour ||
    hoursUntilEvent <= lowerHour
  ) {
    return;
  }

  const attendees =
    await opportunityRef
      .collection("attendees")
      .get();

  console.log(
    `${reminderType}: ${attendees.size} attendees`
  );

  for (const attendee of attendees.docs) {

    const attendeeData =
      attendee.data();

    const uid =
      attendeeData.userId ||
      attendee.id;

    if (!uid) {
      continue;
    }

    const notificationId =
      `${opportunityId}_${reminderType}`;

    const notificationRef =
      db
        .collection("users")
        .doc(uid)
        .collection("notifications")
        .doc(notificationId);

    const existing =
      await notificationRef.get();

    if (existing.exists) {
      continue;
    }

    await notificationRef.set({

      type:
        reminderType,

      title,

      body,

      opportunityId,

      opportunityTitle:
        opportunity.title || "",

      isRead: false,

      createdAt:
        admin.firestore.FieldValue
          .serverTimestamp(),
    });
   await notifications.sendPushToUser(
  uid,
  {
    title,
    body,
    data: {
      type: "opportunity_reminder",
      reminderType,
      opportunityId,
      notificationId,
    },
    preferenceKey: "reminders",
  }
);
  }
}
