'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),os=require('node:os'),path=require('node:path'),{spawnSync}=require('node:child_process');
const script=path.resolve(__dirname,'../scripts/plan_discovery_privacy.js');
test('offline discovery plan leaves its input unchanged and cannot apply changes',()=>{
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'locallink-plan-'));const file=path.join(dir,'records.json');
 try {
 const input=JSON.stringify([{path:'opportunities/standalone',data:{}},{path:'organisations/o/groups/g',data:{}}]);fs.writeFileSync(file,input);
 const result=spawnSync(process.execPath,[script,file],{encoding:'utf8'});assert.equal(result.status,0);const plan=JSON.parse(result.stdout);assert.equal(plan.dryRun,true);assert.equal(plan.records[0].discoveryVisibility,'public');assert.equal(plan.records[1].requiresOwnerReview,true);assert.equal(fs.readFileSync(file,'utf8'),input);
 assert.notEqual(spawnSync(process.execPath,[script,file,'--apply']).status,0);
 fs.writeFileSync(file,JSON.stringify([{path:'users/u',data:{}}]));assert.notEqual(spawnSync(process.execPath,[script,file]).status,0);
 } finally {fs.rmSync(dir,{recursive:true,force:true});}
});
