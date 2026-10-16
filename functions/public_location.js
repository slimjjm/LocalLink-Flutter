'use strict';
function publicCommunityCoordinates(data) {
 const approximate='approxLatitude' in data || 'approxLongitude' in data;
 const number=value=>typeof value==='number'?value:typeof value==='string'&&value.trim()?Number(value):NaN;
 const latitude=number(data[approximate?'approxLatitude':'latitude']);
 const longitude=number(data[approximate?'approxLongitude':'longitude']);
 if(!Number.isFinite(latitude)||!Number.isFinite(longitude)||latitude < -90||latitude > 90||longitude < -180||longitude > 180||(Math.abs(latitude)<0.000001&&Math.abs(longitude)<0.000001))return null;
 return {latitude:approximate?latitude:Number(latitude.toFixed(2)),longitude:approximate?longitude:Number(longitude.toFixed(2))};
}
module.exports={publicCommunityCoordinates};
