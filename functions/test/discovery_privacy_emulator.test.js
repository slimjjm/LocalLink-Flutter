'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('fs'),path=require('path');
const {initializeTestEnvironment,assertFails,assertSucceeds:checkSucceeds}=require('@firebase/rules-unit-testing');
const {doc,setDoc,getDoc,getDocs,collection,query,where,updateDoc,documentId}=require('firebase/firestore');
async function assertSucceeds(operation){const trace=new Error().stack;try{return await checkSucceeds(operation)}catch(error){throw new Error(error.message+'\n'+trace)}}
const admin=require('firebase-admin'),policy=require('../discovery_privacy');
test('private direct/list discovery, legacy privacy, geographic writes and public previews', {skip:!process.env.FIRESTORE_EMULATOR_HOST}, async()=>{
 const [host,port]=process.env.FIRESTORE_EMULATOR_HOST.split(':');
 const env=await initializeTestEnvironment({projectId:'demo-locallink-blockers',firestore:{host,port:Number(port),rules:fs.readFileSync(path.join(__dirname,'../../firestore.rules'),'utf8')}});
 const app=admin.initializeApp({projectId:'demo-locallink-blockers'},'discovery-test'),server=app.firestore();
 try {
 await env.clearFirestore();const common={createdBy:'owner',organiserId:'owner',isActive:true};
 const records={
 'organisations/org':{ownerId:'owner',isActive:true,listingOwnershipStatus:'claimed',adminUserIds:[]},
 'organisations/org/groups/public':{visibility:'public',discoveryVisibility:'public',isActive:true,leaderUserIds:[],membershipMode:'open',memberCount:0},
 'organisations/org/groups/private':{visibility:'private',discoveryVisibility:'restricted',isActive:true,leaderUserIds:['leader'],membershipMode:'open'},
 'organisations/org/groups/unknown':{discoveryVisibility:'restricted',isActive:true,leaderUserIds:['leader']},
 'organisations/org/groups/private/members/member':{userId:'member',status:'active'},
 'organisations/org/members/member':{userId:'member',status:'active',role:'member',groupIds:['private']},
 'organisations/org/members/ordinary':{userId:'ordinary',status:'active',role:'member',groupIds:[]},
 'opportunities/public':{...common,activityAudienceScope:'everyone',isPubliclyDiscoverable:true,discoveryVisibility:'public'},
 'opportunities/private':{...common,organisationId:'org',groupId:'private',activityAudienceScope:'group',isPubliclyDiscoverable:false,discoveryVisibility:'restricted'},
 'opportunities/legacyPrivate':{...common,organisationId:'org',groupId:'private'},
 'opportunities/legacyPublic':{...common},
 'opportunities/organisation':{...common,organisationId:'org',activityAudienceScope:'organisation',isPubliclyDiscoverable:false,discoveryVisibility:'restricted'},
 'opportunities/contradictory':{...common,activityAudienceScope:'everyone',isPubliclyDiscoverable:true,visibility:'private',discoveryVisibility:'restricted'},
 'opportunities/invalidScope':{...common,activityAudienceScope:'group',discoveryVisibility:'restricted'},
 'businesses/geo':{ownerId:'owner',createdBy:'owner',isClaimed:true,listingOwnershipStatus:'claimed',address:'Dundee',latitude:56.46,longitude:-2.97},
 };
 await env.withSecurityRulesDisabled(async c=>{for(const[p,d]of Object.entries(records))await setDoc(doc(c.firestore(),p),d)});
 const db=(uid,provider='password')=>env.authenticatedContext(uid,{firebase:{sign_in_provider:provider}}).firestore();
 const publicActivities=d=>query(collection(d,'opportunities'),where('isActive','==',true),where('discoveryVisibility','==','public'));
 for(const [uid,provider]of [['outsider','password'],['guest','anonymous'],['ordinary','password'],['member','password'],['leader','password']]){
  const d=db(uid,provider);await assertFails(getDocs(query(collection(d,'opportunities'),where('isActive','==',true))));await assertFails(getDocs(query(collection(d,'organisations/org/groups'),where('isActive','==',true))));
  assert.deepEqual((await assertSucceeds(getDocs(publicActivities(d)))).docs.map(d=>d.id),['public']);
  assert.deepEqual((await assertSucceeds(getDocs(query(collection(d,'organisations/org/groups'),where('discoveryVisibility','==','public'))))).docs.map(d=>d.id),['public']);
  if(!['member','leader'].includes(uid))for(const p of ['opportunities/private','opportunities/legacyPrivate','organisations/org/groups/private','organisations/org/groups/unknown'])await assertFails(getDoc(doc(d,p)));
  for(const p of ['opportunities/contradictory','opportunities/invalidScope'])await assertFails(getDoc(doc(d,p)));
  await assertSucceeds(getDoc(doc(d,'opportunities/legacyPublic')));
 }
 await assertFails(getDocs(publicActivities(env.unauthenticatedContext().firestore())));
 for(const uid of ['member','leader']){
  const d=db(uid);await assertSucceeds(getDoc(doc(d,'opportunities/private')));await assertSucceeds(getDoc(doc(d,'opportunities/legacyPrivate')));
  await assertSucceeds(getDocs(query(collection(d,'opportunities'),where('organisationId','==','org'),where('groupId','==','private'),where('isActive','==',true),where('activityAudienceScope','==','group'))));
  await assertSucceeds(getDocs(query(collection(d,'organisations/org/groups'),where(documentId(),'==','private'))));
 }
 await assertSucceeds(getDocs(query(collection(db('leader'),'organisations/org/groups'),where('leaderUserIds','array-contains','leader'))));
 await assertSucceeds(getDocs(collection(db('owner'),'organisations/org/groups')));
 await assertSucceeds(getDocs(query(collection(db('owner'),'opportunities'),where('organisationId','==','org'))));
 await assertSucceeds(getDocs(query(collection(db('ordinary'),'opportunities'),where('organisationId','==','org'),where('activityAudienceScope','==','organisation'),where('isActive','==',true))));
 await assertFails(setDoc(doc(db('outsider'),'organisations/org/groups/private/members/outsider'),{userId:'outsider',userName:'Outsider',role:'member',status:'active'}));
 const owner=db('owner');await assertFails(updateDoc(doc(owner,'opportunities/private'),{discoveryVisibility:'public'}));await assertFails(updateDoc(doc(owner,'opportunities/public'),{isPubliclyDiscoverable:false}));await assertSucceeds(updateDoc(doc(owner,'opportunities/public'),{isPubliclyDiscoverable:false,discoveryVisibility:'restricted'}));
 await assertFails(updateDoc(doc(owner,'organisations/org/groups/private'),{discoveryVisibility:'public'}));
 await assertFails(updateDoc(doc(owner,'businesses/geo'),{address:'Glasgow'}));await assertSucceeds(updateDoc(doc(owner,'businesses/geo'),{address:'Glasgow',locationAddress:'Glasgow',latitude:55.86,longitude:-4.25}));
 await assertFails(updateDoc(doc(db('outsider'),'businesses/geo'),{address:'Aberdeen',locationAddress:'Aberdeen',latitude:57.15,longitude:-2.09}));await assertFails(updateDoc(doc(owner,'businesses/geo'),{address:'Invalid',locationAddress:'Invalid',latitude:100,longitude:0}));
 const handlers=policy.buildDiscoveryPrivacyExports({db:server,onDocumentWritten:(_,fn)=>fn});
 for(const id of ['legacyPublic','legacyPrivate']){const ref=server.doc('opportunities/'+id);await handlers.onActivityDiscoveryChanged({data:{after:{exists:true,ref}}})}
 assert.equal((await server.doc('opportunities/legacyPrivate').get()).data().discoveryVisibility,'restricted');assert.deepEqual((await getDocs(publicActivities(db('outsider')))).docs.map(d=>d.id),['legacyPublic']);
 process.env.GCLOUD_PROJECT='demo-locallink-blockers';const api=require('../index');await assert.rejects(()=>api.getPublicSharePreview.run({data:{type:'activity',id:'legacyPrivate'}}),e=>e.code==='not-found');const preview=await api.getPublicSharePreview.run({data:{type:'activity',id:'legacyPublic'}});assert.equal(preview.id,'legacyPublic');
 await assertSucceeds(getDoc(doc(env.unauthenticatedContext().firestore(),'releaseConfig/clients')));await assertFails(setDoc(doc(owner,'releaseConfig/clients'),{ready:true,minimumBuild:1}));
 }finally{await env.cleanup();await app.delete();if(admin.apps.some(a=>a.name==='[DEFAULT]'))await admin.app().delete();}
});
