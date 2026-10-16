'use strict';
// Dates are calendar dates in the activity zone, not the Functions process zone.
const DEFAULT_ZONE = 'Europe/London';
function parts(date, zone) {
  const values = new Intl.DateTimeFormat('en-GB', {timeZone: zone, year:'numeric', month:'2-digit', day:'2-digit', hour:'2-digit', minute:'2-digit', second:'2-digit', hourCycle:'h23'}).formatToParts(date);
  return Object.fromEntries(values.filter(p=>p.type!=='literal').map(p=>[p.type,Number(p.value)]));
}
function serial(p) { return Date.UTC(p.year,p.month-1,p.day,p.hour||0,p.minute||0,p.second||0); }
function zonedInstant(local, zone) {
  const target=serial(local), offsets=new Set();
  for (const delta of [-2,-1,0,1,2]) {
    const sample=new Date(target+delta*86400000);
    offsets.add(serial(parts(sample,zone))-sample.getTime());
  }
  const candidates=[...offsets].map(offset=>new Date(target-offset));
  const exact=candidates.filter(d=>serial(parts(d,zone))===target).sort((a,b)=>a-b);
  // Fall-back overlap: earlier occurrence. Spring gap: no valid instant.
  if(exact.length)return exact[0];
  return null;
}
function parseTime(value) {
  if(value==null || value==='')return null;
  const match=/^(\d{1,2}):(\d{2})(?:\s*([ap]m))?$/i.exec(String(value).trim());
  if(!match)throw Error('Invalid recurrence eventTime');
  let hour=Number(match[1]),minute=Number(match[2]);
  if(minute>59 || (match[3] ? hour<1||hour>12 : hour>23))throw Error('Invalid recurrence eventTime');
  if(match[3])hour=hour%12+(match[3].toLowerCase()==='pm'?12:0);
  return {hour,minute,second:0};
}
function zoneFor(data) { return data.recurrenceTimeZone || DEFAULT_ZONE; }
function addRepeatInterval(date, repeatType, data={}) {
  const zone=zoneFor(data), local=parts(date,zone), clock=parseTime(data.eventTime);
  if(clock)Object.assign(local,clock);
  const calendar=new Date(serial(local));
  const days={daily:1,weekly:7,fortnightly:14};
  for(let attempt=0;attempt<50;attempt++) {
    if(repeatType in days)calendar.setUTCDate(calendar.getUTCDate()+days[repeatType]);
    else if(repeatType==='monthly')calendar.setUTCMonth(calendar.getUTCMonth()+1); // Preserve existing month-overflow convention.
    else return null;
    const instant=zonedInstant({year:calendar.getUTCFullYear(),month:calendar.getUTCMonth()+1,day:calendar.getUTCDate(),hour:calendar.getUTCHours(),minute:calendar.getUTCMinutes(),second:calendar.getUTCSeconds()},zone);
    // A nonexistent spring-gap time is skipped, never silently moved to a different advertised time.
    if(instant)return instant;
  }
  return null;
}
function sameLocalDay(a,b,data={}) {
  const zone=zoneFor(data),x=parts(a,zone),y=parts(b,zone);
  return x.year===y.year&&x.month===y.month&&x.day===y.day;
}
function afterLocalDay(a,b,data={}) {
  const zone=zoneFor(data),x=parts(a,zone),y=parts(b,zone);
  return Date.UTC(x.year,x.month-1,x.day)>Date.UTC(y.year,y.month-1,y.day);
}
function occurrenceScheduleFields(data,date) {
  const result={recurrenceTimeZone:zoneFor(data)};
  if(typeof data.scheduleText === "string" && /^\d{1,2}\/\d{1,2}\/\d{4}(?:\s|$)/.test(data.scheduleText)) {
    const p=parts(date,zoneFor(data));
    result.scheduleText=data.scheduleText.replace(/^\d{1,2}\/\d{1,2}\/\d{4}/, `${p.day}/${p.month}/${p.year}`);
  }
  return result;
}
module.exports={occurrenceScheduleFields,afterLocalDay,addRepeatInterval,sameLocalDay,zonedInstant,parts,parseTime,DEFAULT_ZONE};
