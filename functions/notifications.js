const admin = require("firebase-admin");

const {
  onDocumentCreated,
  onDocumentUpdated,
} = require("firebase-functions/v2/firestore");

const { getMessaging } =
  require("firebase-admin/messaging");

const db = admin.firestore();

// =================================================
// PUSH HELPER
// =================================================

async function sendPushToUser(
  uid,
  payload,
) {
  if (!uid) {
    console.log(
      "⏭️ sendPushToUser skipped: missing uid"
    );
    return;
  }

  const userRef =
    db.collection("users").doc(uid);

  const snap = await userRef.get();

  if (!snap.exists) {
    console.log(
      "⏭️ sendPushToUser skipped: user doc missing",
      uid
    );
    return;
  }

  const rawTokens =
    snap.data()?.fcmTokens || [];

  const tokens = [
    ...new Set(
      rawTokens.filter(Boolean)
    ),
  ];

  if (!tokens.length) {
    console.log(
      "⏭️ sendPushToUser skipped: no tokens for",
      uid
    );
    return;
  }

  const message = {
    tokens,

    notification: {
      title:
        payload.title ||
        "LocalLink",
      body:
        payload.body || "",
    },

    data: Object.fromEntries(
      Object.entries(
        payload.data || {}
      ).map(([k, v]) => [
        k,
        String(v),
      ])
    ),

    apns: {
      headers: {
        "apns-priority": "10",
      },
      payload: {
        aps: {
          alert: {
            title:
              payload.title ||
              "LocalLink",
            body:
              payload.body || "",
          },
          sound: "default",
          badge: 1,
          contentAvailable: true,
        },
      },
    },
  };

  const response =
    await getMessaging()
      .sendEachForMulticast(
        message
      );

  console.log(
    "📬 Push result",
    {
      uid,
      successCount:
        response.successCount,
      failureCount:
        response.failureCount,
      tokenCount:
        tokens.length,
    }
  );

  const badTokens = [];

  response.responses.forEach(
    (resp, idx) => {
      if (!resp.success) {
        const token =
          tokens[idx];

        const code =
          resp.error?.code ||
          "unknown";

        if (
          code ===
            "messaging/registration-token-not-registered" ||
          code ===
            "messaging/invalid-registration-token"
        ) {
          badTokens.push(
            token
          );
        }
      }
    }
  );

  if (badTokens.length) {
    await userRef.update({
      fcmTokens:
        admin.firestore.FieldValue.arrayRemove(
          ...badTokens
        ),
    });
  }
}

// =================================================
// NEW MESSAGE NOTIFICATION
// =================================================

exports.notifyNewMessage =
  onDocumentCreated(
    {
      document:
        "businessChats/{chatId}/messages/{messageId}",
      region:
        "us-central1",
    },
    async (event) => {
      try {
        const message =
          event.data?.data();

        if (!message) return;

        if (
          message.senderRole ===
            "system" ||
          message.senderId ===
            "system"
        ) {
          return;
        }

        const chatId =
          event.params.chatId;

        const chatSnap =
          await db
            .collection(
              "businessChats"
            )
            .doc(chatId)
            .get();

        if (!chatSnap.exists)
          return;

        const chat =
          chatSnap.data();

        let targetUserId =
          null;

        if (
          message.senderId ===
          chat.customerId
        ) {
          const businessSnap =
            await db
              .collection(
                "businesses"
              )
              .doc(
                chat.businessId
              )
              .get();

          targetUserId =
            businessSnap.data()
              ?.ownerId ||
            null;
        } else {
          targetUserId =
            chat.customerId ||
            null;
        }

        if (!targetUserId)
          return;

        await sendPushToUser(
          targetUserId,
          {
            title:
              "New message",
            body:
              message.text ||
              "You have a new message",
            data: {
              chatId,
              messageId:
                event.params
                  .messageId,
              type:
                "new_message",
            },
          }
        );
      } catch (error) {
        console.error(
          "❌ notifyNewMessage error:",
          error
        );
      }
    }
  );

// =================================================
// BOOKING CANCELLED NOTIFICATION
// =================================================

exports.notifyBookingCancelled =
  onDocumentUpdated(
    {
      document:
        "bookings/{bookingId}",
      region:
        "us-central1",
    },
    async (event) => {
      const before =
        event.data.before.data();

      const after =
        event.data.after.data();

      if (
        !before ||
        !after
      )
        return;

      const wasConfirmed =
        before.status ===
        "confirmed";

      const isCancelled =
        after.status ===
          "cancelled_by_business" ||
        after.status ===
          "cancelled_by_customer";

      if (
        !wasConfirmed ||
        !isCancelled
      ) {
        return;
      }

      await sendPushToUser(
        after.customerId,
        {
          title:
            "Booking cancelled",
          body:
            "Your booking has been cancelled.",
          data: {
            type:
              "booking_cancelled",
            bookingId:
              event.params
                .bookingId,
          },
        }
      );
    }
  );

  // =================================================
// NEW FOLLOWER NOTIFICATION
// =================================================

exports.notifyNewFollower =
  onDocumentCreated(
    {
      document:
        "users/{userId}/followers/{followerId}",
      region: "us-central1",
    },
    async (event) => {
      try {

        const targetUserId =
          event.params.userId;

        const follower =
          event.data?.data();

        if (!follower) return;

        const followerName =
          follower.userName ||
          "Someone";

        // Create notification document

        await db
          .collection("users")
          .doc(targetUserId)
          .collection("notifications")
          .add({

            type: "follow",

            title: "New follower",

            body:
              `${followerName} started following you`,

            followerId:
              follower.userId,

            followerName,

            photoUrl:
              follower.photoUrl || null,

            isRead: false,

            createdAt:
              admin.firestore.FieldValue
                .serverTimestamp(),
          });

        // Push notification

        await sendPushToUser(
          targetUserId,
          {
            title:
              "New follower",

            body:
              `${followerName} started following you`,

            data: {
              type: "follow",
              followerId:
                follower.userId || "",
            },
          }
        );

        console.log(
          "✅ Follow notification created",
          {
            targetUserId,
            followerName,
          }
        );

    
      } catch (error) {

        console.error(
            
          "❌ notifyNewFollower error:",
          error
        );
      }
    }
  );