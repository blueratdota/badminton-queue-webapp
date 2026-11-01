// Shared rule-contract checks for the native-equivalent HTML and React engines.
const assert=require('node:assert/strict'),load=require('./load-page');
const p=load(process.argv[2]||'src/engine.js');
const originalNow=Date.now;let now=1e12;Date.now=()=>now;
const ids=g=>[...g.a,...g.b].map(x=>x.id).sort().join();
const gap=g=>Math.abs(p.sum(g.a)-p.sum(g.b))/2;
const teams=g=>[g.a,g.b].map(t=>t.map(x=>x.id).sort().join()).sort().join('|');
function fixture(skills=Array(8).fill(3)){
 const s={id:'simple',date:now-600000,hours:3,players:skills.map((skill,i)=>({id:'p'+i,name:'P'+i,skill,pref:'any',readyAt:now+i,paused:false})),courts:[p.court('C1','doubles'),p.court('C2','doubles')],results:[]};p.set('S',s);return s;
}
function round(s){for(let i=0;i<s.players.length;i+=4)s.results.push({a:s.players.slice(i,i+2).map(x=>x.id),b:s.players.slice(i+2,i+4).map(x=>x.id),court:'C1',start:now-600000,end:now-60000,winner:0});p.refreshSchedule();}
try{
 let display=fixture();display.courts=display.courts.slice(0,1);
 for(let n=0;n<3;n++)display.results.push({a:['p0','p1'],b:['p2','p3'],winner:0,court:'C1',start:now-600000,end:now-60000});
 for(const mode of ['auto','equalSkill','balancedSkill']){
  p.setQueueMatching(mode);const before=teams(p.nextPairing(display.courts[0])),ratings=display.players.map(x=>x.skill);
  display.results.forEach(r=>r.winner=1);assert.equal(teams(p.nextPairing(display.courts[0])),before,'streak history does not change ordinary queue selection');assert.deepEqual(display.players.map(x=>x.skill),ratings);
 }
 assert.equal(p.streak('p0'),-3);assert.equal(p.streakEmoji(p.streak('p0')),'🧊');
 display.results.push({a:['p0'],b:['p2'],winner:null,start:now,end:now});assert.equal(p.streak('p0'),-3);
 display.results[2].winner=0;assert.equal(p.streak('p0'),1);assert.equal(p.streakEmoji(p.streak('p0')),'');display.results.splice(2,1);assert.equal(p.streak('p0'),-2);

 let s=fixture(Array(4).fill(3));let first=p.pick('doubles',p.queue());s.results.push({a:first.a.map(x=>x.id),b:first.b.map(x=>x.id),court:'C1',start:now-600000,end:now-60000,winner:0});let next=p.pick('doubles',p.queue());assert.equal(ids(first),ids(next));assert.notEqual(teams(first),teams(next));assert(gap(next)<=0.75,'same four rotate balanced teams');
 // Refill through the real preview/Start path, including exhaustion of all three four-player splits.
 for(let n=4;n<=8;n++){
  s=fixture(Array(n).fill(3));s.courts.pop();const c=s.courts[0];
  for(let game=0;game<24;game++){
   const shown=p.nextPairing(c);assert(shown,`${n} players: game ${game+1} must be available`);
   if(n===4&&game===3)assert(shown.rematchFallback,'four-player rematch fallback after three splits');
   p.fill(c.id,shown);assert(c.match,'Start accepts the fallback preview');assert.equal([...c.match.a,...c.match.b].sort().join(),ids(shown));
   now+=12*60000;p.finish(c.id,game%2);
  }
  const counts=s.players.map(x=>p.played(x.id));assert(Math.min(...counts)>0);assert(Math.max(...counts)-Math.min(...counts)<=1,'small roster keeps game counts even');
 }
 s=fixture(Array(4).fill(3));s.courts.pop();
 for(let game=0;game<3;game++){p.fill(s.courts[0].id);now+=12*60000;p.finish(s.courts[0].id,game%2);}
 p.shuffleCourt(s.courts[0].id);let fallback=p.nextPairing(s.courts[0]);assert(fallback);p.fill(s.courts[0].id,fallback);assert(s.courts[0].match,'shuffled fallback can start');p.finish(s.courts[0].id,null);
 fallback=p.nextPairing(s.courts[0]);assert(fallback,'cancellation retains a playable fallback');
 p.addPlayer('Extra',3);assert(!p.automaticMatchupAllowed(fallback.a.map(x=>x.id),fallback.b.map(x=>x.id)),'normal matchup alternatives restore the cooldown check on a stale fallback');
 s=fixture(Array(5).fill(3));s.courts.pop();s.players[4].away=true;
 for(let game=0;game<2;game++){p.fill(s.courts[0].id);now+=12*60000;p.finish(s.courts[0].id,game%2);}
 p.arrive('p4');assert(!s.players[4].credit,'first-30-minute arrival still has zero credit');
 const arrivalGame=p.nextPairing(s.courts[0]);assert(arrivalGame&&[...arrivalGame.a,...arrivalGame.b].some(x=>x.id==='p4'),'recall enough two-game returners to serve an early fifth arrival');
 p.fill(s.courts[0].id,arrivalGame);assert(s.courts[0].match);
 // Twelve newcomers can push every regular outside the old twelve-player search window.
 function arrivalWave(minute=60){
  const s=fixture(Array(12).fill(3)),start=now;
  for(let r=0;r<3;r++)for(let i=0;i<12;i+=4){if(r===2&&i===0)continue;s.results.push({a:['p'+i,'p'+(i+1)],b:['p'+(i+2),'p'+(i+3)],winner:r%2,court:'C1',start:start+r*60000,end:start+(r+1)*60000});}
  now=start+minute*60000;s.courts[0].match={a:['p0','p1'],b:['p2','p3'],start:now};
  for(let i=0;i<12;i++)p.addPlayer('Late'+i,3);
  return s;
 }
 s=arrivalWave();s.players[12].credit=null;assert(p.newcomer(s.players[12]),'late arrival status is independent of credit');
 for(let choice=0;choice<4;choice++){
  const mixed=p.pick('doubles',p.eligible('doubles'),choice);assert(mixed&&gap(mixed)<=0.75);
  assert([...mixed.a,...mixed.b].filter(p.newcomer).length<=2,'keep the newcomer cap while relaxing equal-game selection');
 }
 let mixed=p.nextPairing(s.courts[1]);p.fill(s.courts[1].id,mixed);assert(s.courts[1].match,'mixed preview starts');p.finish(s.courts[1].id,null);
 for(const x of s.players.slice(5,12))x.paused=true;
 const scarce=p.pick('doubles',p.eligible('doubles'));assert(scarce&&[...scarce.a,...scarce.b].filter(p.newcomer).length>2,'waive the cap when only one regular is available');
 s=arrivalWave(29.99);assert(s.players.slice(12).every(x=>!p.newcomer(x)&&!x.credit),'early arrivals retain the thirty-minute grace period');
 s.players[12].since=p.startedAt()+30*60000;assert(p.newcomer(s.players[12]),'grace ends exactly at thirty minutes even with zero credit');
 s=fixture();const before=ids(p.pick('doubles',p.queue()));s.players[7].since=now-60*60000;assert.equal(ids(p.pick('doubles',p.queue())),before);assert.equal(p.balancedOnly(),false);s.courts.pop();assert.equal(p.balancedOnly(),false);
 s=fixture([3,3.2,3.4,3.6,1.8,4.2]);assert.equal(ids(p.pickDoubles(s.players)),'p0,p1,p2,p3','similar-skill stage wins before widening');assert.equal(ids(p.pickDoubles(s.players,0,{justOff:new Set(['p2','p3'])})),'p0,p1,p4,p5','balanced rested mixed group wins before narrower recalled group');
 s=fixture([5,1,1,1,3,3]);const off=new Set(['p4','p5']);let g=p.pickDoubles(s.players,0,{justOff:off,games:Object.fromEntries(s.players.map(x=>[x.id,0]))});assert(gap(g)<=0.75&&[...g.a,...g.b].some(x=>off.has(x.id)),'recall precedes uneven rested teams');g=p.pickDoubles(s.players,0,{justOff:off,games:{p4:1,p5:1}});assert(![...g.a,...g.b].some(x=>off.has(x.id)),'one-game lead cannot be recalled');assert(gap(g)>0.75,'fairest available fallback remains possible');
 for(const [rating,allowed]of [[3,true],[4.75,true],[2.99,false],[4.76,false]]){s=fixture([3.5,3.5,rating,rating]);p.setLock('p0','p1');assert.equal(!!p.pick('doubles',p.queue()),allowed,'locked average band '+rating);}
 for(const [opponent,allowed]of [[3,false],[5,true]]){s=fixture([3.5,3.5,opponent,opponent]);p.setLock('p0','p1');const game=()=>p.lockedGame(s.players,p.lockContext(s.players)[0],p.lockContext(s.players));assert.equal(!!game(),!allowed);for(let n=0;n<3;n++)for(let i=0;i<2;i++)s.results.push({a:['p'+i],b:['p'+(i+2)],winner:0,court:'C1',start:now-600000,end:now-60000});assert.equal(p.streak('p0'),3);assert.equal(p.streak('p2'),-3);assert.equal(!!game(),!allowed,'streaks do not change locked eligibility');assert.deepEqual(s.players.map(x=>x.skill),[3.5,3.5,opponent,opponent]);}
 s=fixture([5,5,2,2]);p.setLock('p0','p1');s.results=[{a:['p0','p2'],b:['p1','p3'],winner:0,court:'C1',start:now-3600000,end:now-1800000}];for(const x of s.players)x.since=now-29*60000;assert.equal(p.pick('doubles',p.queue(),0,true),null);now+=60000;assert(p.pick('doubles',p.queue()),'unmatchable lock releases at 30 minutes');
 s=fixture();p.setLock('p0','p1');p.setLock('p2','p3');const record=(a,b,winner=0)=>s.results.push({a:a.map(i=>'p'+i),b:b.map(i=>'p'+i),winner,court:'C1',start:now-600000,end:now-60000});const rematch=()=>p.keepsLocks(['p0','p1'],['p2','p3'],p.lockContext(s.players),true);assert(rematch());record([0,1],[2,3]);assert(!rematch());record([4,5],[6,7]);record([4,6],[5,7]);assert(!rematch(),'unrelated court games do not clear cooldown');record([0,2],[1,3],1);record([0,3],[1,2],null);assert(!rematch(),'one intervening game plus cancellation does not clear cooldown');record([0,1],[2,4],1);assert(!rematch(),'each participant needs two intervening games');record([3],[5],1);assert(rematch(),'two games per participant clear cooldown');s.results.pop();assert(!rematch(),'deleting history restores cooldown');
 s=fixture();const encounter=(a,b,winner=0)=>s.results.push({a:a.map(i=>'p'+i),b:b.map(i=>'p'+i),winner,court:'C1',start:now-600000,end:now-60000});const allowed=()=>p.automaticMatchupAllowed(['p0','p1'],['p2','p3']);encounter([0,1],[2,3]);assert(!allowed());assert(!p.automaticMatchupAllowed(['p3','p2'],['p1','p0']),'side/player order does not change identity');encounter([0,4],[2,5]);encounter([1,6],[3,7]);assert(!allowed(),'games 3 to 13: separate games do not clear team cooldown');encounter([0,1],[4,5]);assert(!allowed(),'one team changing opponents is insufficient');encounter([2,3],[6,7],null);assert(!allowed());encounter([3,2],[7,6]);assert(allowed());const allHistory=s.results;s.results=s.results.filter((_,i)=>[0,3,5].includes(i));p.setLock('p0','p1');p.setLock('p2','p3');assert(!allowed(),'stricter locked-pair cooldown still applies');s.results=allHistory;p.setLock('p0',null);p.setLock('p2',null);s.results.pop();assert(!allowed(),'deleting qualifying result restores cooldown');s.results[0].winner=null;assert(allowed(),'cancelling original encounter removes restriction');
 s=fixture();const stale=p.nextPairing(s.courts[0]);s.results.push({a:stale.a.map(x=>x.id),b:stale.b.map(x=>x.id),winner:0,court:'C1',start:now-600000,end:now-60000});s.courts[0].plan={a:stale.a.map(x=>x.id),b:stale.b.map(x=>x.id)};assert.equal(p.validPlan(s.courts[0]),null);p.fill(s.courts[0].id,stale);assert(!s.courts[0].match,'Start rejects stale automatic rematch');for(let n=0;n<6;n++){const next=p.nextPairing(s.courts[0]);assert(next&&p.automaticMatchupAllowed(next.a.map(x=>x.id),next.b.map(x=>x.id)));p.shuffleCourt(s.courts[0].id);}s.courts[0].manual=[...stale.a,...stale.b].map(x=>x.id);p.fill(s.courts[0].id,stale);assert(s.courts[0].match,'fully manual lineups override cooldown');
 s=fixture();round(s);const id=p.scheduleMatch('doubles',['p0','p1'],['p2','p3']);let r=s.scheduled.find(x=>x.id===id);const court=r.assignedCourt;assert(court&&p.scheduledOnCourt(court));s.courts.reverse();p.refreshSchedule();assert.equal(r.assignedCourt,court,'assigned court survives reorder');p.shuffleCourt(court);assert.equal(r.assignedCourt,court);p.setManual(court,true);assert(!s.courts.find(x=>x.id===court).manual);assert.equal(p.scheduledStatus(r),'Scheduled · Locked');
 const other=s.courts.find(c=>c.id!==court);p.shuffleCourt(other.id);p.refreshSchedule();assert.equal(r.assignedCourt,court,'other-court shuffle cannot pin or unlock a scheduled court');const ordinary=p.nextPairing(other);p.replace(ordinary.a[0].id,'p0',other.id);assert(!other.plan,'other-court replacement cannot steal a scheduled participant');p.setManual(other.id,true);p.setSlot(other.id,0,'p0');assert.equal(other.manual[0],null,'manual slot cannot steal a scheduled participant');p.setManual(other.id,false);
 p.postponeScheduled(id);assert.equal(p.scheduledOnCourt(court),null);assert.equal(p.scheduledReservation(),null);assert(p.scheduledStatus(r).startsWith('Postponed'));const second=p.scheduleMatch('doubles',['p4','p5'],['p6','p7']);now+=600000;p.refreshSchedule();assert.equal(p.scheduledReservation().id,second,'postponed request cannot preempt an active request');p.cancelScheduled(second);assert.equal(p.scheduledReservation().id,id);assert(p.scheduledOnCourt(r.assignedCourt));s.players[0].paused=true;p.refreshSchedule();assert.equal(r.assignedCourt,undefined);s.players[0].paused=false;p.refreshSchedule();assert(r.assignedCourt);const saved=JSON.parse(JSON.stringify(s));p.set('S',saved);p.refreshSchedule();assert.equal(saved.scheduled[0].assignedCourt,r.assignedCourt,'assignment survives save/load');p.cancelScheduled(id);assert.equal(p.scheduledReservation(),null);
 // Equal Skill scopes both the count floor and minimum necessary recalls to compatible quartets.
 s=fixture([1,4,4.1,4.2,4.3,4.4]);const cohortCounts={p0:0,p1:1,p2:1,p3:1,p4:1,p5:1},cohortOff=new Set(['p5']);
 for(const mode of ['auto','balancedSkill']){s.queueMatching=mode;assert.equal(p.recallLimits(s.players,cohortCounts,cohortOff,1).p5,0,'other modes retain global comparison');}
 s.queueMatching='equalSkill';assert.equal(p.recallLimits(s.players,cohortCounts,cohortOff,1).p5,1,'unmatchable lower skill cannot block recall');
 assert.equal(p.recallLimits(s.players,{...cohortCounts,p1:0},cohortOff,1).p5,0,'compatible fewer-game player still protects their turn');
 s.players[0].skill=3.5;assert.equal(p.recallLimits(s.players,cohortCounts,cohortOff,1).p5,0,'exact 1.0 range includes compatible lower-game player');
 s=fixture([3.1,4,4.5,4.6,4.7,4.8]);s.queueMatching='equalSkill';assert.equal(p.recallLimits(s.players,{p0:0,p1:2,p2:2,p3:2,p4:2,p5:2},new Set(['p1']),1).p1,2,'nearby player without a four-person compatible window cannot block');
 s=fixture([3.4,3.6,4.2,4.4,4.5,4.7,4.9,5]);s.queueMatching='equalSkill';assert.equal(p.recallLimits(s.players,{p0:2,p1:2,p2:3,p3:4,p4:4,p5:2,p6:3,p7:3},new Set(['p2','p3','p4']),1).p2,3,'four rested but incompatible players do not prevent one necessary recall');
 s=fixture([1,4,4.1,4.2,4.3,4.4]);s.queueMatching='equalSkill';for(let i=1;i<5;i++)s.players[i].credit=1;s.results.push({a:['p5'],b:['outside'],winner:0,court:'C1',start:now-600000,end:now-60000});s.players[5].first=true;s.players[5].readyAt=now-1000;const returned=p.pick('doubles',p.eligible('doubles'));assert(returned&&[...returned.a,...returned.b].some(x=>x.id==='p5'),'real Equal Skill picker admits compatible recall');assert(p.skillRangeAllowed([...returned.a,...returned.b].map(x=>x.id)));
 // Adaptive Equal Skill: full attendance includes busy players and all courts in service.
 s=fixture(Array(15).fill(3));s.queueMatching='equalSkill';assert.equal(p.matchingRange(),1.5);assert.equal(p.matchingRange('singles'),1);
 s.players.push({id:'p15',name:'P15',skill:3,pref:'any',paused:false,readyAt:now+15});assert.equal(p.matchingRange(),1);
 s.courts[1].match={a:['p8','p9'],b:['p10','p11'],start:now};assert.equal(p.matchingRange(),1,'busy court and players still count');
 for(const change of [{paused:true},{away:true},{pref:'singles'}]){Object.assign(s.players[15],change);assert.equal(p.matchingRange(),1.5,'only active doubles-eligible players count');Object.assign(s.players[15],{paused:false,away:false,pref:'any'});}
 for(const mode of ['auto','balancedSkill']){s.queueMatching=mode;s.players[15].paused=true;assert.equal(p.matchingRange(),1,'other modes retain their range');s.players[15].paused=false;}
 s=fixture(Array(8).fill(3));s.courts.pop();s.queueMatching='equalSkill';assert.equal(p.matchingRange(),1);s.players[7].paused=true;assert.equal(p.matchingRange(),1.5);s.courts=[];assert.equal(p.matchingRange(),1,'no doubles courts do not widen');
 s=fixture([3,4.2,4.4,4.5,...Array(11).fill(1)]);s.queueMatching='equalSkill';const adaptiveCourt=s.courts[0],adaptiveShown=p.nextPairing(adaptiveCourt);assert(adaptiveShown&&p.skillRangeAllowed([...adaptiveShown.a,...adaptiveShown.b].map(x=>x.id)));assert.equal(Math.max(...adaptiveShown.a.concat(adaptiveShown.b).map(x=>x.skill))-Math.min(...adaptiveShown.a.concat(adaptiveShown.b).map(x=>x.skill)),1.5);
 s.courts[1].match={a:['p4','p5'],b:['p6','p7'],start:now};const keptPlaying=JSON.stringify(s.courts[1].match);adaptiveCourt.plan={a:adaptiveShown.a.map(x=>x.id),b:adaptiveShown.b.map(x=>x.id)};
 s.players.push({id:'p15',name:'P15',skill:1,pref:'any',paused:false,readyAt:now+100});assert.equal(p.matchingRange(),1);assert.equal(p.validPlan(adaptiveCourt),null,'arrival invalidates wide automatic pin');p.fill(adaptiveCourt.id,adaptiveShown);assert(!adaptiveCourt.match,'Start rejects stale wide preview after tightening');assert.equal(JSON.stringify(s.courts[1].match),keptPlaying,'ongoing games are preserved');const refreshed=p.nextPairing(adaptiveCourt);assert(refreshed&&p.skillRangeAllowed([...refreshed.a,...refreshed.b].map(x=>x.id)));
 s.players[15].away=true;assert.equal(p.matchingRange(),1.5);adaptiveCourt.plan={a:adaptiveShown.a.map(x=>x.id),b:adaptiveShown.b.map(x=>x.id)};assert(p.validPlan(adaptiveCourt),'wider preview becomes eligible again');s.players[15].away=false;adaptiveCourt.plan.queueOverride=true;assert(p.validPlan(adaptiveCourt),'explicit organiser replacement remains an override');
 console.log('Simplified queue, recall fairness, team rotation, locked bands, court locking and postponement checks pass.');
}finally{Date.now=originalNow;}
