"use strict";

const APPROVED_ADMIN_EMAILS = [
  "jae19882011@hotmail.co.uk",
  "founder@locallinkapp.co.uk",
];

function normaliseEmail(value) {
  return String(value || "").trim().toLowerCase();
}

async function requestHasAdminAccess({ db, auth }) {
  if (!auth) return false;

  const uid = String(auth.uid || "").trim();
  if (uid) {
    const userRef = db.collection("users").doc(uid);
    const [accountSnap, userSnap] = await Promise.all([
      userRef.collection("private").doc("account").get(),
      userRef.get(),
    ]);
    const isAdmin = accountSnap.exists
      ? accountSnap.data()?.isAdmin === true
      : userSnap.data()?.isAdmin === true;
    if (isAdmin) {
      return true;
    }
  }

  const email = normaliseEmail(auth.token?.email);
  if (!APPROVED_ADMIN_EMAILS.includes(email)) return false;

  const adminEmailSnap = await db.collection("adminEmails").doc(email).get();
  return adminEmailSnap.exists && adminEmailSnap.data()?.enabled !== false;
}

module.exports = {
  APPROVED_ADMIN_EMAILS,
  requestHasAdminAccess,
};
