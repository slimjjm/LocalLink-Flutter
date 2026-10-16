'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const { collection, query, where, limit, getDocs, doc, setDoc } = require('firebase/firestore');
// Existing loopback demo emulator only; never a production project.
const projectId = 'demo-locallink-own-reports';
const queries = db => ({
  created: uid => query(collection(db, 'communityHelpPosts'), where('createdBy', '==', uid), limit(30)),
  claimed: uid => query(collection(db, 'communityHelpPosts'), where('communityAdded', '==', true), where('claimStatus', '==', 'approved'), where('ownerId', '==', uid), limit(30)),
});
(async () => {
  const env = await initializeTestEnvironment({projectId, firestore:{host:'127.0.0.1', port:8897, rules:fs.readFileSync(path.join(__dirname, '..', 'firestore.rules'), 'utf8')}});
  let checks = 0;
  const pass = async (label, run) => {await run(); checks++; console.log(`PASS ${label}`);};
  try {
    await env.withSecurityRulesDisabled(async c => {
      const db = c.firestore();
      const base = {isActive:false, createdBy:'moderator', communityAdded:true, ownerId:'owner', title:'Synthetic report'};
      for (const [id, data] of Object.entries({
        created:{createdBy:'owner', isActive:false},
        legacy_created:{createdBy:'owner'},
        approved:{...base, claimStatus:'approved'},
        pending:{...base, claimStatus:'pending'},
        rejected:{...base, claimStatus:'rejected'},
        missing_status:base,
        forged_owner:{createdBy:'outsider', ownerId:'owner', isActive:false},
        other_owner:{...base, claimStatus:'approved', ownerId:'outsider'},
        active:{createdBy:'outsider', type:'lost_found', isActive:true},
      })) await setDoc(doc(db,'communityHelpPosts',id),data);
    });
    const owner = env.authenticatedContext('owner').firestore();
    const outsider = env.authenticatedContext('unrelated').firestore();
    await pass('creator sees own closed and legacy reports', async()=> assert.deepEqual((await assertSucceeds(getDocs(queries(owner).created('owner')))).docs.map(d=>d.id).sort(), ['created','legacy_created']));
    await pass('approved claimed reports only', async()=> assert.deepEqual((await assertSucceeds(getDocs(queries(owner).claimed('owner')))).docs.map(d=>d.id), ['approved']));
    await pass('ownerId alone still denied', ()=>assertFails(getDocs(query(collection(owner,'communityHelpPosts'),where('ownerId','==','owner'),limit(30)))));
    await pass('outsider cannot query another creator', ()=>assertFails(getDocs(queries(outsider).created('owner'))));
    await pass('outsider cannot query another approved owner', ()=>assertFails(getDocs(queries(outsider).claimed('owner'))));
    await pass('unauthenticated cannot query own reports', ()=>assertFails(getDocs(queries(env.unauthenticatedContext().firestore()).created('owner'))));
    await pass('anonymous cannot query private owner reports', ()=>assertFails(getDocs(queries(env.authenticatedContext('guest',{firebase:{sign_in_provider:'anonymous'}}).firestore()).claimed('owner'))));
    const empty = env.authenticatedContext('new-user').firestore();
    await pass('legitimate empty creator results', async()=>assert.equal((await assertSucceeds(getDocs(queries(empty).created('new-user')))).size,0));
    await pass('legitimate empty approved claims', async()=>assert.equal((await assertSucceeds(getDocs(queries(empty).claimed('new-user')))).size,0));
    await pass('Nearby active query remains permitted', async()=>assert.equal((await assertSucceeds(getDocs(query(collection(owner,'communityHelpPosts'),where('type','==','lost_found'),where('isActive','==',true),limit(50))))).size,1));
    console.log(`${checks} assertions PASS; unchanged candidate rules; isolated demo project.`);
  } finally {await env.cleanup();}
})().catch(error=>{console.error(error);process.exitCode=1;});
