'use strict';
async function ownedBillingBusiness({db,uid,businessId,HttpsError}) {
  if (businessId !== undefined && (typeof businessId !== 'string' || !businessId.trim() || businessId.includes('/'))) {
    throw new HttpsError('invalid-argument','Choose a business to manage its subscription.');
  }
  if (businessId !== undefined) {
    const ref = db.collection('businesses').doc(businessId.trim());
    const snapshot = await ref.get();
    if (!snapshot.exists) throw new HttpsError('not-found','Business not found.');
    if (snapshot.data().ownerId !== uid) throw new HttpsError('permission-denied','Not your business.');
    return ref;
  }
  const owned = await db.collection('businesses').where('ownerId','==',uid).limit(2).get();
  if (owned.empty) throw new HttpsError('not-found','Business not found.');
  if (owned.size !== 1) throw new HttpsError('failed-precondition','Choose which business subscription you want to manage.');
  return owned.docs[0].ref;
}
module.exports = {ownedBillingBusiness};
