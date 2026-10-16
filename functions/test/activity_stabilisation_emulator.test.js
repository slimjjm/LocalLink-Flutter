const assert=require('node:assert/strict');
const admin=require('firebase-admin');
const {buildActivityStabilisationExports}=require('../activity_stabilisation');
require('node:test')('activity transactions, permissions and duplicate prevention', {skip:!process.env.FIRESTORE_EMULATOR_HOST}, async()=>{
admin.initializeApp({projectId:'demo-locallink-stabilisation'});
const db=admin.firestore();
let pushes=0;
const handlers=buildActivityStabilisationExports({admin,db,onCall:(_,fn)=>fn,onDocumentCreated:(_,fn)=>fn,HttpsError:class extends Error{constructor(code,msg){super(msg);this.code=code}},sendPushToUser:async()=>{pushes++;throw Error('synthetic unavailable route')},now:()=>Date.now()});

for(const [p,d]of Object.entries({'users/reviewhost':{name:'Host'},'users/reviewguest':{name:'Guest'},'organisations/runtimeorg':{activityCount:0},'opportunities/runtimeactivity':{organiserId:'reviewhost',createdBy:'reviewhost',eventDate:admin.firestore.Timestamp.fromMillis(Date.now()-100000),title:'Test',activityAudienceScope:'everyone',organisationId:'runtimeorg',isPubliclyDiscoverable:true},'opportunities/runtimeactivity/attendees/reviewguest':{userId:'reviewguest'}}))await db.doc(p).set(d);
const request={auth:{uid:'reviewguest',token:{firebase:{sign_in_provider:'password'}}},data:{opportunityId:'runtimeactivity',organiserId:'reviewhost',rating:5,text:'Helpful'}};
assert.deepEqual(await handlers.submitOrganiserReview(request),{alreadyReviewed:false});
assert.deepEqual(await handlers.submitOrganiserReview(request),{alreadyReviewed:true});
assert.equal((await db.doc('users/reviewhost').get()).data().reviewCount,1);
await assert.rejects(()=>handlers.submitOrganiserReview({...request,auth:{uid:'nonattendee',token:{} }}),e=>e.code==='failed-precondition');
await assert.rejects(()=>handlers.submitOrganiserReview({...request,auth:{uid:'guest',token:{firebase:{sign_in_provider:'anonymous'}}}}),e=>e.code==='unauthenticated');
await handlers.onOrganisationActivityCreated({params:{opportunityId:'runtimeactivity'}});
await handlers.onOrganisationActivityCreated({params:{opportunityId:'runtimeactivity'}});
assert.equal((await db.doc('organisations/runtimeorg').get()).data().activityCount,1);
try{await handlers.onActivityAttendanceCreated({params:{opportunityId:'runtimeactivity',userId:'reviewguest'}})}catch(e){assert.match(e.message,/synthetic/)}
await handlers.onActivityAttendanceCreated({params:{opportunityId:'runtimeactivity',userId:'reviewguest'}});
assert.equal((await db.collection('users/reviewhost/notifications').get()).size,2);
assert.equal(pushes,2);
console.log('PASS: atomic review, idempotency, guest/nonattendee denial, push failure persistence, organisation summary and attendance dedupe');
await admin.app().delete();
});
