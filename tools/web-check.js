// node tools/web-check.js src/engine.js: runs the engine's self-checks (the matchmaking rules the iPad app is tested on).
const loadPage = require('./load-page');
let fails = 0;
try {
  loadPage(process.argv[2] || 'src/engine.js', { onAssert: m => { fails++; console.log('FAIL:', m); } }).selfCheck();
} catch (e) { fails++; console.log('ERROR:', e.stack); }
console.log(fails ? fails + ' problem(s)' : 'all checks pass');
process.exit(fails ? 1 : 0);
