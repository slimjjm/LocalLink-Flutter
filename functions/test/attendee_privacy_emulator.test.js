const fs=require('fs');
const test=require('node:test');
const path=require('node:path');
const {initializeTestEnvironment,assertFails,assertSucceeds}=require('@firebase/rules-unit-testing');
const {doc,setDoc,getDoc,getDocs,collection,collectionGroup,query,where,updateDoc}=require('firebase/firestore');
test('private attendee access, own history and legitimate participation', {skip:!process.env.FIRESTORE_EMULATOR_HOST}, async()=>{
const [host, port] = process.env.FIRESTORE_EMULATOR_HOST.split(':');
const env=await initializeTestEnvironment({projectId:'demo-locallink-stabilisation',firestore:{host,port:Number(port),rules:fs.readFileSync(path.join(__dirname,'../../firestore.rules'),'utf8')}});
await env.clearFirestore();
await env.withSecurityRulesDisabled(async c=>{
 for(const [p,d]of Object.entries({
 'businesses/hours':{ownerId:'member',createdBy:'member',isClaimed:true,listingOwnershipStatus:'claimed',stripeConnected:false,stripeChargesEnabled:false},
 'organisations/org':{ownerId:'manager',listingOwnershipStatus:'claimed',adminUserIds:[]},
 'organisations/org/groups/private':{visibility:'private',leaderUserIds:[]},
 'organisations/org/groups/private/members/member':{userId:'member',status:'active'},
 'opportunities/private':{createdBy:'manager',organiserId:'manager',isActive:true,organisationId:'org',groupId:'private',activityAudienceScope:'group',attendeeCount:1},
 'opportunities/private/attendees/member':{userId:'member',userName:'Private Member',joinedAt:new Date()},
 'opportunities/public':{createdBy:'manager',organiserId:'manager',isActive:true,activityAudienceScope:'everyone',isPubliclyDiscoverable:true,attendeeCount:0},
 })) await setDoc(doc(c.firestore(),p),d);
});
const db=uid=>env.authenticatedContext(uid,{firebase:{sign_in_provider:'password'},email_verified:true}).firestore();
const outside=db('outside'),member=db('member');
await assertFails(getDoc(doc(outside,'opportunities/private')));

 await assertFails(getDoc(doc(outside,'opportunities/private/attendees/member')));
 await assertFails(getDocs(collection(outside,'opportunities/private/attendees')));
 await assertSucceeds(getDocs(collection(member,'opportunities/private/attendees')));
 await assertSucceeds(getDocs(query(collectionGroup(member,'attendees'),where('userId','==','member'))));
 await assertFails(getDocs(collectionGroup(outside,'attendees')));
 await assertSucceeds(setDoc(doc(outside,'opportunities/public/attendees/outside'),{userId:'outside',joinedAt:new Date()}));
 await assertFails(setDoc(doc(outside,'opportunities/private/attendees/outside'),{userId:'outside',joinedAt:new Date()}));
 await assertFails(setDoc(doc(outside,'opportunities/public/attendees/fake'),{userId:'member',joinedAt:new Date()}));
 console.log('CANDIDATE PASS: private denial, authorised roster, own filtered history, public participation and spoof denial.');
await assertSucceeds(updateDoc(doc(member,'businesses/hours'),{openingHours:'Monday 09:00–17:00',openingHoursStructured:{monday:{open:'09:00',close:'17:00'}}}));
await assertFails(updateDoc(doc(outside,'businesses/hours'),{openingHours:'Changed'}));
await assertFails(updateDoc(doc(member,'businesses/hours'),{openingHoursStructured:'invalid'}));
await assertFails(updateDoc(doc(member,'businesses/hours'),{stripeConnected:true}));
await assertFails(setDoc(doc(member,'users/manager/reviews/member'),{rating:5,reviewerId:'member'}));
await env.cleanup();
});
