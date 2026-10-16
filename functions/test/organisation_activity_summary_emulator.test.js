'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const admin=require('firebase-admin');
const {initializeTestEnvironment,assertFails,assertSucceeds}=require('@firebase/rules-unit-testing');
const {doc,setDoc,getDoc,updateDoc}=require('firebase/firestore');
const {buildActivityStabilisationExports}=require('../activity_stabilisation');
const {buildDiscoveryPrivacyExports}=require('../discovery_privacy');

test('organisation summaries publish only public metadata and revoke tracked private summaries', {skip:!process.env.FIRESTORE_EMULATOR_HOST},async t=>{
 const [host,port]=process.env.FIRESTORE_EMULATOR_HOST.split(':');
 assert.equal(host,'127.0.0.1');
 const projectId='demo-locallink-summary-correction';
 const app=admin.initializeApp({projectId},'summary-correction');const db=app.firestore();
 const creation=buildActivityStabilisationExports({admin,db,onCall:(_,fn)=>fn,onDocumentCreated:(_,fn)=>fn,HttpsError:class extends Error{},sendPushToUser:async()=>{throw Error('Unexpected push')}});
 const sync=buildDiscoveryPrivacyExports({admin,db,onDocumentWritten:(_,fn)=>fn});
 try{
 for(const [cohort,rules]of [['candidate',fs.readFileSync(require('node:path').join(__dirname,'../../firestore.rules'),'utf8')],...(process.env.SUMMARY_DEPLOYED_RULES?[['deployed',fs.readFileSync(process.env.SUMMARY_DEPLOYED_RULES,'utf8')]]:[])]){
  await t.test(cohort,async()=>{
   const env=await initializeTestEnvironment({projectId,firestore:{host,port:Number(port),rules}});
   try{
    await env.clearFirestore();
    await env.withSecurityRulesDisabled(async c=>{for(const [p,d]of Object.entries({'users/owner':{isAdmin:false,isBanned:false},'users/outsider':{isAdmin:false,isBanned:false},'organisations/org':{ownerId:'owner',adminUserIds:[],listingOwnershipStatus:'claimed',isActive:true,activityCount:0},'organisations/org/groups/private':{visibility:'private',isActive:true,leaderUserIds:['owner'],membershipMode:'approval_required'}}))await setDoc(doc(c.firestore(),p),d)});
    const owner=env.authenticatedContext('owner',{firebase:{sign_in_provider:'password'}}).firestore(),outsider=env.authenticatedContext('outsider',{firebase:{sign_in_provider:'password'}}).firestore();
    const base={createdBy:'owner',organiserId:'owner',organisationId:'org',isActive:true,eventDate:new Date('2026-10-12T12:00:00Z')};
    await assertSucceeds(setDoc(doc(owner,'opportunities/public'),{...base,title:'Public session',activityAudienceScope:'everyone',isPubliclyDiscoverable:true}));
    await creation.onOrganisationActivityCreated({params:{opportunityId:'public'}});
    await creation.onOrganisationActivityCreated({params:{opportunityId:'public'}});
    let org=(await getDoc(doc(outsider,'organisations/org'))).data();
    assert.equal(org.activityCount,1);assert.equal(org.latestAddedSessionTitle,'Public session');assert.equal(org.latestAddedSessionId,'public');assert.ok(org.latestAddedSessionAt);
    await assertSucceeds(setDoc(doc(owner,'opportunities/private'),{...base,title:'PRIVATE TITLE',groupId:'private',activityAudienceScope:'group',isPubliclyDiscoverable:false}));
    await creation.onOrganisationActivityCreated({params:{opportunityId:'private'}});
    await assertFails(getDoc(doc(outsider,'opportunities/private')));await assertSucceeds(getDoc(doc(owner,'opportunities/private')));
    org=(await getDoc(doc(outsider,'organisations/org'))).data();assert.equal(org.activityCount,2);assert.equal(org.latestAddedSessionTitle,'Public session');assert.equal(org.latestAddedSessionId,'public');
    // Unknown/contradictory source privacy stays restricted, even with a forged marker.
    for(const [id,extra]of [['unknown',{activityAudienceScope:'unknown'}],['conflict',{activityAudienceScope:'everyone',isPrivate:true,isPubliclyDiscoverable:true}]]){
     await db.doc('opportunities/'+id).set({...base,...extra,title:'DO NOT PUBLISH',discoveryVisibility:'public'});
     await creation.onOrganisationActivityCreated({params:{opportunityId:id}});
     assert.equal((await db.doc('organisations/org').get()).data().latestAddedSessionId,'public');
    }
    const ref=db.doc('opportunities/public'),before=await ref.get();
    // Existing rules protect audience changes; simulate an authorised backend transition.
    await ref.update({activityAudienceScope:'group',groupId:'private',isPubliclyDiscoverable:false,title:'NEW PRIVATE TITLE',eventDate:admin.firestore.Timestamp.fromDate(new Date('2026-10-13T12:00:00Z'))});
    const after=await ref.get();
    const event={data:{before,after},params:{opportunityId:'public'}};
    await sync.onActivityDiscoveryChanged(event);await sync.onActivityDiscoveryChanged(event);
    org=(await getDoc(doc(outsider,'organisations/org'))).data();
    for(const key of ['latestAddedSessionId','latestAddedSessionTitle','latestAddedSessionAt'])assert.equal(key in org,false);
    assert.equal(org.activityCount,4);await assertFails(getDoc(doc(outsider,'opportunities/public')));await assertSucceeds(getDoc(doc(owner,'opportunities/public')));
    await creation.onOrganisationActivityCreated({params:{opportunityId:'public'}});
    assert.equal('latestAddedSessionTitle' in (await db.doc('organisations/org').get()).data(),false);
    await setDoc(doc(owner,'opportunities/new-public'),{...base,title:'Another public session',activityAudienceScope:'everyone',isPubliclyDiscoverable:true});
    await creation.onOrganisationActivityCreated({params:{opportunityId:'new-public'}});
    await sync.onActivityDiscoveryChanged(event);
    assert.equal((await db.doc('organisations/org').get()).data().latestAddedSessionId,'new-public');
    // A stale private event must re-read newer public state rather than erase it.
    const pub=db.doc('opportunities/new-public'),current=await pub.get();
    await sync.onActivityDiscoveryChanged({data:{before:after,after:{exists:true,ref:pub,data:()=>({...current.data(),isPrivate:true})}}});
    assert.equal((await db.doc('organisations/org').get()).data().latestAddedSessionTitle,'Another public session');
   }finally{await env.cleanup()}
  });
 }
 }finally{await app.delete()}
});
