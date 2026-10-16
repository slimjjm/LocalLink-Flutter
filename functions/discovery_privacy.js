'use strict';
function explicitPrivacyBlock(data) {
 return ('isPubliclyDiscoverable' in data && data.isPubliclyDiscoverable !== true) || ('isPrivate' in data && data.isPrivate !== false) || ('private' in data && data.private !== false) || ('visibility' in data && data.visibility !== '' && data.visibility !== 'public');
}
function activityScope(data) {
 if (['everyone','organisation','group'].includes(data.activityAudienceScope)) return data.activityAudienceScope;
 if ('activityAudienceScope' in data && data.activityAudienceScope !== '') return 'restricted';
 if (['organisationId','groupId'].some(key=>key in data && typeof data[key] !== 'string')) return 'restricted';
 if (explicitPrivacyBlock(data)) return data.groupId && data.organisationId ? 'group' : data.organisationId ? 'organisation' : 'restricted';
 if (data.isPubliclyDiscoverable===true) return 'everyone';
 if (data.organisationId) return data.groupId ? 'group' : 'organisation';
 if (data.groupId) return 'restricted';
 return 'everyone';
}
function activityDiscoveryVisibility(data) {
 return activityScope(data)==='everyone' && !explicitPrivacyBlock(data) ? 'public':'restricted';
}
function groupDiscoveryVisibility(data) {
 return data.visibility==='public' && !explicitPrivacyBlock(data) ? 'public':'restricted';
}
function legacyDiscoveryPlan(records) {
 return records.map(({path,data})=>{
 const isGroup=/^organisations\/[^/]+\/groups\/[^/]+$/.test(path);
 if(!isGroup&&!/^opportunities\/[^/]+$/.test(path))throw Error('Unsupported discovery path');
 const discoveryVisibility=isGroup?groupDiscoveryVisibility(data):activityDiscoveryVisibility(data);
 const invalidFields=['organisationId','groupId','activityAudienceScope','visibility'].filter(key=>key in data&&typeof data[key]!=='string');
 const invalidFlags=['isPubliclyDiscoverable','isPrivate','private'].filter(key=>key in data&&typeof data[key]!=='boolean');
 const ambiguous=isGroup?!['public','private'].includes(data.visibility):Boolean((data.organisationId||data.groupId)&&!data.activityAudienceScope&&data.isPubliclyDiscoverable!==true&&!explicitPrivacyBlock(data));
 const unknownScope=!isGroup&&data.activityAudienceScope&&!['everyone','organisation','group'].includes(data.activityAudienceScope);
 const orphanGroup=!isGroup&&data.groupId&&!data.organisationId;
 const incompleteAudience=!isGroup&&((data.activityAudienceScope==='organisation'&&!data.organisationId)||(data.activityAudienceScope==='group'&&(!data.organisationId||!data.groupId)));
 const unknownVisibility='visibility' in data&&!['','public','private'].includes(data.visibility);
 const contradictory=(isGroup?data.visibility==='public':data.activityAudienceScope==='everyone'||data.isPubliclyDiscoverable===true||data.visibility==='public')&&explicitPrivacyBlock(data);
 const requiresOwnerReview=Boolean(ambiguous||invalidFields.length||invalidFlags.length||unknownScope||orphanGroup||incompleteAudience||unknownVisibility||contradictory);
 const reasons=[...(ambiguous?['missing-established-visibility']:[]),...invalidFields.map(f=>'invalid-'+f),...invalidFlags.map(f=>'invalid-'+f),...(unknownScope?['unknown-audience']:[]),...(orphanGroup?['unverified-group-context']:[]),...(incompleteAudience?['incomplete-audience-context']:[]),...(unknownVisibility?['unknown-visibility']:[]),...(contradictory?['conflicting-privacy']:[])];
 const changes=requiresOwnerReview||data.discoveryVisibility===discoveryVisibility?{}:{discoveryVisibility};
 return {path,discoveryVisibility,requiresOwnerReview,reasons,changes,
   precondition:{data},
   rollback:('discoveryVisibility' in data)?{discoveryVisibility:data.discoveryVisibility}:{deleteFields:['discoveryVisibility']}};
 });
}
function buildDiscoveryPrivacyExports({db,onDocumentWritten,admin}) {
 const sync = classify => async event => {
  const ref=event.data?.after?.ref;
  if(!event.data?.after?.exists||!ref)return;
  // Re-read inside a transaction: an older trigger event must never republish a newer private record.
  await db.runTransaction(async tx=>{
   const current=await tx.get(ref);if(!current.exists)return;
   const data=current.data(),visibility=classify(data);
   const cleanup=classify===activityDiscoveryVisibility && admin
     ? await require('./activity_stabilisation').privateSummaryCleanup(tx,db,ref.id,data,event.data?.before?.data?.(),admin) : [];
   if(data.discoveryVisibility!==visibility)tx.update(ref,{discoveryVisibility:visibility});
   for(const change of cleanup)tx.update(change.ref,change.fields);
  });
 };
 return {
  onActivityDiscoveryChanged:onDocumentWritten({document:'opportunities/{opportunityId}',region:'us-central1'},sync(activityDiscoveryVisibility)),
  onGroupDiscoveryChanged:onDocumentWritten({document:'organisations/{organisationId}/groups/{groupId}',region:'us-central1'},sync(groupDiscoveryVisibility)),
 };
}
module.exports={activityScope,activityDiscoveryVisibility,groupDiscoveryVisibility,legacyDiscoveryPlan,buildDiscoveryPrivacyExports};
