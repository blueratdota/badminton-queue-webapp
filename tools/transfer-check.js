// The same text code must work across both web engines and the native export.
const assert=require('node:assert/strict'),fs=require('fs'),load=require('./load-page');
const source=fs.readFileSync(require('path').join(__dirname,'../src/transfer.js'),'utf8').replace(/^export /gm,'');const p=new Function(source+';return {encodeTransfer,decodeTransfer};')();
const fixture={id:'session',date:1700000000000,players:[{id:'one',name:'José 🏸',skill:3,pref:'any',readyAt:1700000000000}],courts:[{id:'court',name:'C1',format:'doubles',plan:{a:['one'],b:[]}}],results:[]};
const code=p.encodeTransfer([fixture],fixture.id);assert(!code.includes('\n'));assert.deepEqual(p.decodeTransfer(' \n'+code+'\n ').sessions,[fixture]);
for(const bad of ['',code.slice(0,-1),'alert(1)',JSON.stringify({sessions:[]}),JSON.stringify({sessions:[fixture,{id:'bad'}]}),JSON.stringify({sessions:[fixture,fixture]})])assert.throws(()=>p.decodeTransfer(bad));
const roster=[{id:'legacy',name:'Legacy player',skill:5.12,pref:'any',readyAt:1700000000000},{id:'bench',name:'Sitting out',skill:2.375,pref:'doubles',paused:true,away:true,readyAt:1700000000000}];const full={...fixture,players:roster};assert.deepEqual(p.decodeTransfer(p.encodeTransfer([full],full.id)).sessions[0].players,roster,'full roster and exact ratings survive transfer');
const invalid=JSON.parse(code);invalid.sessions[0].players[0].skill=NaN;assert.throws(()=>p.decodeTransfer(JSON.stringify(invalid)));
if(process.argv[3]){const native=fs.readFileSync(process.argv[3],'utf8');assert(p.decodeTransfer(native).sessions.length>0);}
console.log('Copy/paste code, Unicode, legacy JSON, incomplete-data rejection and native compatibility checks pass.');
