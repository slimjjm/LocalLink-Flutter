const test=require('node:test'), assert=require('node:assert/strict');
const {validReview,aggregateReviews}=require('../activity_stabilisation');
const args={uid:'member',organiserId:'owner',opportunity:{organiserId:'owner',eventDate:new Date(0)},attendee:{userId:'member'},rating:5,text:'Useful session',now:1000};
test('review requires actual attendee and completed activity and matching organiser',()=>{
 assert.equal(validReview(args),true);
 for(const patch of [{attendee:null},{uid:'owner'},{organiserId:'different'},{rating:0},{rating:6},{rating:2.5},{opportunity:{organiserId:'owner',eventDate:new Date(2000)}},{text:'a'.repeat(2001)}])assert.equal(validReview({...args,...patch}),false);
});
test('aggregate recomputes valid reviews rather than incrementing stale client counters',()=>{
 assert.deepEqual(aggregateReviews([{rating:5},{rating:3},{rating:99},{rating:null}]),{reviewCount:2,ratingTotal:8,averageRating:4});
});
