'use strict';
// Offline review tool only. It has no Firebase credentials, network access or apply mode.
const fs = require('node:fs');
const {legacyDiscoveryPlan} = require('../discovery_privacy');
function planFile(file) {
  const records=JSON.parse(fs.readFileSync(file,'utf8'));
  if(!Array.isArray(records)||records.some(record=>!record||typeof record.path!=='string'||!record.data||typeof record.data!=='object'||Array.isArray(record.data))) throw Error('Expected an array of {path, data} discovery records');
  return {dryRun:true,records:legacyDiscoveryPlan(records)};
}
if(require.main===module) {
  try {
    if(process.argv.length!==3||process.argv[2].startsWith('-')) throw Error('Usage: node scripts/plan_discovery_privacy.js exported-records.json (offline dry run only)');
    process.stdout.write(JSON.stringify(planFile(process.argv[2]),null,2)+'\n');
  } catch(error) {process.stderr.write(error.message+'\n');process.exitCode=1;}
}
module.exports={planFile};
