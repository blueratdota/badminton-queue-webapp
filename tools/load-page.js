// Loads the web version's engine (src/engine.js) into Node, so its own code can be run and tested.
// Exposes everything the engine defines (S, pick, fill, finish, queueUpNext, ...) through the returned `page` object.
const fs = require('fs');
module.exports = function loadPage(path, { onAssert } = {}) {
  const js = fs.readFileSync(path, 'utf8').replace(/^export /gm, '');
  global.localStorage = { getItem: () => null, setItem() {} };
  console.assert = (ok, msg) => { if (!ok) (onAssert || (m => console.log('FAIL:', m)))(msg); };
  // The engine's functions become reachable through `page.x`; `page.set('S', value)` assigns its top-level variables.
  const names = [...js.matchAll(/^(?:function\s+([A-Za-z_$][\w$]*)|(?:const|let|var)\s+([A-Za-z_$][\w$]*))/gm)].map(m => m[1] || m[2]);
  // `page.get(name)` reads any top-level name, including ones declared after a comma (const K = 0.3, SPREAD = 2).
  const expose = `({ ${names.map(n => `get ${n}() { return ${n}; }`).join(', ')}, get(n) { return eval(n); }, set(n, v) { eval(n + ' = v'); } })`;
  return (0, eval)(`(function () {\n${js}\n return ${expose}; })()`);
};
