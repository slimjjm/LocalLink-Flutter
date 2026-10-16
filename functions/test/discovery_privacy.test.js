const test=require('node:test'),assert=require('node:assert/strict');
const {activityScope,activityDiscoveryVisibility,groupDiscoveryVisibility,legacyDiscoveryPlan,buildDiscoveryPrivacyExports}=require('../discovery_privacy');
test('legacy standalone activities stay public, linked legacy activities are restricted',()=>{
 assert.equal(activityDiscoveryVisibility({isActive:true}),'public');
 assert.equal(activityScope({organisationId:'o',groupId:'g'}),'group');
 assert.equal(activityDiscoveryVisibility({organisationId:'o',groupId:'g'}),'restricted');
 assert.equal(activityDiscoveryVisibility({organisationId:'o'}),'restricted');
});
test('explicit private and invalid visibility cannot be published by contradictory public flags',()=>{
 for(const privacy of [{visibility:'private'},{isPrivate:true},{private:true},{isPubliclyDiscoverable:false},{activityAudienceScope:'group'},{visibility:'PRIVATE'},{visibility:'unexpected'},{isPrivate:'false'}])assert.equal(activityDiscoveryVisibility({activityAudienceScope:'everyone',isPubliclyDiscoverable:true,...privacy}),'restricted');
});
test('public organisation activity requires explicit public intent',()=>{
 assert.equal(activityDiscoveryVisibility({organisationId:'o',activityAudienceScope:'everyone'}),'public');
 assert.equal(activityDiscoveryVisibility({organisationId:'o',isPubliclyDiscoverable:true}),'public');
});
test('unknown legacy group visibility requires owner review and never defaults public',()=>{
 assert.equal(groupDiscoveryVisibility({}),'restricted');
 assert.equal(groupDiscoveryVisibility({visibility:'public'}),'public');
 const plan=legacyDiscoveryPlan([{path:'organisations/o/groups/g',data:{}},{path:'opportunities/a',data:{}},{path:'opportunities/b',data:{discoveryVisibility:'public'}}]);
 assert.equal(plan[0].requiresOwnerReview,true);assert.deepEqual(plan[0].changes,{});assert.deepEqual(plan[1].changes,{discoveryVisibility:'public'});assert.deepEqual(plan[2].changes,{});
});
test('old trigger events re-read current privacy and do not republish newer private content',async()=>{
 let writes=0;const ref={id:'a'};
 const db={runTransaction:async fn=>fn({get:async()=>({exists:true,data:()=>({activityAudienceScope:'group',organisationId:'o',groupId:'g',discoveryVisibility:'restricted'})}),update:()=>writes++})};
 const handlers=buildDiscoveryPrivacyExports({db,onDocumentWritten:(_,handler)=>handler});
 await handlers.onActivityDiscoveryChanged({data:{after:{exists:true,ref,data:()=>({activityAudienceScope:'everyone'})}}});assert.equal(writes,0);
});
test('uncertain backfill records remain unchanged with auditable reasons and exact preconditions',()=>{
 for(const data of [{organisationId:'o'},{groupId:'g'},{organisationId:12},{activityAudienceScope:'unknown'},{visibility:'public',isPrivate:true},{isPrivate:'false'},{activityAudienceScope:'group'},{activityAudienceScope:'organisation'},{visibility:'unrecognised'}]){
 const row=legacyDiscoveryPlan([{path:'opportunities/a',data}])[0];
 assert.equal(row.requiresOwnerReview,true);assert.deepEqual(row.changes,{});assert.ok(row.reasons.length);assert.deepEqual(row.precondition.data,data);
 }
});
test('safe backfill preserves ownership and privacy; replay is idempotent and rollback records absence',()=>{
 for(const data of [{createdBy:'established'},{createdBy:'established',activityAudienceScope:'group',organisationId:'o',groupId:'g'},{isPrivate:true,discoveryVisibility:'public'}]){
 const row=legacyDiscoveryPlan([{path:'opportunities/a',data}])[0];
 assert.equal(row.requiresOwnerReview,false);assert.equal(Object.keys(row.changes).join(','),'discoveryVisibility');
 const next={...data,...row.changes};assert.equal(next.createdBy,data.createdBy);assert.equal(next.isPrivate,data.isPrivate);
 assert.deepEqual(legacyDiscoveryPlan([{path:'opportunities/a',data:next}])[0].changes,{});
 assert.deepEqual(row.rollback,'discoveryVisibility' in data?{discoveryVisibility:data.discoveryVisibility}:{deleteFields:['discoveryVisibility']});
 }
});
