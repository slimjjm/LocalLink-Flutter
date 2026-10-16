const test=require('node:test'),assert=require('node:assert/strict');
const {ownedBillingBusiness}=require('../business_billing');
class HttpsError extends Error{constructor(code,message){super(message);this.code=code}}
function database(records){return{collection:()=>({doc:id=>({id,get:async()=>({exists:!!records[id],data:()=>records[id]})}),where:(_,__,uid)=>({limit:()=>({get:async()=>{const docs=Object.entries(records).filter(([_,v])=>v.ownerId===uid).slice(0,2).map(([id])=>({ref:{id}}));return{docs,size:docs.length,empty:!docs.length}}})})})}}
test('billing uses the explicitly selected owned business',async()=>{
const result=await ownedBillingBusiness({db:database({a:{ownerId:'owner'},b:{ownerId:'owner'}}),uid:'owner',businessId:'b',HttpsError});assert.equal(result.id,'b');
});
test('billing rejects other owners, missing and malformed business ids',async()=>{
for(const [businessId,code]of [['a','permission-denied'],['missing','not-found'],['a/b','invalid-argument'],['','invalid-argument']])await assert.rejects(()=>ownedBillingBusiness({db:database({a:{ownerId:'other'}}),uid:'owner',businessId,HttpsError}),e=>e.code===code);
});
test('legacy billing request works only with one unambiguous owned business',async()=>{
assert.equal((await ownedBillingBusiness({db:database({a:{ownerId:'owner'}}),uid:'owner',HttpsError})).id,'a');
await assert.rejects(()=>ownedBillingBusiness({db:database({a:{ownerId:'owner'},b:{ownerId:'owner'}}),uid:'owner',HttpsError}),e=>e.code==='failed-precondition');
});
