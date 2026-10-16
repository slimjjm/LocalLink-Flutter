const fs=require('fs');
const {initializeTestEnvironment,assertFails,assertSucceeds}=require('@firebase/rules-unit-testing');
const {doc,setDoc,getDoc,writeBatch,updateDoc}=require('firebase/firestore');
require('node:test')('derived organisation membership permissions', {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async()=>{
 const [host, port] = process.env.FIRESTORE_EMULATOR_HOST.split(':');
const env=await initializeTestEnvironment({projectId:'demo-locallink-stabilisation',firestore:{host,port:Number(port),rules:fs.readFileSync(require('node:path').join(__dirname,'../../firestore.rules'),'utf8')}});
 await env.clearFirestore();
 const db=(uid,provider='password')=>env.authenticatedContext(uid,{firebase:{sign_in_provider:provider}}).firestore();
 await env.withSecurityRulesDisabled(async c=>{
 const d=c.firestore();
 await setDoc(doc(d,'organisations/org'),{ownerId:'manager',adminUserIds:[],listingOwnershipStatus:'claimed'});
 for(const id of ['open','private'])await setDoc(doc(d,`organisations/org/groups/${id}`),{visibility:id==='open'?'public':'private',membershipMode:id==='open'?'open':'approval_required',isActive:true,memberCount:0,leaderUserIds:[]});
 });
 const payload=(uid,ids,role='member')=>({userId:uid,userName:uid,role,status:'active',groupIds:ids,createdAt:new Date(),updatedAt:new Date()});
 const outsider=db('outside'),anon=db('anon','anonymous');
 await assertFails(setDoc(doc(outsider,'organisations/org/members/outside'),payload('outside',['private'])));
 await assertFails(setDoc(doc(anon,'organisations/org/members/anon'),payload('anon',['open'])));
 let batch=writeBatch(outsider);batch.set(doc(outsider,'organisations/org/groups/open/members/outside'),payload('outside',[]));batch.set(doc(outsider,'organisations/org/members/outside'),payload('outside',['open']));batch.update(doc(outsider,'organisations/org/groups/open'),{memberCount:1,updatedAt:new Date()});await assertSucceeds(batch.commit());
 await assertFails(updateDoc(doc(outsider,'organisations/org/members/outside'),{role:'owner'}));
 await assertFails(updateDoc(doc(outsider,'organisations/org/members/outside'),{groupIds:['private','open']}));
 const manager=db('manager');batch=writeBatch(manager);batch.set(doc(manager,'organisations/org/groups/private/members/member'),payload('member',[]));batch.set(doc(manager,'organisations/org/members/member'),payload('member',['private']));await assertSucceeds(batch.commit());
 await assertSucceeds(getDoc(doc(db('member'),'organisations/org/groups/private')));
 await assertFails(getDoc(doc(outsider,'organisations/org/groups/private')));
 batch=writeBatch(outsider);batch.update(doc(outsider,'organisations/org/groups/open/members/outside'),{status:'removed',updatedAt:new Date()});batch.update(doc(outsider,'organisations/org/members/outside'),{groupIds:[],membershipGroupId:'open',updatedAt:new Date()});batch.update(doc(outsider,'organisations/org/groups/open'),{memberCount:0,updatedAt:new Date()});await assertSucceeds(batch.commit());
 await env.withSecurityRulesDisabled(async c=>{
 await setDoc(doc(c.firestore(),'organisations/org/members/secretary'),{...payload('secretary',[],'secretary'),roleLabel:'Club secretary',invitationId:'existing'});
 await setDoc(doc(c.firestore(),'organisations/org/members/former'),{...payload('former',[],'organisation_admin'),status:'removed'});
 });
 const secretary=db('secretary');batch=writeBatch(secretary);batch.set(doc(secretary,'organisations/org/groups/open/members/secretary'),payload('secretary',[]));batch.update(doc(secretary,'organisations/org/members/secretary'),{groupIds:['open'],updatedAt:new Date()});await assertSucceeds(batch.commit());
 const former=db('former');batch=writeBatch(former);batch.set(doc(former,'organisations/org/groups/open/members/former'),payload('former',[]));batch.update(doc(former,'organisations/org/members/former'),{groupIds:['open'],status:'active',updatedAt:new Date()});await assertFails(batch.commit());
 console.log('PASS: self-grant/anonymous/escalation/injected groups denied; open join, manager approval, private member read and leave work.');
 await env.cleanup();
});
