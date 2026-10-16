const test=require('node:test'),assert=require('node:assert/strict');
const {publicCommunityCoordinates}=require('../public_location');
test('community coordinates prefer one complete approximate pair over a conflicting exact pair',()=>{
 assert.deepEqual(publicCommunityCoordinates({approxLatitude:56.4621,approxLongitude:-2.9712,latitude:52.67,longitude:-1.92}),{latitude:56.4621,longitude:-2.9712});
});
test('partial approximate data never mixes with or falls back to an exact private coordinate',()=>{
 assert.equal(publicCommunityCoordinates({approxLatitude:56.46,longitude:-1.92}),null);
 assert.equal(publicCommunityCoordinates({approxLatitude:null,approxLongitude:null,latitude:56.46,longitude:-2.97}),null);
});
test('legacy coordinates remain in their supplied area with reduced precision and invalid locations are rejected',()=>{
 assert.deepEqual(publicCommunityCoordinates({latitude:56.4621,longitude:-2.9712}),{latitude:56.46,longitude:-2.97});
 for(const pair of [[0,0],[91,2],[55,181],[NaN,2],['',2]])assert.equal(publicCommunityCoordinates({approxLatitude:pair[0],approxLongitude:pair[1]}),null);
});
