'use strict';
const fs=require('fs'),assert=require('node:assert/strict');
const {initializeTestEnvironment,assertSucceeds,assertFails}=require('@firebase/rules-unit-testing');
const {doc,setDoc,getDoc,updateDoc,getDocs,collection,query,where}=require('firebase/firestore');
const {activityDiscoveryVisibility}=require('../functions/discovery_privacy');
(async()=>{
 if(!process.env.FIRESTORE_EMULATOR_HOST)throw Error('Local emulator required');
 const [host,port]=process.env.FIRESTORE_EMULATOR_HOST.split(':');if(host!=='127.0.0.1')throw Error('Only loopback emulator allowed');
 const payload=JSON.parse(fs.readFileSync(process.env.MODERATOR_PAYLOAD_FILE || 'test/fixtures/moderator_public_listing_payloads.json'));
 const env=await initializeTestEnvironment({projectId:'locallink-995a5',firestore:{host,port:Number(port),rules:fs.readFileSync('firestore.rules','utf8')}});
 const auth=uid=>env.authenticatedContext(uid,{firebase:{sign_in_provider:'password'}}).firestore();
 const adminDb=auth('moderator'),viewer=auth('viewer');
 await env.clearFirestore();
 await env.withSecurityRulesDisabled(async c=>setDoc(doc(c.firestore(),'users/moderator/private/account'),{isAdmin:true}));
 await env.withSecurityRulesDisabled(async c=>setDoc(doc(c.firestore(),'users/moderator/private/access'),{isAdmin:true}));
 await assertSucceeds(getDoc(doc(adminDb,'users/moderator/private/access')));
 await assertFails(getDoc(doc(adminDb,'users/moderator/private/account')));
 await assertFails(updateDoc(doc(adminDb,'users/moderator/private/access'),{isAdmin:false}));
 await assertFails(getDoc(doc(viewer,'users/moderator/private/access')));
 console.log('PASS owner-readable immutable access projection, private account denied even to administrator');
 await assertSucceeds(setDoc(doc(adminDb,'organisations/moderator-org'),payload.organisation));
 const moderatorOrganisations=await assertSucceeds(getDocs(query(collection(adminDb,'organisations'),where('createdByModerator','==',true))));
 assert.deepEqual(moderatorOrganisations.docs.map(d=>d.id),['moderator-org']);
 await assertFails(getDocs(query(collection(viewer,'organisations'),where('createdByModerator','==',true))));
 console.log('PASS administrator organisation listing query; ordinary viewers cannot query all moderator records');
 for(const name of ['publicLinked','publicStandalone','publicRecurring','restrictedOrganisation']){
  const data=name==='publicRecurring'?{...payload[name],recurrenceTimeZone:'Europe/London'}:payload[name];assert.equal(activityDiscoveryVisibility(data),name==='restrictedOrganisation'?'restricted':'public');
  await assertSucceeds(setDoc(doc(adminDb,'opportunities/'+name),data));
  const read=getDoc(doc(viewer,'opportunities/'+name));
  if(name==='restrictedOrganisation')await assertFails(read);else await assertSucceeds(read);
 }
 await assertFails(setDoc(doc(viewer,'opportunities/forged-moderator'),{...payload.publicLinked,createdBy:'viewer'}));
 await assertFails(updateDoc(doc(viewer,'opportunities/restrictedOrganisation'),{activityAudienceScope:'everyone',isPubliclyDiscoverable:true,discoveryVisibility:'public'}));
 const profileQuery = query(collection(viewer,'opportunities'), where('organisationId','==','moderator-org'), where('discoveryVisibility','==','public'), where('isActive','==',true));
 const profileDocs = await assertSucceeds(getDocs(profileQuery));
 assert.deepEqual(profileDocs.docs.map(d=>d.id).sort(), ['publicLinked','publicRecurring']);
 for (const doc of profileDocs.docs) {
   assert.equal(doc.data().organisationId, 'moderator-org');
   assert.equal(doc.data().organisationName, payload.organisation.name);
   assert.equal(doc.data().activityContext, 'organisation');
   assert.equal(doc.data().listingOwnershipStatus, 'unclaimed');
 }
 console.log('PASS exact organisation profile query includes linked setup activities, excludes standalone/restricted items, before claiming');
 const publicDocs=await assertSucceeds(getDocs(query(collection(viewer,'opportunities'),where('discoveryVisibility','==','public'),where('isActive','==',true))));
 assert.equal(publicDocs.size,3);console.log('PASS creation/public queries/restricted reads/forgery protections');
 // Exercise existing claim and recurrence handlers against LOCAL Firestore only.
 const functions=require('../functions/index');
 await env.withSecurityRulesDisabled(async c=>setDoc(doc(c.firestore(),'listingClaims/organisation-claim'),{listingType:'organisation',listingId:'moderator-org',claimantUserId:'representative',status:'pending'}));
 await functions.reviewListingClaim.run({data:{claimId:'organisation-claim',approve:true},auth:{uid:'moderator',token:{firebase:{sign_in_provider:'password'}}}});
 const claimed=(await getDoc(doc(viewer,'organisations/moderator-org'))).data();
 assert.equal(claimed.ownerId,'representative');assert.ok(claimed.adminUserIds.includes('representative'));
 for(const key of ['visibility','isPubliclyDiscoverable','discoveryVisibility','isActive'])assert.equal(claimed[key],payload.organisation[key]);
 assert.equal((await getDoc(doc(viewer,'opportunities/publicLinked'))).data().organisationId,'moderator-org');
 await assertSucceeds(updateDoc(doc(auth('representative'),'organisations/moderator-org'),{description:'Managed by authorised representative'}));
 await assertSucceeds(updateDoc(doc(auth('representative'),'opportunities/publicLinked'),{title:'Representative-managed community walk'}));
 assert.equal((await getDoc(doc(viewer,'opportunities/publicLinked'))).data().discoveryVisibility,'public');
 console.log('PASS actual claim transfer preserves public visibility and existing activities, with representative management access');
 const admin=require('firebase-admin'),store=admin.firestore();
 const oldDate=admin.firestore.Timestamp.fromDate(new Date(Date.now()-86400000));
 for(const [id,data]of [['recurrence-public',payload.publicRecurring],['recurrence-private',{...payload.restrictedOrganisation,isRecurring:true,repeatType:'weekly',seriesId:'private-series',seriesStatus:'active'}]])await store.doc('opportunities/'+id).set({...data,eventDate:oldDate,nextOccurrenceId:null});
 await functions.processRecurringOpportunities.run({});
 for(const id of ['recurrence-public','recurrence-private']){
  const original=(await store.doc('opportunities/'+id).get()).data();assert.ok(original.nextOccurrenceId);
  const next=(await store.doc('opportunities/'+original.nextOccurrenceId).get()).data();
  for(const key of ['activityAudienceScope','isPubliclyDiscoverable','discoveryVisibility','organisationId'])assert.equal(next[key],original[key]);
  assert.equal(activityDiscoveryVisibility(next),id==='recurrence-public'?'public':'restricted');
 }
 console.log('PASS actual recurring generator preserves public and restricted audiences');

 const RealDate=Date;
 try {
  for(const [label,seed,now,expected] of [
   ['october','2026-10-19T17:30:00Z','2026-10-20T12:00:00Z','2026-10-26T18:30:00.000Z'],
   ['march','2026-03-23T18:30:00Z','2026-03-24T12:00:00Z','2026-03-30T17:30:00.000Z']]) {
   global.Date=class extends RealDate { constructor(...args){super(...(args.length?args:[now]));} static now(){return new RealDate(now).getTime();} };
   for(const [privacyName,template] of [['public',payload.publicRecurring],['private',payload.restrictedOrganisation]]) {
    const id='dst-'+label+'-'+privacyName;
    await store.doc('opportunities/'+id).set({...template,isRecurring:true,repeatType:'weekly',recurrenceTimeZone:'Europe/London',eventTime:'18:30',endTime:'19:30',eventDate:admin.firestore.Timestamp.fromDate(new RealDate(seed)),seriesId:id,seriesStatus:'active',nextOccurrenceId:null,bookingEnabled:true,bookingCapacity:20});
   }
   const cancelledId='dst-cancelled-'+label;
   await store.doc('opportunities/'+cancelledId).set({...payload.publicRecurring,isRecurring:true,repeatType:'weekly',recurrenceTimeZone:'Europe/London',eventTime:'18:30',eventDate:admin.firestore.Timestamp.fromDate(new RealDate(seed)),seriesId:cancelledId,seriesStatus:'active',nextOccurrenceId:null,cancelledDates:[admin.firestore.Timestamp.fromDate(new RealDate(label==='october'?'2026-10-26T00:00:00Z':'2026-03-29T23:00:00Z'))],repeatEndDate:admin.firestore.Timestamp.fromDate(new RealDate(label==='october'?'2026-11-02T00:00:00Z':'2026-04-05T23:00:00Z'))});
   await functions.processRecurringOpportunities.run({});
   const cancelledOriginal=(await store.doc('opportunities/'+cancelledId).get()).data();
   assert.ok(cancelledOriginal.nextOccurrenceId);
   const afterCancellation=(await store.doc('opportunities/'+cancelledOriginal.nextOccurrenceId).get()).data();
   assert.equal(afterCancellation.eventDate.toDate().toISOString(),label==='october'?'2026-11-02T18:30:00.000Z':'2026-04-06T17:30:00.000Z');
   for(const privacyName of ['public','private']) {
    const id='dst-'+label+'-'+privacyName,original=(await store.doc('opportunities/'+id).get()).data();
    assert.ok(original.nextOccurrenceId);
    const next=(await store.doc('opportunities/'+original.nextOccurrenceId).get()).data();
    assert.equal(next.eventDate.toDate().toISOString(),expected);
    for(const key of ['organisationId','createdBy','organiserId','listingOwnershipStatus','claimStatus','activityAudienceScope','isPubliclyDiscoverable','discoveryVisibility','eventTime','endTime','bookingEnabled','bookingCapacity'])assert.deepEqual(next[key],original[key],key);
    const read=getDoc(doc(viewer,'opportunities/'+original.nextOccurrenceId));
    if(privacyName==='private')await assertFails(read);else await assertSucceeds(read);
   }
  }
 } finally {global.Date=RealDate;}
 console.log('PASS actual March/October DST generator, booking/ownership/association preservation and private read protection');
 await env.cleanup();
})().catch(error=>{console.error(error);process.exitCode=1});
