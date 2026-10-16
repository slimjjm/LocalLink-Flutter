const admin = require("firebase-admin");

const {
  onSchedule,
} = require("firebase-functions/v2/scheduler");

const db = admin.firestore();

const { addRepeatInterval, sameLocalDay, afterLocalDay, occurrenceScheduleFields } = require("./recurrence_calendar");

function isCancelledDate(
  date,
  cancelledDates,
  data = {},
) {

  return cancelledDates.some(
    (cancelled) => {

      if (!cancelled || !cancelled.toDate) {
        return false;
      }

      return sameLocalDay(
        date,
        cancelled.toDate(),
        data,
      );
    },
  );
}

function calculateNextOccurrenceDate(
  currentDate,
  repeatType,
  cancelledDates,
  data = {},
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
        data,
      );

    if (!nextDate) {
      return null;
    }

    if (
      !isCancelledDate(
        nextDate,
        cancelledDates,
        data,
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
        ...occurrenceScheduleFields(latestData, nextDate),

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
          ...occurrenceScheduleFields(latestData, nextDate),
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
      preserveExternalChanges: true,
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
        try {
          new Intl.DateTimeFormat("en-GB", { timeZone: data.recurrenceTimeZone || "Europe/London" });
        } catch (error) {
          console.error(`Invalid recurrence timezone ${doc.id}: ${error.message}`);
          continue;
        }

        if (
          data.seriesStatus === "ended"
        ) {
          continue;
        }

        if (
          data.repeatEndDate &&
          afterLocalDay(now, data.repeatEndDate.toDate(), data)
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

        let nextDate;
        try {
          nextDate = calculateNextOccurrenceDate(
            currentDate,
            data.repeatType,
            cancelledDates,
            data,
          );
        } catch (error) {
          console.error(`Invalid recurring schedule ${doc.id}: ${error.message}`);
          continue;
        }

        if (!nextDate) {
          continue;
        }

        if (
          data.repeatEndDate &&
          afterLocalDay(nextDate, data.repeatEndDate.toDate(), data)
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