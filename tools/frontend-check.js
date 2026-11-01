// Small checks for the visual math; independent of the browser and matchmaking.
const assert = require('node:assert/strict');
(async () => {
  const { rallySeed, rallyUnit } = await import('../src/rally.js');
  const { streakEmoji } = await import('../src/engine.js');
  const seed = rallySeed('court-a');
  assert.equal(rallyUnit(seed, 5, 1), rallyUnit(seed, 5, 1));
  assert.notEqual(rallyUnit(seed, 5, 1), rallyUnit(rallySeed('court-b'), 5, 1));
  assert.equal(new Set(Array.from({ length: 40 }, (_, i) => rallyUnit(seed, i, 1))).size, 40);
  assert(Array.from({ length: 100 }, (_, i) => rallyUnit(seed, i, 0)).every(x => x >= 0 && x <= 1));
  assert.equal(streakEmoji(2),'');assert.equal(streakEmoji(-2),'');assert.equal(streakEmoji(3),'🔥');assert.equal(streakEmoji(-3),'🧊');
  console.log('frontend checks pass');
})().catch(e => { console.error(e); process.exitCode = 1; });
