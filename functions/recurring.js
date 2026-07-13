const admin = require("firebase-admin");

const {
  onSchedule,
} = require("firebase-functions/v2/scheduler");

const db = admin.firestore();

function addRepeatInterval(
  date,
  repeatType,
) {

  const nextDate =
    new Date(date);

  switch (repeatType) {

    case "daily":
      nextDate.setDate(
        nextDate.getDate() + 1
      );
      return nextDate;

    case "weekly":
      nextDate.setDate(
        nextDate.getDate() + 7
      );
      return nextDate;

    case "fortnightly":
      nextDate.setDate(
        nextDate.getDate() + 14
      );
      return nextDate;

    case "monthly":
      nextDate.setMonth(
        nextDate.getMonth() + 1
      );
      return nextDate;

    default:
      return null;
  }
}

function isSameDay(
  firstDate,
  secondDate,
) {

  return (
    firstDate.getFullYear() ===
      secondDate.getFullYear() &&
    firstDate.getMonth() ===
      secondDate.getMonth() &&
    firstDate.getDate() ===
      secondDate.getDate()
  );
}

function isCancelledDate(
  date,
  cancelledDates,
) {

  return cancelledDates.some(
    (cancelled) => {

      if (!cancelled || !cancelled.toDate) {
        return false;
      }

      return isSameDay(
        date,
        cancelled.toDate(),
      );
    },
  );
}

function calculateNextOccurrenceDate(
  currentDate,
  repeatType,
  cancelledDates,
) {

  let nextDate =
    new Date(currentDate);

  let safetyCounter = 0;

  while (safetyCounter < 50) {

    safetyCounter++;

    nextDate =
      addRepeatInterval(
        nextDate,
        repeatType,
      );

    if (!nextDate) {
      return null;
    }

    if (
      !isCancelledDate(
        nextDate,
        cancelledDates,
      )
    ) {
      return nextDate;
    }

    console.log(
      `Skipping cancelled date ${nextDate}`,
    );
  }

  console.log(
    "Stopped recurrence calculation after too many cancelled dates.",
  );

  return null;
}

async function createNextOccurrence(
  currentRef,
  currentId,
  nextDate,
) {

  await db.runTransaction(
    async (transaction) => {

      const latest =
        await transaction.get(
          currentRef,
        );

      if (!latest.exists) {
        return;
      }

      const latestData =
        latest.data();

      if (latestData.nextOccurrenceId) {
        return;
      }

      const nextRef =
        db
          .collection("opportunities")
          .doc();

      const nextOpportunity = {

        ...latestData,

        eventDate:
          admin.firestore.Timestamp.fromDate(
            nextDate,
          ),

        createdAt:
          admin.firestore.FieldValue.serverTimestamp(),

        updatedAt:
          admin.firestore.FieldValue.serverTimestamp(),

        occurrenceNumber:
          (latestData.occurrenceNumber ?? 1) + 1,

        previousOccurrenceId:
          currentId,

        nextOccurrenceId:
          null,

        attendeeCount: 0,

        commentCount: 0,

        reminder24hSent: false,

        reminder1hSent: false,

        skipNext: false,

        resumeAfter: null,

        seriesId:
          latestData.seriesId,

        seriesStatus:
          "active",
      };

      transaction.set(
        nextRef,
        nextOpportunity,
      );

      transaction.update(
        currentRef,
        {
          nextOccurrenceId:
            nextRef.id,

          updatedAt:
            admin.firestore.FieldValue.serverTimestamp(),
        },
      );

      console.log(
        `Created occurrence ${nextRef.id}`,
      );
    },
  );
}

async function skipNextOccurrence(
  currentRef,
  currentId,
  nextDate,
) {

  await db.runTransaction(
    async (transaction) => {

      const latest =
        await transaction.get(
          currentRef,
        );

      if (!latest.exists) {
        return;
      }

      const latestData =
        latest.data();

      if (latestData.nextOccurrenceId) {
        return;
      }

      transaction.update(
        currentRef,
        {
          eventDate:
            admin.firestore.Timestamp.fromDate(
              nextDate,
            ),

          skipNext: false,

          updatedAt:
            admin.firestore.FieldValue.serverTimestamp(),
        },
      );

      console.log(
        `Skipped next occurrence for ${currentId}`,
      );
    },
  );
}

exports.processRecurringOpportunities =
  onSchedule(
    {
      schedule: "every 15 minutes",
      region: "us-central1",
    },
    async () => {

      console.log(
        "Checking recurring opportunities...",
      );

      const snapshot =
        await db
          .collection("opportunities")
          .where(
            "isRecurring",
            "==",
            true,
          )
          .where(
            "isActive",
            "==",
            true,
          )
          .get();

      console.log(
        `Found ${snapshot.size} recurring opportunities.`,
      );

      const now =
        new Date();

      for (const doc of snapshot.docs) {

        const data =
          doc.data();

        if (
          data.seriesStatus === "ended"
        ) {
          continue;
        }

        if (
          data.repeatEndDate &&
          data.repeatEndDate.toDate() < now
        ) {
          continue;
        }

        if (
          data.resumeAfter &&
          data.resumeAfter.toDate() > now
        ) {
          continue;
        }

        if (
          data.resumeAfter &&
          data.resumeAfter.toDate() <= now
        ) {

          await doc.ref.update(
            {
              resumeAfter: null,

              updatedAt:
                admin.firestore.FieldValue.serverTimestamp(),
            },
          );
        }

        if (data.nextOccurrenceId) {
          continue;
        }

        if (!data.eventDate) {
          continue;
        }

        const currentDate =
          data.eventDate.toDate();

        if (currentDate > now) {
          continue;
        }

        const cancelledDates =
          data.cancelledDates ?? [];

        const nextDate =
          calculateNextOccurrenceDate(
            currentDate,
            data.repeatType,
            cancelledDates,
          );

        if (!nextDate) {
          continue;
        }

        if (
          data.repeatEndDate &&
          nextDate > data.repeatEndDate.toDate()
        ) {
          continue;
        }

        if (data.skipNext === true) {

          await skipNextOccurrence(
            doc.ref,
            doc.id,
            nextDate,
          );

          continue;
        }

        await createNextOccurrence(
          doc.ref,
          doc.id,
          nextDate,
        );
      }

      return;
    },
  );