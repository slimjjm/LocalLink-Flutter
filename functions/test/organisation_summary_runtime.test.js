"use strict";
const test=require('node:test'),assert=require('node:assert/strict');
test('existing selected functions preserve external options without reset markers',()=>{
 process.env.GCLOUD_PROJECT='demo-locallink-runtime-check';process.env.FIREBASE_CONFIG=JSON.stringify({projectId:'demo-locallink-runtime-check'});
 const api=require('../index');
 for(const name of ['getPublicSharePreview','askLocalLink','refreshNearbyMissingPetAlerts','processNearbyMissingPetAlerts']){
  const endpoint=api[name].__endpoint;
  for(const key of ['maxInstances','minInstances','serviceAccountEmail','ingressSettings','concurrency'])assert.equal(Object.hasOwn(endpoint,key),false,name+': '+key);
 }
 assert.equal(api.askLocalLink.__endpoint.availableMemoryMb,512);assert.equal(api.askLocalLink.__endpoint.timeoutSeconds,30);
 assert.equal(api.askLocalLink.__endpoint.secretEnvironmentVariables[0].key,'OPENAI_API_KEY');
 assert.equal(api.processNearbyMissingPetAlerts.__endpoint.scheduleTrigger.schedule,'every 15 minutes');
});
