'use strict';
const fs=require('node:fs'),path=require('node:path'),test=require('node:test'),assert=require('node:assert/strict');
const {initializeTestEnvironment,assertSucceeds,assertFails}=require('@firebase/rules-unit-testing');
const {collection,doc,setDoc,getDoc,getDocs,query,where,orderBy,updateDoc,onSnapshot,or,and}=require('firebase/firestore');
let env;
const db=(uid,provider='password')=>uid?env.authenticatedContext(uid,{firebase:{sign_in_provider:provider}}).firestore():env.unauthenticatedContext().firestore();
const series=(d,scope={},id='shared')=>query(collection(d,'opportunities'),where('seriesId','==',id),...Object.entries(scope).map(([key,value])=>where(key,'==',value)),orderBy('eventDate'));
test.before(async()=>{if(!process.env.FIRESTORE_EMULATOR_HOST)return;const [host,port]=process.env.FIRESTORE_EMULATOR_HOST.split(':');env=await initializeTestEnvironment({projectId:'demo-locallink-recurring-final',firestore:{host,port:Number(port),rules:fs.readFileSync(path.join(__dirname,'../../firestore.rules'),'utf8')}});await env.clearFirestore();await env.withSecurityRulesDisabled(async c=>{
const d=c.firestore(),common={createdBy:'creator',organiserId:'organiser',organisationId:'org',groupId:'private',seriesId:'shared',eventDate:new Date('2030-01-01'),activityAudienceScope:'group',discoveryVisibility:'restricted',isActive:true};
for(const [p,data]of Object.entries({
 'users/admin/private/account':{isAdmin:true},
 'organisations/org':{ownerId:'owner',adminUserIds:['org-admin'],listingOwnershipStatus:'claimed',isActive:true},
 'organisations/org/members/secretary':{status:'active',role:'secretary'},
 'organisations/org/members/suspended':{status:'removed',role:'organisation_admin'},
 'organisations/org/members/ordinary':{status:'active',role:'member'},
 'organisations/org/members/label-only-leader':{status:'active',role:'group_leader'},
 'organisations/org/groups/private':{visibility:'private',leaderUserIds:['leader']},
 'organisations/org/groups/private/members/member':{userId:'member',status:'active'},
 'opportunities/active':common,
 'opportunities/inactive':{...common,isActive:false,eventDate:new Date('2030-01-02'),occurrenceStatus:'cancelled'},
 'opportunities/legacy-creator':{createdBy:'creator',seriesId:'shared',eventDate:new Date('2030-01-03'),isActive:false},
 'opportunities/foreign':{...common,createdBy:'foreign',organiserId:'foreign',organisationId:'foreign',groupId:'foreign',eventDate:new Date('2030-01-04')},
 'opportunities/active/attendees/attendee':{userId:'attendee',userName:'Private Attendee'},
 }))await setDoc(doc(d,p),data);
})});
test.after(async()=>{await env?.cleanup()});
const opts={skip:!process.env.FIRESTORE_EMULATOR_HOST};
test('bare legacy series query is rejected except for verified platform admin',opts,async()=>{
 for(const uid of ['creator','organiser','owner','org-admin','secretary','leader','ordinary','outsider',null])await assertFails(getDocs(series(db(uid))));
 await assertFails(getDocs(series(db('guest','anonymous'))));
 assert.equal((await assertSucceeds(getDocs(series(db('admin'))))).size,4);
});
test('creator-only legacy and organiser queries preserve active and cancelled own occurrences',opts,async()=>{
 assert.deepEqual((await assertSucceeds(getDocs(series(db('creator'),{createdBy:'creator'})))).docs.map(d=>d.id),['active','inactive','legacy-creator']);
 assert.deepEqual((await assertSucceeds(getDocs(series(db('organiser'),{organiserId:'organiser'})))).docs.map(d=>d.id),['active','inactive']);
 await assertFails(getDocs(series(db('outsider'),{createdBy:'creator'})));
});
test('claimed organisation owner, admin and active secretary manage all scoped occurrences',opts,async()=>{
 for(const uid of ['owner','org-admin','secretary']){
 assert.deepEqual((await assertSucceeds(getDocs(series(db(uid),{organisationId:'org'})))).docs.map(d=>d.id),['active','inactive']);
 await assertSucceeds(getDoc(doc(db(uid),'opportunities/inactive')));
 await assertSucceeds(updateDoc(doc(db(uid),'opportunities/inactive'),{occurrenceStatus:'active',updatedAt:new Date()}));
 }
});
test('actual group leader manages inactive occurrences, but cannot list foreign organisation or whole org',opts,async()=>{
 assert.deepEqual((await assertSucceeds(getDocs(series(db('leader'),{organisationId:'org',groupId:'private'})))).docs.map(d=>d.id),['active','inactive']);
 await assertSucceeds(getDoc(doc(db('leader'),'opportunities/inactive')));
 await assertSucceeds(updateDoc(doc(db('leader'),'opportunities/inactive'),{occurrenceStatus:'skipped'}));
 await assertFails(getDocs(series(db('leader'),{organisationId:'org'})));
 await assertFails(getDocs(series(db('leader'),{organisationId:'foreign',groupId:'foreign'})));
});
test('ordinary members, inactive admins, role-labelled leaders and outsiders cannot manage private series',opts,async()=>{
 for(const uid of ['ordinary','suspended','label-only-leader','outsider',null]){
 await assertFails(getDocs(series(db(uid),{organisationId:'org',groupId:'private'})));
 await assertFails(getDoc(doc(db(uid),'opportunities/inactive')));
 await assertFails(updateDoc(doc(db(uid),'opportunities/inactive'),{occurrenceStatus:'active'}));
 }
 await assertFails(getDocs(series(db('guest','anonymous'),{organisationId:'org',groupId:'private'})));
});
test('ordinary group participation stays active-only and does not gain attendee roster access',opts,async()=>{
 await assertFails(getDocs(series(db('member'),{organisationId:'org',groupId:'private'})));
 const q=query(collection(db('member'),'opportunities'),where('seriesId','==','shared'),where('organisationId','==','org'),where('groupId','==','private'),where('isActive','==',true),where('activityAudienceScope','==','group'),orderBy('eventDate'));
 assert.deepEqual((await assertSucceeds(getDocs(q))).docs.map(d=>d.id),['active']);
 for(const uid of ['ordinary','outsider']){await assertFails(getDocs(collection(db(uid),'opportunities/active/attendees')));await assertFails(getDoc(doc(db(uid),'opportunities/active/attendees/attendee')))}
});
test('revoking verified group leadership removes inactive series and direct access immediately',opts,async()=>{
 await env.withSecurityRulesDisabled(c=>updateDoc(doc(c.firestore(),'organisations/org/groups/private'),{leaderUserIds:[]}));
 await assertFails(getDocs(series(db('leader'),{organisationId:'org',groupId:'private'})));
 await assertFails(getDoc(doc(db('leader'),'opportunities/inactive')));
});

