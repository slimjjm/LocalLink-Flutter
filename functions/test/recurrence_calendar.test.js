'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {addRepeatInterval,parts,parseTime,sameLocalDay}=require('../recurrence_calendar');
const london={recurrenceTimeZone:'Europe/London',eventTime:'18:30'};
test('weekly October and March maintain London wall clock',()=>{
 assert.equal(addRepeatInterval(new Date('2026-10-19T17:30Z'),'weekly',london).toISOString(),'2026-10-26T18:30:00.000Z');
 assert.equal(addRepeatInterval(new Date('2026-03-23T18:30Z'),'weekly',london).toISOString(),'2026-03-30T17:30:00.000Z');
});
for(const [type,start,expected] of [
 ['daily','2026-10-24T17:30Z','2026-10-25T18:30:00.000Z'],
 ['daily','2026-03-28T18:30Z','2026-03-29T17:30:00.000Z'],
 ['fortnightly','2026-10-12T17:30Z','2026-10-26T18:30:00.000Z'],
 ['fortnightly','2026-03-16T18:30Z','2026-03-30T17:30:00.000Z'],
 ['monthly','2026-09-26T17:30Z','2026-10-26T18:30:00.000Z'],
 ['monthly','2026-02-28T18:30Z','2026-03-28T18:30:00.000Z'],
])test(type+' '+start,()=>assert.equal(addRepeatInterval(new Date(start),type,london).toISOString(),expected));
test('legacy UK date-only seed uses eventTime, no Sunday child',()=>{
 const next=addRepeatInterval(new Date('2026-10-18T23:00Z'),'weekly',{eventTime:'6:30 PM'});
 assert.equal(next.toISOString(),'2026-10-26T18:30:00.000Z');
});
test('multiple future transitions retain same weekday and time',()=>{
 let d=new Date('2026-10-19T17:30Z');for(let i=0;i<110;i++){d=addRepeatInterval(d,'weekly',london);const p=parts(d,'Europe/London');assert.equal(p.hour,18);assert.equal(p.minute,30);assert.equal(new Date(Date.UTC(p.year,p.month-1,p.day)).getUTCDay(),1);}
});
test('cross-midnight event keeps start 23:30 and next local date',()=>{
 const next=addRepeatInterval(new Date('2026-03-28T23:30Z'),'daily',{...london,eventTime:'23:30',endTime:'00:30'});
 assert.equal(next.toISOString(),'2026-03-29T22:30:00.000Z');assert.equal(parts(next,'Europe/London').day,29);
});
test('DST gap skips nonexistent time; overlap chooses earlier instant',()=>{
 assert.equal(addRepeatInterval(new Date('2026-03-28T01:30Z'),'daily',{...london,eventTime:'01:30'}).toISOString(),'2026-03-30T00:30:00.000Z');
 assert.equal(addRepeatInterval(new Date('2026-10-24T00:30Z'),'daily',{...london,eventTime:'01:30'}).toISOString(),'2026-10-25T00:30:00.000Z');
});
test('explicit zones and cancellation days are respected',()=>{
 assert.equal(addRepeatInterval(new Date('2026-10-19T17:30Z'),'weekly',{recurrenceTimeZone:'UTC',eventTime:'17:30'}).toISOString(),'2026-10-26T17:30:00.000Z');
 assert.equal(sameLocalDay(new Date('2026-10-26T18:30Z'),new Date('2026-10-26T00:00Z'),london),true);
});
test('invalid schedule fails closed, missing time retains local clock, unsupported repeat returns null',()=>{
 assert.throws(()=>addRepeatInterval(new Date(),'weekly',{recurrenceTimeZone:'invalid'}));assert.throws(()=>parseTime('25:00'));assert.throws(()=>parseTime('7:60 PM'));
 assert.equal(addRepeatInterval(new Date('2026-10-19T17:30Z'),'weekly',{}).toISOString(),'2026-10-26T18:30:00.000Z');
 assert.equal(addRepeatInterval(new Date(),'none',{}),null);
});
test('monthly preserves historical end-of-month overflow',()=>assert.equal(addRepeatInterval(new Date('2026-01-31T18:30Z'),'monthly',london).toISOString(),'2026-03-03T18:30:00.000Z'));

test('recurrence end date includes the final local calendar day',()=>{const {afterLocalDay}=require('../recurrence_calendar');assert.equal(afterLocalDay(new Date('2026-10-26T18:30Z'),new Date('2026-10-26T00:00Z'),london),false);assert.equal(afterLocalDay(new Date('2026-10-27T00:00Z'),new Date('2026-10-26T00:00Z'),london),true);});

test('Ask LocalLink accepts generated upcoming public dates and blocks restricted counterparts',()=>{
 const ask=require('../ask_locallink')._private;
 for(const [seed,iso] of [['2026-10-19T17:30Z','2026-10-26T18:30:00.000Z'],['2026-03-23T18:30Z','2026-03-30T17:30:00.000Z']]) {
  const next=addRepeatInterval(new Date(seed),'weekly',london),data={isActive:true,organisationId:'org',activityAudienceScope:'everyone',isPubliclyDiscoverable:true,discoveryVisibility:'public',eventDate:{toDate:()=>next,toMillis:()=>next.getTime()},eventTime:'18:30'};
  assert.equal(next.toISOString(),iso);assert.equal(ask.isPublicActivityVisible(data,new Date(next.getTime()-3600000)),true);
  assert.equal(ask.isPublicActivityVisible({...data,activityAudienceScope:'organisation',isPubliclyDiscoverable:false,discoveryVisibility:'restricted'},new Date(next.getTime()-3600000)),false);
 }
});

test('generated date labels follow occurrence, custom schedule text is preserved',()=>{const {occurrenceScheduleFields}=require('../recurrence_calendar');assert.deepEqual(occurrenceScheduleFields({...london,scheduleText:'19/10/2026 18:30 - 19:30'},new Date('2026-10-26T18:30Z')),{recurrenceTimeZone:'Europe/London',scheduleText:'26/10/2026 18:30 - 19:30'});assert.deepEqual(occurrenceScheduleFields({...london,scheduleText:'Meet outside reception'},new Date()),{recurrenceTimeZone:'Europe/London'});});

test('monthly schedule crosses spring clock change',()=>assert.equal(addRepeatInterval(new Date('2026-03-15T18:30Z'),'monthly',london).toISOString(),'2026-04-15T17:30:00.000Z'));
