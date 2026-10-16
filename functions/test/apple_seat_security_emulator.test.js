'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
test('unverified Apple product IDs cannot grant seats or mutate existing entitlements', {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  process.env.GCLOUD_PROJECT = 'demo-locallink-stabilisation';
  const api = require('../index');
  const admin = require('firebase-admin');
  const ref = admin.firestore().doc('businesses/apple-security');
  const data = {ownerId:'apple-owner', staffSeatCount:2, entitlements:{staffSeats:2}, stripeSubscriptionStatus:'active'};
  await ref.set(data);
  const request = {auth:{uid:'apple-owner',token:{firebase:{sign_in_provider:'password'}}},data:{businessId:'apple-security',productId:'forged-product'}};
  await assert.rejects(() => api.verifyAppleSeatPurchase.run(request), e => e.code === 'failed-precondition');
  assert.deepEqual((await ref.get()).data(), data);
  await assert.rejects(() => api.verifyAppleSeatPurchase.run({...request,auth:{uid:'outsider',token:{}}}), e => e.code === 'permission-denied');
  await assert.rejects(() => api.verifyAppleSeatPurchase.run({...request,auth:undefined}), e => e.code === 'unauthenticated');
  await assert.rejects(() => api.verifyAppleSeatPurchase.run({...request,auth:{uid:'apple-owner',token:{firebase:{sign_in_provider:'anonymous'}}}}), e => e.code === 'failed-precondition');
  await admin.app().delete();
});
