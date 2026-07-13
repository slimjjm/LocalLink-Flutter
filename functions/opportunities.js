const admin = require("firebase-admin");

const {
  onSchedule,
} = require("firebase-functions/v2/scheduler");

const db = admin.firestore();

exports.expireOldOpportunities =
  onSchedule(
    {
      schedule: "every day 02:00",
      region: "us-central1",
    },
    async () => {

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

          const eventDate =
            data.eventDate;

          if (!eventDate) return;

          const date =
            eventDate.toDate();

          if (date < now) {

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