test('authoritative group listener revokes on leadership change; fresh private-series queries deny',opts,async()=>{
 await env.withSecurityRulesDisabled(c=>updateDoc(doc(c.firestore(),'organisations/org/groups/private'),{leaderUserIds:['leader']}));
 let unsubscribe,firstResolve,deniedResolve;
 const first=new Promise(resolve=>{firstResolve=resolve});
 const denied=new Promise(resolve=>{deniedResolve=resolve});
 unsubscribe=onSnapshot(doc(db('leader'),'organisations/org/groups/private'),snap=>firstResolve(snap),error=>deniedResolve(error));
 let timer;
 try {
 assert.equal((await first).data().leaderUserIds[0],'leader');
 await env.withSecurityRulesDisabled(c=>updateDoc(doc(c.firestore(),'organisations/org/groups/private'),{leaderUserIds:[]}));
 const error=await Promise.race([denied,new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('Authority listener did not revoke within 5 seconds')),5000)})]);
 assert.equal(error.code,'permission-denied');
 await assertFails(getDocs(series(db('leader'),{organisationId:'org',groupId:'private'})));
 }finally{clearTimeout(timer);unsubscribe?.()}
});

test('group membership cannot list explicit unknown audience, while actual member feed preserves public/group and manager legacy access',opts,async()=>{
 await env.withSecurityRulesDisabled(async c=>{
  const d=c.firestore();
  await setDoc(doc(d,'opportunities/unknown-audience'),{createdBy:'other',organiserId:'other',organisationId:'org',groupId:'private',seriesId:'shared',eventDate:new Date('2030-01-05'),isActive:true,activityAudienceScope:'restricted',discoveryVisibility:'restricted'});
  await setDoc(doc(d,'opportunities/legacy-group'),{createdBy:'other',organiserId:'other',organisationId:'org',groupId:'private',eventDate:new Date('2030-01-06'),isActive:true});
  await setDoc(doc(d,'opportunities/public-group'),{createdBy:'other',organiserId:'other',organisationId:'org',groupId:'private',eventDate:new Date('2030-01-07'),isActive:true,activityAudienceScope:'everyone',discoveryVisibility:'public'});
 });
 const feed=(d,scoped)=>query(collection(d,'opportunities'),and(where('organisationId','==','org'),where('groupId','==','private'),where('isActive','==',true),...(scoped?[or(where('activityAudienceScope','==','group'),where('discoveryVisibility','==','public'))]:[])));
 await assertFails(getDoc(doc(db('member'),'opportunities/unknown-audience')));
 await assertFails(getDocs(feed(db('member'),false)));
 assert.deepEqual((await assertSucceeds(getDocs(feed(db('member'),true)))).docs.map(d=>d.id).sort(),['active','public-group']);
 await assertSucceeds(getDocs(feed(db('owner'),false)));
 await assertSucceeds(getDoc(doc(db('owner'),'opportunities/legacy-group')));
 await assertFails(getDocs(feed(db('outsider'),true)));
});
